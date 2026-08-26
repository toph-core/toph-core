# Lifecycle Risk Review — Create / Delete / Close / Print

Adversarial correctness review of the four operations a cashier performs constantly,
against the **working tree** of `claude/pos-architecture-spec-uw9wmh` (uncommitted
changes included), cross-checked against the backend at
`/home/spike/Documents/work/MARY_AI/back` and `back/order-total-calculation.md`.

Read-only review. Nothing here was fixed.

**Scope note.** `OFFLINE_FIRST_AUDIT_2026-08-23.md` already documents the LAN/socket
failure family (`LA` listener leak → N× duplicated prints, `LB`/`LC` orphan sockets,
`W7` non-order create duplication, the `clearPending` refcount hole). Those are still
present in the working tree; they are restated here only where a lifecycle path makes
them worse, or where this review found the *election* half of the same problem, which
that audit did not cover.

**Confidence.** Every finding marked CONFIRMED was traced end to end in the working
tree (and, where the verdict depends on the server, in `back/`). SUSPECTED means the
code reads wrong but one link in the chain was not executed or fully traced.

---

## Summary — worst five, ranked

### 1. Paying an open time-based bill from the Archive screen charges **zero** table time — a pure-time bill is silently comped
**Critical. CONFIRMED.**
`archive_right_sider_bar.dart:83-88` navigates to the payment screen with
`arguments: {'order_id': archive.id}` — **no `hour_amount`, no `table_type`, no timer
fields**. `payment_screen.dart:41-46` therefore reads `_passedHourAmount == 0`, the
`upadeHourPrice` event at `:74-78` is gated on `> 0` and never fires, and the timer is
never paused. The fallback that was meant to cover this is dead: `HourPriceBloc` is
provided at `payment_screen.dart:92` but **`HourPriceEvent.started` is dispatched
nowhere in the codebase** (grep across `lib/` returns only the freezed factory
declaration), so the `BlocListener` at `:107-118` never fires. `OrderTotals.fromDetail`
never reads `detail.tableAmount` either — the only table input is the `tableCharge`
parameter (`order_totals.dart:135-163`).

Billiard room, 3 h at 60 000 = 180 000 so'm, no food. Cashier opens the bill from
Archive and taps Оплатить → `totals().grandTotal == 0` → `payment_bloc.dart:166-174`
takes the `dueTot <= 0` branch → **`cancelZeroTotalOrder`**: the check is written
`status: 'cancelled'`, a `/orders/{id}/cancel` is queued, the timer is evicted, the
table is freed and a receipt prints. **180 000 so'm recorded as a comp, no error, no
signal.** With food on the bill the food is charged and the table time is dropped.

### 2. Changing an existing line's quantity writes the local line at **price 0** — offline the line is free, and a one-line check auto-comps
**Critical. CONFIRMED.**
`detail_bloc.dart:565` and `:605` construct the `GoodsModel` handed to
`OrdersRepository.addItems` with `price: '0'`, and `orders_repository_impl.dart:441`
stores `'price': (double.tryParse(item.goods.price) ?? 0).round()` — so the replica row
for the re-created line is priced **0**. Every local read (payment screen, order
screen, receipt) sums that 0. The minus branch (`detail_bloc.dart:590-614`) cancels all
original lines and re-creates one at 0; if that was the only line on the check,
`dueTot <= 0` again routes into `cancelZeroTotalOrder`. Online it self-heals on the
next pull; offline it does not.

### 3. The charged total is the server's **stale `grand_total`**, and an offline-created order is charged **without service**
**Critical. CONFIRMED.**
`order_totals.dart:173-174` takes `coreTotal = detail.grandTotal` whenever no line is
`cancelled` and the stored value is > 0; the compensating `offlineExtra` is now
permanently 0 (`forPayment:212-232` and `payment_bloc.dart:305-316` never pass it). The
doc block at `order_totals.dart:123-134` predicted exactly this ("Phase 4 must switch
this path to `OrderTotals.compute` … in the same change"; it was not). Separately,
`_writeOrderWithItems` writes no `service_percent` (`orders_repository_impl.dart:268-278`)
and the screen's fallback comes from the same empty bill
(`order_actions_bar.dart:736-737`), so an offline-created order prices service at 0 while
`applyService` defaults to **true** (`payment_state.dart:18`) and the server stamps the
branch default (`back/.../order.go:518-529`). Both produce the same ending: undercharge
→ `400 insufficient payment` → permanent → quarantined → `_pending` released → the bill
**reopens unpaid** hours later, customer gone.

### 4. Timer operations carry **no timestamps**, so the first hydration after reconnect erases hours of offline accrual
**Critical. CONFIRMED.**
`timer_shift_outbox.dart:113-122` posts `dio.post(entry.value(orderId))` with **no body
at all**, and `table_timer_local_repository_impl.dart:210-215` enqueues only
`{'order_id', 'action'}`. The server times the session by its own clock at replay time.
18:00 offline start, 23:00 close, 23:05 reconnect → the drain sends `start` and `pause`
milliseconds apart → the server records ≈ 0 s. Both ops then leave the queue, so
`pendingLocalTimerOrderIds` (`:515-531`) stops shielding the order, and the next
`SyncEngine._hydrateTableTimers` pass (`sync_engine.dart:346-379`) overwrites
`accumulated_active_sec` and `current_amount` wholesale from the server snapshot
(`:462-487`). **Five hours of accrual and its charge become ~0 on the terminal.** The
guard's own docstring (`:489-513`) says it exists to prevent this; it covers only the
window while the op is *pending*, and the corruption happens after it succeeds.

### 5. Backend `CreateOrder` drops `client_item_id` on inline items — every item rung at order-open is stored **twice**, and voiding one can never reach the server
**Critical. CONFIRMED.**
`back/app/internal/service/order.go:556-568` builds `CreateOrderItemParams` without
`ClientItemID` (the field exists — `order.sql.go:534` — and `AddOrderItems` sets it).
So the server row returns with `client_item_id = NULL`,
`ChangeApplier._retireClientTwin` bails at `apply_change.dart:328`, and the client-uuid
row written by `_writeOrderWithItems` survives beside the server's — verbatim the
"the table says 1 000 000 and the orders tab says 500 000" symptom that file's own doc
claims to have closed. Same root cause: a cancel of such a line addresses the client
uuid, which the backend answers with **HTTP 500** (`handler/order.go:2348-2355`), and
the voided line comes back on the next pull. `OFFLINE_FIRST_AUDIT_2026-08-23.md:1723`
marks order items "safe" citing the *AddOrderItems* path and misses this one.

**Close behind these five:** the shift close hard-codes `closing_cash`/`closing_card`
to `"0"` (T8); a backing-off outbox op does not block its causal chain, so a pay or a
shift close overtakes the create it depends on (X1); a follower never re-points at a
leader whose IP changed at the same epoch, stranding it for the rest of the shift (L1);
and a re-announced print job prints a second physical copy because the receiving side
has no jobId dedup (P1).

---

## CREATE

### C1 — Order-create items are duplicated in the replica (Critical) — CONFIRMED
**Where.** `back/app/internal/service/order.go:556-568`; `apply_change.dart:321-336`;
`orders_repository_impl.dart:296-316, 470-475`.

**Sequence.**
1. Cashier opens table 5 with 3 items. `_writeOrderWithItems` mints 3 client uuids,
   writes 3 local `order_items` rows keyed by them, and enqueues one `orders/create`
   whose body carries `client_item_id` per line (`_createItemBody`, `:470`).
2. The create drains. `CreateOrder`'s inline loop calls `CreateOrderItem` with
   `ID: uuid.New()` and **no `ClientItemID`** → server rows have `client_item_id = NULL`.
3. `orders/create`'s handler returns `succeeded()` with no `serverRow`
   (`orders_outbox.dart:59-60`), so `OutboxDrainer._succeed` has nothing to reconcile.
4. The next pull delivers the 3 server rows. `_retireClientTwin` reads
   `raw['client_item_id']` → null → returns at `apply_change.dart:328` without deleting
   the twin. `_applyUpsert` inserts the server row alongside.
5. `OrderDetailQuery.itemsForOrder` now returns **6** rows for 3 physical lines.

**Consequence.** The order screen's `existingTotal` (`order_actions_bar.dart:90-96`) and
the printed receipt's `subtotal` (`cashier_receipt_builder.dart:670-673`) both double,
while the charged total (which takes the server's `grand_total`, T1) stays right.
Cashier and customer see two different numbers for one bill.

**Fix direction.** One line on the backend: pass `ClientItemID` in `CreateOrder`'s
inline loop, as `AddOrderItems` does. Client-side belt-and-braces: have `orders/create`
return the created order and reconcile item ids from it.

### C2 — A quarantined provisional create leaves a permanent ghost row (High) — CONFIRMED
**Where.** `outbox_drainer.dart:344-365`; `local_writer.dart:97-122`.

A hall / table / category / good / staff user created offline is written under a
provisional id and marked (`local_writer.dart:106-120`). If the create is rejected on
the merits (403, 400, stop-listed good, taken username) the drainer takes
`_fail(..., permanent: true)`, which calls **only** `_db.clearPending` — never
`clearProvisional`, never `deleteRow`. `grep clearProvisional` finds three call sites,
all inside the success path. Dismissing the quarantined op deletes the op and leaves
the row.

**Consequence.** Exactly the "permanent ghost … undeletable because no server row
matches it" that `DECISIONS.md` D1 says this design avoids. Worse for `cafe_tables`:
the ghost table sits on the floor plan, a cashier opens a check on it, and the
`orders/create` fails with `cafe table not found` → 400 → permanent → **the whole check
is quarantined and lost**, with cash possibly already in the drawer. That order's local
row keeps `bill_status: 'open'`, so `TableOccupancyReconciler` keeps writing `busy`
forever and its timer accrues indefinitely (see T13).

**Fix direction.** On permanent failure of a `create` whose entity id is provisional,
delete the local row through the applier (so peers hear it) and clear the marker — the
branch `_reconcile` already uses when the server names no id (`outbox_drainer.dart:303-309`).

### C3 — The 409 duplicate-table merge is **not idempotent** and leaves a phantom order (High) — CONFIRMED
**Where.** `orders_outbox.dart:276-315`, especially `:304`.

1. Two terminals open table 5 while the lease is unreachable
   (`create_order_bloc.dart:140-147` allows it deliberately).
2. Loser's `orders/create` gets 409. `_mergeCreateOrderConflict` posts the loser's items
   to the winning order with **`'client_item_id': generateUuidV4()`** — a fresh key per
   attempt, deliberately defeating the backend's `(order_id, client_item_id)` dedup
   index (`migrations/tenants/70_…`).
3. The merge POST commits server-side but the response is lost. `_mapDioError` sees no
   status code → `retry`.
4. Next pass: create → 409 → merge again → **new** key → the same lines land twice.

**Consequence.** Duplicate lines on a live check, customer charged twice, stock
double-decremented (`consumeItemStockWithModifiers` runs per created row).

**Second defect, same handler.** The merge returns `succeeded()` for an op whose
`entityId` is the **losing** order id. `_succeed` clears that row's pending guard but
never removes it, and no server row exists for it, so no feed delete will ever arrive.
The loser's replica keeps a phantom open bill forever; `liveOrderForTable` orders by
`created_at DESC` and may hand *that* one to the payment screen.

**Fix direction.** Reuse the per-line `client_item_id` already persisted in
`op.payload['items'][i]`, and delete the losing local order + items on a successful merge.

### C4 — Non-order creates duplicate on a lost response (High) — CONFIRMED (already `W7`)
`halls_tables_outbox.dart:54`, `menu_admin_outbox.dart:42-58, 95-112`,
`users_outbox.dart:26-33`, `transactions_repository_impl.dart:161, 182, 218` all POST a
create with no client idempotency key. `outcomeForFailure` maps
Connection/Timeout/Server/**Unknown** → `retry`, and `main_datasources.dart:1188-1191`
turns *any* non-Dio exception (including a decode failure on a 200) into
`UnknownFailure` → retry. Duplicated cash-in/cash-out transactions are the sharp end —
they land in till reconciliation.

### C5 — Creating a table inside a queued hall relies on the provisional mechanism, not the chain key (Medium) — CONFIRMED
`halls_tables_outbox.dart:69, 88` attach `_hallChain` to `update` and `delete` but **not**
to `create`. It works only because `_awaitsProvisionalId` blocks any op whose body
quotes an unresolved provisional id. Once the hall's create is *quarantined*,
`_unresolvedProvisionalIds` (which reads `pending()` only, `outbox_drainer.dart:201`)
drops it, and the table create is sent with a dead `hall_id` → quarantined too. With C2
the venue keeps a ghost hall full of ghost tables.

### C6 — `saveOrderDetailSnapshot` is a silent no-op on the path that needs it (Low) — CONFIRMED
`create_order_bloc.dart:155-158` calls it right after `createOrder`, but
`orders_repository_impl.dart:192` routes through `applyOne('update')`, which
short-circuits on `_db.isPending('orders', id)` — set one line earlier by
`LocalWriter.write`. The whole snapshot is discarded as `skippedPending`. Harmless
today; a latent trap for anyone who later relies on it.

---

## DELETE

### D1 — Voiding a line rung at order-create time **never reaches the server**, and the line comes back (Critical) — CONFIRMED
**Where.** `orders_repository_impl.dart:366-385`; `orders_outbox.dart:122-153`;
`back/app/internal/handler/order.go:2322-2356`.

1. Order created with 3 items — local rows keyed by **client** uuids, unguarded and not
   provisional (the class doc explains why, `orders_repository_impl.dart:26-44`).
2. Cashier voids one. `LocalWriter.delete` hard-deletes the row and enqueues
   `order_items/delete` with `entityId` = the client uuid.
3. Nothing reconciles that id (C1).
4. The handler POSTs `/api/v1/order-items/{clientUuid}/cancel`. The backend parses the
   uuid, fails the lookup, and returns **HTTP 500** (`handler/order.go:2348-2355`) — not
   the 404 the handler is written to tolerate at `orders_outbox.dart:144-146`. It
   retries 8 times over ~10 minutes and quarantines with an opaque `HTTP 500`.
5. The next pull delivers the still-active server row under its own uuid. The `_pending`
   guard was placed on the *client* id, so nothing shields against it: the voided line
   **reappears on the open check**.

**Consequence.** Customer charged for an item the cashier removed; the kitchen still has
the ticket; the operator sees a quarantined op whose message explains nothing.

**Note.** Lines added via `addItems` are safe — they are provisional and
`_reconcile` → `rewriteReferences` repoints the queued cancel onto the server id before
it is sent (`outbox_drainer.dart:312-322`, with the re-read guard at `:100-104`). The
bug is confined to the first round of items, which is the common case.

### D2 — A voided line disappears instead of being cancelled, so the total never drops (High) — CONFIRMED
`LocalWriter.delete` (`local_writer.dart:131-151`) **hard-deletes**. But
`OrderTotals.fromDetail` only leaves the stale-`grand_total` branch when it can see a
line with `status == 'cancelled'` (`order_totals.dart:165, 173`). Since the row is gone,
`hasCancelled` is false and the total stays at the pre-void `grand_total`. **Offline,
voiding an item does not reduce what the customer is charged.**

This also contradicts `OrderDetailQuery`'s own doc (`order_detail_query.dart:147-155`:
"Cancelled lines are included deliberately — the payment and archive screens render them
as a struck-through section"). They cannot be; nothing writes `status = 'cancelled'`
locally.

**Fix direction.** Make a local void a `status = 'cancelled'` update (matching the
server) rather than a delete, and compute totals from the lines.

### D3 — `applyLocalDelete` never reconciles table occupancy (Medium) — CONFIRMED
`apply_change.dart:458-468` is the only apply path that omits `_noteOrderTables` /
`_reconcileTouchedTables` — every sibling has them (`applyLocalWrite:430, 447`;
`applyOne:375, 378`; `_applyEntityChanges:266`). Latent today (nothing deletes an
`orders` row locally) but it is the one hole in an otherwise closed invariant.

### D4 — Deleting a hall or table has no cascade and no in-use guard (Medium) — CONFIRMED
`halls_tables_local_repository_impl.dart:103-107` deletes the row and queues, full stop.
Deleting a hall orphans its `cafe_tables` rows locally until the next pull. Deleting a
table with a live bill removes it from the floor plan while the `orders` row still
points at it — the check becomes unreachable from the floor, and
`liveOrderForTable`'s `LEFT JOIN` resolves it with a null `table_number`, so the receipt
prints "Стол: —".

### D5 — A deleted provisional row can survive on a peer forever (High) — CONFIRMED
`outbox_drainer.dart:303-321` retires a provisional row by
`_applier.applyOne(action: 'delete', entityId: provisionalId)`, which reaches peers as a
fire-and-forget LAN frame. `LanHubClient.send` drops it silently when not connected
(`lan_hub_client.dart:164-169`).

Terminal t1 creates a hall offline under provisional id P and broadcasts row P. Peers
store P **unguarded and unmarked-provisional** (`applyFromPeer` deliberately does
neither, `apply_change.dart:386-396`). t1 drains, the server returns id S, t1 deletes P
locally and broadcasts the delete — but f2 was momentarily disconnected. f2 keeps P
forever: no pull can delete it, because the server never knew P. It also receives S.
**Two rows for one thing, undeletable, on one terminal only** — the ghost D1 was written
to avoid, arrived at from the peer side.

### D6 — Quarantine releases the `_pending` guard for the **row**, not the operation (Medium) — CONFIRMED (already audited, still open)
`outbox_drainer.dart:344-365`; no per-row refcount anywhere. Two queued ops on one entity
id (create + pay, add + cancel, write + transfer) share one guard: the first to resolve
clears it, and a pull landing before the second op drains overwrites the local row. The
prior audit rates this MEDIUM and self-healing; the lifecycle consequence worth
restating is that a cashier looking at a check that has flipped back to *unpaid* is
exactly the operator who re-collects.

---

## CLOSE

### T1 — The payment total is the server's stale `grand_total` (Critical) — CONFIRMED
**Where.** `order_totals.dart:164-178`; `payment_bloc.dart:305-316`;
`order_detail_query.dart:129-145`.

`grand_total` is a real, server-maintained column on `orders`
(`migrations/tenants/6_orders.up.sql:37`, recomputed by
`RecalculateOrderTotalsFromItems`, `bills_custom.go:158-181`) and it replicates
(`entity_registry.dart:468-496`). `OrderDetailQuery._assemble` returns the stored blob
verbatim, so `detail.grandTotal` is whatever the server last computed.

Order synced at 100 000. Uplink lost. Cashier rings 50 000 more — local `order_items`
rows exist, `hasCancelled` is false, `offlineExtra` is 0 → `fromDetail` returns 100 000.
Screen shows 100 000, the pay button enforces `entered >= 100 000`, cashier takes
100 000 and prints. On reconnect the item adds land (server recomputes 160 000), then
`orders/pay` with `customer_paid_amount = "100000"` → `400 insufficient payment` →
permanent → quarantined → `_pending` cleared → the next pull puts the bill back on the
table, unpaid.

**Fix direction.** What `order_totals.dart:123-134` already prescribes: in the
no-table-charge branch compute from `detail.goods` via `OrderTotals.compute`, and trust
the server aggregate only for a bill that is already `paid`.

The waiter path has the identical defect with the identical acknowledging comment:
`waiter_cubit.dart:358-364` returns `order.totalAmountValue` whenever the table charge
is 0.

### T2 — An offline-created order is charged without service, but the server charges it (Critical) — CONFIRMED
`_writeOrderWithItems` writes no `service_percent` (`orders_repository_impl.dart:268-278`).
`fromDetail` falls back to `servicePercentFallback`, sourced by the payment screen from
`detailBloc.lastDetail?.servicePercent ?? 0` (`order_actions_bar.dart:736-737`) — the
same 0. So `serviceInt = 0` and the charged total is food-only, while
`PaymentState.applyService` defaults to **true** (`payment_state.dart:18`) and
`CreateOrder` stamps `GetDefaultServicePercentByTable` (branch default, doc says 20 %
fallback — `back/.../order.go:518-529`). ~20 % shortfall → 400 → quarantine → bill
reopens.

**Fix direction.** Stamp the branch's default service percent onto the locally-created
order row at create time, and source the payment screen's fallback from the branch.

### T3 — Archive-screen pay drops the table charge entirely (Critical) — CONFIRMED
Summary finding 1. `archive_right_sider_bar.dart:83-88` (only `order_id` is passed);
`payment_screen.dart:41-46, 74-78, 107-118`; `HourPriceEvent.started` never dispatched;
`order_totals.dart:135-163` never reads `detail.tableAmount`;
`payment_bloc.dart:166-174` comps the zero-total bill.

**Fix direction.** Either pass the timer arguments from this call site as
`order_actions_bar.dart:700-717` does, or — better, since a third call site will
eventually make the same mistake — have `OrderTotals` derive the table charge from the
local timer record keyed by order id rather than from a navigation argument.

### T4 — The receipt total is a **fifth** independent formula and ignores the service toggle (High) — CONFIRMED
`cashier_receipt_builder.dart:667-760` (`buildFromDetail`) sums `detail.goods` itself
(`:670-673`), derives its own `serviceAmt` (`:722-729`), its own `preDiscount` (`:744`)
and its own `toPay` — it never calls `OrderTotals`. And
`printCashierReceiptFromDetail` (`printer_service.dart:219-232`) has **no
`applyService` parameter**, so when the cashier switches the service charge off (the
toggle at `payment_screen.dart:164-186`) the charge drops but the printed receipt still
shows and includes it.

Combined with T1 and C1, the number on the paper and the number in the drawer diverge by
three independent mechanisms.

**Fix direction.** Pass the settled `OrderTotals` (which `PaymentRepository.pay` already
receives as `settled:`) into the builder and print its fields.

### T5 — Nothing re-checks the amount at the bloc; the only underpayment guard is a widget (High) — CONFIRMED
`payment_bloc.dart:145-203` validates only `enteredAmt <= 0` for cash
(`cashNeedsAmount`, `:152-154`). The `entered >= finalTotal` rule lives solely in
`_ConfirmButton.cashOk` (`payment_right_side_bar.dart:616-619`). Any other dispatcher of
`PaymentEvent.payment()` books a partial payment as a full close. The bloc should own
the invariant that guards money.

Related: `_payment` has no already-paid guard. `liveOrderById` deliberately ignores
`bill_status` (`order_detail_query.dart:91-93`), so the screen keeps rendering a settled
bill and a second confirm enqueues a second `orders/pay` **and prints a second
receipt**. The server is idempotent (`order.go:1334-1336`), so no double charge — but
the second receipt is real.

### T6 — Split payment is not implemented; `PaymentType.qr` would be rejected (Medium) — CONFIRMED
`back/order-total-calculation.md` §8 documents `payment_type: "split"` with
`cash_amount` + `card_amount`. The client has no split option and never sends those
fields (`payment_repository_impl.dart:75-113`). Separately,
`enum PaymentType { cash, card, qr }` (`constants.dart:51`) and `_payment` sends
`state.paymentType.name` verbatim; the backend rejects anything outside `cash|card|split`
(`order.go:1466-1469`, `:1385-1391`) with 400 → permanent → quarantine → bill reopens
with money already taken. **Currently unreachable** — no UI offers `qr`
(`payment_center_column.dart:96-121`, `bill_detail_panel.dart:1619-1636`) — but it is
one dropdown entry away from a silent money-loss path.

### T7 — The payment screen resolves by **table first**, so it can retarget onto a different bill mid-payment (High) — CONFIRMED (new in the working tree)
`payment_bloc.dart:342` (`_detailKeys => [state.tableId, state.orderId]`);
`orders_repository_impl.dart:98-105` (`_resolveAny` returns the first key that hits);
`order_actions_bar.dart:700-705` (both args are passed for dine-in).

`liveOrderForTable` returns *whatever bill is currently live on that table*. If another
terminal settles this bill and opens a new one on the same table while the payment
screen is open, the stream emits the **new** bill, `_onDetailUpdated` swaps
`state.detail`, and Confirm pays `detail.id` — the wrong order. Reversing the key order
(id first, table as fallback) preserves the spinner fix this change was made for while
removing the retarget.

### T8 — Shift close: zero declared cash, two entry points, one unguarded, wrong chain (High) — CONFIRMED
* **Zero totals.** `shift_bloc.dart:160-172` enqueues `'closing_cash': '0',
  'closing_card': '0'`, always. `state.cashSum` / `state.cardSum` are read only when
  *opening* (`:213-214`) and are reset on close. `_printShiftCloseFromState` (`:129-134`)
  prints `closingCard: 0`, and `shift_close_receipt_builder.dart:90-102` prints only
  that line plus "Наличные на чеке не отображаются".
  `timer_shift_outbox.dart:~235` faithfully forwards the zeros. **Every shift on the
  server closes with 0/0 — till reconciliation is impossible and a cash discrepancy is
  undetectable.**
* **Two close buttons, one unguarded.** `close_shift_screen.dart:1878-1898` blocks on
  `tables.where((t) => t.status == TableStatus.busy)`;
  `w_shift_bottom.dart:59-76` dispatches `ShiftEvent.closeShift()` straight after the
  pincode with no check at all. `ShiftBloc._closeShift` (`:181-201`) checks only
  `state.shift == null`.
* **The guard is the wrong predicate anyway.** It tests occupancy, not live bills, so an
  unpaid **takeaway** order (`createTakeawayOrder`, no `table_id` —
  `orders_repository_impl.dart:236-250`) never blocks the close. And occupancy is now
  derived by `TableOccupancyReconciler`, which frees a table on a locally-fabricated
  `paid` (T12).
* **Chain.** The close's chain key is the cash-register id (`:163-164`) while every
  `orders/pay` chains on its order id — see X1.

### T9 — A shift close can overtake the payments of its own shift (High) — CONFIRMED
Instance of X1, spelled out because the money consequence is specific. Cashier pays
table 4 at 22:40 (op A, chain `order-4`), table 9 at 22:45 (op B), closes the shift at
23:00 (op C, chain `CR-1`). Uplink returns 23:01. Pass 1: A → 502 → `markFailed`,
`next_attempt_at = now+~5 s`; B → OK; C → **sent** — `remote.checkShift(CR-1)` finds the
shift open and closes it. Pass 2, 5 s later: A lands on a register whose shift is
already closed. **Table 4's payment is booked outside the shift it belongs to.** Nothing
anywhere gates the close on `OutboxStore.depth == 0`.

### T10 — The shift record and its outbox op are not atomic, in both directions (High) — CONFIRMED
`shift_bloc.dart:227-240` (open) writes the local record *then* enqueues;
`:188-189` (close) enqueues *then* clears the local record. `LocalWriter.enqueueOnly`
deliberately opens no transaction (`local_writer.dart:160-175`), and the shift record
lives in `SharedPreferences`, not SQLite, so no transaction *could* span them.
Crash between the two on open → a shift the server never hears about, and every later
sale is attributed to whatever shift the register actually has. Crash on close → the
close is queued while the cashier keeps ringing into a shift the outbox will close.

This is the one write path in the app that `LocalWriter`'s "one transaction" guarantee
explicitly does not cover.

### T11 — An empty `cash_register_id` produces an unclosable phantom shift (Medium) — CONFIRMED
`_resolveCashRegisterId` (`shift_bloc.dart:112-116`) returns `''` when the token is
absent or carries no claim, and `_openShift` does not check it: it writes a local shift
with `cashRegisterId: ''` and enqueues with `entityId: ''`. Both handlers reject it
permanently (`timer_shift_outbox.dart:173-178`, `:209-213`). Secondary: with
`entityId == ''`, `chainKeyOf` falls through to `'op/${op.id}'`
(`outbox_executor.dart:100`), so open and close land on **different chains** — the
documented "a close can never overtake the open" invariant (`timer_shift_outbox.dart:199-203`)
silently does not hold for exactly the case where it matters. Nothing on screen says
anything.

### T12 — A quarantined pay leaves a locally-`paid` bill and a freed table (High) — CONFIRMED
`payment_repository_impl.dart:149-156` commits `bill_status: 'paid'` and the
`orders/pay` op atomically. If that op quarantines on any 4xx (T1, T2, T6, or a 404
because the order's own create quarantined first), `OutboxDrainer._fail` deletes nothing
and clears the guard (`outbox_drainer.dart:344-364`). The order stays `paid` locally
forever, with no operation left to send and — where the server never heard of the order
— no row to correct it. `TableOccupancyReconciler` then frees the table on the strength
of that fabricated row (`table_occupancy_reconciler.dart:88-99`), and because occupancy
is what T8's close guard checks, **the shift then closes cleanly over a sale the server
never received.** The reconciler's comment ("The settled bill is the evidence",
`:36-39`) is true only for bills the *server* settled.

### T13 — A quarantined `orders/create` leaves the table busy and its timer running forever (High) — CONFIRMED
Mirror of T12. The local row keeps `bill_status: 'open'`
(`orders_repository_impl.dart:272`), so `liveOrderForTable` keeps returning it and
`table_occupancy_reconciler.dart:88-91` keeps writing `busy`. The server has no row to
correct it with, and `_fail`'s `clearPending` does not help because no pull will ever
carry that id. `evictSettledTimers` will not touch the timer either (the order is
"live"), so it accrues indefinitely — the exact "54 hours and 2.7M so'm" shape that
file's own header describes, reached from the other direction. The only escape is paying
it, which routes into T12.

### T14 — There is no "close timer" operation; a play tap can resurrect a timer on a paid bill (Medium/SUSPECTED)
`kTimerStart` / `kTimerPause` / `kTimerResume` are the only registered verbs
(`timer_shift_outbox.dart:76-78, 94-132`). At payment,
`payment_bloc.dart:259-265` calls `evictTimer`, which deletes the local row and
LAN-broadcasts `kTimerEvict` with **no outbox op**
(`table_timer_local_repository_impl.dart:444-451`); the server closes its own session as
a side effect of `/pay`. The two return-from-payment paths are guarded
(`order_actions_bar.dart:726-731`, `payment_bloc.dart:214-231`), but the plain play
button is not: `order_actions_bar.dart:393-394` and `order_side_bar_widget.dart:1300-1301`
call `resumeTimer()` unconditionally, and `TableTimerCubit.resumeTimer:388-399` falls
through to `startTimer()` when `state.timer == null` — building a fresh running record
and enqueueing a `start` for a paid order. **SUSPECTED** — the widget states that make
that tap reachable after payment were not driven.

### T15 — Timer accrues at 0 so'm when `price_per_hour` is missing, silently (High) — CONFIRMED
`_tablePriceFor` (`table_timer_local_repository_impl.dart:171-175`) reads
`cafe_tables.price_per_hour` **once**, at start/create (`:341`, `:369`), and freezes it
into the record; `computeAnchoredLiveAmount` short-circuits on a non-positive rate
(`table_timer_response_model.dart:188`). Two ways in: the `cafe_tables` row has not
replicated yet (fresh terminal, or a table created offline — C2), or
`TableTimerCubit.startTimer` is reached through `resumeTimer`'s `state.timer == null`
branch after a `fetchTimer` on a cold cubit, where `_activeTableId` is still `''`
(`table_timer_cubit.dart:210-271, 347, 396-399`). The clock ticks visibly, the amount
stays 0, and a record with `table_id: ''` never matches `watchTimerForTable`
(`:235-251`) so the table badge shows nothing either. The rate is never re-read.

### T16 — Timer eviction by the reconciler is not broadcast to peers (Medium) — CONFIRMED
`table_occupancy_reconciler.dart:141` calls `_db.evictTableTimer(orderId)` directly.
`TableTimerLocalRepositoryImpl.evictTimer` (`:444-451`) is emphatic that the drop must
reach peers or "a paid-off table keeps its timer on every screen but this one, and the
next order on that table inherits a stale one." The reconciler path skips that. Peers
usually self-heal by applying the same paid row and running their own reconciler —
except when the paid row arrived by a route the peer does not share (a cloud pull on the
leader while a follower is LAN-only), which then feeds T17.

### T17 — An orphaned timer hijacks the next open on its table (High) — CONFIRMED
`evictSettledTimers` uses an INNER `JOIN orders o ON o.id = t.order_id`
(`table_occupancy_reconciler.dart:132-135`), so a timer whose `orders` row was *deleted*
— which `OutboxDrainer._reconcile` does at `:303-307` and `:315-319`, and any replicated
hard delete does too — matches nothing and lives forever. `createTimedOrder`'s
double-tap guard then finds it:

```dart
if (tid == tableId && stateName != 'closed' && existingOrderId.isNotEmpty) {
  return Right(TimedOrderCreateResult(existingOrderId, wasExisting: true));
}
```
(`table_timer_local_repository_impl.dart:279-288`)

The cashier taps a free time-based table and is bound to a **dead order id**;
`wasExisting: true` skips `startTimer`, and every subsequent write goes to an order that
exists neither locally nor on the server. `watchTimerForTable` has no `orders` join, so
the table still renders a ticking badge.

### T18 — The global timer sweep is gated behind a non-empty table set (Medium) — CONFIRMED
`reconcileTables` returns at `table_occupancy_reconciler.dart:81`
(`if (ids.isEmpty) return 0;`) **before** reaching `changed += evictSettledTimers();` at
`:101`, and `_reconcileTouchedTables` returns early on the same condition
(`apply_change.dart:135`), with `_noteOrderTables` recording only non-empty `table_id`s
(`:120-129`). So the sweep only fires when some order write happened to name a table. On
a quiet terminal, or one whose only recent activity is takeaway, a settled order's timer
survives arbitrarily long — which is also what keeps T14's resurrected timer alive.
Same shape at cold start: `reconcileAll` (`:114-119`) unions two sets that are both
empty on a terminal whose replica has not been pulled yet at `di.dart:253`, so the
startup heal does nothing.

### T19 — Occupancy can be freed under a bill this replica has not seen (Medium) — SUSPECTED
`table_occupancy_reconciler.dart:94-99` frees a table when there is no live bill locally
**and** at least one settled order exists for it. A terminal holding yesterday's settled
bill for table 5 and no visibility of a fresh remote open (no LAN, no pull) frees it,
inviting a second open → C3. The guard is "nothing settled here", much weaker than the
doc's "never on a guess" (`:43-44`) implies for a table used before today.

### T20 — Waiter close sends no `settled` totals and forces `applyService: true` (Medium) — CONFIRMED
`waiter_local_repository_impl.dart:243-252` calls `PaymentRepository.pay` without
`settled:`, so `payment_repository_impl.dart:137-146` is skipped: the locally-closed row
gets no `food_total`, `service_amount`, `grand_total`, `total_amount` or
`change_amount`, and the bill shows as a zero-total settled check in the local archive
until the pull corrects it. It also passes `applyService: true` unconditionally (`:248`)
while `_payAmountSom` may have computed the amount with `servicePercent = 0` — the T2
shortfall through a second door.

### T21 — Transfer/ledger and rounding notes (Low–Medium) — CONFIRMED
* `createTransferTransaction` (`transactions_repository_impl.dart:170-188`) writes only
  the `transfer_expense` leg; the income leg is the server's. Offline the local ledger
  does not balance. Documented at `:174-176`.
* `updateTransaction` (`:190-208`) uses `merge: true`, and `LocalWriter.write:68` writes
  the patch as-is when the row is missing — fabricating a `transactions` row with no
  `type` / `cash_register_id` that `TransactionsQuery` (`transactions_query.dart:42-55`,
  filter is only `deleted_at IS NULL`) then shows and counts.
* Nothing writes a `cash_register_shift_id` on a payment or transaction, and
  `TransactionsQuery` has no shift filter — so there is no local basis on which a shift
  report *could* be computed even if T8 were fixed.
* `payment_screen.dart:581` and `receipt_preview_modal.dart:79` render the table charge
  with `.toInt()` (truncate) while the total and the request use `.round()` — a 1 so'm
  display/charge mismatch. And `order_totals.dart:163` rounds `(foodSum + tableCharge)`
  together while `:149` rounds `tableCharge` alone for the request field, so the local
  `grand_total` can land 1 so'm off the server's and visibly jump on the next pull.

---

## PRINT

### P1 — A re-announced print job prints again; the receiving side has **no jobId dedup** (High) — CONFIRMED
**Where.** `print_queue_service.dart:315-332` (`_onLeaseExpired`), `:281-298`
(`_onClaimTimeout`), `:366-389` (`onRemoteAnnounce`); `lan_hub_service.dart:412-420`
(the dispatch, also without dedup).

Terminal A submits a kitchen ticket for a USB printer owned by terminal B. B receives
the announce, broadcasts a claim, and starts printing. Either the claim frame is lost →
A's 3 s `claimWait` fires → `_onClaimTimeout` re-announces (`:290`); or B's spooler
takes longer than the 10 s lease → `_onLeaseExpired` re-announces (`:324`). Either way
B's `onRemoteAnnounce` runs again with **no record of jobs it already printed** — it
claims and prints a second copy.

**Consequence.** The kitchen gets two tickets for one order and cooks the dish twice; a
customer receipt prints in duplicate. A's bookkeeping stays clean (`onRemoteClaim` and
`onRemoteResult` are state-guarded at `:304` and `:338`), so **nothing on the originating
till signals it.**

**Fix direction.** Keep a bounded set of already-printed `jobId`s on the receiving side
and re-broadcast the stored result instead of reprinting.

### P2 — Every LAN restart stacks another message listener, multiplying prints (High) — CONFIRMED
`lan_hub_service.dart:185-195` registers `_client.onMessage.listen(_handleRemoteMessage)`
without storing the subscription. `restart()` (`:542-550`) calls `_client.disconnect()`,
which does **not** close the broadcast controller (`lan_hub_client.dart:258-263`; only
`dispose()` does, `:270`), so every restart adds a subscription. `restart()` is reached
from `_becomeFollower:319`, `_claimLeadership:355`, and four settings paths
(`lan_network_section.dart:74, 95, 112, 133`).

Most handlers are idempotent; `printJobAnnounce` is not. After two leadership flaps the
terminal owning the USB printer prints **three copies** of every relayed ticket, and
`LocalChangeRelay`'s `received` counter on the sync-status screen inflates by the same
factor — so the diagnostic actively lies. (This is `LA` in the prior audit; restated
because P1 makes it multiplicative rather than additive.)

### P3 — Restart marks in-flight jobs failed even when they printed (Medium) — CONFIRMED
`_recoverStaleJobs` (`print_queue_service.dart:114-123`) flips every `queued`/`claimed`
row to `failed` on construction. A job that printed and whose result frame arrived after
the crash is indistinguishable from one that never left. The operator then uses
`retryFailedJob` (`:145-157`), which resubmits under a **fresh job id** with no dedup — a
second physical copy.

### P4 — A kitchen ticket with no configured printer is dropped silently (High) — CONFIRMED
`printer_service.dart:444-449` — an item whose category has no printer is `continue`d
out of the ticket with a `debugPrint`. `:455-460` — if *no* item has a printer, the whole
function returns with a `debugPrint` and **no user-facing notification**, in contrast to
the explicit `_notifyPrinterFailed` on every other failure path (`:497-502`).

**Consequence.** The cashier rings an order, sees success, and the kitchen never receives
it — or receives a ticket missing exactly the items whose category was misconfigured.
Nobody finds out until a customer asks where the food is.

### P5 — Voiding an item never sends a cancellation ticket to the kitchen (High) — CONFIRMED
`KitchenReceiptBuilder.buildWithHeader` takes a `cancelled` flag, and
`printer_service.dart:433-435` notes "template-only, no call site passes true yet".
`OrdersRepository.cancelLineItems` and `DetailBloc._deleteExistingByKey` print nothing.
The kitchen cooks and plates a dish the cashier removed — and with D2 that dish is still
on the customer's total anyway.

### P6 — The receipt prints before anything but the local write, and a rejection is never surfaced (Medium) — CONFIRMED by design, blast radius under-managed
`payment_bloc.dart:242-290` prints, evicts the timer, broadcasts the table free, clears
the saved draft and navigates — all on one local write. Every quarantine path above (T1,
T2, T3, T6, T12, X1) then reopens the bill. The success toast is
`"To'lov navbatga qo'shildi — internet kelganda yuboriladi"` (`:197-200`), shown
unconditionally including when the terminal is online and the pay drains in 750 ms.
There is no path back: **nothing tells the cashier when a queued payment is rejected** —
it lands in a quarantine list they are not looking at.

Kitchen tickets have the same shape at `create_order_bloc.dart:175, :195, :231` and
`detail_bloc.dart:653` — `unawaited(...)`, printed before the `orders/create` has left
the terminal. Food is cooked for orders that may be permanently quarantined (C2).

### P7 — Offline receipts carry no bill number (Low) — CONFIRMED
`orders_outbox.dart:59-60` discards `POST /orders`' response, so `bill_no`,
`service_percent` and `grand_total` never reach the local row until a pull. The receipt
prints `bilNumber = 0`.

---

## CROSS-CUTTING: outbox ordering and LAN

These are not one of the four operations but every one of them depends on them.

### X1 — A **backing-off** operation does not block its causal chain (High) — CONFIRMED
`OutboxStore.ready()` (`outbox_store.dart:136-144`) filters `next_attempt_at <= now`,
and `OutboxDrainer.drain` rebuilds `blockedChains` empty every pass
(`outbox_drainer.dart:81`). An op that failed on a previous pass is therefore invisible
to this pass and contributes nothing, so a later op on the same chain sails past it. The
chain-key doc (`outbox_executor.dart:60-69`, `orders_outbox.dart:26-29`) claims the
opposite.

* create backing off, pay ready → the pay addresses an order the server has never seen.
* item-add backing off, pay ready → the pay succeeds for a total *including* that item,
  then the add lands and `AddOrderItems` refuses with `cannot add items to paid order`
  (`order.go:105-110`) → 400 → quarantined. The customer paid for an item the server has
  no record of.
* pay backing off, shift close ready → T9.

The one mechanism that would have caught this, `_unresolvedProvisionalIds`, does read
`pending()` (`outbox_drainer.dart:201`) — but only blocks ops whose body *quotes* the
provisional id (`:215-223`). A pay quotes only the order id, which is not provisional.

**Fix direction.** Seed `blockedChains` at the top of each pass from every pending op
that is *not* ready, so a chain with a backing-off member is held whole.

### L1 — A follower never re-points at a leader whose IP changed at the same epoch (Critical) — CONFIRMED
`leader_election_service.dart:264-267`:

```dart
if (_role != ElectionRole.leader) {
  _currentLeaderIp = a.ip;
  return;
}
```

`_onAnnouncement` handles exactly three cases: higher epoch → `_adopt` (`:249-253`),
equal epoch **while I am leader** → tiebreak (`:268-289`), and everything else → update a
display-only field and return. There is no path where a *follower* hearing an
equal-epoch leader at a **different ip/port** calls `_becomeFollower`, and
`_lanHub.serverIp`/`serverPort` are only ever written there (`:316-318`).

**Most likely trigger: the leader's IP changes on a DHCP renew.** The epoch does not
move, so **every follower is stranded at once** — each keeps dialling the old address
with backoff (`lan_hub_client.dart:133-162`), hears the new beacon, and ignores it. Also
reachable after a segment split where both halves increment from the same persisted base
to the same epoch and the tiebreak loser's followers keep pointing at its now-stopped hub.

**Consequence.** The till shows "connected: no" on the cluster card and nothing else. No
`localChange` in or out, no `changeFeed`, every `acquireTableLease` returns `unreachable`
(`lease_manager.dart:110-114`) so every table-open self-grants with the "unverified"
warning. Silent island for the rest of the shift.
`LeaderElectionService.currentLeaderIp` and `LanHubService.serverIp` then disagree, and
nothing reads the first. `test/leader_takeover_test.dart:303` exercises only the
higher-epoch path.

### L2 — A follower that loses the LAN link never pulls the change feed (Critical) — CONFIRMED
`sync_engine.dart:217-255` + `change_feed_relay.dart:36, 43, 61-64`. In `LanMode.client`,
`_replication.drain()` runs **only** when `_feed.needsBackfill` (`sync_engine.dart:244`),
and `needsBackfill` is set **only** inside `ChangeFeedRelay.apply`
(`change_feed_relay.dart:61-62`), reachable only from a `changeFeed` frame arriving over
the hub (`lan_hub_service.dart:389-398`).

So a follower stranded by L1 — or one whose leader's hub is dead (L3) — but with
perfectly good internet receives no `changeFeed` → `needsBackfill` stays false → it never
pulls. It still drains its own outbox and refreshes the profile, so `_recordSync()` fires
at `:251` and the sync-status screen shows a **green, recent "last synced"**.

**Consequence.** Menu price changes, new goods, staff changes and every other terminal's
orders never arrive, while the screen says everything is fine. This directly defeats
`DECISIONS.md` D4: the uplink survives "as gap recovery only", but the gap *detector*
travels over the LAN link, so it is blind precisely when the LAN link is what broke.

Secondary: `backfillDone()` is called only in the client branch (`:247`), so a follower
promoted to leader with `needsBackfill == true` never clears it. Harmless today (the
server branch pulls unconditionally at `:263`), but the flag is now permanently wrong.

### L3 — Liveness is measured on UDP while what must work is TCP; a dead hub is never re-elected (High) — CONFIRMED
`_checkLeaderAlive` (`leader_election_service.dart:322-330`) consults only
`_missedBeats`, zeroed by any same-branch announcement (`:247`). Nothing consults
`isClientConnected`, `activeHubPort` or `hubBindError`.

`_claimLeadership:354-360` does `await _lanHub.restart(); … wsPort: _lanHub.activeHubPort ?? _lanHub.preferredHubPort`.
`LanHubServer.start` walks 10 candidate ports and, if all fail, sets `_boundPort = null`
and `_lastBindError` **without throwing** (`lan_hub_server.dart:125-128`). So a terminal
can be elected leader with **no bound hub**, advertise a port nothing is listening on,
and keep every follower's `_missedBeats` at 0 forever. Same outcome if UDP passes but TCP
8765 is firewalled (a Windows Defender profile flip on a network-type change). The venue
silently loses peer propagation and leases with no re-election, and it shows only on the
leader's settings card.

### L4 — A leader never steps down, and holds `LanMode.server` through any partition (High) — CONFIRMED
`leader_election_service.dart:324-326` returns early while role is `leader` or
`candidate`. A leader that loses all connectivity keeps `mode == server` forever, and
`LeaseManager.acquireTableLease` takes the server branch (`lease_manager.dart:106-108`)
and **self-grants every lease from local state with no warning at all** — unlike the
client-unreachable path, which at least shows "tekshirilmadi"
(`create_order_bloc.dart:137-143`). Two terminals on either side of a partition each
silently grant themselves the same table.

Same hole, different trigger: after the leader's app restarts, `mode` persists as
`server` so `LanHubService.init()` binds immediately (`:155-170`) while
`LeaderElectionService.start()` sets role = **follower** (`:207-209`). For up to
`missedBeatsBeforeDead × heartbeatInterval` ≈ 9 s there are two `LanMode.server`
terminals in the venue, both self-granting, and `handleLeaseRequestAsLeader`
(`lease_manager.dart:147-154`) does not verify that this terminal is actually the leader.

### L5 — Higher epoch wins unconditionally, so the flakiest terminal ratchets into leadership (Medium) — CONFIRMED
`leader_election_service.dart:249-252` + `:349`. `priority` (`:122-128`, `:338-340`) only
shortens the pre-claim wait (1.0 s → 2.3 s across `[1,999]`) and has no effect once a
claim lands; `_epoch` is monotone per terminal and never reconciled downward. A terminal
on a weak AP misses 3 beats, claims epoch N+1, wins; drops again, claims N+2, wins again.
There is **no** demotion debounce, no minimum leader tenure, no cooldown and no flap-rate
bound — the only hysteresis is `missedBeatsBeforeDead = 3` on the follower side. Each
migration does `setMode` + `restart()` venue-wide (stalling propagation, timing out
in-flight `requestLease` calls into "unverified" opens) and, via P2, adds another
duplicate print.

Fragile coupling worth noting: `heartbeatInterval` (3 s, `:70`) drives only the watchdog,
while the real beacon rate is hard-coded at `lan_discovery_service.dart:46` (2 s).
Lowering `heartbeatInterval` below 2 s makes every terminal declare the leader dead on a
healthy network.

### L6 — A `localChange` broadcast during a handover is dropped with no retry (High) — CONFIRMED
`lan_hub_client.dart:164-169` (`send` → `if (!isConnected) return;`), reached from
`lan_hub_service.dart:463` → `:495` → `LocalChangeRelay.broadcast`
(`local_change_relay.dart:113-139`). A cashier rings an order on f1 exactly as leadership
moves; `_becomeFollower:319` calls `restart()`, which disconnects the client; `afterCommit`
fires, `send` finds `isConnected == false`, returns. The frame is gone.
`LocalChangeRelay`'s doc (`:110-112`) says "Convergence … is the next cloud pull's job" —
but on a follower there is no next cloud pull (L2), and if the follower has no internet
there is no outbox drain either (L7). This is also the mechanism behind D5.

### L7 — A LAN-only follower can never send its writes; the relay is dead code (High) — CONFIRMED
`sync_engine.dart:229` gates the entire client branch on `_connectivity.isOnline`; the
comment at `:218-228` admits it. `OfflineQueueService.relayViaLan` (`:236`) has zero call
sites, and `LanHubService.relayOperation` (`:358-367`) / `_handleRelayOp` (`:318-345`) are
the leader half of a protocol nobody initiates.

**In the exact deployment this architecture exists for** — one terminal with the dongle,
the rest LAN-only — the LAN-only terminals accumulate an outbox that never drains. Their
writes reach peers (correctly) but never the server, and because the single-drainer rule
is correctly enforced (below), no peer picks up the slack.

### What is correct — worth recording so it is not broken later
* **The single-drainer rule holds.** `ChangeApplier._fromPeer` (`apply_change.dart:93`) is
  set only by `applyFromPeer` (`:397-414`), checked at the single emission site (`:152`),
  and `applyOne` never calls `markPending` or `OutboxStore.enqueue`. Verified end to end
  for `localChange` (`lan_hub_service.dart:399-406`), `timerAction`
  (`:407-411` → `local_change_relay.dart:224-250`) and `tableStatus`
  (`:384-387` → `main_cubit.dart:55-75` → `tables_repository_impl.dart:47-50`). **No path
  was found where a peer enqueues an outbox op for another terminal's write.**
* **The cursor arithmetic is right.** `replication_service.dart:153-159` captures
  `_db.syncCursor` before the apply; `change_feed_relay.dart:61-64` holds it back on a
  gap; `apply_change.dart:207-212` writes it inside the batch transaction and never
  backwards. D4's *mechanism* is sound — only its trigger is unreachable (L2).
* **Local write atomicity holds.** `LocalWriter.write/create/delete`
  (`local_writer.dart:57-151`) commit the replica row, the pending guard and the outbox
  row in one SQLite transaction, with the LAN broadcast deferred to `afterCommit`
  (`apply_change.dart:145-156`). Leadership changes do not touch the outbox. The one
  exception is the shift record (T10).
* **Timer pause/resume cannot be reordered or double-counted.** `ready()` is strictly FIFO
  by `(created_at, rowid)`, coalescing is deliberately absent
  (`table_timer_local_repository_impl.dart:189-199`), the repository no-ops a pause on a
  non-running record (`:392-394`) and a resume on a non-paused one (`:418`), and
  `_settleToNow` folds the live interval before every transition.
* **Transactions-ledger writes are atomic** (`transactions_repository_impl.dart:156-243`,
  all through `LocalWriter`).

---

## Docs vs code

| Claim | Where claimed | Reality |
|---|---|---|
| "Creates now write a row under a provisional id, and the drainer swaps it… `LocalWriteResult` is gone with the asymmetry it described." | `DECISIONS.md` D1 | True for the success path only. A **quarantined** create leaves the provisional row and its marker forever — the "permanent ghost" D1 was written to prevent (C2). A dropped retirement broadcast does the same on a peer (D5). |
| "The id a terminal invents offline is the id the row keeps forever." | `local_writer.dart:34-38` | True for `orders`. False for `order_items` **on the create path** — `CreateOrder` mints its own and does not even record `client_item_id` (C1). |
| `client_item_id` "earns replay idempotency and twin retirement." | `orders_repository_impl.dart:456-469` | Earns both for `addItems`, neither for the order-create path — the backend ignores the field there (C1). |
| "if the order's own create is still failing, its items wait rather than racing ahead" | `outbox_executor.dart:60-69`, `orders_outbox.dart:26-29` | Only within a single pass. A create that is *backing off* is filtered out by `ready()` and blocks nothing (X1). |
| "a close can never overtake the open it belongs to" | `timer_shift_outbox.dart:199-203` | Holds only while `cash_register_id` is non-empty; with `''` both ops fall to `'op/${op.id}'` and land on different chains (T11). And the close shares no chain with the *payments* of its shift (T9). |
| "a 404… same tolerance the per-line cancel gives" | `orders_outbox.dart:116-121, 144-146` | The backend returns **500**, not 404, for a missing order item (`handler/order.go:2348`). The tolerance branch is dead code. |
| "§12 rule 1 … a client-generated idempotency key" (`client_payment_id`) | `payment_repository_impl.dart:80-88` | No `client_payment_id` exists anywhere in `back/app/internal` (grep → zero hits); the field is silently discarded. Pay *is* idempotent, but via the already-paid short-circuit at `order.go:1334`, not this key. |
| "Cancelled lines are included deliberately — rendered as a struck-through section" | `order_detail_query.dart:147-155` | `LocalWriter.delete` hard-deletes the row; nothing ever writes `status = 'cancelled'` locally (D2). |
| "Phase 4 must switch this path to `OrderTotals.compute` … in the same change that migrates the writes — the two are one unit, not two steps." | `order_totals.dart:123-134` | The writes migrated; the totals path did not. `offlineExtra` is now permanently 0 and nothing replaced it (T1). |
| Order items "safe" from lost-response duplication | `OFFLINE_FIRST_AUDIT_2026-08-23.md:1723` | Verified against `AddOrderItems` only; the create path has no dedup key at all (C1). |
| "a follower with no uplink of its own now stays current" / LAN relay of writes | `sync_engine.dart:230-235`, `LAN_HUB_AND_LEASING_PLAN.md` §7 | Reads yes, **writes no** — `sync_engine.dart:229` gates the drain on `isOnline`, and `:222-228` says so: "Relaying outbox operations over the hub is unbuilt work." A LAN-only follower accumulates payments it cannot send (L7). |
| D4: the follower keeps its uplink "as gap recovery only" | `DECISIONS.md` D4 | The cursor logic is correct, but `needsBackfill` is only ever set by a frame arriving *over the LAN*, so the recovery is unreachable in the one failure mode it exists for (L2). |
| "the discovery beacon becomes the heartbeat channel" | `leader_election_service.dart:34-39` | Faithfully implemented, and that is the problem: liveness is UDP while the data plane is TCP, so a leader with an unbound or firewalled hub is never re-elected (L3). |
| "the durable check below still applies to whatever *did* land" (lease) | `lease_manager.dart:73-76` | True only if the peer's `localChange` for the order landed — which is exactly what is down during a handover (L6). |
| "a paid-off table keeps its timer on every screen but this one … the next order inherits a stale one" | `table_timer_local_repository_impl.dart:444-451` | The reconciler's own eviction path bypasses that broadcast (T16), and an orphaned timer then binds the next open to a dead order id (T17). |
| "one pass at startup heals a terminal that was off while the venue closed its checks" | `di.dart:246-253`, `table_occupancy_reconciler.dart:106-113` | No-ops when both the occupancy overlay and `orders` are empty at DI time (T18). |
| Split payment (`payment_type: "split"`, `cash_amount` + `card_amount`) | `back/order-total-calculation.md` §8 | Not implemented client-side at all (T6). |
| Shift close reports the counted till | implied throughout the shift flow | Hard-coded `'0'`/`'0'` in both the request and the receipt (T8). |
