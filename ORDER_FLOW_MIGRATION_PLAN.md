# Order-flow migration — done, pending on-device QA

Status: **implemented and CI-verified; on-device QA outstanding.** The order /
waiter flow is off the Hive `LocalDatabase` (`core/database/`) and onto the
SQLite replica. This document is now the record of what was built and the
on-device checklist that closes it — the one gate CI cannot cover, because the
correctness that lives in the running app (the `detail_bloc` overlay, the
waiter list, kitchen printing, live billing) has no CI harness.

The change was made deliberately, not blind-in-the-dark: the data layer is
pinned end to end by tests (`orders_replica_write_test`, `orders_outbox_test`,
`order_flow_integration_test`, `order_detail_query_test`), and the one design
fork that mattered — how offline order *items* reconcile — was resolved against
a primary source (the backend), not guessed. What remains genuinely un-testable
without the app is flagged below.

## The integrity fork, and how it was resolved

The risk in this migration is a **duplicated or vanished order** in a running
POS. The specific hazard: an optimistic order *item* written locally under a
client-invented id would become a second row when the server's own row arrives,
unless the server honours that client id.

Checked directly in `mary-ai-backend` (`internal/model/order.go`,
`internal/service/order.go`): `CreateOrderItemInline.ID` and
`CreateOrderItemEntry.ID` are **client-supplied primary keys, honoured
idempotently** (`resolveCreateID` returns the existing row on replay). So the id
a terminal invents offline is the id the line keeps, and a later pull converges
onto the same row instead of duplicating it. (The client previously sent
`client_item_id`, which the backend ignores — the new path sends `id`.)

This is the plan's Phase-F precondition for optimistic items, and it is already
satisfied on the backend branch — so the full-replica approach (below) was
chosen over an overlay.

## What was built

1. **Order outbox handlers** — `core/outbox/orders_outbox.dart`
   (`registerOrdersOutboxHandlers`): `orders/create` (POST `/orders`, with the
   409 "table already open" merge ported verbatim from the legacy
   `_execCreateOrder`), `order_items/create` (POST `/orders/{id}/items`, chain
   key = order id so a line never overtakes its order), `order_items/delete`
   (per-line `/order-items/{id}/cancel`, 404-tolerant), `orders/pay`,
   `orders/cancel`, `orders/transfer`. 4xx → permanent, 5xx/timeout/dropped →
   retry. It speaks Dio directly (order logic with no home in a CRUD
   repository), and took over the §9.1 transport allowlist slot the legacy
   queue held.

2. **Writes on the outbox + replica.** `OrdersRepositoryImpl` writes the
   `orders` row (pending-guarded, clears on the create ack) and its
   `order_items` rows to the replica, and enqueues the matching outbox op —
   item ids shared between the local rows and the create body. Initial lines
   ride in the create body unguarded (the server can't clobber a row it has
   never heard of; it converges on the first post-sync pull); added lines are
   their own guarded ops; cancels are guarded so a pull can't resurrect a
   removed line.

3. **Reads on the replica.** `watchOrderDetail`/`getOrderDetail` assemble from
   `OrderDetailQuery` — by table for dine-in, by order id for takeaway. The
   waiter open-order list reads `OrderDetailQuery.openOrders()`.

4. **`detail_bloc` overlay collapsed.** The `⏳` pending-add overlay that read
   the retiring Hive queue is gone (an offline add is a real replica row now);
   existing-line +/- resolves its ids from the replica rows instead of a
   network fetch that returned nothing offline.

5. **Hive order-detail store retired for this flow.** The waiter reads moved to
   the replica, the `saveOrderDetailSnapshot` Hive mirror is gone, and
   `orders_repository_impl.dart` no longer imports `core/database` — it is off
   the §7 Hive-store ratchet.

6. **Table-timer store on the replica (§8).** The billing state machine's
   stored record (elapsed time, amount due, pause intervals) moved from the Hive
   `LocalDatabase` box to a `_table_timers` local-only table on the SQLite
   replica, with reactive `watchTableTimer`/`watchTableTimers` reads. The billing
   *engine* is untouched — this is a storage swap only, so the money math is
   byte-identical; only where the record is persisted changed.
   `table_timer_local_repository_impl.dart` is off the §7 Hive-store ratchet.

7. **Waiter repo fully off the Hive store (§9 tail).** Two stragglers moved:
   the staff list (`getStaffWaiters`) now reads the replica's `users` rows via
   `UsersQuery.all()` instead of the Hive user box; and the waiter table-open
   (`createOrder`) now delegates to `OrdersRepository.createOrder` — the same
   outbox + replica path the cashier uses, carrying an optional `waiter_id` in
   the create body and row — instead of the legacy `OfflineQueueService` +
   `saveOrderDetailSnapshot`. `waiter_local_repository_impl.dart` is off the §7
   ratchet, and payment is now the only remaining `OfflineQueueService`
   consumer.

8. **Payment reads a single source for offline items.** The payment total and
   the payment screen's item list both had a supplement that summed pending
   `addItems` from the legacy `OfflineQueueService`. Since added items are real
   replica rows now (item 2), that queue no longer carries them, so both
   supplements were dead (contributing 0) and, in the total's case, a latent
   double-count. Removed; `OrderTotals.forPayment` keeps its `offlineExtra`
   param (default 0, test-covered) with no caller.

## On-device QA checklist (the part CI cannot cover)

Run these on a device, dine-in **and** waiter **and** takeaway where noted:

- Create an order **offline** → it appears on the table instantly.
- Reconnect → it syncs; after the next pull there is **exactly one** order (no
  duplicate under a second id), with the server's bill number/total.
- Add an item offline → appears instantly; cancel a line → disappears; both
  survive a cold restart before sync.
- Existing-line **+/- quantity** offline → adjusts and re-syncs (this used to
  need a network fetch; verify it now works with no connectivity).
- Transfer a table → the bill moves and does not resurrect at the old table.
- Pay → the bill closes; replaying the queued pay on an already-paid order is a
  no-op (idempotent).
- Kill the app mid-order (write landed, ack not) → on restart the order is still
  shown and still queued, and does not double-send.
- Two terminals open the **same table** while both offline → on reconnect the
  409 merge folds the losing terminal's items into the winning order (rare;
  the one path the tests can't exercise).
- Waiter open-order list shows the same open bills the floor does, and a
  just-paid dine-in table drops off it when it goes free.
- **Waiter opens a table** (with a waiter assigned) **offline** → it shows
  instantly on the floor and in the waiter list (this used to land only in Hive
  and was invisible until sync); reconnect → exactly one order, the assigned
  waiter preserved, no duplicate.
- Waiter staff picker lists the current waiters (now read from the replica, not
  the Hive user cache); a removed staff member is not offered.

## Still on Hive (not this flow)

- **`login_data_scope` (§9).** Auth-critical tenant-switch wipe + a "did setup
  land data" check; entangled with what still populates the Hive catalog.
  Deferred to a session where the app runs, because the failure mode (a tenant
  switch that leaves stale data, or a setup-check that mis-reports) is not
  CI-observable and lands on the login path.
- **`SyncEngine`** still hydrates the Hive catalog (goods/categories/users/…)
  and `CacheService` (≈20 files still read it — the menu goods lookups for
  receipts, the PIN-login user cache, `main_repository` REST fallbacks). Those
  readers must move before the Hive `LocalDatabase`/`CacheService` can be
  deleted (§10).
- **`di.dart`** is the composition root, retired last with the Hive
  `LocalDatabase`/`CacheService` (§10).

The table-timer store (§8) previously listed here is **done** — see item 6 in
"What was built."
