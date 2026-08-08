# Offline-First Target Architecture — Execution Concerns

Companion to `OFFLINE_FIRST_EXECUTION_PROGRESS.md`. These are the judgment
calls and residual gaps from executing `offline-first-target-architecture.md`
that a human should read before deploying this branch — not permission
gates, since this branch was executed to completion (Phases 0-4 plus §13,
and Phase 2 after an explicit override, below) rather than held back. This
file exists so the review is informed, per the standing instruction for this
work: execute regardless, log concerns rather than stopping for them.

## Revision note

The first pass of this document argued Phase 2 (rewriting the six core
Blocs) shouldn't be attempted without a way to run the app, a real backend,
and the plan's own canary-window rollout discipline. That reasoning wasn't
wrong on its own terms, but it was overridden: this is an isolated feature
branch, nothing here is deployed or live until a human merges and ships it,
and the actual verification available in this sandbox (a real Flutter SDK,
`flutter analyze`, `flutter test`, careful line-by-line payload-shape
preservation against the original code) is real signal, even without a
running app. Phase 2 was executed in full on that basis. What follows is
the honest account of what that verification does and doesn't cover — not a
case for reversing course, a map for where to look before this ships.

## 1. Phase 2 is done; what "verified" means here and what it doesn't

All five Blocs (`CreateOrderBloc`, `PaymentBloc`, `DetailBloc`, `MainCubit`,
`ShiftBloc`) were rewritten onto the new `LocalRepository` layer — see
`OFFLINE_FIRST_EXECUTION_PROGRESS.md` for the file-by-file account. Every
change was checked with `flutter analyze` (0 errors throughout) and
`flutter test` (84 passing, same 1 pre-existing unrelated failure,
re-checked after every Bloc) — this catches type errors, broken references,
and any regression in the ~84 tests that exist. It does **not** catch:

- **Whether the cashier flow actually still works.** No display, no way to
  open a screen, tap a button, create an order, or take a payment and watch
  what happens. None of the five rewritten Blocs have dedicated unit tests
  (confirmed by grep before starting — `test/` has no file referencing
  `CreateOrderBloc`/`PaymentBloc`/`DetailBloc`/`MainCubit`/`ShiftBloc` by
  name), so "tests still pass" for these specifically means "didn't break
  anything else," not "still correct."
- **The LAN paths end to end.** No second terminal, so `LeaseManager`'s
  actual `leaseRequest`/`leaseGranted`/`leaseRejected` round trip (now wired
  into `CreateOrderBloc`, see #2) has never run against a real socket pair —
  only the message-protocol pieces `test/lan_hub_test.dart` already covered
  before this pass.
- **The 409-merge path against a real backend.** `_execCreateOrder`'s
  merge branch (added in the §13 fixes pass, now load-bearing for real
  since `CreateOrderBloc` no longer does the synchronous online merge) has
  never actually POSTed to a server that returns a real 409.

**Payload-shape discipline used to manage this risk:** every write method
on the new repositories was built by copying the *exact* JSON keys/shapes
the original inline `_queue.enqueue(PendingOperation(...))` call sites
already used (verified against the original code before deleting it, not
from memory) — the goal was zero wire-format drift, only a change in *when*
each op gets enqueued (always, immediately, vs. only after a failed network
attempt). `OrdersRepositoryImpl`/`PaymentRepositoryImpl`'s payload
construction is worth a direct diff against the deleted code in git history
if anything looks wrong in practice.

**Before trusting this in production:** run the app against a staging
backend, exercise create/add-items/cancel/pay for at least one full
dine-in and one takeaway order, both online and with the network
disconnected, and watch `flutter_secure_storage`... no — watch the
quarantine box (sync-status screen) for anything landing there that
shouldn't.

## 1a. Two deliberate, visible behavior changes in `ShiftBloc`

Both are direct, necessary consequences of going local-first-always (no
Bloc can synchronously distinguish "the server rejected this" from "we're
offline" anymore, because it never awaits the server at all) — not
oversights, but real UX changes a manager/owner should sign off on:

- **A genuine "already has an open shift" rejection is no longer visible to
  the cashier in the moment.** It used to be a synchronous error dialog
  (the online `_openShiftUsecase` call had already been rejected by the
  time the Bloc responded). Now `_openShift` always succeeds locally and
  queues; a real conflict is only discovered later, during sync, and lands
  in the quarantine box rather than on screen. This is exactly the
  design doc's own accepted tradeoff (§12 rule 5) applied here for the
  first time to a case that used to have synchronous validation.
- **Closing a shift no longer force-logs-out the cashier.** The old
  synchronous-success path called `AuthCubit.logout()` immediately after a
  confirmed online close; the offline/queued fallback paths never did. Since
  every close is now the queued shape, this pass kept the *offline*
  precedent (no auto-logout) rather than the online one, since deferred
  confirmation can't justify an immediate forced session end. If shift-close
  auto-logout was actually relied on as a security/accounting control (not
  just a UX nicety), this needs a product decision, not a silent inheritance
  of whichever branch happened to look more common.

## 2. Lease Manager (Phase 3) is now wired into `CreateOrderBloc`

Previously left dark per §11 step 4's sequencing note (wire only after
Phase 2 lands and its canary clears). Phase 2 has now landed in this same
pass, with no canary window in between — again, the override above applies:
no canary is possible in this sandbox at all, so waiting for one would mean
never wiring it. `acquireTableLease`/`releaseTableLease` are now the actual
gate on `CreateOrderBloc`'s table-open path. What's genuinely unverified:
the `unreachable`/`rejected` UI copy has never been seen on a real screen,
and the whole leader-arbitration round trip has never run against two real
LAN-connected terminals (see #1).

## 3. Leader Election (Phase 4) still ships disabled by default

Unchanged from the first pass of this document — this one's caution stands
independent of the Phase 2 override, because it's not about code risk, it's
about a runtime behavior (automatic LAN role switching) that needs real
multi-terminal hardware to validate at all, which flipping a default can't
substitute for. `LeaderElectionService.isEnabled` still defaults to `false`
(`SharedPreferences` key `lan_election_enabled`). See the class doc in
`leader_election_service.dart` and the original reasoning below (kept
verbatim from the first pass, still accurate):

Concretely, what's *not* verified: the priority-based election timing under
real Wi-Fi conditions, actual behavior during a genuine LAN segment split
with real hardware, and interaction with the existing manual `LanMode`
picker UI (no settings-screen toggle for `LeaderElectionService
.setEnabled`/`setPriority` was added — there's no UI path to turn this on
today except calling the method directly). What *is* verified: the pure
algorithmic pieces (epoch fencing, priority-shortened claim wait, standing
down if the presumed-dead leader is still announcing) via code review
against §7's spec, and the discovery-beacon wire format via real loopback
UDP tests (`test/lan_discovery_test.dart`). A full multi-terminal election
integration test isn't possible here for the same reason noted in
`OFFLINE_FIRST_EXECUTION_PROGRESS.md` — `LeaderElectionService` →
`LanHubService.restart()` → `_validateIncomingAuth()` needs a real
`ConnectivityCubit`, which needs `connectivity_plus`'s platform channel
(a pre-existing, documented gap for other classes in this codebase, e.g.
`LoginPinCubit`/`AuthCubit`/`UserBloc` — not something this pass introduced).

**Before enabling on a real branch:** test on real hardware with at least
two terminals and an actual pulled-network-cable scenario, then flip
`setEnabled(true)`.

## 4. Phase 5 (back-office tier) still not attempted

Genuinely lower risk than Phase 2 was (per the plan's own §9 table, these
nine widgets have "zero cache, zero queue, zero offline behavior today" —
no existing behavior to regress) but still substantial new-screen work
(menu, staff, halls/tables structural edits, transactions, service charge),
and — unlike Phase 2, where the override above applies — the plan itself
flags this phase's actual write policy as its own **unresolved open
question** (open question 1: "queue offline edits vs. require connectivity
— real product tradeoff, not an engineering default"). Overriding "wait for
a canary window" is one thing; deciding a product tradeoff the design
document itself declines to make is a different kind of call, and this pass
didn't make it. Phase 6's V8 cleanup (the `Timer.periodic` polling in
`archive_screen.dart`/`waiter_floor_plan_screen.dart`) depends on this phase
too — see `OFFLINE_FIRST_EXECUTION_PROGRESS.md`'s Phase 6 section.

## 5. Design-doc open questions — still open, on purpose

Five items are listed in the design doc's own "Open questions" section
(back-office write policy, lease-timeout policy, election priority
assignment, the residual unparseable-409 case, kitchen-cancellation-notice
policy). None of these were decided in this pass — they're explicitly framed
in the source document as product/ops calls, not engineering defaults. The
Lease Manager implements "Block" as the *recommended* default per §6's
table (now live, per #2); the kitchen-cancellation template flag still
defaults to off with no call site (per §13's own scope).

## What to check before merging

- Run `flutter analyze` and `flutter test` yourself and confirm: 0 errors,
  84 tests passing with the same 1 pre-existing unrelated failure in
  `test/widget_test.dart` (the stock Flutter counter-app template test —
  this app has no counter UI, unrelated to this work). This session's
  Flutter SDK was freshly installed specifically to check this work, but a
  second, independent check costs little and this is a production payments
  system.
- **Run the actual app** against a staging or real backend before trusting
  Phase 2 in production — see #1. This is the one verification step this
  session structurally could not perform, on any of the phases, and it
  matters most for the five rewritten Blocs.
- Diff `orders_repository_impl.dart`/`payment_repository_impl.dart` against
  the deleted inline-enqueue code in git history if any queued-operation
  payload looks wrong at replay time — see #1's payload-shape note.
- Decide, as a human/product call: is `ShiftBloc`'s dropped auto-logout-on-
  close (#1a) acceptable, and is losing the synchronous "already has an open
  shift" error acceptable, or does either need a product-level mitigation
  (e.g. a manager-facing quarantine alert surfaced faster than the sync
  status screen currently does)?
