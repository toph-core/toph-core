# Offline-First Target Architecture — Execution Concerns

Companion to `OFFLINE_FIRST_EXECUTION_PROGRESS.md`. These are the judgment
calls and gaps from executing `offline-first-target-architecture.md` that a
human should read before treating this migration as further along than it
is. Nothing below blocks what *was* shipped (Phases 0/1/3/4, §13) — all of
that is additive, analyzed clean, and test-covered. These are about what
comes next.

## 1. Phase 2 (rewrite the six core Blocs) was not attempted — this is the
   big one

The plan's own §11 describes Phase 2 as "the only phase touching live
money/order paths," to be done "one Bloc at a time, each behind its own
flag... reviewed against the old implementation line-by-line," with
`CreateOrderBloc` going first, a canary window clearing before `PaymentBloc`,
and so on. That process assumes a human watching a real deployment between
steps.

This session had none of the preconditions that process depends on:

- **No way to run the app.** No display, no way to open a screen, tap a
  button, create an order, or take a payment and see what happens. Every
  other phase in this pass was verified with `flutter analyze`/`flutter
  test`; Phase 2's actual correctness bar — "does the cashier flow still
  work" — isn't something either of those tools checks.
- **No real backend, no printer hardware, no second terminal.** Can't
  exercise the 409-merge path, the LAN relay path, or a real table-open race
  end to end.
- **No canary window.** The plan's own rollout discipline for this exact
  phase requires field time between each Bloc before the next one is
  touched. A single autonomous pass can't provide that even in principle.

Given that, rewriting `CreateOrderBloc`/`PaymentBloc`/`DetailBloc`/
`MainCubit`/`ShiftBloc` — deleting their existing `await usecase.call()` /
`isOnline` branches and replacing them with untested new code, in a live POS
system that handles real payments — was judged too risky to do blind. I did
not build partial scaffolding for this either (no `OrdersRepository`/
`PaymentRepository` classes) — an unconsumed near-duplicate of the existing
order/payment payload logic (client-generated ids, idempotency keys, the
exact JSON shapes `CreateOrderRequestModel`/`_handleOfflineOrder` already
get right) would just be a second place for that logic to drift out of sync
with the real thing, for zero behavioral benefit since nothing would call it.

**What would need to be true to safely do this:** a way to run the app
against a real or staging backend, ideally two terminals for the LAN paths,
and — matching the plan's own words — willingness to ship one Bloc at a time
with a real observation window before the next.

## 2. Lease Manager (Phase 3) is built but not wired to any call site

This one follows directly from #1, not a separate judgment call: §11 step 4
says explicitly that wiring `LeaseManager.acquireTableLease` into
`CreateOrderBloc`'s table-open path should happen "only after Phase 2's
rewrite of that same Bloc has already proven stable, not in the same
change." Phase 2 didn't happen, so per the plan's own sequencing this stays
dark. The component itself (`lease_manager.dart`, the new LAN message types,
server/client wiring) is real, registered in DI, and analyzed clean — it's
just inert until something calls `acquireTableLease`.

## 3. Leader Election (Phase 4) ships disabled by default

`LeaderElectionService.isEnabled` defaults to `false` (a
`SharedPreferences` flag, `lan_election_enabled`). The plan's §11 step 5
says this phase "ships behind the existing manual `LanMode` toggle as a
fallback until its own canary window clears" — I read that as: the new
automatic-failover behavior needs field validation before it's what actually
runs on a branch's terminals, and the existing manual toggle (already in
production, already trusted) is what should keep working unconditionally
until then. This sandbox cannot provide that field validation — no two real
terminals, no real network partition to test against, no way to watch what
happens when a real leader terminal is powered off mid-shift.

Concretely, what's *not* verified: the priority-based election timing under
real Wi-Fi conditions, actual behavior during a genuine LAN segment split
with real hardware, and interaction with the existing manual `LanMode`
picker UI (I did not add a settings-screen toggle for
`LeaderElectionService.setEnabled`/`setPriority` — there's no UI path to turn
this on today except calling the method directly, which is itself another
layer of "this needs a deliberate decision before it does anything").

What *is* verified: the pure algorithmic pieces (epoch fencing always wins
on higher epoch, priority shortens the claim wait, a candidate stands down if
it hears the presumed-dead leader is actually still there) via code review
against §7's spec, and the discovery-beacon wire format via real loopback UDP
tests. I could not write a full multi-terminal election integration test
because `LeaderElectionService` → `LanHubService.restart()` →
`LanHubService._validateIncomingAuth()` needs a real `ConnectivityCubit`,
which (per this codebase's own existing test comments, e.g.
`test/offline_queue_quarantine_test.dart`) needs `connectivity_plus`'s
platform channel — already a documented, pre-existing gap for other classes
in this codebase (`LoginPinCubit`/`AuthCubit`/`UserBloc`), not something new
I introduced.

**Before enabling on a real branch:** read `leader_election_service.dart`'s
class doc, test it on real hardware with at least two terminals and an
actual pulled-network-cable scenario, then flip `setEnabled(true)` — ideally
from a settings-screen control that doesn't exist yet.

## 4. Phase 5 (back-office tier) was not attempted

Lower risk than Phase 2 in one sense (per the plan's own §9 table, these nine
widgets have "zero cache, zero queue, zero offline behavior today" — so
there's no existing behavior to regress, only new behavior to add) but still
substantial new-screen work (menu, staff, halls/tables structural edits,
transactions, service charge), and the plan itself flags the actual write
policy for these screens as its own open question 1 ("queue offline edits vs.
require connectivity — real product tradeoff, not an engineering default").
Given the size of what was already delivered in this pass and that this
phase's own product question (open question 1) is unresolved by the design
doc itself, I stopped here rather than guessing at that tradeoff to unblock
writing code nothing yet depends on.

## 5. Phase 6 (delete dead code) correctly did not run

Not a gap — the plan's own §8 says this phase runs "last, and only after
each corresponding phase's canary window has fully cleared." Since Phases 2
and 5 (the ones that would make `Timer.periodic` polling / the `FutureBuilder`
image fetch / most of `main_repository_impl.dart`'s passthrough methods
actually dead) didn't run, none of that code is dead yet. Deleting it now
would just break currently-working screens for no reason.

## 6. Design-doc open questions — still open, on purpose

Five items are listed in the design doc's own "Open questions" section
(back-office write policy, lease-timeout policy, election priority
assignment, the residual unparseable-409 case, kitchen-cancellation-notice
policy). None of these were decided in this pass — they're explicitly framed
in the source document as product/ops calls, not engineering defaults, and
nothing built here required deciding them (the Lease Manager implements
"Block" as the *recommended* default per §6's table without that being load-
bearing anywhere yet, since it's unwired; the kitchen-cancellation template
flag defaults to off with no call site).

## What to check before merging

- Run `flutter analyze` and `flutter test` yourself and confirm the same
  baseline this document claims (71→75 issues, 0 errors both before and
  after; 82→84 tests passing, same one pre-existing unrelated failure in
  `test/widget_test.dart`). This session's Flutter SDK was freshly installed
  specifically to check this work, but a second, independent check costs
  little and this is a production payments system.
- Everything in Phases 0/1/3/4 and the §13 fixes is additive — no existing
  Bloc, screen, or executor had its behavior changed for any currently-live
  code path. The only currently-live-path change in the whole pass is
  `_execCreateOrder`'s new 409-merge branch (offline_queue_service.dart) and
  the (currently unused, default-off) `cancelled` parameter on kitchen
  receipt printing — both additive in the sense that the old behavior only
  changes on a path (a duplicate-table-open 409 during offline replay) that
  previously just silently dropped items into quarantine, strictly an
  improvement over the prior behavior, not a new risk to a working path.
