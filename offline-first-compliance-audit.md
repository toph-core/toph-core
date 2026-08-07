# Offline-First Compliance Audit

**Date:** 2026-08-06. **Branch:** `offline-again` (uncommitted working tree at time of audit).
**Method:** independent verification against live source — five parallel research passes each
read the actual current files in full and cross-checked every claim in the pre-existing
`offline-first-architecture-plan.md` (2227 lines, self-authored by a prior work session,
claiming Phases 0-6 complete plus same-day backend idempotency fixes). That document is
**not** taken at face value anywhere below; every finding here is grounded in file:line
citations from a direct read of the current code, not the plan doc's narrative. Where the
plan doc's claims held up, that's noted; where they didn't, that's called out explicitly.

---

## 1. Executive summary

This app has two architecturally distinct tiers, and they are nowhere near the same
maturity level:

- **The core staff-facing POS loop** (take an order, edit it, pay, open/close a shift,
  print) has a genuinely sophisticated offline layer underneath it: a 60s-tick sync
  engine, a 6-operation-type outbox with real exponential backoff + jitter + a
  quarantine mechanism for permanently-failed ops, an authenticated LAN leader/follower
  relay that forwards queued writes to a designated "local server" terminal, a
  persisted print-job queue with claim/lease semantics for shared USB printers, and an
  offline-auth cache with OS-backed secure storage and a "revoked only on confirmed
  server rejection" model. This machinery is real, wired up, and unusually well
  covered by tests for a codebase this size (parallel research pass C confirmed no
  stubs/TODOs/dead code across any of it). Most of Rules 3, 4 (partially), and 5 are
  genuinely met **for this tier**.
- **Everything else** — menu/category/ingredient/compound management, staff
  administration, transactions/finance (Kassa), hall/table structural editing, service
  charge configuration — was apparently never brought into this effort. Nine separate
  Widget `State` classes and one Cubit hold a `DioClient` field directly and perform
  full network CRUD with **zero** cache, **zero** connectivity check, and **zero**
  offline queue. None of these are mentioned anywhere in the 2227-line internal plan
  document — they are a complete blind spot, not a deferred/acknowledged gap.

Underneath both tiers, the actual repository/data-source layer
(`MainRepositoryImpl`/`MainDataSourcesImpl`) is **100% network-only** — every one of
its 21 methods hits Dio directly with no cache read, no cache write, no connectivity
check. Every bit of offline behavior that exists in the "core" tier was hand-rolled
per-Bloc (`DetailBloc`, `PaymentBloc`, `CreateOrderBloc`, `ShiftBloc`, `WaiterCubit`,
`MainCubit` each inject `CacheService`/`ConnectivityCubit`/`OfflineQueueService`
directly and implement their own cache-first/queue logic around the still-network-only
usecases). This is the single biggest structural reason the app is inconsistent: **the
local-DB-first property is emergent per-screen, not structural.** Rule 1 ("every
repository... should read from local DB") is false at the one layer that's supposed to
guarantee it app-wide.

**Bottom line:** for a waiter or cashier doing ordinary service, this app is
*surprisingly* close to true offline-first — closer than most POS codebases this size
get without a dedicated data layer. For anyone touching back-office administration, it
has no offline story at all. And several of the "compliant" core flows are compliant
*in effect* while still *literally violating* Rule 2 (Blocs importing `DioClient`
directly), which will make this fragile to maintain even where it currently works.

---

## 2. Severity-ranked findings

### Critical

| # | Finding | Why it's critical |
|---|---|---|
| C1 | **Back-office CRUD screens are 100% network-blocking with zero offline capability**: menu/category/recipe management, staff management, transactions/finance, hall/table structural editing, service-charge config. Nine Widget-State classes + `ServiceChargeCubit` hold `DioClient` directly. | These edit the exact reference data (goods, categories, ingredients, compounds, tables, halls, staff) that the rest of the app depends on to *be* offline-first. A branch office with intermittent connectivity gets silent failures with no queue — an edited menu item, a staff deactivation, or a corrected transaction can simply be lost with no record it was attempted. |
| C2 | **`MainRepositoryImpl`/`MainDataSourcesImpl` — 100% of 21 methods are network-only**, zero cache read/write, zero connectivity check, anywhere in the file. | This is the one place a cache/offline decorator was supposed to live centrally (correctly identified as the root cause in the pre-existing plan doc). It's still true. Every screen not individually retrofitted with ad hoc offline logic in its Bloc has no offline capability at all, and any *new* screen built against this repository inherits zero offline behavior by default. |
| C3 | **Payment: zero-total order cancellation bypasses the offline queue entirely** — `payment_bloc.dart:156-171` calls `inject<DioClient>().dio.post(ListAPI.cancelOrder(...))` directly with no `ConnectionFailure` branch; any failure (including pure disconnection) shows a raw error and stops. | This is a money-adjacent, in-service-loop operation (closing a fully-discounted/comped check) that Rule 5 explicitly names. A comped table cannot be closed at all while offline. |
| C4 | **`Users`/staff are never cached, and the real fetch is hard-disabled** — `main_datasources.dart:259-262` unconditionally `return const Right(<UserModel>[])` with the real implementation commented out (Uzbek comment: "temporary — 403 on some roles, call disabled"). | Rule 4 explicitly requires Users to be synced at login. Today they aren't fetched *or* cached under any condition — the waiter-assignment dropdown is permanently empty, online or offline. This is a live functional bug wearing an offline-first audit's clothes. |
| C5 | **Offline-auth revocation can misfire during the exact outage it's meant to survive.** `dio_exception_handler.dart:27-34` maps *any* HTTP response whose JSON body contains an `error` key to `MessageFailure` — checked before the status-code switch, so it also catches 500/502/503/504. `MessageFailure` is classified as a **definite auth rejection** (`failure.dart:145-151`), which purges the offline-cached credential (`removeUser`/`removeForPin`). | The whole point of the no-TTL "revoked only by a confirmed rejection" design (Phase 6) is to keep staff logged in through a real outage. If the backend's 5xx error responses happen to include an `error` field (common), a transient server failure — not a real credential rejection — locks a legitimate cached user out mid-outage. Unverified against the real backend's actual 5xx body shape (flagged, not reproduced), but plausible and high-blast-radius if true. |

### High

| # | Finding | Why it's high |
|---|---|---|
| H1 | **`DetailBloc`, `PaymentBloc`, and part of `CreateOrderBloc` import and call `DioClient`/`ListAPI` directly**, bypassing `MainRepository` entirely, even though each wraps the call with a `ConnectionFailure`→enqueue fallback. `detail_bloc.dart:234,641,646,764,776,803,816`; `payment_bloc.dart:158,234,240,472-474`; `create_order_bloc.dart:229-243`. | These are the three highest-traffic Blocs in the app. They are functionally offline-resilient today, but they are a literal violation of Rule 2 ("no Bloc... should fetch data from an API"), which makes the codebase fragile: any future edit to these call sites has no repository seam forcing it to preserve the offline-queue wrapping, and there is no single place to audit for "does this write go through the outbox." |
| H2 | **No bulk reference-data prefetch for Categories, Departments, Halls, or Tables** — only Goods gets a full paginated prefetch (`cache_service.dart:194-227`, 30-min TTL). The other four are populated lazily, incrementally, whenever their screen happens to be opened, with no TTL and no periodic refresh from `SyncEngine.tick()` (confirmed: it only ever calls `prefetchAllGoods`, `sync_engine.dart:109`). | Rule 4 requires the app to "download and persist everything required for complete offline operation" after login — not "whatever the operator happened to click through once." A terminal that goes offline before a manager ever opens the department-selection or hall-management screen has an incomplete local copy of core reference data. |
| H3 | **Takeaway order creation has no offline path at all, by design** — `create_order_bloc.dart:89-123`, comment: "Takeaway — always requires online." Any failure (including `ConnectionFailure`) surfaces as an error; nothing is queued. | An entire order-creation flow is fully network-dependent, contradicting Rule 1/5. May be an intentional business decision (worth confirming with stakeholders) rather than an oversight, but as written it's a hole in "every user action should operate on the local database first." |
| H4 | **Two more direct-API widgets bypass properly-built parallel mechanisms**: `TimeBasedTableBadge` (`time_based_table_badge.dart:181,189,207,209`) polls `ListAPI.orderWithTableId`/`orderTableTimer` every 60s via raw `DioClient` and duplicates functionality `TableTimerCubit` already implements more carefully; `TransferTableDialog` (`transfer_table_dialog.dart:88-91`) posts a table transfer via raw `DioClient` with no queue. | Two parallel, inconsistent implementations of the same feature increases the chance the "wrong" (unqueued) one is hit in practice, and a table-transfer that fails offline is simply lost with no retry. |
| H5 | **Ingredients/Compounds have zero local caching** — `menu_manage_screen.dart:667-673` fetches `/api/v1/ingredients` and `/api/v1/compounds` fresh every time the recipe editor opens; `CacheService` has no methods for either. | Explicitly named in Rule 4. Scope is narrow (one manager-only recipe-editing screen — there is no POS-wide stock/inventory feature in this app at all), but the gap is real for that screen. |
| H6 | **Business settings (service charge %) are network-only, no cache, no offline fallback** — `service_charge_cubit.dart:39-44,68`. | Settings are named explicitly in Rule 4. A branch offline at boot cannot even *display* its configured service charge, let alone edit it. |

### Medium

| # | Finding | Why it's medium |
|---|---|---|
| M1 | **Misleadingly-named "Local" repositories with no local storage.** `TableTimerLocalRepositoryImpl` (`table_timer_local_repository_impl.dart:1-129`) has zero cache/persistence despite the name — this is a deliberate design choice per the plan doc (table-timer billing must use the cloud as the metering source of truth) but the naming actively misleads future maintainers. Most of `WaiterLocalRepositoryImpl` is the same — only `getOpenOrders` is cache-first; `getOrderDetail`, `getOrderItems`, and all six write methods are pure network passthroughs. | Not a functional gap where it's deliberate (table timer), but a real one where it isn't obviously deliberate (`WaiterLocalRepositoryImpl`'s write methods) — a future maintainer reading the class name would reasonably assume more offline coverage exists than actually does. |
| M2 | **Inconsistent connection-failure classification across Blocs.** `DetailBloc._isConnectionIssue` treats connection errors *and* all three Dio timeout types as queue-worthy; `CreateOrderBloc`/`PaymentBloc`/`ShiftBloc` check only `is ConnectionFailure`, which excludes timeouts. (Noted as a known, unreconciled gap in the plan doc itself.) | A slow-but-eventually-failing request (timeout, not a hard disconnect) is queued in one Bloc and surfaced as a bare error in the others — inconsistent user-facing behavior for what should be the same underlying condition. |
| M3 | **`AppScaffold._prefetchAttempted` is a `static bool`, never reset on logout** (`app_scaffold.dart:56,79-82`). If a different brand/user logs into the same running app instance, the immediate first-mount goods-prefetch trigger won't fire again — only the pre-existing 60s `SyncEngine` timer eventually repopulates goods. | Minor staleness window (up to ~60s) after an in-process re-login on a shared terminal, not data loss. |
| M4 | **Receipt info (business name/address/phone/INN) is local-only, never synced from or to any backend entity** — `receipt_info_section.dart` reads/writes only `SharedPreferences` via `ReceiptInfoStorage`. | Not a hydration *gap* (there's nothing server-side to hydrate from), but a multi-terminal consistency gap: a value set on one terminal never appears on another, undermining "settings" as a centrally-managed, synced entity per Rule 4's spirit. |
| M5 | **HTTP 403 is mapped to `UnauthenticatedFailure`**, which `isDefiniteAuthRejection` treats as a definite rejection (`dio_exception_handler.dart:46-47`, `failure.dart:145-151`). 403 conventionally means "authenticated but forbidden" (e.g., a branch/IP restriction), not "this credential is invalid." | Same failure mode as C5 but narrower: a 403 unrelated to credential validity could still incorrectly purge a valid offline-cached user. Pre-existing mapping, not introduced by the offline-auth work, but it now feeds directly into a purge decision that didn't exist before. |

### Low

| # | Finding | Why it's low |
|---|---|---|
| L1 | `TokensStorageKeys.posUser` is declared, migrated, and deleted on logout, but nothing in the codebase ever writes to it. | Dead code, not a functional or security issue. |
| L2 | A prior cross-tenant cache-contamination bug is documented as fixed same-day in the internal plan doc (§14.1: `CacheService`'s single unscoped Hive box leaked one brand's halls/tables into a different brand re-provisioned on the same terminal). This audit did not independently re-verify the fix. | Worth a targeted regression test (logout-from-app → re-login as a different brand → confirm no stale halls/tables) before trusting it's closed, since it wasn't reproduced or re-checked here — flagged as residual, not re-confirmed. |

---

## 3. Direct API calls from the UI/presentation layer (Rule 2 violations)

Every one of these is a `Widget State` class or `Bloc`/`Cubit` that holds a `DioClient`
reference and calls `.get`/`.post`/`.put`/`.delete` directly, with **no** repository
interface in between.

### Complete bypass — zero cache, zero connectivity check, zero offline queue

| Class | File | Call sites |
|---|---|---|
| `ServiceChargeCubit` | `lib/features/view/main/presentation/cubit/service_charge/service_charge_cubit.dart` | `load()` L43, `save()` L68 |
| `_TimeBasedTableBadgeState` | `lib/features/view/main/presentation/pages/main/widgets/time_based_table_badge.dart` | `_sync()` L181,189; `_togglePause()` L207,209 |
| `_TransferTableDialogState` | `lib/features/view/main/presentation/pages/detail/widgets/transfer_table_dialog.dart` | `_submit()` L88-91 |
| `_MenuMealsListScreenState` | `lib/features/view/main/presentation/pages/menu/menu_meals_list_screen.dart` | L88, 106, 148 |
| `_MenuManageScreenState` | `lib/features/view/main/presentation/pages/menu/menu_manage_screen.dart` | L266, 299-301, 343, 415, 451, 454, 525, 531, 582, 625, 667-673, 704 |
| `_TransactionsListSectionState` | `lib/features/view/main/presentation/pages/transactions/sections/transactions_list_section.dart` | L122, 146, 166-172, 283, 850, 863, 877 |
| `_TransactionCategoriesSectionState` | `lib/features/view/main/presentation/pages/transactions/sections/transaction_categories_section.dart` | L54, 130, 380, 385 |
| `_UsersSectionState` | `lib/features/view/main/presentation/pages/settings/sections/users_section.dart` | L73-80, 147-170, 179-186, 677, 687, 701 |
| `_HallsTablesSectionState` (+ nested table/hall editors) | `lib/features/view/main/presentation/pages/settings/sections/halls_tables_section.dart` | L41-47, 101-112, 399-405, 587-604, 666-676, 1338-1379, 2465-2491 |

### Partial — some local data, but the mutating/refresh paths still bypass the repository

| Class | File | Notes |
|---|---|---|
| `_PrintersSectionState` | `lib/features/view/main/presentation/pages/settings/sections/printers_section.dart` | Printer routing config itself is local (`PrinterConfigStorage`/`SharedPreferences`) — that part is fine. But category refresh (L58) and `_pushToBackendBestEffort()` (L781, posts/puts L791,793) are raw `DioClient` calls. |
| `DetailBloc` | `lib/features/view/main/presentation/cubit/detail/detail_bloc.dart` | Direct `DioClient`/`ListAPI` calls at L234, 641, 646, 764, 776, 803, 816 — but every mutation path (`cancelLineItems`/`addItems`) does fall back to the offline queue on a connection-class failure. Architecturally still a Rule-2 violation; functionally offline-resilient. |
| `PaymentBloc` | `lib/features/view/main/presentation/cubit/payment/payment_bloc.dart` | Normal payment path queues on failure (compliant in effect). Zero-total cancel path (L156-171) does not — see C3. `resumeTimerAfterFailedPay` (L233-240) and `_fetchItemTimestamps` (L472-474) are unguarded direct calls with silently swallowed failures — non-critical (timer resume / display enrichment), but still direct-to-network from a Bloc. |
| `CreateOrderBloc` | `lib/features/view/main/presentation/cubit/create_order/create_order_bloc.dart` | New-order/takeaway paths route through usecases correctly (though takeaway has no offline fallback — H3). `_addItemsToExistingOrder()` (L229-243) calls `DioClient.post` directly, bypassing `CreateOrderUsecase`, though it does queue on `ConnectionFailure`. |

---

## 4. Component compliance matrix

### Fully compliant (local-DB-first reads, queued/optimistic writes, no direct API access)

| Component | Evidence |
|---|---|
| `ArchivesBloc` / `ArchiveBloc` | No Dio/ListAPI import; routes through `ArchivesLocalRepository`, genuinely cache-first (`archives_local_repository_impl.dart:26-77`). |
| `DepartmentSelectionCubit` | No Dio/ListAPI import; routes through `MenuLocalRepository`, cache-first for departments/categories (`menu_local_repository_impl.dart:19-55`). Minor gap: `searchGoodsByName()` has no cache fallback (network-only), but it's still routed through the repository seam. |
| `WaiterCubit` | No Dio/ListAPI import; reads (`getOpenOrders`) are cache-first; all four write paths (create/cancel/send/close) enqueue to the offline outbox on `ConnectionFailure` **and** apply a real optimistic local-state mutation immediately (`waiter_cubit.dart:230-239, 354-374, 484-544, 640-653`) — the UI reflects the action before any network round trip. |
| `MainCubit` (tables/halls) | No Dio/ListAPI import; hand-rolled cache-first pattern reads local Hive cache first and emits immediately, network refresh is a background-only step that never blocks the initial render (`main_cubit.dart:55-97, 116-164, 174-243`). |
| `ShiftBloc` | No Dio/ListAPI import; local shift persisted via `SharedPreferences` immediately, both open and close genuinely enqueue outbox operations on `ConnectionFailure` with real reconciliation (`closeShift` looks up the real shift by register id and waits rather than erroring if `openShift` hasn't synced yet — `offline_queue_service.dart:354-381`). This is a real fix over the historical "local-only, never reconciles" fallback the plan doc describes as the prior state. |
| Sync engine / offline outbox / LAN relay / print queue (the whole `lib/core/sync/`, `lib/core/services/offline_queue/`, `lib/core/services/lan_hub/`, `lib/core/services/print_queue/` stack) | Independently confirmed real and fully wired — see §6. This is the one part of the app where the plan doc's claims essentially hold up under direct inspection. |
| Offline auth cache + secure storage + audit log (`OfflineAuthCache`, `AppTokenStorage`, `PrivilegedActionAuditLogService`) | Independently confirmed real — secure-storage-backed, no plaintext credentials remaining anywhere in the codebase, genuine append-only audit log wired into all 4 manager-pincode call sites. See C5/M5 for the one real bug found in the *classification logic* feeding this otherwise-sound mechanism. |

### Partial (some offline coverage, but with real gaps or architectural violations)

`DetailBloc`, `PaymentBloc`, `CreateOrderBloc`, `TableTimerCubit`/`TableTimerLocalRepositoryImpl` (online-only by explicit design, not a gap, but misleadingly named), `WaiterLocalRepositoryImpl` (only the open-orders list is cached; detail/items/all writes are pure network), `PrintersSection` — see §3 for specifics on each.

### Complete bypass of the local database

`MainRepositoryImpl`/`MainDataSourcesImpl` (the shared data layer underneath most of
the app), `ServiceChargeCubit`, `TimeBasedTableBadge`, `TransferTableDialog`,
`MenuMealsListScreen`, `MenuManageScreen`, `TransactionsListSection`,
`TransactionCategoriesSection`, `UsersSection`, `HallsTablesSection` — see §3/§2 C1/C2.

---

## 5. First-login / initial-sync hydration audit (Rule 4)

| Entity | Status | Evidence |
|---|---|---|
| Goods/Menu items | **Full paginated prefetch**, 30-min TTL, but triggered *opportunistically* (first `AppScaffold` mount / 60s periodic tick) rather than deterministically at login | `cache_service.dart:194-227`, `sync_engine.dart:109`, `app_scaffold.dart:79-82` |
| Categories | Lazy on-demand only, no TTL, no bulk prefetch | `detail_bloc.dart:120-166`, `menu_local_repository_impl.dart:38-55` |
| Departments | Lazy on-demand only, no TTL | `menu_local_repository_impl.dart:18-36`, `printer_service.dart:121-140` |
| Halls | Lazy on `MainScreen.initState`, 5-min fetch throttle (not a staleness TTL), no bulk prefetch | `main_cubit.dart:116-164` |
| Tables | Lazy per-hall, 30s fetch throttle, no bulk prefetch | `main_cubit.dart:55-97, 174-243` |
| Users/Staff | **Not cached at all**; real fetch hard-disabled (returns empty unconditionally) | `main_datasources.dart:259-262` — see C4 |
| Settings — printer routing | **Genuinely synced at login** — the one entity that fully meets Rule 4 | `user_bloc.dart:73-84` fires `SyncPrinterSettingsUsecase` on every successful `getUser` |
| Settings — service charge | Not cached, network-only every access | `service_charge_cubit.dart:39-44` — see H6 |
| Settings — receipt info | Local-only, never synced (no backend entity) | `receipt_info_section.dart` — see M4 |
| Orders (open orders, branch-wide) | No bulk download at login; only a single-page, per-mode cache populated when the waiter/archive screen happens to be opened | `waiter_local_repository_impl.dart:30-67`, `archives_local_repository_impl.dart:26-56` |
| Ingredients/Compounds | **Not cached at all**, network-only every time the recipe editor opens (narrow scope — one manager screen, no app-wide stock/inventory feature exists) | `menu_manage_screen.dart:667-673` — see H5 |

**Cold-start behavior (confirmed good):** `main.dart`/`initDi()` never makes a network
call before the UI is usable. `SplashScreen` branches purely on locally-stored tokens
and navigates to the main screen *before* any network call resolves
(`splash_screen.dart:51-53`, `UserEvent.getUser()` fired but not awaited). Once on the
main screen, halls/tables/categories/goods/current-bill all read from cache
synchronously before any network attempt. **A terminal with a prior session and a warm
cache genuinely reaches a usable floor-plan screen with zero network round-trips.**
This part of Rule 1 ("UI must never depend on the network to function") is met for the
core screens — it is *not* met for Users/Staff, Service Charge, or the back-office
screens in §3/§4, which show empty/error states with no local fallback at all.

---

## 6. Sync engine, offline queue, LAN relay, print queue — verified as-built

Independently confirmed (not just per the plan doc) to be real, complete, and wired up
end-to-end, with no stubs, TODOs, or dead code found in any of these files:

- **`SyncEngine`** (`lib/core/sync/sync_engine.dart`): real `Timer.periodic` 60s tick,
  started unconditionally in `di.dart:150`, re-entrancy guarded. Drains the outbox,
  then refreshes goods. In LAN-`client` mode it relays through the leader regardless
  of this terminal's own connectivity (deliberate — a follower with LAN-but-no-WAN
  must still sync).
- **Offline outbox** (`offline_queue_service.dart`, `pending_operation.dart`,
  `quarantined_operation.dart`): 6 real operation types (`createOrder`, `addItems`,
  `payOrder`, `openShift`, `closeShift`, `cancelLineItems`), each with a real handler.
  Real exponential backoff with jitter (5s base, 2min cap, formula at
  `offline_queue_service.dart:107-114`). A genuine quarantine mechanism — 4xx
  ("terminal") failures are persisted with a reason to a separate Hive box instead of
  being silently dropped, with `retryQuarantined`/`dismissQuarantined` for manual
  resolution, both surfaced in a real settings UI (`sync_status_section.dart`).
- **LAN leader/follower relay** (`lan_hub_service.dart`, `lan_hub_server.dart`,
  `lan_hub_client.dart`, `lan_hub_message.dart`): real, authenticated (JWT-gated
  WebSocket handshake, 5s auth timeout, socket held out of the broadcast set until
  approved), with a genuine follower→leader op-relay and leader→cloud replay path.
  Split-brain (two terminals both set to "server") is detected via a UDP discovery
  beacon and surfaced as a warning, not auto-resolved. One disclosed, accepted
  weakness: the offline-leader auth fallback checks JWT expiry only, not signature.
- **Print queue** (`print_queue/print_queue_service.dart`, `print_job.dart`): real
  persisted claim/lease state machine (3s claim wait, 10s lease, one bounded retry),
  crash-recovery sweep on startup, genuinely wired into every real print call site in
  `printer_service.dart` (confirmed via grep of callers, not orphaned). Printing itself
  never depends on backend reachability — it's pure TCP/LAN or local USB, no Dio calls
  anywhere in the transport path.
- **Reachability/backoff on the LAN client and connectivity probe**: both have real
  exponential backoff with jitter, and `ConnectivityCubit` runs a genuine
  application-level HTTP reachability probe (not just OS link state) every 20s.

This is the strongest part of the codebase relative to the stated architecture, and
the one place this audit found the pre-existing internal plan document's claims to be
essentially accurate rather than aspirational.

---

## 7. Missing sync mechanisms / missing offline queues

- **No sync coverage at all** for the entities behind the back-office screens in §3:
  menu items, categories, ingredients, compounds, staff/users, transactions, hall/table
  structural data, service-charge config. If any of these are edited while offline,
  the edit simply fails with no queue and no retry — there is no operation type for
  any of them in the 6-type outbox.
- **No queue coverage for the zero-total payment cancel path** (C3) or **takeaway
  order creation** (H3) — both are explicit gaps in an otherwise well-queued area.
- **No periodic/background refresh for Categories, Departments, Halls, Tables, Users,
  or Settings** — `SyncEngine.tick()` only ever refreshes goods (§5, §6). These
  entities have no "download remote changes" mechanism at all beyond whatever a
  screen's own lazy on-open fetch does.
- **No conflict-resolution mechanism beyond the single documented case** (the 409
  duplicate-order-create race, handled by `order_conflict_helper.dart`, used in
  `create_order_bloc.dart`/`table_timer_cubit.dart`/`waiter_cubit.dart`). Nothing
  exists for concurrent item edits across two terminals, stock counters (moot — no
  stock feature exists), or stale reference-data reads mid-order beyond the
  already-correct server-side price-snapshotting behavior.

---

## 8. Architectural inconsistencies

1. **The offline-first property is emergent, not structural.** It lives in six
   individually-retrofitted Blocs/Cubits rather than in the shared repository/data
   layer (§2 C2). Any new screen built the "normal" way (inject a usecase, call
   `MainRepository`) inherits zero offline behavior by default — there is no seam that
   forces a new feature to be offline-safe, unlike, say, a decorator pattern at the
   repository boundary would provide.
2. **"LocalRepository"-suffixed classes with no local storage** (M1) — the naming
   convention promises more than several of these classes deliver, which will mislead
   future maintainers into assuming coverage that isn't there.
3. **Inconsistent connection-failure classification** (M2) — the same underlying
   condition (a slow request that eventually times out) is treated as queue-worthy in
   one Bloc and as a hard error in three others.
4. **Direct-API Blocs that *are* offline-resilient still violate the letter of Rule
   2** (H1) — `DetailBloc`/`PaymentBloc`/parts of `CreateOrderBloc` import `DioClient`
   directly. This is functionally fine today but structurally fragile: nothing stops a
   future edit to one of these call sites from dropping the queue-fallback wrapping,
   since there's no repository interface enforcing it.
5. **A failure-classification bug that undermines a security-critical mechanism during
   its exact intended use case** (C5/M5) — the offline-auth revocation model is sound
   in design but the `Failure` classification feeding it can misfire on ordinary
   backend errors (5xx-with-body, 403), purging valid credentials mid-outage instead
   of preserving them.
6. **Two independent implementations of table-timer functionality** (H4) — one
   properly routed through `TableTimerCubit`/`TableTimerLocalRepository`, one a raw
   `DioClient` poll in a widget `State` class (`TimeBasedTableBadge`). No obvious
   reason for both to exist.

---

## 9. Overall assessment

**How close is this app to true offline-first?**

For the narrow slice of functionality the prior work session's plan document actually
scoped — order-taking, order editing, payment, shift open/close, printing, and the
sync/queue/LAN/print infrastructure underneath them — this app is **genuinely close**,
closer than the norm for a codebase this size. The sync engine, outbox, LAN relay, and
print queue are real, tested, and correctly designed around the hard cases (backoff,
quarantine, idempotency keys threaded through to a backend fix made the same day this
audit was requested, claim/lease printing, no-TTL auth revocation). This is not
vaporware; five independent research passes read every file involved and found the
mechanisms actually wired together end to end.

But **the app as a whole is not close to Rule 1 or Rule 2 being true in the general
case.** The moment you step outside the six retrofitted Blocs — into menu management,
staff administration, transactions, hall/table editing, service-charge config, or the
shared `MainRepositoryImpl`/`MainDataSourcesImpl` layer every screen ultimately sits
on — the architecture reverts to a completely ordinary, network-blocking, no-cache
Flutter app with zero resilience to a dropped connection. None of that tier appears
anywhere in the 2227-line internal plan document, which suggests it was genuinely out
of scope for the effort so far rather than a known, accepted gap.

**Practical framing:** if this app were deployed to a branch with an unreliable
internet connection today, a waiter working the floor — taking orders, editing bills,
processing payment, printing receipts — would mostly not notice an outage. A manager
trying to update the menu, adjust staff, review transactions, or reconfigure the
floor plan during that same outage would find every one of those screens simply
broken, with no indication anything was queued for later and no way to retry short of
regaining connectivity and redoing the work from scratch.

### Priority order for closing the gap

1. **C2** — put a cache-first decorator (or equivalent) behind `MainRepositoryImpl`
   so offline behavior becomes the default for every screen built on it, not an
   opt-in per Bloc. This is the highest-leverage single change; it's also what the
   pre-existing plan document itself identified as the root cause and never actually
   fixed.
2. **C1** — bring the back-office tier (menu, staff, transactions, halls/tables,
   service charge) into the same repository/queue pattern already proven out for the
   core POS loop, or explicitly scope it out as "requires connectivity by design" if
   that's an acceptable product decision — but that should be a stated decision, not
   an accidental blind spot.
3. **C3, C4, C5** — each is a narrow, mechanically simple fix (add a
   `ConnectionFailure` branch + enqueue for the zero-total cancel path; re-enable and
   fix the `getUsers` call, or fix its 403 issue properly; narrow
   `isDefiniteAuthRejection`'s classification to exclude 5xx and reconsider 403).
4. **H1-H6** — architectural cleanup (route the three "partial" Blocs through a real
   repository seam) and the remaining reference-data hydration gaps.
