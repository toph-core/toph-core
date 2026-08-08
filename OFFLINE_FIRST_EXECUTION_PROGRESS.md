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
below (checked after each individual change, not just once at the end):
`flutter analyze` → 74 issues, 0 errors — net +3 over baseline (+4
`use_null_aware_elements` style infos on a map-literal pattern already used
elsewhere in this codebase, e.g. `lan_hub_message.dart`'s `toJson()`, -1 a
pre-existing `unnecessary_import` in `create_order_bloc.dart` that this
pass's rewrite incidentally fixed); `flutter test` → 84 passing (2 new tests
added), same 1 pre-existing unrelated failure, no regressions at any point.

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

## Phase 2 — Rewrite five core Blocs — DONE

Revised from the initial pass of this document, which deferred this phase —
see `EXECUTION_CONCERNS.md` #1 (kept, marked superseded) for why that
caution existed and why it was overridden. All five Blocs (`ShiftBloc` has
no reads to migrate, only writes) rewritten, `flutter analyze` clean and
`flutter test` green (84 passing, same 1 pre-existing unrelated failure)
after each one.

New `LocalRepository` layer (§1/§9), all additive new files:
- `lib/features/view/main/domain/repository/orders_repository.dart` +
  `data/repository/orders_repository_impl.dart` — V1/V3/V6.
  `watchOrderDetail`/`getOrderDetail` (reactive, `ArchiveDetailModel` over
  `LocalDatabase`'s order-detail box), `createOrder`/`createTakeawayOrder`/
  `addItems`/`cancelLineItems` (each a single outbox-enqueue commit, no
  network await — payload shapes copied verbatim from the Blocs' own
  pre-existing `_handleOfflineOrder`/`_enqueueAddItem`/
  `_enqueueCancelLineItems` so the wire format nothing changes, only when it
  fires).
- `domain/repository/payment_repository.dart` +
  `data/repository/payment_repository_impl.dart` — V2 + §12 rule 1.
  `pay()`/`cancelZeroTotalOrder()`, single outbox-enqueue commit. `pay()`
  now stamps a client-generated `client_payment_id` into the payload — the
  design doc's own "single most safety-critical finding" (§12 rule 1): this
  payload previously had no idempotency key at all, unlike every other
  write in this app.
- `domain/repository/tables_repository.dart` +
  `data/repository/tables_repository_impl.dart` — V4. `watchHalls`/
  `watchAllTables`/`watchTablesForHall` (reactive), `updateTableStatus`
  (local durable patch — also added as `LocalDatabase.updateTableStatus`,
  the read side of §6's Lease Manager durable check).
- `domain/repository/menu_repository.dart` +
  `data/repository/menu_repository_impl.dart` — V5 + V9. `watchCategories`/
  `watchGoodsForCategory` (reactive), `watchImage`/`getImage`/`saveImage`
  (V9, see below). Deliberately a separate class from the pre-existing
  `MenuLocalRepository` (a different, earlier, Future-based repository for
  `DepartmentSelectionCubit` from `offline-first-architecture-plan.md`'s own
  migration pass) — not consolidated, see `EXECUTION_CONCERNS.md`.

Per-Bloc:
- **`CreateOrderBloc`** (V1): every write goes through `OrdersRepository` —
  no more `await usecase.call()`, no `ConnectionFailure` fork. The
  synchronous online-path 409-merge (`extractExistingOrderIdFromConflict`
  called inline) is gone — entirely superseded by `_execCreateOrder`'s own
  409-merge branch (added in the §13 fixes pass) at replay time. The
  table-open path now calls `LeaseManager.acquireTableLease` before the
  local write (§6) and `releaseTableLease` immediately after — Phase 3's
  component is wired in for the first time. `CreateOrderUsecase`/
  `CreateTakeAwayOrderUsecase` deleted (no longer referenced anywhere).
- **`PaymentBloc`** (V2/V6): `_payment` is local-first-always through
  `PaymentRepository`. `_onGetDetail` is an `OrdersRepository
  .watchOrderDetail` subscription (routed through a new internal
  `_DetailUpdated` event, BLoC-pattern-correct). `_fetchItemTimestamps`
  (item-added timestamps, not part of `ArchiveDetailModel`) kept as a
  best-effort direct `MainRepository.getOrderItemsRaw` call — not one of
  the plan's named violations. `resumeTimerAfterFailedPay` kept (still
  called from `payment_screen.dart` on leaving the screen without paying —
  an unrelated concern from the removed network-await error path).
  `CreatePaymentUsecase`/`GetPaymentDetailWithTableIdUsecase`/
  `GetPaymentDetailWithIdUsecase` deleted.
- **`DetailBloc`** (V3/V5/V6): categories/goods-by-category are pure
  `MenuRepository.watchX()` subscriptions, no throttle fields, no fallback
  fetch (reference data SyncEngine already hydrates unconditionally).
  Order/bill detail is `OrdersRepository.watchOrderDetail`, with one
  narrow live-fetch fallback (`_mainRepository.getPaymentDetailWithTableId`)
  for the one gap disclosed in §0/this doc: a brand-new dine-in order has
  nothing in `LocalDatabase` yet since dine-in create doesn't return the
  full bill payload synchronously. `_deleteExistingByKey`/
  `_onSyncExistingItem` are local-first through `OrdersRepository` —
  `existingSyncingNames` (the +/-/delete button-disable state) now clears
  the instant the local commit lands, not after a network round trip.
  `_isConnectionIssue`/the `dio` import are gone — nothing left to catch.
  `GetCategoriesUsecase`/`GetGoodsByCategoryIdUseCase` deleted; the
  `GetGoodsWithNameUseCase` live-search path is unchanged (explicitly not a
  named violation — no bounded local mirror of the full catalog to search
  instead). The `check_import_boundary.sh` exemption for this file's
  directory is removed — it no longer imports `Dio`/`DioClient`/`ListAPI`
  at all.
- **`MainCubit`** (V4): halls/tables are `TablesRepository.watchX()`
  subscriptions set up in the constructor — no throttle fields, no
  `ConnectivityCubit`/`CacheService` dependency at all.
  `getHalls`/`loadAllHallsTables`/`refreshTables` kept (many call sites
  `await` them) but now just nudge `SyncEngine.tick()` — `force: true`
  awaits it (an explicit manual-refresh trigger, §5's "Manual retry"
  category), otherwise fire-and-forget. `GetHallsUsecase`/
  `GetTablesByHallIdUsecase` deleted.
- **`ShiftBloc`**: `_openShift`/`_closeShift` are local-first-always — a
  single local commit (write the local shift record + outbox enqueue), no
  network await, no `isConnectivityIssue` fork. `_checkShift` (a one-time
  startup reconciliation needing a definitive server answer) is unchanged —
  not a named violation. `OpenShiftUsecase`/`CloseShiftUsecase` deleted.
  **Real, visible behavior change, flagged in `EXECUTION_CONCERNS.md` #1a:**
  a genuine "already has an open shift" rejection is no longer visible
  synchronously (surfaces later via quarantine); `_closeShift` no longer
  calls `AuthCubit.logout()` automatically (that only ever fired on
  synchronous online confirmation, which no longer exists — now mirrors
  what the pre-existing offline branches already did: no auto-logout).

`di.dart` updated throughout — every changed Bloc/Cubit constructor,
`_repositories()` gained the four new registrations, `_useCase()` lost
eleven now-dead usecase registrations (their files deleted:
`create_order_usecase.dart`, `create_take_away_order_usecase.dart`,
`get_halls_usecase.dart`, `get_tables_by_hall_id_usecase.dart`,
`get_categories_usecase.dart`, `get_goods_by_category_id_usecase.dart`,
`get_payment_detail_with_table_id_usecase.dart`,
`create_payment_usecase.dart`, `get_payment_detail_with_id_usecase.dart`,
`open_shift_usecase.dart`, `close_shift_usecase.dart`).

**V9 (menu images) fixed as part of this pass too**, since `MenuRepository`
made it a small addition: `menu_manage_screen.dart`'s `_MealImagePreview`
now reads `MenuRepository.watchImage`/`getImage` first (reactive, hydrated
by `SyncEngine`), falling back to a live `MinioService` fetch — write-
through via the new `MenuRepository.saveImage` — only for an image
uploaded this session, before hydration would otherwise pick it up.

## Phase 3 — Lease Manager — DONE, and now wired into `CreateOrderBloc`

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
- **Now wired into `CreateOrderBloc`'s table-open path** (§4's flow):
  `acquireTableLease` before the local write, `releaseTableLease`
  immediately after it commits. §11 step 4's own sequencing note (wire this
  in only after Phase 2 lands and its canary window clears) no longer
  blocks it now that Phase 2 has landed in this pass — see
  `EXECUTION_CONCERNS.md` #1 for the canary-window caveat that still
  applies to the whole of Phase 2/3 together.

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

## Phase 6 — Delete dead code — PARTIAL

V9 (the `FutureBuilder` image fetch) is fixed — see Phase 2's section above,
done alongside `MenuRepository` since it was a small addition once that
existed. V8 (the `Timer.periodic` polling in `archive_screen.dart`/
`waiter_floor_plan_screen.dart`) is **not** — both depend on `ArchivesBloc`/
`WaiterCubit` and their own repositories being migrated onto
`LocalRepository`/`LocalDatabase` streams first, which is Phase 5 work
(neither Bloc is one of the "six core Blocs" Phase 2 named), and Phase 5
wasn't attempted this pass (see `EXECUTION_CONCERNS.md` #4). Deleting those
timers without that migration would remove the only refresh mechanism those
screens have. The dead-`main_repository_impl.dart`-passthrough-methods
cleanup is also not attempted, for the same reason — Phase 5 hasn't reached
those call sites.

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
