# Backend Side: Sync Engine / Leader / Lease Plan

Scope: the in-app sync/leader layer — `SyncEngine`, `OfflineQueueService`, `LeaseManager`,
`LanHubService`, `LeaderElectionService`. This is the machinery allowed to touch the
network; the counterpart client-facing plan (`CLIENT_FACING_OFFLINE_PLAN.md`, repo root)
covers making sure nothing *else* does. Full scope as confirmed: §5 sync triggers, §6
lease, §7 leader election, §12 conflict resolution.

**A note on sources:** `offline-first-target-architecture.md` (and most of the other
planning/audit docs this work was tracked against — `chat.md`,
`offline-first-violations-audit.md`, `EXECUTION_CONCERNS.md`, etc.) were removed from the
tree in your `cleanup` commit (`1a2d4b5`, Aug 8). This plan doesn't restore or depend on
that file — it's built fresh from reading the actual current code, using git history only
to keep the §-numbers below traceable to what that doc used to call them. If you want it
back for reference, it's one `git show 1a2d4b5^:offline-first-target-architecture.md`
away, but nothing here requires it.

## The headline finding

Going in, the expectation (yours and the deleted doc's own status line) was that Leader
Election "does not exist in any form" and Lease Manager was "additive, dark, not wired."
**Neither is true of the code as it stands.** `LeaderElectionService`
(`lib/core/services/lan_hub/leader_election_service.dart`, 252 lines) is a complete
implementation — epoch fencing persisted to disk, priority, heartbeat-piggybacked
liveness, jittered claims, automatic mode failover — registered and auto-started in DI.
`LeaseManager` is fully wired into `CreateOrderBloc`'s table-open path. The §12
conflict-resolution fixes for `createOrder`'s 409-merge and `payOrder`'s idempotency key
are both implemented, with code comments citing this doc's old section numbers directly.

So this plan is mostly **not** "design and build." It's: turn on what's built but inert,
close the specific coverage gaps where a fix landed on one code path but not its
duplicate, add the tests that have never existed for any of this, and make two real
product-scope decisions about things that were never decided.

---

## Current state, by section

| Section | Deleted doc's framing | Actual state |
|---|---|---|
| §5 Sync Triggers | event-primary, several trigger types | Periodic (60s), reconnect-edge, app-startup, and manual-retry triggers all exist. **Local-write → immediate sync is not wired anywhere.** LAN-reconnect → immediate relay is not wired. No leader→follower broadcast message type exists. |
| §6 Lease | additive, not wired | **Fully implemented and wired** into `CreateOrderBloc`. Gap is coverage: `WaiterCubit`'s own create-order path never calls it. Two in-code comments (`lease_manager.dart`, `di.dart`) still say otherwise. |
| §7 Leader Election | does not exist | **Fully implemented**, registered, auto-started — and **disabled by default with zero call sites anywhere that ever set it enabled.** 100% inert in every real build. Also missing the terminal-id tiebreak the doc itself called load-bearing. |
| §12 Conflict Resolution | rule 1 has a gap; `_execCreateOrder` 409-merge unbuilt | Both **fixed** for `CreateOrderBloc`/`PaymentBloc`. **`WaiterCubit`'s parallel payment path has no idempotency key.** Coalescing (rule 4) still unbuilt everywhere, as expected. |

The single recurring pattern across §6, §7, and §12: **fixes and safeguards keep landing on
the `CreateOrderBloc`/`PaymentBloc`/`OrdersRepository` path and not on `WaiterCubit`**,
which is a second, independent, still-online-first-primary order/payment path
(`WaiterLocalRepositoryImpl.createOrder`/`closeOrder` call `Dio` directly and only
fall back to the outbox on a connectivity failure). `WaiterCubit`'s rebuild is already
scoped as item 5 in `CLIENT_FACING_OFFLINE_PLAN.md`; finishing that closes three
separate "backend" gaps below as a side effect. Treat the two plans as coupled on this
point, not independent.

---

## §5 — Synchronization Triggers

**Gap 1 — local write never triggers a sync pass.** Checked every `enqueue()` call site
(`OrdersRepositoryImpl`, `PaymentRepositoryImpl`, `ShiftBloc`, `WaiterCubit`): none call
`SyncEngine.tick()` afterward. In the common online case, a newly-placed order can sit in
the outbox up to 60s (the periodic timer's interval) before it syncs, unless a reconnect
or manual refresh happens to land first. **Fix:** fire `unawaited(syncEngine.tick())`
right after `enqueue()` at each of those call sites. Safe to call liberally —
`tick()` already has a re-entrancy guard (`_tickRunning`) and `OfflineQueueService`
already has exponential backoff or consecutive-failure state, so an extra call when a
sync is already in flight or backing off is a no-op, not a storm.

**Gap 2 — LAN reconnect doesn't trigger an immediate relay.** `LanHubClient` already
exposes connection-state changes (`onClientConnectionChanged`), but nothing subscribes to
call `tick()` when a follower's LAN link to the leader comes back — it waits for whatever
trigger fires next. **Fix:** subscribe to that stream inside `SyncEngine` itself and call
`tick()` on reconnect, same shape as the existing internet-reconnect handling.

**Structural note, not a functional gap:** the internet-reconnect and app-startup
triggers currently live in `app_scaffold.dart`'s `StatefulWidget` lifecycle, not inside
`SyncEngine`. Worth moving into `SyncEngine` itself while touching this area, so all
trigger logic is in one place — lower priority than the two gaps above, bundle it in if
convenient rather than as a separate pass.

**Gap 3 — no leader→follower reference-data broadcast.** Today, a follower only refreshes
categories/menu/tables/etc. when *it itself* has internet — the leader never pushes deltas
to followers over LAN. `LanHubMessageType` has no message variant for this at all.
**This is a real design/build item, not a wiring fix** — a new message type, leader-side
fan-out, follower-side apply logic. **Flagging as an open question, not decided here:** is
this actually needed, or is "every terminal independently hydrates when it has its own
internet" an acceptable model for how these venues are actually networked? If most
terminals have their own direct internet most of the time, this is low-value work; if
LAN-only followers (no direct internet, relying entirely on the leader) are a real
deployment shape, it's necessary. Confirm before scoping it in.

## §6 — Table Lease

Mostly nothing to build — it's implemented and wired. Concrete items:

- **`WaiterCubit.createOrder` never calls `LeaseManager` at all** — a second table-open
  path that isn't gated against the same double-booking race `CreateOrderBloc`'s call is
  there to prevent. **No new backend code needed for this** — it's already covered by the
  Waiter rebuild in the client-facing plan (item 5), since that rebuild reuses
  `OrdersRepository.createOrder`, which already goes through the lease. Listed here only
  so it isn't lost track of as "someone else's problem" — it's this plan's gap too, just
  closed by the other plan's work.
- **Two stale doc comments** claim the lease isn't wired: `lease_manager.dart:22-28` and
  `di.dart:150-152`. Fix while touching either file — correct or delete them, they'll
  mislead the next person who trusts the class doc over the call site.
- **Coordination note with the client-facing plan:** that plan's carve-out #2 comments out
  the one real caller of `acquireTableLease` (`create_order_bloc.dart:123`) until the
  double-booking race is picked back up as its own piece of work. Once that lands,
  `LeaseManager` becomes exactly as "wired but inert" as `LeaderElectionService` is today.
  That's fine and expected — just don't read "no active caller" as a regression if you
  come back to this section later and find it quiet.
- **No test coverage exists** (`lease_manager_test.dart` doesn't exist). Real, low-risk,
  independent-of-the-UI-carve-out work: solo-mode arbitration, durable-check against
  `LocalDatabase`, ephemeral-claim TTL expiry, client-mode round trip against a fake
  `LanHub`, the unreachable/timeout branch. Worth doing regardless of whether the UI is
  currently calling it, since it'll matter again once the client side re-enables it.

## §7 — Leader Election

Reframe from "build" to "expose, tiebreak, and test something that already exists but has
never run against real hardware, because nothing has ever turned it on."

- **Gap 1 — inert by default, no enable path.** `isEnabled` reads a SharedPreferences
  flag defaulting to `false`; grepped every call site of `setEnabled`/the pref key across
  `lib/features/**` — there are none. The settings screen that shows LAN/hub status
  (`sync_status_section.dart`) reads `LanHubService.mode` directly and has no reference to
  `LeaderElectionService` at all. **Open product question, not decided here:** should this
  be a manual per-venue settings toggle, or default-on once it's been tested? This governs
  which terminal thinks it's the leader — genuinely bigger blast radius than the other
  items in this plan, so it deserves an explicit answer rather than a default guess.
- **Gap 2 — no terminal-id tiebreak.** On an equal-epoch announcement from a different
  terminal, `_onAnnouncement`'s equal-epoch branch just stands down / records the peer's
  IP — it never compares terminal IDs. Two candidates that both compute the same new
  epoch and claim before hearing each other land exactly here, with no deterministic
  winner. **Fix:** add a deterministic comparison (e.g., terminal ID string ordering)
  before standing down in that branch, so a genuine simultaneous-claim collision resolves
  the same way on both sides instead of however timing happens to fall out.
- **Gap 3 — zero tests.** No `leader_election_test.dart`. Given this code has never been
  exercised against real multi-terminal conditions (nothing has ever enabled it), this is
  the highest-priority item in this whole section — write it, and use it to validate the
  tiebreak fix above, *before* any enable-path decision gets acted on. Turning this on for
  the first time in a real venue without test coverage on epoch fencing and mode failover
  is the kind of thing that goes wrong in front of a customer, not in CI.
- **Sequencing note:** because this decides `LanMode` (server/client) that both
  `LeaseManager` and `SyncEngine` branch on, recommend it's the *last* thing enabled of
  everything in this plan, and behind a staged rollout (one pilot multi-terminal venue)
  rather than a global flag flip.

## §12 — Conflict Resolution

- **`WaiterCubit._enqueueCloseOrder`'s payload has no idempotency key.**
  `PaymentRepositoryImpl.pay()` already bakes in `client_payment_id: generateUuidV4()`
  (citing this doc's old §12 rule 1 in its own comment) — `WaiterCubit`'s parallel
  pay/close-order path (`waiter_cubit.dart`, payload built around line 567-579) carries no
  such field. A retried `payOrder` from the Waiter screen has no dedup key server-side.
  **Fix:** add the same `client_payment_id` field to that payload, generated once and
  persisted the same way. Small, precise, low-risk — good candidate to do first in this
  section.
- **Coalescing (rule 4) is unimplemented everywhere**, as expected — every `enqueue()`
  call site uses a timestamp-based unique key (`OfflineQueueService.newId()`), never a
  deterministic `"update:{tableId}:{itemId}"`-style key, so repeated rapid edits to the
  same logical thing enqueue N separate ops instead of coalescing to one. **None of the
  current 7 operation types obviously need this today** (they're mostly one-shot events,
  not repeated-edit-of-the-same-field operations) — but the client-facing plan's Table
  Timer rework introduces start/pause/resume ops, which are exactly the shape that would
  benefit (a cashier tapping pause/resume rapidly shouldn't enqueue a growing pile of
  ops). **Recommendation:** build the mechanism now (an optional deterministic-key
  parameter on `enqueue()`, replacing-not-appending when a matching key is already queued
  and unsynced) so it's ready when the Table Timer ops land, rather than bolting it on
  under time pressure later.
- **No per-operation retry tracking.** `PendingOperation` has no `retryCount`/
  `lastAttempt` fields — only global state (`_consecutiveFailures`, one timestamp) lives
  on `OfflineQueueService`. A single stuck op and a healthy queue with one new op look the
  same from the outside. **Fix (medium priority, mostly observability):** add
  `retryCount`/`lastAttempt` to `PendingOperation`, increment per-op on failure, and
  optionally feed a "N consecutive failures on this specific op" rule into the existing
  quarantine path as a second trigger alongside the current terminal-error classification.

---

## Suggested sequencing

1. **Small, precise, do first:** `WaiterCubit` payment idempotency key; local-write →
   `tick()` wiring (§5 gap 1); correct the two stale lease doc comments;
   `lease_manager_test.dart`.
2. **Still self-contained, slightly bigger:** LAN-reconnect → `tick()` wiring (§5 gap 2);
   terminal-id tiebreak fix; `leader_election_test.dart` (write this before touching
   anything about enabling election in step 4).
3. **Needs a product answer before scoping further, not before starting the section:**
   leader→follower reference-data broadcast (§5 gap 3) — confirm it's actually needed
   first; coalescing mechanism on `enqueue()`; per-op retry tracking.
4. **Last, deliberately:** Leader Election enable path — settings toggle vs. default-on is
   an open decision, and whichever way it's answered, ship it behind a staged rollout
   (one pilot venue), only after step 2's test coverage exists.
5. **Shared with the client-facing plan:** the `WaiterCubit` rebuild there closes this
   plan's lease-coverage and payment-idempotency gaps for the Waiter screen as a
   byproduct — sequence that work with awareness of both documents, not just one.

This is a plan document only — nothing listed above has been implemented.
