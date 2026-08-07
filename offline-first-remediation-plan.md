# Offline-First Remediation Plan

**Companion to:** `offline-first-compliance-audit.md` (the findings this plan closes)
and `offline-first-architecture-plan.md` (the prior effort that built the sync
engine/outbox/LAN relay/print queue infrastructure this plan assumes is already real —
independently re-verified during the audit, not just trusted).

**Purpose:** a concrete, phased plan to take the app from "offline-first for six
retrofitted Blocs" to "offline-first by default," closing every Critical/High/Medium
finding in the audit. Ordered by risk and blast radius, cheapest/highest-leverage
first. Each phase names concrete files and gives acceptance criteria.

---

## 0. What this plan does *not* redo

The audit confirmed the following are real, complete, and correctly built — this plan
does not touch their internals, only extends what feeds into them:

- `SyncEngine` (60s tick, `lib/core/sync/sync_engine.dart`)
- The offline outbox — 6 op types, exponential backoff + jitter, quarantine
  (`lib/core/services/offline_queue/`)
- The LAN leader/follower relay (`lib/core/services/lan_hub/`)
- The print job claim/lease queue (`lib/core/services/print_queue/`)
- Offline auth cache + secure storage + audit log (`lib/core/services/auth/`,
  `lib/core/auth/storage/`, `lib/core/services/audit/`)

Where a phase below needs a *new* outbox operation type or a *new* cached entity, it
reuses these existing mechanisms (add a case to the existing enum, add a method to the
existing `CacheService`) rather than inventing parallel infrastructure.

---

## 1. Target end-state, per rule

| Rule | Done looks like |
|---|---|
| 1. Local DB is the single source of truth | Every repository (not just the six hand-retrofitted Blocs) reads cache-first; every screen in the app — including back-office — renders from local data with zero network round-trips when offline. |
| 2. UI never talks to the backend directly | Zero `DioClient`/`Dio`/`ListAPI` imports anywhere under `lib/features/**/presentation/**` or `lib/features/**/cubit/**`. All reads/writes go through a repository interface. |
| 3. Background sync layer is the only network component | Already true for the six-Bloc core tier; extended in this plan to cover every entity/screen. |
| 4. First login hydrates everything | Every entity named in the audit's §5 table (Categories, Departments, Halls, Tables, Users, Settings, Ingredients, Compounds) gets the same paginated-prefetch treatment `prefetchAllGoods` already gives Goods. |
| 5. Every user action is local-first | Every mutation in the app — not just the six-Bloc core tier — writes locally/queues immediately; nothing blocks the UI on a live network round-trip except where an explicit, documented product decision says otherwise (e.g. takeaway, if kept online-only). |

---

## 2. Architectural approach

**Don't add a new abstraction layer on top of what already works.** The six
retrofitted Blocs' write-side pattern (`ConnectionFailure` → `OfflineQueueService
.enqueue(...)` → optimistic local state) is correct and proven (real tests, real
reconciliation logic). The problem isn't the pattern — it's that only six places use
it, and reads have no shared cache-first mechanism at all below the Bloc layer.

Two structural moves close most of the gap:

1. **Push cache-first reads down into `MainRepositoryImpl`/`MainDataSourcesImpl`
   itself**, entity by entity, using the exact pattern already proven in
   `menu_local_repository_impl.dart`/`archives_local_repository_impl.dart` (online →
   write cache → return; offline/failed → read cache). Once a method lives there,
   *every* caller gets offline reads for free — no more hand-rolling per Bloc.
2. **Add the missing repository methods for the raw-Dio call sites still living
   inside Blocs/widgets**, so those call sites stop importing `DioClient` directly.
   The existing enqueue-on-`ConnectionFailure` logic in those Blocs is *already
   correct* — it just needs to call a repository method instead of `DioClient`
   directly. This is a call-site relocation, not a rewrite of working queue logic.

For the back-office tier (Phase 4), which has no offline logic at all today, the same
two moves apply, but the write-side decision (queue offline edits vs. require
connectivity) is a real product tradeoff spelled out in that phase rather than assumed.

---

## 3. Phase 1 — Repository-layer cache-first reads + missing cached entities

**Closes:** C2 (root-cause repository gap), H2 (no bulk prefetch for
categories/departments/halls/tables), H5 (ingredients/compounds), H6 (service
charge), most of §7's "no periodic refresh" gap.

### 1a. Extend `CacheService` (`lib/core/services/cache/cache_service.dart`)

Add, mirroring the existing `saveGoods`/`getGoods`/`prefetchAllGoods` shape:

| New method pair | Backing key | Notes |
|---|---|---|
| `saveUsers`/`getUsers` | `_users` | Branch-scoped list, no pagination needed at typical staff-list scale |
| `saveIngredients`/`getIngredients` | `_ingredients` | |
| `saveCompounds`/`getCompounds` | `_compounds` | |
| `saveServiceCharge`/`getServiceCharge` | `_serviceCharge` (keyed by `branchId`) | Single small object, not a list |
| `prefetchAllCategories`/`prefetchAllDepartments`/`prefetchAllHalls`/`prefetchAllTables` | reuse existing `_categories`/`_departments`/`_halls`/`_tables` keys | Same paginated-loop shape as `prefetchAllGoods` (`cache_service.dart:194-227`); these entities are small enough that pagination may collapse to one page, but keep the same code path for consistency and future-proofing |

All new methods follow the existing box/key conventions already in the file — no new
Hive box, no schema migration needed (raw JSON blobs, same as everything else in this
file today).

### 1b. `MainDataSourcesImpl`/`MainRepositoryImpl` — make reads cache-first

For each of the 21 methods audited as 100% network-only
(`main_datasources.dart:94-711`), split by whether it's reference data (cache-first,
background refresh) or genuinely transactional (network-first is correct, cache is
just a fallback):

| Method | Treatment | New behavior |
|---|---|---|
| `getCategories`, `getDepartments`, `getHalls`, `getTablesByHallId` | Cache-first | Read cache, emit/return immediately if present; background-refresh via network; write-through to `CacheService` on success. Same pattern `MainCubit` already hand-rolls (`main_cubit.dart:55-97,116-164`) — move it down a layer so `DetailBloc`'s category/goods loading (currently duplicating this logic inline, `detail_bloc.dart:120-166`) can delete its own copy and call the repository instead. |
| `getUsers` | Cache-first + **fix the disabled call** | Re-enable the real network call (currently hardcoded to `Right(<UserModel>[])`, `main_datasources.dart:259-262`) — see Phase 2 for the 403 root-cause fix — then wrap it with the same cache-first pattern. |
| `getPrinterSettings` | Already synced at login via a separate path (`SyncPrinterSettingsUsecase`) — leave as-is, just confirm no duplicate logic is needed here. | |
| `checkShift`, `openShift`, `closeShift`, `createOrder`, `createTakewayOrder`, `createPayment`, `getOrderIdWithTableId`, `getPaymentDetailWithId`, `getPaymentDetailWithTableId`, `getGoodsByCategoryId`, `getGoodsWithName`, `getArchives`, `getArchiveWithId`, `getUser` | **Leave network-first** (these are genuinely transactional/live-state reads, or already have their own cache-first wrapper one layer up — e.g. archives already goes through `ArchivesLocalRepository`) | No change — these are correctly *not* reference data; don't force a cache pattern where "cache-first" would mean showing stale money-relevant state. |

New: add `ingredients`/`compounds`/`serviceCharge` read+write methods to
`MainRepository`/`MainDataSourcesImpl` (currently these calls happen directly inside
`menu_manage_screen.dart`/`service_charge_cubit.dart` — Phase 4 moves the call sites,
this phase just adds the repository-level plumbing so Phase 4 has something to call).

### 1c. Bulk hydration at login

Extend `SyncEngine.tick()` (`sync_engine.dart:97-125`) — currently only calls
`_cache.prefetchAllGoods` — to also call the new `prefetchAllCategories`/
`prefetchAllDepartments`/`prefetchAllHalls`/`prefetchAllTables`/`getUsers`(cache-write)/
`getServiceCharge`(cache-write) on the same tick. These are small relative to goods, so
no new pagination/staleness infrastructure is needed beyond what §1a already adds —
just wire the calls in.

Also fix **M3**: reset `AppScaffold._prefetchAttempted = false` in
`AuthCubit.logoutFromApp` (`auth_cubit.dart:126-133`, alongside the existing
`CacheService.clearAll()` call) so a re-login in the same process re-triggers full
hydration instead of waiting up to 60s for the next periodic tick.

**Acceptance:** cold-start with a warm cache and no network shows tables, halls,
categories, departments, and the staff list with no network round-trip (same test
shape as the existing "cache-hit path" manual checks noted for Phase 2 of the prior
plan). `flutter analyze` clean; extend `cache_service`-adjacent tests (there don't
appear to be dedicated `CacheService` unit tests today — add them for the new methods
following the existing `test/support/` in-memory-storage pattern).

---

## 4. Phase 2 — Fix the Critical bugs (money and security)

**Closes:** C3 (zero-total payment cancel), C4 (disabled `getUsers`), C5/M5 (auth
failure misclassification).

### 2a. C3 — zero-total payment cancel

`payment_bloc.dart:156-171` currently calls `DioClient` directly with no
`ConnectionFailure` branch. Fix:

1. Add a new `PendingOperationType.cancelOrder` to `pending_operation.dart` (mirrors
   `payOrder`'s payload shape: `{orderId}`).
2. Add an `_execCancelOrder` handler to `offline_queue_service.dart`'s switch
   (alongside the existing 6), posting to `ListAPI.cancelOrder(orderId)` — treat 404
   ("already gone/already cancelled") as `OpOutcome.synced`, same tolerance pattern
   `cancelLineItems` already uses.
3. In `payment_bloc.dart`'s zero-total branch, wrap the direct `dio.post` call in the
   same try/catch shape the rest of the file uses, branch on
   `failure is ConnectionFailure` → enqueue `cancelOrder` + optimistic success (print
   receipt, close out), else surface the real error as today.

### 2b. C4 — `getUsers` hard-disabled

`main_datasources.dart:259-262`'s comment says the real call 403s "on some roles."
Before re-enabling: confirm with the backend team (or by reading backend source, as
the prior session did for the idempotency work in §14 of the architecture plan) which
role/permission is actually required for `GET /api/v1/users`, and whether the POS
terminal's session token carries it. Once confirmed:

1. Re-enable the real call.
2. If it turns out to be a genuine permission gap (not a client bug), either (a)
   request a backend scope/permission fix, or (b) call a narrower endpoint the POS
   session token *does* have access to (check `api-docs/` for a
   branch-scoped-staff-list variant before assuming none exists).
3. Wire through Phase 1's new `CacheService.saveUsers`/`getUsers`.

### 2c. C5/M5 — auth-rejection misclassification

`dio_exception_handler.dart:27-34` maps any response body containing an `error` key
to `MessageFailure` **before** checking status code. Fix: only take that branch for
4xx responses; for 5xx, always classify as `ServerFailure` (already correctly treated
as inconclusive) regardless of body shape. Separately, reconsider whether HTTP 403
should stay in `isDefiniteAuthRejection`'s set (`failure.dart:145-151`) — if the
backend ever uses 403 for anything other than "this credential is invalid" (branch
restriction, IP allowlist, etc.), it needs its own `Failure` subtype excluded from the
purge trigger. Resolve by checking actual backend 403 usage (same "read the backend
source directly" approach the prior session used for the idempotency audit) rather
than guessing.

**Acceptance:** add a case to `test/offline_auth_revocation_test.dart` asserting a
5xx-with-error-body response does **not** classify as a definite rejection. Add a
`cancelOrder`-path case to whatever test currently covers `payment_bloc.dart`'s queue
behavior (or add one if none exists) confirming a connection failure on the zero-total
path enqueues rather than erroring. Manual verification of `getUsers` against a real
backend/role before considering C4 closed — this one can't be verified by static
analysis alone.

---

## 5. Phase 3 — Eliminate remaining direct-Dio Bloc/widget violations

**Closes:** H1 (`DetailBloc`/`PaymentBloc`/`CreateOrderBloc` direct Dio calls), H4
(`TimeBasedTableBadge`/`TransferTableDialog`), M2 (inconsistent connection-failure
classification), the "duplicate table-timer implementation" inconsistency.

### 3a. Route remaining raw-Dio call sites through repository methods

For each site below, add a thin method to `MainRepository`/`MainRepositoryImpl` (or,
where one already exists and just isn't used, switch the call site to it) that wraps
the existing Dio call — **no behavior change**, the enqueue-on-`ConnectionFailure`
logic already in the Bloc stays exactly as-is, only the network call itself moves
behind the interface:

| Call site | New/existing repository method to add |
|---|---|
| `detail_bloc.dart:234` (`_enrichExistingGoodsWithTimestamps`) | `MainRepository.getOrderItemTimestamps(orderId)` |
| `detail_bloc.dart:641,646` (`_deleteExistingByKey`) | `MainRepository.cancelOrderItem(id)` |
| `detail_bloc.dart:764,776,803,816` (`_onSyncExistingItem`) | `MainRepository.createOrderItems(...)` / `cancelOrderItem(...)` (reuse the same methods as above) |
| `payment_bloc.dart:233-240` (`resumeTimerAfterFailedPay`) | `MainRepository.getOrderTableTimer`/`resumeOrderTableTimer` |
| `payment_bloc.dart:472-474` (`_fetchItemTimestamps`) | Same as `detail_bloc.dart:234` above — reuse, don't duplicate |
| `create_order_bloc.dart:229-243` (`_addItemsToExistingOrder`) | `MainRepository.createOrderItems(...)` — same method as the `detail_bloc` add-item path, both bypass `CreateOrderUsecase` for the same underlying endpoint today; unifying them onto one repository method also removes the current code duplication |
| `time_based_table_badge.dart:181,189,207,209` | Delete this widget's private Dio logic entirely; replace with `TableTimerLocalRepository`/`TableTimerCubit` (already exists and does the same job — see the "duplicate implementation" note in the audit, H4) |
| `transfer_table_dialog.dart:88-91` | `MainRepository.transferTable(...)` (new), with the same `ConnectionFailure`→enqueue pattern as everything else — add a `PendingOperationType.transferTable` outbox op if this needs offline support (recommended, since a table transfer is a normal in-service action Rule 5 names) |

### 3b. Unify connection-failure classification (M2)

`DetailBloc._isConnectionIssue` currently includes Dio timeouts;
`CreateOrderBloc`/`PaymentBloc`/`ShiftBloc` check only `is ConnectionFailure`. Pick
one behavior (recommend: include timeouts everywhere — a timeout is not a definite
server rejection, same reasoning already applied to `isDefiniteAuthRejection` in
Phase 2c) and extract a single shared helper (e.g. `Failure.isConnectivityIssue` next
to the existing `isDefiniteAuthRejection` in `failure.dart`), then point all four
Blocs at it.

**Acceptance:** `flutter analyze` clean; grep confirms zero `DioClient`/`ListAPI`
imports remain under `lib/features/**/presentation/**` and
`lib/features/**/cubit/**` except inside the repository implementation files
themselves. Existing behavior-preservation discipline from the prior session's Phase 2
(re-read each old branch against the new one line-by-line) applies here too, since
these are live money/order-mutation paths.

---

## 6. Phase 4 — Bring the back-office tier online

**Closes:** C1 — the largest gap in the audit. Nine widget classes + one Cubit with
zero cache, zero queue, zero connectivity awareness.

This tier is lower-frequency and typically used by managers/admins rather than staff
mid-service, so the **write-side** tradeoff is a real product decision, not a pure
engineering one: queuing an offline edit to shared reference data (a menu item's
price, a staff member's active flag, a hall's table layout) has a higher
conflict/consistency cost than queuing an order mutation, because two managers editing
the same menu item on two terminals during a partition is a much messier merge than
two waiters adding items to two different tables. **Recommendation: read-side goes
fully offline in every sub-phase below (cache-first, browsable with no network); the
write-side ships online-required-with-a-clear-blocked-state first (v1), with
queued-offline-writes as an explicit opt-in v2 per screen once the conflict story for
that specific entity is worked out** — don't queue writes to shared reference data
by default just because the mechanism exists.

Ordered by how much the rest of the app depends on the data being correct:

### 4a. Menu management (highest priority)
`menu_meals_list_screen.dart`, `menu_manage_screen.dart` — goods, categories,
ingredients, compounds CRUD.
- New `MenuManagementRepository` wrapping today's direct Dio calls.
- Reads: cache-first via Phase 1's new `getIngredients`/`getCompounds` and the
  already-cached `getGoods`/`getCategories`.
- Writes (v1): keep online-required, but route through the repository and surface a
  clear "you're offline, this screen requires a connection" state instead of letting
  individual save/delete calls fail with a raw error per field.
- Writes (v2, follow-up): if queued offline edits are wanted later, this is the
  highest-value entity to do it for (goods/categories are read by every order-taking
  screen) — needs a conflict policy decided first (recommend: last-write-wins is
  **not** acceptable here given price/recipe correctness; needs either an
  online-required constraint kept permanently for this entity, or a real
  optimistic-concurrency check once the backend gains a `version` field — see the
  architecture plan's own §2.2 note that no entity has one today).

### 4b. Staff/Users management
`users_section.dart`.
- New `StaffRepository` (or extend `MainRepository` with the admin CRUD methods,
  distinct from the read-only `getUsers` Phase 1 already adds).
- Reads: cache-first via Phase 1's `getUsers`.
- Writes (v1): online-required with clear blocked state, same as 4a.

### 4c. Halls/Tables structural editing
`halls_tables_section.dart`.
- New repository methods for hall/table CRUD, distinct from the existing
  read-only `getHalls`/`getTablesByHallId`.
- **Coordinate carefully with `MainCubit`'s existing halls/tables cache** — a
  structural edit (delete a table, move it between halls) needs to invalidate/refresh
  the same `CacheService` entries `MainCubit` reads, or floor-plan screens will show
  stale structure. This is the same class of bug already found and fixed once in this
  codebase (§14.1 of the architecture plan, the cross-tenant cache-contamination bug)
  — reuse that fix's pattern (filter displayed rows against current authoritative
  IDs) rather than assuming a cache write-through is enough on its own.
- Writes (v1): online-required with clear blocked state.

### 4d. Transactions / Kassa (finance)
`transactions_list_section.dart`, `transaction_categories_section.dart`.
- New `TransactionsRepository`.
- Reads: cache-first (first-page-only is an acceptable v1 scope, matching the
  existing archives/waiter-list precedent).
- Writes (v1): online-required with clear blocked state — financial-record edits are
  the last place to introduce a queued-offline-write risk without a specific ask.

### 4e. Service charge settings (smallest, can move earlier if convenient)
`service_charge_cubit.dart`.
- Wire onto Phase 1's `getServiceCharge`/`saveServiceCharge` repository methods.
- Reads: cache-first. Writes: online-required (single config value, low volume,
  no reason to add queue complexity for this one).

**Acceptance per sub-phase:** the screen's list/detail views render from cache with no
network; going offline mid-screen shows a clear, distinct "reconnect to make changes"
state rather than a raw Dio error; `flutter analyze` clean; zero remaining
`DioClient`/`ListAPI` imports in the touched files.

---

## 7. Phase 5 — Consistency cleanup

**Closes:** M1 (misleading "LocalRepository" naming), the takeaway-offline policy
question (H3).

- `WaiterLocalRepositoryImpl`: either add cache to `getOrderDetail`/`getOrderItems`
  (if that's wanted — note the original design deliberately left these live-only to
  avoid showing a stale item list understating what a guest owes, per the prior
  session's own reasoning; if that reasoning still holds, leave as-is but add a doc
  comment explaining why the class isn't fully cache-first, so it reads as a decision
  rather than an oversight) or split it into `WaiterOpenOrdersLocalRepository`
  (genuinely local) + `WaiterOrderDetailRepository` (genuinely live-only) so the
  naming stops overpromising.
- `TableTimerLocalRepositoryImpl`: same treatment — it's deliberately online-only by
  design (cloud is the metering source of truth); rename to drop "Local" or add a
  clear doc comment, don't leave it silently misleading.
- **H3 — takeaway offline policy**: this is a product decision, not an engineering
  one. Confirm with whoever owns POS operations whether takeaway orders are expected
  to work during an outage. If yes: reuse `CreateOrderBloc`'s existing dine-in
  offline path (client-generated order id, `createOrder` outbox op, optimistic
  success + immediate receipt print) with an `isTakeaway` flag threaded through — the
  mechanism already exists, it's just gated off today. If no: leave as-is, but add a
  one-line comment at `create_order_bloc.dart:90` recording that this was a deliberate
  decision (with a date/reason), not an oversight — the same "disclosed, not silent"
  discipline the rest of this codebase's offline work already follows.

---

## 8. New outbox operation types introduced by this plan

| Type | Introduced in | Payload | Executor notes |
|---|---|---|---|
| `cancelOrder` | Phase 2a | `{orderId}` | Treat 404 as already-done/synced, same tolerance as `cancelLineItems` |
| `transferTable` | Phase 3a | `{orderId, fromTableId, toTableId}` | New — check for a 409/conflict shape similar to the existing order-create race before assuming a plain retry is safe |
| (optional, v2 only) menu/staff/hall-table edit ops | Phase 4, deferred | entity-specific | Not recommended for v1 — see Phase 4's write-policy discussion; only build if/when a conflict policy is agreed for that specific entity |

---

## 9. Testing & rollout

Follow the existing project convention (real Hive boxes, real sockets over loopback,
`fake_async` for time-compression, no mocking framework — see the prior session's test
files under `test/` for the established style):

- Phase 1: `CacheService` unit tests for the new entity methods (currently no
  dedicated `cache_service_test.dart` exists — add one).
- Phase 2: extend `offline_auth_revocation_test.dart` (5xx case) and add/extend a
  payment-bloc-adjacent test for the new `cancelOrder` op.
- Phase 3: no new test infrastructure needed — these are call-site relocations;
  confirm via `flutter analyze` + manual re-read of each moved branch against its
  original, matching the discipline already established in this codebase's Phase 2
  Bloc migrations.
- Phase 4: at minimum, a cache-hit-path test per screen (open online once, go
  offline, confirm cached view still renders) — matches the "still needs a manual
  pass" bar the prior session left for its own Phase 2 work.
- Rollout: same mechanics already recommended in `offline-first-architecture-plan.md`
  §11 (feature-flag per phase, one low-volume branch canary, 2-4 week field-proof
  window before cutting over) — no reason to invent a different process for this plan.

---

## 10. Priority-ordered checklist

1. [ ] Phase 1 — cache-first reads in `MainRepositoryImpl`/`MainDataSourcesImpl` +
   new `CacheService` entities + bulk hydration on `SyncEngine.tick()`
2. [ ] Phase 2a — `cancelOrder` outbox op, fix zero-total payment cancel
3. [ ] Phase 2b — re-enable and fix `getUsers`
4. [ ] Phase 2c — narrow `isDefiniteAuthRejection`/`handleDioException` 5xx/403 handling
5. [ ] Phase 3 — route `DetailBloc`/`PaymentBloc`/`CreateOrderBloc`/
   `TimeBasedTableBadge`/`TransferTableDialog` off direct `DioClient`; unify
   connection-failure classification
6. [ ] Phase 4a — Menu management repository seam + cache-first reads (writes v1:
   online-required, clearly signposted)
7. [ ] Phase 4b — Staff management repository seam + cache-first reads
8. [ ] Phase 4c — Halls/Tables structural editing repository seam (coordinate with
   `MainCubit` cache invalidation)
9. [ ] Phase 4d — Transactions/Kassa repository seam
10. [ ] Phase 4e — Service charge settings onto Phase 1's new repository methods
11. [ ] Phase 5 — naming cleanup (`WaiterLocalRepositoryImpl`,
    `TableTimerLocalRepositoryImpl`), takeaway-offline policy decision recorded
12. [ ] (Deferred, v2, only if scoped later) offline-write queueing for back-office
    entities, per-entity conflict policy required first
