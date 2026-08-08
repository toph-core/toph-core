# Client-Facing Side: Zero-Request Plan

Scope: **only** the client/terminal app's UI layer (blocs/cubits/widgets under
`lib/features/view/**/presentation/**`). The backend/sync-engine side (whatever keeps
`LocalDatabase` populated in the background — today: `SyncEngine`, `OfflineQueueService`)
is a separate, out-of-scope "other side." This plan assumes that side exists and keeps
doing its job; it does not redesign it, except where a client-facing fix is blocked on
something that side doesn't do yet — those spots are called out explicitly as
cross-side dependencies, not solved here.

## The rule

Every screen/bloc that shows tables, categories, menus, or handles opening/adding-to/
closing/paying/removing-items-from orders, or starting/pausing/resuming the table timer,
reads only from `LocalDatabase` and writes only to `LocalDatabase` (+ outbox enqueue for
eventual sync). No direct network call, ever, no matter online/offline state — "online"
just means the outbox drains fast, it never means the UI is allowed to await Dio again.

## Two explicit carve-outs (confirmed with product owner)

**1. First-time login / initial setup.** A terminal that has never completed setup for
its current brand+branch is allowed to hit the network — this is prep phase, not runtime.
After that initial fetch, login must work with no internet. Rule for what happens to
existing local data on a *new* login:

| New login is... | Action |
|---|---|
| Same brand, same branch as last time | No special handling — normal offline-capable login |
| Same brand, **different branch** | Keep existing local data, allow a refetch for the new branch's data (additive, not destructive) |
| **Different brand** entirely | Clear local brand-scoped data first, then run first-time setup fresh |

**2. Table-open lease check.** Comment out the `LeaseManager.acquireTableLease` /
`releaseTableLease` calls in `create_order_bloc.dart` — do not delete `LeaseManager` or
its service. Table-open becomes a pure local write like everything else for now; the
double-booking race this was guarding against gets picked back up later as its own piece
of work. This directly resolves the one previously-agreed exception in
`offline-first-target-architecture.md` §6 — that document will need a follow-up note once
this lands, since it currently describes the lease wait as intentional.

---

## Current-state audit (verified by reading the actual code, not the doc comments)

| Area | Status |
|---|---|
| Cafe tables list/grid (`MainCubit`, `TablesRepository`) | Clean — already local-first |
| Order create/add-items/cancel-items (`CreateOrderBloc`, `DetailBloc`, `OrdersRepository`) | Clean — already local-first (aside from the lease wait, carve-out #2) |
| Payment `pay()` / `cancelZeroTotalOrder()` (`PaymentBloc`, `PaymentRepository`) | Clean — already local-first |
| Shift open/close (`ShiftBloc`) | Clean — only startup reconciliation is direct network |
| Categories/goods display (`MenuRepository`) | Clean — already local-first |
| **Table Timer** (`TableTimerCubit`, `TableTimerLocalRepositoryImpl`) | **Direct network by design** — every method, plus a 60s poll loop |
| **`TimeBasedTableBadge` widget** | **Direct network** — its own independent 60s poll + pause/resume, bypasses the cubit entirely |
| **Waiter screen** (`WaiterCubit`, `WaiterLocalRepositoryImpl`) | **Direct network-first** for every read and write; outbox only as a failure fallback |
| **Archive screens** (`ArchivesBloc`/`ArchiveBloc`) | **Direct network-first** for anything other than the default "today, page 1" view |
| **Close-shift screen** | Active 30s poll that force-refetches archives over the network |
| Goods search (department selection + detail-screen search) | **Direct network**, explicitly documented as having no local mirror |
| `PaymentBloc.resumeTimerAfterFailedPay` / `_fetchItemTimestamps` | **Direct network** side calls |
| `transferTable`, `saveServiceCharge`, `getHourPrice`, `getUser`, PIN-verify | **Direct network**, scattered single call sites |

---

## 1. Login & first-time setup

**Files:** `login_repository_impl.dart`, `auth_datasource.dart`, `login_pin_cubit.dart`,
`token_storage_impl.dart`, `splash_screen.dart`, `auth_cubit.dart`.

Current state is closer to done than it looks: `loginWithBrandId()` is already local-only,
and `LoginPinCubit.login()` already has an offline branch reading `OfflineAuthCache`. What's
missing is the brand/branch-aware retention rule above. Concretely:

- **Persist "last known brand + branch" locally.** `BrandIdTokenPair` stores `brandId`
  already; branch is currently only ever decoded from the JWT's `cash_register_id`
  (`shift_bloc.dart:94-115`) and never persisted on its own. Add a stored "last
  authenticated brand id + cash_register_id" pair, written after every successful login.
- **On each new login, compare against that stored pair** before touching any cached
  data:
  - brand matches, cash_register_id matches → normal path, no data action.
  - brand matches, cash_register_id differs → allow a scoped refetch for the new branch
    (tables/halls/open-orders for that branch); do not wipe brand-level catalog data
    (categories/goods/ingredients/compounds).
  - brand differs → clear brand-scoped `LocalDatabase` boxes, then run the first-time-setup
    fetch again.
- **Open question, needs product input, not decided here:** which `LocalDatabase` boxes
  are brand-scoped (wipe on brand switch) vs. branch-scoped (refresh on branch switch) vs.
  device-scoped (never touched by login at all)? From `local_database.dart:49-64`:
  `categories`, `departments`, `goods`, `goodsByCategory`, `ingredients`, `compounds` read
  as brand-wide catalog; `halls`, `tables`, `cashRegisters`, `archives`, `orderDetail` read
  as branch-scoped; `printerSettings` reads as device-scoped (shouldn't be touched by
  login at all — it's a property of the physical hardware, not the account). This needs a
  yes/no pass from whoever owns that call before implementation, since getting it wrong
  either leaks one branch's open orders into another's view or force-redownloads the full
  catalog on every branch switch.
- **`isPosInitialized`** (`token_storage_impl.dart:178-185`) is currently written but never
  read anywhere — this is the natural flag to gate "first-time setup vs. normal login," it
  just needs an actual read site added at splash/login time instead of sitting unused.
- **Two calls to reconsider, not strictly in your named list but load-bearing for "shows on
  the UI":**
  - `ShiftBloc._checkShift()` (`shift_bloc.dart:296`) — direct network startup check, but
    already has a `_readLocalShift` fallback. Flip it: local read is primary, no network
    call initiated from here at all. If shift state can drift from the server, that's the
    sync engine's job to reconcile in the background, not this bloc's.
  - `UserBloc._getUser()` (`user_bloc.dart:43`) — fire-and-forget profile fetch on splash
    and every reconnect (`app_scaffold.dart:110`). Already has `_tryOfflineUser` fallback.
    Same treatment: stop initiating it from the UI layer; rely on cached profile.

## 2. Table Timer — the biggest architectural reversal in this plan

**Files:** `table_timer_cubit.dart`, `table_timer_local_repository_impl.dart`,
`time_based_table_badge.dart`, plus the two side-calls in `payment_bloc.dart`.

`TableTimerLocalRepositoryImpl`'s own doc comment (lines 11-21) states the network-only
design is **deliberate**, for billing correctness — not an oversight like the others. Your
instruction explicitly names "starting, closing, resuming the table timer" as in scope, so
this plan includes it, but flagging directly: converting this to local-first means the
elapsed time / amount-due a terminal shows can now disagree with the server (and with any
other terminal) until sync catches up, exactly the class of risk that doc comment was
written to avoid. Worth a conscious sign-off before work starts here, not just a side
effect of following the general rule.

What changes:
- `fetchTimer()`, `_fetchBillDetails()`, `createTimedOrderAndStart()`, `startTimer()`,
  `pauseTimer()`, `resumeTimer()` (`table_timer_cubit.dart:265-508`) all become local
  writes to `LocalDatabase` + outbox enqueue, reading back from local state, not Dio.
- `_ensureServerSync()`'s `Timer.periodic(60s)` poll (`table_timer_cubit.dart:48-57`) gets
  deleted outright — that's a request trigger by definition.
- Elapsed-time math already exists locally (`computeAnchoredLiveAmount`,
  `table_timer_cubit.dart:59-100`) and becomes the sole source of truth instead of a
  UI-only tick between reconciliations.
- **`TimeBasedTableBadge`** (`time_based_table_badge.dart:165-210`) runs a fully
  independent 60s poll + pause/resume network calls, parallel to and bypassing
  `TableTimerCubit` entirely. This needs to be rebuilt to read the same local timer state
  instead of polling on its own — right now there are two different code paths that can
  each hit the network for the same table's timer, and only one of them is even in the
  cubit you'd otherwise be fixing.
- **New local storage needed:** elapsed/paused timer state isn't currently modeled as its
  own thing locally (no dedicated box) — needs a place to live, most likely alongside the
  existing `orderDetail` box entry for that order since the timer is order-scoped.
- `PaymentBloc.resumeTimerAfterFailedPay()` (`payment_bloc.dart:215-235`) — direct network,
  converts to a local operation once the above lands.
- **New outbox operation types needed** (current `PendingOperationType` enum has 7 values:
  `createOrder`, `addItems`, `payOrder`, `openShift`, `closeShift`, `cancelLineItems`,
  `cancelOrder` — none cover timer actions). Needs new type(s) for
  create-timed-order/start/pause/resume, defined in
  `lib/core/services/offline_queue/pending_operation.dart` alongside a new
  `_execTimerAction`-style branch in `OfflineQueueService`.

## 3. Goods/menu search

**Files:** `department_selection_cubit.dart:73-86`, `detail_bloc.dart:919-943`,
`menu_local_repository_impl.dart:57-60`.

Both search paths are explicitly documented as "no local mirror to search against" and go
straight to `MainRepository.getGoodsWithName` over the network, debounced 500ms. Given the
login/setup phase (item 1) is expected to pull the full catalog into `LocalDatabase`
already (that's what makes categories/goods display local-first today), this becomes a
local filter over the already-synced `goods` box instead of a network query — no new data
dependency, just swapping what `searchGoodsByName` does under the hood.

## 4. Archive screens

**Files:** `archives_bloc.dart`, `archive_bloc.dart`, `archives_local_repository_impl.dart`,
`close_shift_screen.dart:54-63`, `sync_engine.dart:264-276` (`_hydrateArchives`).

- `watchArchives()` is already local-first, but only the box's current contents — and
  `SyncEngine._hydrateArchives()` only ever hydrates the default "today, page 1" view into
  that box (confirmed by reading `sync_engine.dart:264-276` directly). Every filtered,
  paginated, searched, or date-ranged archive view, and every archive **detail** view
  (`getArchiveWithId`), currently has no local data behind it beyond that one default page.
- **This is a real cross-side dependency, not something this plan alone can finish:** making
  `ArchivesBloc`'s filter/search/pagination/detail local-first requires the backend/sync
  side to actually hydrate more than "today, page 1" into the `archives` box first. The
  client-facing change here (querying/filtering/paginating locally instead of over the
  network) is straightforward once that data is there; it does nothing useful before that.
  Flagging this explicitly so it doesn't get silently scoped as "just swap the repository
  call" — it isn't, on the data side.
- `close_shift_screen.dart:54-63`'s `Timer.periodic(1s)` that force-refetches archives every
  30 ticks needs to go, in favor of the reactive stream — `archive_screen.dart` already did
  exactly this same removal once (its own comment at line 51 says so), this is the same
  fix applied to the one remaining poll site.
- `ArchiveBloc` (singular, `archive_bloc.dart`) is currently dead code — registered in DI
  but no screen references it (confirmed by grep). Doesn't need conversion work; flagging
  so it isn't mistaken for a second thing to fix.

## 5. Waiter screen — largest single item

**Files:** `waiter_cubit.dart`, `waiter_local_repository_impl.dart`.

This repository's own doc comment (lines 17-32) calls itself "a pure online transport":
every read (`loadStaffWaiters`, `loadOpenOrders`, `loadOrderDetail`, `loadOrderItems`) and
every write (`cancelOrderItem`, `sendItems`, `closeOrder`, `createOrder`) goes to Dio first,
every time, when online — outbox enqueue only happens in the *cubit* as a fallback after a
connectivity failure, which is the inverse of the local-first-then-sync pattern
`OrdersRepository`/`PaymentRepository` already use correctly.

Recommendation: don't patch `WaiterLocalRepositoryImpl` method-by-method — retire it and
rebuild `WaiterCubit` on top of the repositories that are already correct
(`OrdersRepository`, `PaymentRepository`, `TablesRepository`, `MenuRepository`). Concretely:
- `loadOpenOrders`/`loadOrderDetail`/`loadOrderItems` → `watch`-style reads already exposed
  by `OrdersRepository`/`TablesRepository`, same as `MainCubit`/`DetailBloc` use.
- `createOrder`/`cancelOrderItem`/`sendItems` → same local-write-then-outbox calls
  `CreateOrderBloc`/`DetailBloc` already make — no new operation types needed here, this
  is reuse, not new plumbing.
- `closeOrder` (`waiter_local_repository_impl.dart:236-249`, posts to
  `payToOrder` directly) is a second, independent pay/close-order path parallel to
  `PaymentBloc`. Once rebuilt, it should just call `PaymentRepository.pay()` instead of
  having its own — one pay path, not two.
- `loadStaffWaiters` → `_users` box already exists in `LocalDatabase`
  (`local_database.dart:53`) and is populated via `MainRepository.getUsers()`'s existing
  cache-first path; likely just needs a `watchUsers()`-style read added, not new sync
  plumbing.

**Before investing here, worth confirming (not blocking the plan on it, just flagging):**
is the Waiter screen actively used in production, or is it a parallel/earlier UI to the
cashier `detail_screen.dart` + `PaymentBloc` flow? The two screens do overlapping jobs
through entirely different repositories, which reads like one may have superseded the
other. If Waiter isn't in active use, this item drops from "largest item in the plan" to
"can be deferred or dropped."

## 6. Payment-screen side calls

**Files:** `payment_bloc.dart`, `hour_price_bloc.dart`.

- `PaymentBloc._fetchItemTimestamps()` (`payment_bloc.dart:378-413`) — direct network,
  fires unconditionally on every order-detail update. Needs the add-item timestamp
  captured locally at the moment items are written (in `CreateOrderBloc`/`DetailBloc`'s
  existing local-write path) so this can become a pure local read. Currently unconfirmed
  whether that timestamp is captured anywhere today — needs a check during implementation,
  not assumed.
- `HourPriceBloc._getPrice()` (`hour_price_bloc.dart:26-35`) — direct network, no cache,
  called on the payment screen for time-based tables. No dedicated local box for this
  config today; needs one, populated the same way `serviceCharge`'s box already is.
- `resumeTimerAfterFailedPay` — covered under Table Timer (item 2).

## 7. Misc single call sites

- `transfer_table_dialog.dart:86-89` — "transfer to another table," awaited directly in a
  widget, no outbox at all. In scope (it's an order operation shown on the UI, same
  category as create/add-items/cancel). Convert to local write + outbox, same shape as
  `OrdersRepository`'s other methods. Needs a new operation type.
- `service_charge_cubit.dart:59-79` `save()` — explicitly documented as intentionally
  online-only, fails fast instead of queuing. This is a back-office config write, not an
  operational floor action — recommend **excluding** it from this plan rather than silently
  converting a deliberate fail-fast write to queue-and-hope; flag if you want it included
  instead.
- Admin/back-office menu management (`menu_meals_list_screen.dart`, `menu_manage_screen.dart`)
  — self-documented in-code as "online-required" by design (`menu_meals_list_screen.dart:68-70`).
  Same call: recommend **excluding** from this plan as an admin tool rather than an
  operational cashier/waiter screen. Flag if it should actually be in scope.
- Manager-PIN verify (`auth_datasource.dart:63-127`, `manager_pincode_dialog.dart`) —
  already has an offline cache-fallback path; also currently dead code (no call sites
  found anywhere in the app). Lowest priority regardless.

---

## Suggested sequencing

1. **Login/first-setup groundwork** (item 1) — everything else's "is the data already
   local" assumption depends on this being right first, especially the brand-vs-branch
   box-scoping question, which needs a product answer before any box gets cleared by code.
2. **Cheap, isolated wins:** goods search (item 3), `transferTable` (item 7),
   `_checkShift`/`getUser` flip (item 1).
3. **LeaseManager carve-out** (comment out, don't delete) — trivial, two call sites.
4. **Table Timer** (item 2) — largest scope after Waiter, and the one place this plan
   knowingly trades away a documented correctness guarantee, so worth a explicit go-ahead
   before starting rather than discovering the tradeoff mid-implementation.
5. **Archive screens** (item 4) — client-facing part is straightforward, but gated on
   confirming the sync-engine hydration gap gets picked up on the other side; can start
   the default-view/poll-removal parts immediately and hold the rest.
6. **Waiter rebuild** (item 5) — largest item, worth confirming it's still an active
   screen before committing the effort.

This is a plan document only — nothing listed above has been implemented.
