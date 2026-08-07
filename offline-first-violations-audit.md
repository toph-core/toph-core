# Offline-First Violations Audit

**Date:** 2026-08-07. **Branch:** `offline-again`.
**Relationship to other docs in this repo:** re-reads the same code as
`offline-first-compliance-audit.md` (2026-08-06) but applies a **stricter, zero-tolerance
rule set**: any UI-layer code path that awaits a live network call — even one that falls
back to the offline queue on failure — counts as a violation, not a "compliant in effect"
pass. The prior audit graded `DetailBloc`/`PaymentBloc`/`CreateOrderBloc` as "functionally
offline-resilient" (its H1). This audit disagrees with that grade on principle: **a write
path that blocks on the network whenever the network happens to be up is still a network
dependency**, regardless of what it does when the network is down. Read both; the file:line
evidence is consistent between them, the verdict on the core Blocs is not.

---

## VERDICT: NOT OFFLINE-FIRST

This breaks the offline-first architecture. The required infrastructure exists
(`OfflineQueueService`, `CacheService`/Hive, `SyncEngine`, `LanHubService`) but the UI layer
still makes network-vs-local decisions itself and blocks state transitions on awaited HTTP
calls. That is true even in the app's *best-built* flows (order creation, payment, item
edit), not just its neglected corners.

---

## Quick-reference violation table

| # | Severity | Forbidden pattern (verbatim from rules) | Where | 
|---|---|---|---|
| V1 | 🔴 Critical | "Blocking order creation because request hasn't finished" | [create_order_bloc.dart:81-244](lib/features/view/main/presentation/cubit/create_order/create_order_bloc.dart#L81-L244) |
| V2 | 🔴 Critical | "Blocking payment because request hasn't finished" | [payment_bloc.dart:141-224](lib/features/view/main/presentation/cubit/payment/payment_bloc.dart#L141-L224) |
| V3 | 🔴 Critical | "Blocking table changes because request hasn't finished" (item add/cancel/qty-sync) | [detail_bloc.dart:634-887](lib/features/view/main/presentation/cubit/detail/detail_bloc.dart#L634-L887) |
| V4 | 🟠 High | "If local empty, fetch server" / "Fetch when opening screen" | [main_cubit.dart:55-164](lib/features/view/main/presentation/cubit/main/main_cubit.dart#L55-L164) |
| V5 | 🟠 High | "If local empty, fetch server" / "Load Categories" | [detail_bloc.dart:125-181,958-1028](lib/features/view/main/presentation/cubit/detail/detail_bloc.dart#L125-L181) |
| V6 | 🟠 High | "Fetch when opening screen" (bill/order detail has no Sync Engine coverage at all) | [payment_bloc.dart:396-512](lib/features/view/main/presentation/cubit/payment/payment_bloc.dart#L396-L512) |
| V7 | 🟠 High | "Repository deciding whether to fetch remotely" (35+ of ~40 methods are bare network passthroughs; the 5 that aren't do it ad hoc) | [main_repository_impl.dart](lib/features/view/main/data/repository/main_repository_impl.dart) |
| V8 | 🟡 Medium | "Network requests inside Widgets" (per-screen polling loops duplicating `SyncEngine`'s tick) | [archive_screen.dart:56-59](lib/features/view/main/presentation/pages/archive/archive_screen.dart#L56-L59), [waiter_floor_plan_screen.dart:75-78](lib/features/view/main/presentation/pages/main/waiter_floor_plan_screen.dart#L75-L78) |
| V9 | 🟡 Medium | "FutureBuilder calling APIs" | [menu_manage_screen.dart:2432-2434](lib/features/view/main/presentation/pages/menu/menu_manage_screen.dart#L2432-L2434) |

Back-office CRUD (menu, staff, transactions, halls/tables, service charge) is **not**
re-listed here — it's already fully covered as Critical (C1/C2) in
`offline-first-compliance-audit.md` and the grade there stands: those screens have zero
cache, zero queue, zero offline behavior at all.

---

## V1 — Order creation blocks on the network when online

**File:** `create_order_bloc.dart:81-244`

`_createOrder` does: `emit(Status.LOADING)` → `await _createOrderUsecase.call(request)` (a
live HTTP POST) → only on `ConnectionFailure` does it fall into `_handleOfflineOrder` and
enqueue. Same shape for takeaway (`_createTakeAwayOrderUsecase`, L113) and for adding items
to an already-open table (`_addItemsToExistingOrder` → `_mainRepository.createOrderItems`,
L259).

**Why this is a violation:** the branch taken depends on `_connectivity.isOnline` /
whether the awaited call throws a connectivity-classified failure — a client-side
network-first decision living in the Bloc. When the network is up (the common case), the
cashier's "create order" action is gated on a full round-trip to the backend.

**Fix:** delete the online branch. Every call to `_createOrder` writes to the local
DB/outbox unconditionally, no `await` on a network usecase, no `Status.LOADING` tied to a
network response. `OfflineQueueService` (already built, already draining every 60s via
`SyncEngine.tick()`) is the only thing that ever POSTs this to the backend.

## V2 — Payment blocks on the network when online

**File:** `payment_bloc.dart:141-224`

`_payment` does: `emit(Status.LOADING)` → `await _createPaymentUsecase.call(...)` → only on
`ConnectionFailure` does it call `_enqueuePayment()`. Same shape for the zero-total
cancel-order path (L159, `_mainRepository.cancelOrder`).

**Why this is a violation:** identical shape to V1, for the single highest-stakes action
in the app (taking money). "I don't care if it's cached" / "no exceptions" applies exactly
here — a slow network makes the cashier wait for a response before the UI accepts the
payment happened, purely because the app happened to be online.

**Fix:** same as V1 — write-then-queue unconditionally, no awaited network call in the
Bloc's success path.

## V3 — Existing-item edits (add/cancel/qty change) block on the network when online

**File:** `detail_bloc.dart:634-887` (`_deleteExistingByKey`, `_onSyncExistingItem`)

Both handlers set `existingSyncingNames` (which disables the item's +/-/delete buttons in
the UI) and then `await _mainRepository.cancelOrderItem(...)` / `createOrderItems(...)`
directly — falling into the offline queue only in the `catch` block, only if
`_isConnectionIssue(e)` is true.

**Why this is a violation:** button-disable-until-network-responds is a soft version of a
blocking spinner, and it's driven by an awaited HTTP call inside a presentation-layer
Bloc — "network requests inside Controllers/ViewModels," listed as forbidden.

**Fix:** apply the quantity/cancel change to local state + outbox synchronously; re-enable
the buttons the instant the local write completes, not when the network call resolves.

## V4 — `MainCubit` reads cache, then unconditionally calls the network itself

**File:** `main_cubit.dart:55-164` (`_getTablesByHallId`, `getHalls`, `loadAllHallsTables`)

Each method: emit cached tables/halls first, then (throttled by a timestamp the Cubit
tracks itself) `await` a usecase that hits the backend directly, then emit again.

**Why this is a violation:** this is "if local empty, fetch server" relocated into the
Cubit. The Cubit — not a repository, not the Sync Engine — decides to hit the network
based on `_connectivity.isOnline` and its own throttle map.

**Fix:** `MainCubit` should only ever read `CacheService`/local DB, ideally reactively
(subscribed to a listenable), with zero network calls of its own. All hall/table refresh
belongs in `SyncEngine.tick()`, which already hydrates halls/tables for the reference-data
bundle (`sync_engine.dart:141-184`) — there is no reason for `MainCubit` to *also* fetch
them.

## V5 — `DetailBloc` categories/goods follow the same cache-then-fetch shape

**File:** `detail_bloc.dart:125-181` (`_onGetCategories`), `:958-1028` (`_onSetSelectedCategoryId`)

Same shape as V4: show cache, throttle-check, `await _getCategoriesUsecase`/
`_getGoodsByCategoryIdUseCase` directly, emit again.

**Fix:** same as V4 — this data already gets hydrated by `SyncEngine._hydrateReferenceData()`
for categories; goods-by-category has no Sync Engine equivalent today and would need one,
but that hydration belongs in the Sync Engine, not in `DetailBloc`.

## V6 — Bill/order detail has no Sync Engine coverage — it's 100% fetch-on-open

**File:** `payment_bloc.dart:396-512` (`_onGetDetail`)

Cache is shown first, then `_getPaymentDetailWithTableIdUsecase`/`_getPaymentDetailWithIdUsecase`
is awaited directly with no Sync Engine equivalent ever populating this cache in the
background. This is the purest form of "fetch when opening screen" in the codebase — there
is no other path that ever refreshes this data.

**Fix:** either the Sync Engine periodically pulls open-order detail for all open tables,
or (more realistically, given order detail is keyed per-table and can be large) the
*local* write side (V1/V3) is trusted as the source of truth for what's on a bill, and the
network fetch is deleted entirely rather than "moved" — since every mutation already goes
through the outbox, the UI has no actual need to re-derive bill state from the network at
all once local-first writes are in place.

## V7 — The repository layer has no consistent offline behavior to inherit

**File:** `main_repository_impl.dart`

Of ~40 methods, only `getUsers` (L61), `getServiceCharge` (L215), `getTransactionGroups`
(L251), `getIngredients` (L435), and `getCompounds` (L450) have any cache-fallback logic.
`getCategories` (L118), `getHalls` (L113), `getAllTables` (L86), `getTablesByHallId` (L96),
`getGoodsByCategoryId` (L128), `getArchiveWithId` (L147), `getOrderTableTimer` (L199),
`getPrinterSettings` (L164) — all bare one-line passthroughs to `_dataSources`.

**Why this is a violation:** whatever cache-first behavior exists for these entities (V4,
V5) was reinvented per-Bloc because the repository itself has no opinion. New code built
against this repository inherits zero offline behavior by default.

**Fix:** this repository should not hold a `ConnectivityCubit` or a network-backed
datasource at all. Its read methods query the local DB; nothing else has any business
calling `DioClient`.

## V8 — Screens run their own polling loops, duplicating the Sync Engine

**Files:** `archive_screen.dart:56-59`, `waiter_floor_plan_screen.dart:75-78`

Both `initState()` methods set up `Timer.periodic` that checks
`inject<ConnectivityCubit>().isOnline` and, if true, triggers a Bloc method/event that
performs a live fetch — a second (and third) independent polling loop living in the widget
tree, alongside `SyncEngine`'s own 60s tick.

**Fix:** delete both timers. `SyncEngine` is the only clock in this system.

## V9 — `FutureBuilder` calling an API directly

**File:** `menu_manage_screen.dart:2432-2434`

```dart
return FutureBuilder<Uint8List?>(
  future: MinioService.instance.getImageByObjectName(ref),
  ...
```

Named verbatim as forbidden. Lower blast radius (meal images, not transactional data) but
unchanged in the code as of this audit.

**Fix:** same as everywhere else — the image bytes/URL should come from local state
populated by a background sync step, not a `Future` built inside the widget tree.

---

## Why this audit's verdict differs from `offline-first-compliance-audit.md`

The prior audit's H1 finding acknowledges the exact same code (V1-V3 here) and calls it
"functionally offline-resilient... compliant in effect" because the `ConnectionFailure`
branch does correctly enqueue. That's true as far as it goes. This audit scores it as a
hard violation anyway, because the standard being applied here is explicit and absolute:
**"If the UI depends on the network to do anything, that's a bug... I don't care if it's
only one request... if the UI waits for the network, you f\*\*\*ed up."** A write path
that is network-first whenever the network is reachable, with the queue only as an
exception handler for the unreachable case, *is* a UI that depends on the network for its
normal-case behavior. It is not local-first with the network as an optional accelerant —
it is network-first with local-first as the degraded mode.

Both framings are internally consistent; they're answering different questions. The prior
audit asks "does the offline queue eventually catch every write." This one asks "does the
UI ever wait on the network to do its job." The answer to the second question is yes, in
every core flow, which is why the verdict here is an unqualified **no**.
