import 'dart:convert';

import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the live order-detail read,
/// assembled from the SQLite replica instead of the Hive snapshot the order
/// screen reads today.
///
/// This is the **stored** side only: the open order for a table and its live
/// items, joined to `goods` for names and `cafe_tables`/`halls` for the header,
/// exactly as the server's projection did. It is the same assembly
/// [ArchivesQuery] does for closed bills, keyed on the open bill of a table.
///
/// It intentionally does NOT merge the offline queue's pending/provisional
/// operations. `detail_bloc` overlays those — optimistic adds, `pending_offline`
/// items, cancels — on top of whatever the read returns, and that merge is the
/// stateful part that stays in the bloc. Swapping the bloc's source from the
/// Hive snapshot to this query is the remaining step, and it needs the app
/// running to verify the overlay still behaves.
class OrderDetailQuery {
  final LocalDatabase _db;

  const OrderDetailQuery(this._db);

  /// The screen rebuilds when the order, its items, or the goods they name
  /// change — a price edit on another terminal reaches the open bill live.
  static const watchedTables = {'orders', 'order_items', 'goods', 'cafe_tables', 'halls'};

  /// What makes a bill live, as one SQL predicate over an `orders o`.
  ///
  /// Two clauses, and each of them is a shape the server actually produces.
  ///
  ///  * **`bill_status IN ('open', 'opened')`.** The backend's `bill_status`
  ///    enum is `('opened', 'closed', 'paid', 'debt', 'deleted')` —
  ///    `migrations/tenants/6_orders.up.sql` — and `to_jsonb(NEW)` puts that
  ///    label verbatim in the change feed. The client writes `'open'` on a
  ///    locally-created order. Matching only one of the two spellings loses
  ///    half the open bills in the venue: `= 'open'` alone hides every order
  ///    the feed delivered (one opened on another terminal, or this
  ///    terminal's own once its create acks and the pull re-delivers it).
  ///  * **not `status = 'cancelled'`.** A comped check closes through
  ///    `/orders/{id}/cancel`, and `CancelOrder` sets `status = 'cancelled'`
  ///    while leaving `bill_status` at `opened`. Without this clause a
  ///    cancelled bill stays on its table forever, on the server's own shape.
  ///    `status` is nullable in the replica, and `NULL <> 'cancelled'` is NULL
  ///    in SQL, so the null case is spelled out rather than left to the
  ///    comparison.
  ///
  /// [liveOrderById] deliberately applies neither: the payment screen holds an
  /// order id and must keep rendering the bill it just settled.
  ///
  /// Public because `TableOccupancyReconciler` derives table occupancy from the
  /// same predicate. Two definitions of "this bill is still on the table" that
  /// could drift apart is precisely how a floor ends up disagreeing with its
  /// own order screen.
  static const liveBill =
      "o.deleted_at IS NULL AND o.bill_status IN ('open', 'opened') "
      "AND (o.status IS NULL OR o.status <> 'cancelled')";

  /// The open bill for [tableId], or null if the table is free.
  ///
  /// "Open" is [liveBill] — which is also how [ArchivesQuery] filters closed
  /// ones, from the other side. If two open orders ever exist for one table —
  /// which the flow is not supposed to allow — the most recently created wins,
  /// so the screen shows the current bill rather than a stale one.
  Map<String, dynamic>? liveOrderForTable(String tableId) {
    final rows = _db.select(
      '''
      SELECT o.id AS id, o.data AS data,
             t.number AS table_number, h.name AS hall_name
        FROM orders o
        LEFT JOIN cafe_tables t ON t.id = o.table_id AND t.deleted_at IS NULL
        LEFT JOIN halls       h ON h.id = t.hall_id   AND h.deleted_at IS NULL
       WHERE o.table_id = ? AND $liveBill
       ORDER BY o.created_at DESC
       LIMIT 1
      ''',
      [tableId],
    );
    return _assemble(rows);
  }

  /// The bill with primary key [orderId], regardless of `bill_status`, or null.
  ///
  /// The keyed-by-id sibling of [liveOrderForTable], for the paths that hold an
  /// order id rather than a table: takeaway (which has no table and pays through
  /// the same detail read) and the payment screen (which must keep showing the
  /// bill after `bill_status` has flipped to paid). The table/hall join stays a
  /// LEFT JOIN, so a takeaway order with no `table_id` still assembles.
  ///
  /// The absence of [liveBill] here is load-bearing, not an omission: paying
  /// now flips the row to `paid` synchronously, and this is the read that keeps
  /// the settled bill on screen and in the archive afterwards.
  Map<String, dynamic>? liveOrderById(String orderId) {
    final rows = _db.select(
      '''
      SELECT o.id AS id, o.data AS data,
             t.number AS table_number, h.name AS hall_name
        FROM orders o
        LEFT JOIN cafe_tables t ON t.id = o.table_id AND t.deleted_at IS NULL
        LEFT JOIN halls       h ON h.id = t.hall_id   AND h.deleted_at IS NULL
       WHERE o.id = ? AND o.deleted_at IS NULL
       LIMIT 1
      ''',
      [orderId],
    );
    return _assemble(rows);
  }

  /// Every open bill, each assembled exactly like [liveOrderById] (header +
  /// joined table/hall + items), newest first. The waiter open-order list's
  /// source, off the replica instead of iterating the retiring Hive box.
  List<Map<String, dynamic>> openOrders() {
    final ids = _db.select(
      "SELECT o.id AS id FROM orders o "
      "WHERE $liveBill "
      "ORDER BY o.created_at DESC",
    );
    final out = <Map<String, dynamic>>[];
    for (final row in ids) {
      final id = row['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final order = liveOrderById(id);
      if (order != null) out.add(order);
    }
    return out;
  }

  Map<String, dynamic>? _assemble(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return null;

    final row = rows.first;
    final order = _decode(row['data']);
    if (order == null) return null;
    final id = row['id'] as String? ?? order['id']?.toString() ?? '';

    return {
      ...order,
      'id': id,
      // Joined, not stored — the server synthesised these onto the projection.
      'table_number': row['table_number'],
      'hall_name': row['hall_name'],
      'items': itemsForOrder(id),
    };
  }

  /// Every non-deleted item of an order, each carrying its good's name from the
  /// joined `goods` row. Ordered oldest first, the order they were rung in.
  ///
  /// Cancelled lines are included deliberately — the payment and archive
  /// screens render them as a struck-through section, so filtering them here
  /// would make a voided line vanish from the bill instead of showing as
  /// voided. Callers that want only live lines (`detail_bloc`'s grouping)
  /// filter on `status` themselves.
  ///
  /// `order_items` promotes only `order_id`/`good_id`/`status` to real columns,
  /// so `created_at` is not one — it lives inside the stored `data` blob and is
  /// read back with `json_extract` (the same access the registry prescribes for
  /// any non-promoted field). Ordering by the bare `oi.created_at` column, as an
  /// earlier revision did, raises `no such column` against the real schema. A
  /// row whose payload carries no `created_at` sorts first, then by `id`.
  /// The live line items of [orderId] — the ungrouped list the detail screen's
  /// overlay works from. Public because `detail_bloc` resolves an existing
  /// item's line id and `good_id` from here now, off the replica, instead of
  /// the network `getOrderItemsRaw` fetch that broke offline.
  List<Map<String, dynamic>> itemsForOrder(String orderId) =>
      _itemsForOrder(orderId);

  List<Map<String, dynamic>> _itemsForOrder(String orderId) {
    final rows = _db.select(
      '''
      SELECT oi.data AS data, g.name AS good_name
        FROM order_items oi
        LEFT JOIN goods g ON g.id = oi.good_id AND g.deleted_at IS NULL
       WHERE oi.order_id = ? AND oi.deleted_at IS NULL
       ORDER BY json_extract(oi.data, '\$.created_at') ASC, oi.id ASC
      ''',
      [orderId],
    );
    final items = <Map<String, dynamic>>[];
    for (final row in rows) {
      final item = _decode(row['data']);
      if (item == null) continue;
      items.add({...item, 'good_name': row['good_name']});
    }
    return items;
  }

  Stream<Map<String, dynamic>?> watchLiveOrderForTable(String tableId) =>
      _db.watch(watchedTables, () => liveOrderForTable(tableId));

  static Map<String, dynamic>? _decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
