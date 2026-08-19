# Order-flow migration — the last, app-gated piece

Status: **planned, not started.** This is the remaining §6b work to take the
order/waiter repositories off the Hive `LocalDatabase` (`core/database/`) and
onto the SQLite replica. It is deliberately not attempted blind: every step
below changes the live order lifecycle, and the failure mode is a **duplicated
or vanished order** in a running POS. It must be built and verified where the
app runs.

The three consolidation steps that landed this session (`transactions`,
`lease_manager`, `menu`) were safe because behaviour was pinnable by a query
test. This one is not — the correctness lives in server-replay timing and the
`detail_bloc` optimistic overlay, neither of which CI can exercise.

## Where the order flow is today

- **Write path is on the legacy queue, not the outbox.** `OrdersRepositoryImpl`
  and `WaiterLocalRepositoryImpl` enqueue `createOrder` / `addItems` /
  `cancelLineItems` / `transferTable` through `OfflineQueueService` — a
  **Hive-backed** `Box<PendingOperation>` (`offline_queue_service.dart`), replayed
  by `_execCreateOrder` et al. over Dio. The Phase-2 outbox
  (`LocalWriter` → `OutboxStore` → `OutboxDrainer`) is **not** used for orders.
- **No order outbox handlers exist.** `OutboxExecutors` has handlers registered
  only for `users`, `menu_admin`, and `halls_tables`
  (`data/outbox/*_outbox.dart`). There is no `orders`/`order_items`/`payments`
  send handler.
- **Display is a Hive JSON snapshot.** `createOrder` writes nothing to the
  replica `orders`/`order_items` tables; the optimistic display comes from
  `saveOrderDetailSnapshot(tableId, json)` → `LocalDatabase.saveOrderDetail`,
  and `detail_bloc` reads it via `OrdersRepositoryImpl.watchOrderDetail`.
- **The replica read exists but is unwired.** `OrderDetailQuery`
  (`core/db/order_detail_query.dart`) already assembles the open bill + items
  from the replica and is verified by `order_detail_query_test`. Its own doc:
  it returns the **stored** side only; `detail_bloc` overlays pending/optimistic
  ops on top, and *"Swapping the bloc's source from the Hive snapshot to this
  query is the remaining step, and it needs the app running to verify the
  overlay still behaves."*

## The integrity decision that forces the ordering

The plan (§6b) says to write a new order into the replica guarded by `_pending`
so `OrderDetailQuery` can show it immediately. **`_pending` is only cleared by
the outbox drainer** (`OutboxDrainer.clearPending`, on ack). The legacy queue
never clears it. So writing an order to the replica under `_pending` *while it
still replays through the legacy queue* would shield the server's authoritative
row **forever** — the local provisional order never converges.

⇒ The order write path must move onto the outbox **before** the replica write +
read swap. That is step 1–2 below; it is not optional and not reorderable.

## Sequence

1. **Build the order outbox handlers.** New `data/outbox/orders_outbox.dart`
   registering `OutboxExecutors` handlers for the order operations, porting the
   endpoint/response logic from `OfflineQueueService._execCreateOrder` /
   `_execAddItems` / `_execCancelLineItems` / `_execTransferTable` /
   `_execPayOrder`. Reuse the existing chain-key rule (an `order_items` op
   returns its `order_id` so items never overtake their order — the machinery in
   `outbox_executor.dart` already exists for exactly this). Unit-test with
   `test/support/fake_http_client_adapter.dart`, mirroring `outbox_handlers_test`
   and `id_reconciliation_test` (client order id is accepted idempotently by
   `CreateOrder`; item ids reconcile via the drainer's id-swap).

2. **Route writes through `LocalWriter`.** Replace each `_queue.enqueue(...)` in
   the order/waiter repos with the matching `LocalWriter.create` / `.write` /
   `.delete`, so the op lands in the outbox with `_pending` set and cleared on
   ack. Retire the order `PendingOperationType`s from `OfflineQueueService`
   (leave the box + its non-order ops until those migrate).

3. **Write order + items to the replica on create/add.** `createOrder` /
   `addItems` `applyLocalWrite` the `orders` and `order_items` rows in the shape
   `OrderDetailQuery` reads (`bill_status = 'open'`, `table_id`, item
   `order_id`/`good_id`/`created_at`). `LocalWriter` already sets `_pending`;
   the drainer clears it on ack; the next pull then converges the row to the
   server's version. **Drop the `saveOrderDetailSnapshot` Hive write.**

4. **Swap the read.** Point `detail_bloc`'s source from
   `OrdersRepository.watchOrderDetail` (Hive snapshot) to
   `OrderDetailQuery.watchLiveOrderForTable`, keeping the bloc's existing overlay
   of pending/optimistic/cancel ops on top of the stored read.

5. **Delete the Hive snapshot path** — `watchOrderDetail`/`getOrderDetail`/
   `saveOrderDetailSnapshot`/`evictOrderDetail` from the orders & waiter repos
   and their interfaces, and the `core/database` import. That drops both files
   from the §7 Hive-store ratchet (`architecture_guard_test.dart`), 5 → 3.
   `transferTable`'s re-key becomes a replica update + outbox op.

## App-verification checklist (the part CI cannot cover)

- Create an order **offline** → it appears on the table instantly.
- Reconnect → it syncs; after the next pull there is **exactly one** order (no
  duplicate under a second id), with the server's bill number/total.
- Add an item offline → appears instantly; cancel a line → disappears; both
  survive a cold restart before sync.
- Transfer a table → the bill moves and does not resurrect at the old table.
- Pay → the bill closes; replaying the queued pay on an already-paid order is a
  no-op (idempotent).
- Kill the app mid-order (write landed, ack not) → on restart the order is still
  shown and still queued, and does not double-send.

## Why the countdown stops at 5 here

`orders` and `waiter` are blocked on steps 1–4 above; `table_timer` shares the
same write-path/live-state problem (its `saveTableTimer` local writes + live
elapsed-time compute); `login_data_scope` is the tenant-switch wipe; `di.dart`
is the composition root, deleted last. None is a query-testable read swap. This
document is the executable plan for closing them where the app can confirm it.
