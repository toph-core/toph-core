# Offline-First Target Architecture — Execution Progress

Tracks execution of `offline-first-target-architecture.md` (the plan document
committed just before this work started). Companion file: `EXECUTION_CONCERNS.md`
— read that one for anything that needs a human decision or a hardware/field
validation step before going further. This file is a status log only.

**Execution model:** every phase below was implemented directly in the
codebase (not just described), verified with a real Flutter SDK installed
into this session (`flutter analyze` + `flutter test`), and committed. Phases
not marked done were deliberately not attempted in this pass — see
`EXECUTION_CONCERNS.md` for why, phase by phase.

## Verification environment

This sandbox had no Flutter/Dart SDK preinstalled. Flutter 3.44.9 (Dart
3.12.2, stable channel) was cloned and set up specifically to verify this
work — `flutter analyze` and `flutter test` were run after every phase below,
not just at the end. Baseline before any change: `flutter analyze` → 71
pre-existing info/warning-level issues, 0 errors; `flutter test` → 82 passing,
1 pre-existing unrelated failure (`test/widget_test.dart`'s default Flutter
counter-app template test — this app has no counter UI at all; that test
predates this work and is unrelated to it). Final state after every phase
below: `flutter analyze` → 75 issues (all 4 new ones are
`use_null_aware_elements` style infos on a map-literal pattern already used
elsewhere in this codebase, e.g. `lan_hub_message.dart`'s `toJson()`), 0
errors; `flutter test` → 84 passing (2 new tests added), same 1 pre-existing
unrelated failure, no regressions.

## Phase 0 — Local Database facade — DONE

`lib/core/database/local_database.dart` (new). Typed, reactive, one-`Box`-
per-entity Hive storage with a uniform `watchX()`/`getX()`/`saveX()` surface
built on `Box.watch()`, per §1.2/§8 Phase 0. Covers every entity §1.2 lists:
categories, departments, halls, tables (+ `watchTablesForHall`), users, goods
(all + per-category), ingredients, compounds, transaction groups, service
charge, printer settings, order/bill detail, menu images. Purely additive —
`CacheService` untouched, nothing read from it yet at this point in the
migration. Registered in `di.dart` as `LocalDatabase.init()` →
`inject.registerSingleton`.

## Phase 1 — Sync Engine full hydration + import-boundary CI check — DONE

`lib/core/sync/sync_engine.dart` extended: `_hydrateReferenceData` now also
writes categories/departments/halls/tables/users into `LocalDatabase` (not
just `CacheService`, as before), and five new hydration passes cover every
entity §1's SyncEngine row flagged as having no path at all — ingredients,
compounds, transaction groups, printer settings, service charge (via the
same `inject<UserBloc>()` branch-id pattern `LanHubService` already uses),
goods-by-category (looped per hydrated category), order/bill detail for
currently-busy tables (`getOrderIdWithTableId` → `getOrderItemsRaw`), and
menu images (`MinioService.getImageByObjectName`, skipping object names
already cached). `tick()` also now mirrors `CacheService`'s existing
`prefetchAllGoods` result into `LocalDatabase` (no new network call). Each
new hydration helper is independently try/caught so one entity's failure
doesn't block the others.

`scripts/check_import_boundary.sh` (new) + `.github/workflows/analyze.yml`
(new): grep-based check per §8 Phase 1 — fails CI if
`DioClient`/`ListAPI`/`Dio` appears under `lib/features/**/presentation/**`
or `lib/features/**/cubit/**`. One exemption today:
`lib/features/view/main/presentation/cubit/detail` (the only such file that
currently violates it — confirmed by grep before writing the check), to be
removed when/if `DetailBloc` is rewritten in a real Phase 2 pass.

## Phase 2 — Rewrite six core Blocs — NOT DONE

No Bloc code was rewritten. See `EXECUTION_CONCERNS.md` #1 for why, and what
exists instead (nothing — no scaffolding repositories were built either, to
avoid an unconsumed near-duplicate of live order/payment logic).

## Phase 3 — Lease Manager — DONE (built, not wired to any live call site)

- `lib/core/services/lan_hub/lan_hub_message.dart`: new message types
  `leaseRequest`/`leaseGranted`/`leaseRejected`/`leaseRelease`, new fields
  `leaseTerminalId`/`leaseHeldBy`, wired through `toJson`/`tryParse`.
- `lib/core/services/lan_hub/lan_hub_server.dart`: `LanLeaseHandler`/
  `LanLeaseReleaseHandler` typedefs, `onLeaseRequest`/`onLeaseRelease`
  callbacks in `start()`, dispatch in `_handleRequest` (directed RPC, same
  shape as the existing `relayOp` handling — answers only the sender, never
  broadcasts to other followers).
- `lib/core/services/lan_hub/lan_hub_client.dart`: `requestLease()` (send +
  wait for correlated `leaseGranted`/`leaseRejected`, 5s timeout) and
  `releaseLease()` (fire-and-forget), mirroring the existing `relayOp`
  pattern.
- `lib/core/services/lan_hub/lan_hub_service.dart`: public `requestLease`/
  `releaseLease` methods delegating to the client; server-mode `init()` now
  wires `onLeaseRequest`/`onLeaseRelease` to `inject<LeaseManager>()` (lazy
  resolution, same DI-ordering pattern already used for `MainRepository`/
  `UserBloc` elsewhere in this file).
- `lib/core/services/lease/lease_manager.dart` (new): `LeaseManager` class
  implementing §6 exactly — durable check against `LocalDatabase`'s
  replicated table status, leader-only in-memory ephemeral-claim map with a
  5s TTL, `acquireTableLease`/`releaseTableLease` for the solo/server/client
  cases, leader-side `handleLeaseRequestAsLeader`/`handleLeaseReleaseAsLeader`
  for the wire protocol. Registered in `di.dart`.
- **Not wired into `CreateOrderBloc`'s table-open path.** §11 step 4 is
  explicit that this wiring should land only after Phase 2 has rewritten that
  same Bloc and its own canary window has cleared — Phase 2 didn't happen in
  this pass, so per the plan's own sequencing this stays dark. See
  `EXECUTION_CONCERNS.md` #2.

## Phase 4 — Leader Election / automatic failover — DONE (built, disabled by default)

- `lib/core/services/lan_hub/lan_discovery_service.dart`: `HubAnnouncement`
  gained optional `role`/`priority`/`epoch`/`terminalId` fields;
  `startAnnouncing` gained an optional `heartbeatExtra` callback invoked
  fresh every tick, so the beacon doubles as §7's heartbeat channel without a
  second UDP mechanism. Backward compatible — an announcer that never passes
  `heartbeatExtra` produces the exact same wire payload as before.
- `lib/core/services/lan_hub/leader_election_service.dart` (new):
  `LeaderElectionService` — epoch persisted in `SharedPreferences`
  (survives restart, per §7), priority persisted (random 1–999 fallback the
  first time, `setPriority` for a future settings screen — design doc's own
  "Open questions" #3 leaves this unresolved, so the simpler option was
  picked rather than deciding it), bully-algorithm election with jitter
  (`_startElection`/`_claimLeadership`), epoch fencing on every heard
  announcement (`_onAnnouncement`/`_adopt`) including standing down mid-
  election if the presumed-dead leader turns out to still be announcing at
  the same epoch, non-blocking startup listen window, automatic
  `LanHubService.setMode`/`setServerIp`/`restart()` on both becoming leader
  and adopting one.
- `lib/core/services/lan_hub/lan_hub_service.dart`: `init()`'s `server`
  branch now skips the old warn-only `_watchForConflicts()` when election is
  enabled (both would otherwise try to bind the same UDP port).
- Registered in `di.dart`, `start()` called at boot — but `start()` itself is
  a no-op unless `LeaderElectionService.isEnabled` (a
  `SharedPreferences`-backed flag, default **false**). See
  `EXECUTION_CONCERNS.md` #3 for why this ships off by default.
- Tests: `test/lan_discovery_test.dart` gained two tests covering the new
  heartbeat fields (propagation, per-tick updates, backward compatibility).
  Full multi-terminal election scenarios (priority ordering, epoch fencing
  under simulated leader death) are **not** covered by an automated test —
  see `EXECUTION_CONCERNS.md` #3 for why and what this codebase's own
  existing precedent for this gap is.

## Phase 5 — Back-office tier — NOT DONE

Not attempted — see `EXECUTION_CONCERNS.md` #4.

## Phase 6 — Delete dead code — NOT DONE

Not attempted. Per the plan's own §8: "last, and only after each
corresponding phase's canary window has fully cleared, not opportunistically
mid-migration" — Phases 2 and 5, which is what would make this code dead,
didn't happen in this pass, so nothing here is actually dead yet.

## §13 gap fixes — DONE (both)

- `lib/core/services/offline_queue/offline_queue_service.dart`:
  `_execCreateOrder` now has a 409-merge branch (`_mergeCreateOrderConflict`)
  mirroring the online path's existing merge in `create_order_bloc.dart` —
  extracts the winning order id via the already-shared
  `extractExistingOrderIdFromConflict`, generates fresh `client_item_id`s at
  merge time, re-submits the bundled items via add-items instead of silently
  dropping them into quarantine. Unparseable-409 residual (no order id
  findable) falls through to the existing `_dropped()`/quarantine path,
  unchanged, per the design doc's open question 4.
- `lib/core/service/printer/receipt/kitchen_receipt_builder.dart` +
  `printer_service.dart`: `cancelled: bool` (default `false`) added to
  `buildWithHeader`/`printKitchenReceiptFor`/`printKitchenReceipt`, swapping
  the printed header. Template-only, by design — no new call site passes
  `true`, matching the plan's own open question 5 (deciding *when* a
  cancellation notice should print is an explicitly unresolved kitchen-
  operations policy question, not something this pass decides).
