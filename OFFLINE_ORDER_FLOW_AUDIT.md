# Offline Order-Flow Audit — every action, checked for actual correctness

**Purpose:** work order for the next agent. The rule is absolute: **every action
in the ordering flow is offline-first — a single local commit + outbox enqueue,
no direct requests, and NO network fallbacks.** "It enqueues" is not the bar;
the bar is: *after the action, is the local database a correct, coherent
picture of the order — the one the payment screen, the table map, the waiter
list, and the receipt will all be computed from?*

Every claim below was verified by reading the current code on branch
`claude/client-facing-offline-plan-f8jbom` (file:line refs are to that state).
Defects are numbered **D1–D12** and cross-referenced from the actions; the
prioritized fix list is at the bottom. Read `EXECUTION_CONCERNS.md` alongside —
this doc supersedes its flow-level notes where they overlap.

**Key storage facts referenced throughout:**

- The **local bill row** = `LocalDatabase`'s `orderDetail` box entry, keyed by
  `tableId` (dine-in) or `clientOrderId` (takeaway), wire-shaped like
  `ArchiveDetailModel` (`items` list where each item has `id` (line id),
  `good_id`, `good_name`, `quantity`, `price`, `status`, `created_at`).
- The **outbox** = `OfflineQueueService` (`PendingOperation`), replayed by type
  in this order: `createOrder → addItems → cancelLineItems → transferTable →
  timerAction → payOrder → cancelOrder → openShift → closeShift`
  (`offline_queue_service.dart:160-176`).
- **Totals** = `OrderTotals.fromDetail` (`core/utils/order_totals.dart`) —
  sums `detail.goods` where `status != 'cancelled'`, adds service % from the
  detail (or a caller-supplied fallback), plus table charge and offline extras.

---

## Part 1 — Action-by-action

### A1. Open table — cashier dine-in (`CreateOrderBloc._createOrder`)

- **Does:** shift check (local) → lease (LAN/in-memory, §A16) →
  `OrdersRepository.createOrder` (enqueue `createOrder` op with client-generated
  order id) → writes a local bill snapshot via `saveOrderDetailSnapshot`
  (`create_order_bloc.dart:158-165`) → kitchen receipt → SUCCESS.
- **Local truth after:** bill row exists under `tableId` with the order id,
  items, prices, `foodTotal`. ✅ mostly correct, with three defects:
  - The snapshot's items are `OrderFoodModel`s that carry `good_id`
    (`goodId: o.goods.id`) but leave the line **`id` field at its `''`
    default** (`_buildLocalOrderSnapshot`, `create_order_bloc.dart:253-270`).
    No line ids ⇒ these items cannot be individually cancelled later, locally
    or at replay (→ **D1/D2**).
  - `servicePercent` is not written into the snapshot even though the venue's
    percent sits locally in the `serviceCharge` box ⇒ totals for
    locally-created orders silently omit service (→ **D4**).
  - The table is NOT marked busy in `LocalDatabase` by the repository — only a
    LAN broadcast fires (`orders_repository_impl.dart:96-100`;
    `LanHubService.tableStatusChanged` only broadcasts, `lan_hub_service.dart:329-335`,
    and broadcasts **no-op entirely in `LanMode.disabled`**, i.e. every solo
    venue). The busy write happens *screen-side* via
    `MainCubit.updateTableStatus` (`department_selection_screen.dart:107`,
    `detail_screen.dart:124`, `order_actions_bar.dart:590`) (→ **D5**).

### A2. Open table — waiter screen (`WaiterLocalRepositoryImpl.createOrder`)

- **Does:** local double-open guard → lease → enqueues its own `createOrder`
  payload (keeps `waiter_id`) → writes bill snapshot → **does** call
  `_localDb.updateTableStatus(busy)` + LAN broadcast → grants release.
- **Local truth after:** ✅ correct shape; same snapshot weaknesses as A1
  (no line ids, no service percent → **D1/D4**). Note the asymmetry with A1:
  this path updates the table box itself; A1 doesn't (→ **D5**).

### A3. Open timed order (`TableTimerLocalRepositoryImpl.createTimedOrder`)

- **Does:** reuse guard → lease → `OrdersRepository.createOrder` (empty items)
  → minimal bill snapshot → initial timer record with the table's local
  `price_per_hour` → grant release. Table busy comes from
  `OrdersRepository.createOrder`'s LAN broadcast + the *screen's*
  `MainCubit.updateTableStatus` (`detail_screen.dart:124`) (→ **D5**).
- **Local truth after:** ✅ bill row + timer record correct. But
  `detail_screen._autoStartTimedOrder` then fires
  `fetchBillOrders(force: true)` which triggers the **network fallback fetch**
  (→ **D6**).

### A4. Takeaway create (`CreateOrderBloc._handleTakeaway`)

- **Does:** enqueue `createOrder` (takeaway shape) → snapshot under
  `clientOrderId` → navigate straight to payment.
- **Local truth after:** ✅ correct for paying immediately. ❌ after the pay
  (A11) the row is never evicted or marked paid, so a stale "open" takeaway
  row lives in the box forever and surfaces in the waiter open-orders list
  (which filters takeaway rows by `status == open`,
  `waiter_local_repository_impl.dart:79-87`) (→ **D3**).

### A5. Add items to a NEW order (cart, before first send)

- Pure in-memory state (`DetailBloc.selectedGoods`, `SavedOrdersBloc` drafts).
  ✅ fully local, no issues.

### A6. Add items to an EXISTING order (`DetailBloc` send / `OrdersRepository.addItems`)

- **Does:** enqueue `addItems` (with `client_item_id` idempotency keys) +
  record item timestamps + LAN busy broadcast. Returns instantly. ✅ as a write.
- **Local truth after:** ❌ **the bill row is NOT updated**
  (`orders_repository_impl.dart:118-146` — enqueue + timestamps only; contrast
  with the waiter path, which patches the row,
  `waiter_local_repository_impl.dart:228-262`). Consequences:
  - The payment screen's **item list** doesn't show the new items until a
    server hydration pass lands (needs internet).
  - The **due total** is papered over by `PaymentBloc.pendingOfflineExtra`
    (`payment_bloc.dart:277-304`), which re-derives pending items' cost from
    the queue + goods cache. Total ≈ right, list wrong, and the whole
    mechanism exists only because the row isn't patched. (→ **D2**)
  - On screen close/reopen, `DetailBloc` rebuilds `existingGoods` from the
    (stale) row — offline-added items **disappear from the cashier's view**
    while still being owed. (→ **D2**)

### A7. Increment existing item (`DetailBloc._onIncrementExistingItem` → `_onSyncExistingItem`)

- **Does (intended):** debounced net-delta → `OrdersRepository.addItems` for
  the delta. Local commit only. ✅ in shape.
- **❌ BROKEN offline:** the sync handler requires `snapshot.goodId`, which
  comes exclusively from `_existingLineInfo` — populated **only** by the
  direct network call `MainRepository.getOrderItemsRaw`
  (`detail_bloc.dart:212-283`, fired from every detail update). If that fetch
  has not succeeded this session, the edit is refused with *"Ma'lumot
  yuklanmagan. Yana urinib ko'ring."* (`detail_bloc.dart:641-651`). This is a
  **direct-request dependency in the middle of the core flow** — the exact
  thing the rule forbids. The absurdity: the local bill row already contains
  `good_id` per item for hydrated orders — the network round trip re-fetches
  data that is sitting in the box. (→ **D1**)
- Also: the delta-add doesn't patch the bill row (→ **D2**).

### A8. Decrement existing item (same handler, negative delta)

- **Does (intended):** cancel ALL original lines (`cancelLineItems`) +
  re-add remainder as one line. Local commit only.
- **❌ BROKEN offline, twice:**
  1. Same `goodId`/line-id dependency on the network fetch as A7 (→ **D1**).
  2. Even when it proceeds: `cancelLineItems` **does not patch the bill row**
     (`orders_repository_impl.dart:148-168`), and `pendingOfflineExtra` only
     ADDS pending `addItems` — nothing subtracts pending cancels. Offline
     sequence: decrement 3→1 ⇒ queue holds [cancel 3 lines, add 1] ⇒ due
     total = stale row (3) + pending add (1) = **4 portions charged for 1
     kept**. This is a live **overcharge** path. (→ **D2**)

### A9. Delete existing item (`DetailBloc._deleteExistingByKey`, waiter `cancelOrderItem`)

- **Cashier:** `_resolveLineIds` falls back to the bill row's own line ids
  when the network map is empty (`detail_bloc.dart:789-795`) — works offline
  for **hydrated** orders; for never-synced local orders the ids are empty/
  client-generated, so the replayed cancel 404s and is **silently skipped** —
  the item is never cancelled server-side while the local UI says it is
  (→ **D1**, replay half). Bill row not patched ⇒ same total overcharge as A8
  (→ **D2**).
- **Waiter:** ✅ better — `WaiterLocalRepositoryImpl.cancelOrderItem` enqueues
  AND patches the row's item status to `cancelled`
  (`waiter_local_repository_impl.dart:196-226`), and `OrderTotals` excludes
  cancelled lines. The two paths disagree about what a cancel does locally —
  the waiter behavior is the correct one; make the cashier path match.

### A10. Item comments / cancel reasons

- Captured at write time into the op payloads (`comment` on add,
  `comment` on cancel). ✅ local. Cancel reason lost from the *local row*
  (only in the payload) — acceptable, note only.

### A11. Pay (`PaymentBloc._payment` → `PaymentRepository.pay`)

- **Does:** computes due (see A12) → enqueues `payOrder` with
  `client_payment_id` idempotency key → prints receipt from state → evicts
  the local **timer** record → broadcasts table free → navigates. ✅ as a
  write; no direct requests.
- **Local truth after:** ❌ incomplete in three ways:
  1. The bill row is neither marked paid nor evicted
     (`payment_repository_impl.dart` is queue-only;
     `payment_bloc.dart:237-273` touches timer + table + drafts only).
     Dine-in: a stale "open" row lingers under the tableId (mostly masked
     because the next open overwrites it, and hydration only refreshes busy
     tables — but the waiter list's takeaway filter and any reader between
     pay and reopen sees a paid order as open). Takeaway: **permanently**
     stale (see A4). (→ **D3**)
  2. An offline-paid order appears in **no archive/shift report** until the
     server syncs and hydrates archives — the close-shift screen undercounts
     the shift while offline. (→ **D10**, cross-side)
  3. Table-free write: `MainCubit.broadcastTableStatus` does write the local
     box (`main_cubit.dart:66-74`) — ✅ — but again only because the *bloc*
     calls it, not the repository that owns the commit (→ **D5**).

### A12. The due total itself (`PaymentBloc.effectiveTotal` vs `payment_screen`)

- ❌ **The amount charged and the amount displayed are computed differently.**
  The screen computes `OrderTotals.fromDetail(... offlineExtra,
  servicePercentFallback: _servicePercent /* nav arg */, includeService …)`
  (`payment_screen.dart:137-151`); the bloc's `_payment` computes
  `effectiveTotal(detail, tableCharge) + pendingOfflineExtra` with **no
  service fallback and no includeService flag** (`payment_bloc.dart:150-155,
  306-312`). For a locally-created order (snapshot `servicePercent == 0`,
  → D4) the displayed total includes service via the nav-arg fallback while
  the card/QR charged amount omits it. One formula must be computed in one
  place with the same inputs. (→ **D4/D11**)

### A13. Cancel whole order / zero-total close (`PaymentRepository.cancelZeroTotalOrder`)

- Enqueues `cancelOrder`; replay tolerates 404. ✅ as a write. Same bill-row
  non-eviction as A11 (→ **D3**).

### A14. Waiter close order (`WaiterLocalRepositoryImpl.closeOrder`)

- ✅ the model citizen: pays via `PaymentRepository.pay`, evicts the bill row,
  evicts the timer record, frees the table locally + broadcast — all in the
  repository. This is what A11/A13 should look like.
- ⚠️ `applyService: true` is hard-coded (`waiter_local_repository_impl.dart:270`)
  where the old direct POST omitted the field — confirm backend equivalence
  (already flagged in EXECUTION_CONCERNS §6).

### A15. Transfer table (`OrdersRepository.transferTable`)

- **Does:** re-keys the bill row to the target table, patches both table
  statuses locally, enqueues, broadcasts. ✅ correct for plain tables.
- ❌ For a **running timed order**: the timer record's `table_id` /
  `price_per_hour` are NOT re-keyed (`local_db_table_timers` untouched), so
  the badge stops following the order and offline single-segment pricing
  continues at the old table's rate. (→ **D7**)

### A16. Table-open lease (all three paths)

- Solo/`server`: in-memory, zero hops. `client`: one LAN round trip (5s cap);
  rejection blocks, unreachable allows-with-warning. **This is the one
  sanctioned wait and it is LAN, not internet — keep.** But note the durable
  check reads the local tables box (`lease_manager.dart:164-179`), which makes
  **D5** (who writes busy locally, and when) load-bearing for lease
  correctness: on the cashier path the busy write happens screen-side *after*
  the commit, widening the race the ephemeral claim must cover.

### A17. Timer start/pause/resume (+ resume after abandoned pay)

- ✅ fully local: record transitions + `timerAction` ops, UI ticks off the
  record, badge and cubit share it, PaymentBloc's resume reads the record.
  Accepted billing-drift tradeoffs documented in EXECUTION_CONCERNS §1.

### A18. Replay-order logic check (does the queue itself do the right thing?)

- Type ordering is correct for the happy paths (create before addItems before
  cancels before pay). Verified issues:
  - ❌ **A cancel of a not-yet-synced item can never succeed.** The queued
    cancel carries local/client line ids; `_execCancelLineItems` 404-skips
    them, `_execAddItems` then (or already) creates the items server-side ⇒
    server bill contains items the cashier deleted; the queued `payOrder`
    amount was computed locally without them ⇒ server-side mismatch on top of
    the local overcharge from A8. Root cause is the missing
    `client_item_id ↔ line id` mapping. (→ **D1**, replay half)
  - ⚠️ `_execAddItems` resolves the open order **by table** over the network
    at replay (`_getOpenOrderIdByTable`) — fine (it's background), but it
    means addItems for a *takeaway* order (tableId '') can never resolve.
    Verify takeaway add-items is impossible in the UI (it appears to be —
    takeaway pays immediately) or fix the executor to use the client order id.

---

## Part 2 — Defect list for the fixing agent (priority order)

### D1 — Existing-item edits depend on a live network fetch; kill it. **(worst)**
Files: `detail_bloc.dart` (lines ~186-283, 577-591, 641-651, 789-795),
`orders_repository_impl.dart`, `offline_queue_service.dart`.
1. Delete `_enrichExistingGoodsWithTimestamps`'s network call
   (`getOrderItemsRaw`) entirely — no fallback.
2. Build `_existingLineInfo` (name → line ids + good_id + qty) **from the
   local bill row** (`detail.goods` already carries `id`/`goodId` for
   hydrated orders) inside `_applyDetailToState`.
3. Make every local write keep that row complete so step 2 always works:
   - `OrdersRepository.addItems` must append items to the row **with their
     `client_item_id` as the line `id`** and real `good_id`/price (see D2).
   - `CreateOrderBloc._buildLocalOrderSnapshot` must write each item's
     `client_item_id` as its line id (generate them at snapshot time and pass
     the SAME ids into `createOrder`'s payload items).
4. Close the replay half: cancels referencing a `client_item_id` must
   resolve server-side. Preferred: `_execCancelLineItems` first tries the id
   as-is; on 404, resolves via `GET order-items` by `client_item_id` match,
   then cancels the real line id. (Backend already stores `client_item_id`
   for idempotency — use it.) If the API can cancel by `client_item_id`
   directly, use that instead.
5. Item timestamps: derive from `detail.goods[].created_at` locally in
   `PaymentBloc._onDetailUpdated`; delete the `CacheService` timestamp store
   and `OrdersRepositoryImpl._recordItemTimestamps` once the row carries
   `created_at` on every locally-written item.

### D2 — The cashier path must patch the bill row on every write, then delete the compensation hacks.
Files: `orders_repository_impl.dart`, `payment_bloc.dart`, `order_totals.dart` callers.
1. `addItems`: append the items to the row (id = client_item_id, good_id,
   name, price from the passed `OrderItem.goods`, `status: 'pending'`,
   `created_at: now`) and bump `food_total` — exactly what
   `WaiterLocalRepositoryImpl.sendItems` already does; move that logic INTO
   `OrdersRepositoryImpl.addItems` so both paths share it, then delete the
   waiter repo's duplicate.
2. `cancelLineItems`: mark matching row items `status: 'cancelled'` (move
   `_markLineCancelledLocally` from the waiter repo into
   `OrdersRepositoryImpl`).
3. Then **delete `PaymentBloc.pendingOfflineExtra` and every call site** —
   with the row always current, the row is the single source of the total.
   This also fixes the A8 overcharge automatically (cancelled lines excluded
   by `OrderTotals`).

### D3 — Pay/cancel must finish the local story.
Files: `payment_bloc.dart`, `payment_repository_impl.dart` (or a shared spot).
1. On `pay`/`cancelZeroTotalOrder` commit: update the bill row's status to
   paid/cancelled **and evict it** from the `orderDetail` box (dine-in key =
   tableId, takeaway key = clientOrderId — evict both lookups like the waiter
   close does). Do it in the repository, not the bloc, so every caller gets it.
2. This kills the stale takeaway rows in the waiter list (A4) and the
   paid-shown-as-open window (A11).

### D4 — Service percent must come from local data, one formula, one place.
Files: `create_order_bloc.dart`, `waiter_local_repository_impl.dart`,
`payment_bloc.dart`, `payment_screen.dart`.
1. Snapshots (A1/A2/A3) write `service_percent` from
   `LocalDatabase.getServiceCharge(branchId)` (branch id from the logged-in
   user) so locally-created orders carry the venue's percent from birth.
2. `PaymentBloc._payment` and the screen must compute the SAME total: give
   `PaymentBloc` the `servicePercentFallback`/`includeService` inputs (or
   better, compute `OrderTotals` once in the bloc and have the screen render
   `state`), eliminating the charged-vs-displayed divergence (A12).

### D5 — Table busy/free writes belong to the repository commit, not screens.
Files: `orders_repository_impl.dart`, the three screens listed in A1.
`createOrder` → `_localDb.updateTableStatus(busy)` inside the repository
(waiter/timed already comply); pay/cancel → free inside `PaymentRepository`'s
commit (needs `LocalDatabase` + `LanHubService` injected there). Screens keep
only presentation. Note `LanHubService.tableStatusChanged` broadcasts nothing
in solo mode — the local write is the ONLY thing keeping a solo venue's table
map and lease-durable-check honest.

### D6 — Remove the bill-row network fallback fetch.
File: `detail_bloc.dart:180-200`. Per the rule ("no fallbacks"): delete the
`getPaymentDetailWithTableId` call and the `force` flag. Local snapshot +
SyncEngine hydration are the only sources. (Cross-terminal orders appear on
the next hydration pass — if that latency matters, the fix is LAN bill
broadcast, not a cloud fetch from the UI.) Also remove `MainRepository` from
`DetailBloc`'s deps once D1 lands — after these two, the bloc has zero
network-capable dependencies.

### D7 — `transferTable` must move the timer record.
File: `orders_repository_impl.dart` (`transferTable`). If a timer record
exists for the order: settle it to now, update `table_id`/`current_table_id`
and `price_per_hour` to the target table's, save. (Multi-rate segment
history stays a documented offline limitation.)

### D8 — (folded into D1 step 5 — timestamps from the row.)

### D9 — Waiter list scoping.
`getOpenOrders(mode)` serves the same set for waiter vs cashier. Store
`waiter_id`/`cashier_id` in the bill snapshot at create (the waiter path
already knows it) and filter `myOrders` by the logged-in user. Low priority.

### D10 — Offline-paid orders are invisible to the shift report until sync.
Cross-side: at pay commit, append a minimal local archive entry (bill no,
total, payment type, time) to a local "today" list the archives box merges
with hydrated data, so the close-shift screen is correct offline. Requires a
small dedupe rule (client_payment_id) when server hydration later lands the
same order.

### D11 — (folded into D4 step 2.)

### D12 — Replay executor for takeaway addItems (A18 second bullet): verify
unreachable in UI or fix `_execAddItems` to resolve by client order id.

---

## Part 3 — What is already correct (do not "fix")

- New-order create, takeaway create, pay/cancel/close/transfer/shift/timer
  **as writes**: single local commit + outbox, idempotency keys on pay
  (`client_payment_id`) and items (`client_item_id`), 409-merge on create
  replay, per-op retry counters. No UI await of the cloud anywhere.
- Waiter screen reads/writes (post-rebuild) — and its `sendItems`/
  `cancelOrderItem` row-patching is the reference implementation D2 promotes.
- Timer runtime (local record, shared by cubit/badge/payment).
- The lease LAN wait — sanctioned, keep as is.
- Replay type-ordering — correct once D1's id mapping exists.

*Audit of branch `claude/client-facing-offline-plan-f8jbom` as of this
commit. Written blind to a compiler like everything else here — line numbers
drift, grep the symbols.*
