# EXECUTION_CONCERNS — CLIENT_FACING_OFFLINE_PLAN.md execution notes

Written during the execution of `CLIENT_FACING_OFFLINE_PLAN.md` (all items,
per product sign-off: box scoping as proposed, full timer conversion, waiter
rebuild, item-7 exclusions accepted). Existing code comments from earlier
phases already reference a file by this name that was never on this branch —
this file now also serves as that reference target.

Nothing here blocked execution. These are the tradeoffs, judgment calls, and
cross-side gaps that someone should read before treating this branch as done.

---

## 0. Environment caveat — code not compiled

The execution environment has **no Flutter/Dart toolchain**: nothing was
compiled, analyzed, or test-run. Consequences:

- `pending_operation.g.dart` (Hive TypeAdapter) was **edited by hand** to add
  the `transferTable` (7) and `timerAction` (8) enum values — re-running
  `build_runner` should produce the same output; verify before release.
- No new freezed models/events were added anywhere (codegen unavailable);
  `UserBloc`'s existing `started` event was repurposed as the local
  profile read instead of adding a new event.
- **Run `flutter analyze` + the test suite before merging.** Syntax was
  written carefully but is unverified by a compiler.
- A full adversarial review pass of the diff was run at the end of
  execution; it found and led to fixes for three defects (a non-exhaustive
  `PendingOperationType` switch in `sync_status_section.dart`, a leaked
  local timer record on waiter-side close, and the brand-switch wipe
  missing the `pos_local_active_shift` prefs record). No other
  compile-level or DI mismatches were found by that pass — but it is not a
  substitute for the analyzer.

## 1. Table Timer — the consciously traded-away guarantee (plan §2)

Signed off explicitly, but restating what was given up:

- **Billing truth is now local-first.** Elapsed time / amount due shown on a
  terminal can disagree with the server and with other terminals until
  `SyncEngine._hydrateTableTimers` reconciles. The old repository's doc
  comment ("cloud is the metering source of truth") described a real
  guarantee; it is gone.
- **Replay skew.** A queued start/pause/resume replays whenever connectivity
  returns; the server prices intervals by *its own* receive time, so the
  server-billed interval differs from what the terminal showed. A long
  offline pause can bill very differently server-side.
- **Stale timer actions quarantine noisily.** A replayed pause on a timer the
  server already closed returns 4xx → the op lands in the quarantine box for
  manual resolution.
- **Offline pricing is single-segment.** The local engine prices all local
  seconds at the record's `price_per_hour`. A transfer between
  differently-priced time-based tables *while offline* would misprice —
  currently transfer of running timed orders offline should be considered
  unsupported.
- **Timers started on another terminal** appear here only after a hydration
  pass (needs connectivity). Fully-offline multi-terminal timer visibility
  would need LAN relay of timer state (not built; candidate follow-up on the
  LAN hub).

## 2. Login retention rule — decisions the approved table didn't cover (plan §1)

The approved classification named specific boxes. Boxes it didn't name were
classified by analogy — **verify with product**:

- `users`, `transactionGroups`, `menuImages` → brand-scoped (wiped on brand
  switch).
- `serviceCharge` (keyed by branchId), `tableTimers`, `orderDetail` → wiped on
  brand switch, kept/additively refreshed on branch switch.
- `printerSettings` → device-scoped, never touched by login (as approved).

Other calls made here:

- **`logoutFromApp` resets first-time setup.** It calls
  `AppTokenStorage.deleteAll()`, which drops `pos_last_auth_context` and
  `pos_is_initialized` — the next login is treated as first-time (prep-phase
  network allowed/required). Session-only `logout()` keeps setup, as before.
- **Brand switch while offline** ends with an empty terminal until
  connectivity returns: the wipe is local and immediate, the refetch needs
  the network. This is inherent to the approved rule (different brand ⇒ clear
  first, fetch fresh).
- **`isPosInitialized` semantics changed** from "brand login happened" to
  "first-time setup fetch actually landed data" — it is set only after the
  login-triggered hydration finds tables/categories locally, and cleared on
  brand switch. It finally has read sites (LoginDataScopeService).

## 3. Session/profile checks moved to the background (plan §1)

- The deactivated-user detection (`UserBloc.getUser`'s definite-rejection
  purge + redirect to login) now fires from `SyncEngine.tick()` — throttled
  to at most once per 5 minutes — instead of on every reconnect edge and
  splash. Worst-case detection latency is therefore ~5 minutes of connected
  time, vs. "immediately on reconnect" before.
- The login response's `user` object is now cached at login time
  (brand-level + per-pincode), so the purely-local profile read works right
  after a first-ever login. If the login endpoint ever stops returning
  `user`, the profile stays empty until the first background `getUser`.

## 4. ShiftBloc._checkShift is local-only — cross-side dependency

The local shift record (`pos_local_active_shift` in SharedPreferences) is now
the *only* startup source. A shift that exists server-side but not locally
(fresh install, cleared storage, shift opened from another tool) will not be
discovered by the client. **The sync side needs a shift-reconciliation pass**
(compare server active shift for this register against the local record in
`SyncEngine`); it does not exist yet. Until it does, the open-shift flow may
be offered on a register the server considers open — the queued `openShift`
replay will then be rejected as terminal (4xx) and quarantined, which is
recoverable but noisy.

(Prior-phase concerns, restated from code comments that pointed at this
file: `_openShift`/`_closeShift` no longer surface synchronous validation
rejections — "already has an open shift" now appears via the quarantine box,
and close-shift no longer auto-logs-out on the old online-success path.)

## 5. Archives — the plan's explicitly flagged cross-side gap (plan §4)

- `SyncEngine._hydrateArchives` still hydrates **only "today, page 1"**.
  Filtered, searched, date-ranged, paginated-beyond-page-1 list views and
  every archive **detail** view still fetch over the network (with the old
  cache fallback). Converting those client-side is pointless until the sync
  side hydrates more — this was scoped by the plan itself as a cross-side
  dependency, not silently "solved."
- What did land: the close-shift screen's 30s force-refetch poll is deleted
  (reactive stream instead), the manual sync button nudges `SyncEngine`
  rather than dispatching a fetch, and the default archive view opens from
  the hydrated snapshot with the network fetch only as a never-hydrated
  first-fill fallback.
- `ArchiveBloc` (singular) remains dead code — registered in DI, no screen
  uses it. Left untouched intentionally.

## 6. Waiter rebuild — behavior deltas (plan §5)

- **List modes are no longer distinct.** `GET /orders/my` vs `GET /orders`
  used to scope the list by waiter vs branch. The local order-detail box has
  no waiter attribution, so both modes serve the same local set (all open
  local bills). Restoring waiter-scoping needs waiter_id captured in the
  hydrated bill rows (sync-side) — flagged, not built.
- **`closeOrder` now goes through `PaymentRepository.pay()`** — one pay path.
  The queued payload includes `apply_service: true` and a
  `client_payment_id`, where the old direct waiter POST sent neither. Verify
  the backend treats `apply_service: true` as equivalent to the old
  field-omitted default for waiter closes.
- **Cancel of a line the server hasn't seen yet** (created this session,
  outbox not drained): the local snapshot's line id is client-side; the
  replayed cancel 404s and is skipped by the existing per-line 404
  tolerance. The local UI state is correct; the server-side net effect
  relies on the add-items op being cancelled-out at replay ordering — worth
  a test once a toolchain is available.
- **Open-orders freshness now equals hydration freshness.** Another
  terminal's new orders appear after the next `SyncEngine` hydration pass,
  not live.
- The plan's open question "is the Waiter screen actively used?" was answered
  "rebuild it" — the usage question itself was never verified in production.

## 7. Payment side calls (plan §6)

- **Item timestamps**: captured locally at commit time (earliest-wins).
  Items added by *other* terminals, or before this build, have no timestamp
  until a sync-side hydration of `order-items` exists (none does — the old
  per-screen network fetch was the only filler and it's deleted). The
  payment screen simply shows no time for those rows.
- **HourPriceBloc was already dead in practice**: no screen dispatches
  `HourPriceEvent.started` (the payment screen receives `hour_amount` via
  navigation arguments). It was converted to read the local timer record
  anyway so any future dispatch is offline-safe. Consider deleting the bloc
  outright instead.
- `GetHourPriceUsecase`, `GetGoodsWithNameUseCase`, `CheckShiftUsecase` are
  now unregistered/unused (dead files kept, same policy as `ArchiveBloc`).

## 8. transferTable (plan §7)

A transfer to a table that another terminal occupies meanwhile is no longer
rejected synchronously — the local commit always succeeds and a genuine
conflict surfaces later via the outbox quarantine. The dialog's old
conflict-specific error messages (`strSelectedTableIsBusy`, …) are unused on
this path now.

## 9. Lease carve-out — and the missing architecture doc (carve-out #2)

`LeaseManager.acquireTableLease`/`releaseTableLease` are commented out (not
deleted) in `create_order_bloc.dart`; the double-booking race on table-open
is **unguarded** until the follow-up work item picks it back up. The
replay-time 409-merge in `OfflineQueueService` remains the only mitigation.

The plan asked for a follow-up note in `offline-first-target-architecture.md`
§6 (which described the lease wait as intentional) — **that file was deleted
from this branch in commit `1a2d4b5` ("cleanup") before this execution**, so
the note lives here instead: *the §6 "one deliberate exception" (lease wait
before table-open) is no longer in effect; table-open is a pure local write
per CLIENT_FACING_OFFLINE_PLAN.md carve-out #2.* If that document is
restored, carry this note into it.

## 10. BACKEND_SYNC_PLAN.md execution notes

Executed after (and on top of) the client-facing plan, with these product
answers: LAN reference-data broadcast **deferred**; leader election exposed
as a **settings toggle, default OFF**; coalescing built as
**mechanism-only** (timer taps all replay); per-op retry tracking is
**observability-only** (no auto-quarantine).

- **Gaps the plan listed that the client-facing execution had already
  closed** (the plan was written against the pre-rebuild code): the Waiter
  payment path now goes through `PaymentRepository.pay()` and therefore
  carries `client_payment_id`; the Waiter online/offline forks are gone.
  One nuance the plan's §6 assumed wrong: the rebuilt
  `WaiterLocalRepositoryImpl.createOrder` enqueues its own payload (to keep
  `waiter_id`) rather than calling `OrdersRepository.createOrder`, so when
  the lease carve-out is reverted the Waiter create path must be routed
  through `LeaseManager` explicitly — noted in `lease_manager.dart`'s class
  doc.
- **§5 deviation from the letter of the plan:** the local-write→tick wiring
  is one central hook inside `OfflineQueueService.enqueue` (lazy-injected,
  guarded), not per-call-site `unawaited(tick())` at ~10 places. Same
  effect, less duplication; `retryQuarantined` gets the nudge for free.
- **§5 startup trigger ordering:** `SyncEngine.start()` is called from
  `initDi()` only *after* `_cubit()` — i.e. after every registration the
  startup tick's hydration pass resolves lazily. (An earlier draft deferred
  the tick by a microtask instead; the review pass showed that didn't clear
  the existing `await PrintQueueService.init` and was replaced by this
  ordering.) Keep `start()` after the registration block if `initDi` is
  ever reshuffled.
- **§5 gap 3 (leader→follower broadcast) deferred** per product answer:
  terminals are assumed to have their own internet; LAN-only followers only
  get reference data via the leader-relayed *outbox*, not reads. If a
  LAN-only-follower deployment appears, this is the first thing to build.
- **§7 tiebreak semantics:** the equal-epoch collision now resolves
  deterministically (lexicographically smaller terminal id wins) only when
  *both* sides announce role `leader`. A long-lived genuine segment split
  still only warns (LanHubService conflict watcher) — unchanged philosophy.
- **§7 toggle runtime caveat:** enabling election at runtime while this
  terminal is in `server` mode with the plain conflict watcher active means
  both want the same UDP port; the discovery socket bind is best-effort
  (logged failure). An app restart after flipping the toggle is the clean
  path — `LanHubService.init()` gates the conflict watcher on the election
  pref at startup. Not engineered around in this pass.
- **§7 rollout:** per the plan, do NOT flip the new toggle outside a pilot
  multi-terminal venue until `leader_election_test.dart` has run green in
  CI and the pilot has soaked.
- **§12 coalescing concurrency edge:** replacement guarantees one op per
  key *in the queue*; an op already handed to an in-flight `syncAll` POST
  can't be recalled, so old+new can both reach the wire in that window.
  Irrelevant while no call site sets a key.
- **§12 retry counters** reset when a quarantined op is manually retried
  (`toRetryable` builds a fresh op) — intentional: a manual retry is a new
  attempt series.
- **Tests written blind:** `lease_manager_test.dart` and
  `leader_election_test.dart` are the first tests these services have ever
  had, but this environment has no Dart toolchain — they have never been
  *run*. Run `flutter test` before trusting them; expect at worst minor
  compile fixes, not design problems.
- **Election `start()` while logged out:** `setEnabled(true)` from the
  settings screen calls `start()`, which no-ops if the user's branch id is
  empty. The toggle then shows enabled but the service is idle until the
  next app start with a logged-in user. Cosmetic, worth a follow-up.

## 11. Accepted exclusions (approved — client-facing plan)

- `service_charge_cubit.save()` — stays intentionally online-only,
  fail-fast (back-office config write).
- Admin menu management (`menu_meals_list_screen.dart`,
  `menu_manage_screen.dart`) — stays online-required by design.
- Manager-PIN verify — already offline-capable, currently dead code, left
  alone (lowest priority, per plan).
