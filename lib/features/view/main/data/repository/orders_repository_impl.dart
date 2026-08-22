import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/database/local_database.dart' as hive;
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart'
    show OrderItem;

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §B2/§B3 — the order aggregate on the single
/// SQLite replica.
///
/// This is the migration off the Hive snapshot the order screen used to read.
/// Every write lands two things together: the local rows the screen renders
/// (`orders` + `order_items` in the replica) and the outbox op that will carry
/// the change to the server. Reads are the replica read [OrderDetailQuery]
/// assembles — the same rows a `/sync/pull` delivers, so a brand-new offline
/// order and a server-synced one are indistinguishable to the screen.
///
/// ## Why item rows can be written without their own pending guard
///
/// The backend honours a client-supplied order-item id (`CreateOrderItemInline`
/// / `CreateOrderItemEntry`, both idempotent on replay), so the id a terminal
/// invents for a line is the id that line keeps. Two consequences:
///
///  * A line created as part of an order's create ([_writeOrderWithItems])
///    rides inside the create body — there is no per-item op to clear a pending
///    guard, so the row is written **unguarded**. That is safe because the
///    server has never heard of the order until its create syncs, so no pull
///    can clobber or delete the line before then; and once it does sync, the
///    pull re-delivers the same-id row and the local copy converges to it.
///  * A line added to an *existing* order ([addItems]) is its own write with
///    its own op, so it *is* pending-guarded and clears on ack, the ordinary
///    back-office pattern.
///
/// A cancel ([cancelLineItems]) is always guarded: the server still has the
/// line until the cancel syncs, so without the guard a pull would resurrect the
/// line the operator just removed.
class OrdersRepositoryImpl implements OrdersRepository {
  final LocalDatabase _db;
  final ChangeApplier _applier;
  final LocalWriter _writer;
  final OrderDetailQuery _detail;
  final LanHubService _lanHub;

  /// The retiring Hive order-detail store. The detail screen now reads the
  /// replica, but the waiter subsystem (`WaiterLocalRepositoryImpl`) still
  /// synthesises its open-order list from this box, so a snapshot is mirrored
  /// here until §B's waiter reads move across too (§7). Nothing in this class
  /// *reads* it — the mirror is write-only, and this dependency goes with the
  /// waiter migration.
  final hive.LocalDatabase _hive;

  /// Occupancy is the replica's local-authority overlay, set through the
  /// repository that owns it rather than by rewriting a cached row here.
  final TablesRepository _tables;

  OrdersRepositoryImpl({
    required LocalDatabase db,
    required ChangeApplier applier,
    required LocalWriter writer,
    required OrderDetailQuery detail,
    required hive.LocalDatabase hiveStore,
    required LanHubService lanHub,
    required TablesRepository tables,
  })  : _db = db,
        _applier = applier,
        _writer = writer,
        _detail = detail,
        _hive = hiveStore,
        _lanHub = lanHub,
        _tables = tables;

  // ── Reads ────────────────────────────────────────────────────────────────

  /// [key] is a table id for dine-in and an order id for takeaway (the two ways
  /// the screens hold a bill), so both lookups are tried — table first, then id.
  Map<String, dynamic>? _resolve(String key) =>
      _detail.liveOrderForTable(key) ?? _detail.liveOrderById(key);

  ArchiveDetailModel? _decode(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return ArchiveDetailModel.fromJson(json);
    } catch (_) {
      // A malformed row is treated as "nothing for this table yet" rather than
      // crashing a bloc's stream subscription.
      return null;
    }
  }

  @override
  Stream<ArchiveDetailModel?> watchOrderDetail(String key) =>
      _db.watch(OrderDetailQuery.watchedTables, () => _resolve(key)).map(_decode);

  @override
  ArchiveDetailModel? getOrderDetail(String key) => _decode(_resolve(key));

  @override
  Future<void> evictOrderDetail(String key) async {
    // The replica needs no eviction — a bill leaves the open-order read the
    // moment its `bill_status` stops being 'open' (pay/cancel write that), which
    // is exactly what [OrderDetailQuery] filters on. Only the Hive mirror the
    // waiter list still reads has to be cleared explicitly.
    await _hive.evictOrderDetail(key);
  }

  @override
  Future<void> saveOrderDetailSnapshot(String key, Map<String, dynamic> json) async {
    // Mirror to the retiring Hive box first, so the waiter open-order list keeps
    // resolving until its reads move to the replica (§7).
    await _hive.saveOrderDetail(key, json);

    // Then the replica. Belt-and-suspenders for the callers that hand a
    // pre-built bill in (the takeaway preview, the waiter open-table snapshot):
    // the create paths below already wrote the authoritative rows, so this is an
    // idempotent upsert — and [ChangeApplier] skips a row whose pending guard is
    // still held, so it can never overwrite a just-written create with the
    // snapshot's thinner shape.
    final orderId = json['id']?.toString() ?? '';
    if (orderId.isEmpty) return;
    // key != id ⇒ key is a table id (dine-in); key == id ⇒ takeaway, no table.
    final tableId = key != orderId ? key : (json['table_id']?.toString() ?? '');
    final row = Map<String, dynamic>.from(json)..remove('items');
    row['id'] = orderId;
    if (tableId.isNotEmpty) row['table_id'] = tableId;
    row['bill_status'] = (json['bill_status'] ?? 'open').toString();
    _applier.applyOne(entity: 'orders', action: 'create', payload: row);

    final items = json['items'];
    if (items is List) {
      for (final raw in items.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final id = item['id']?.toString() ?? '';
        // No id ⇒ cannot place the line without risking a duplicate once the
        // server assigns its own; skip it. The create path always supplies ids.
        if (id.isEmpty) continue;
        item['order_id'] = orderId;
        _applier.applyOne(entity: 'order_items', action: 'create', payload: item);
      }
    }
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  @override
  Future<void> createOrder({
    required String tableId,
    required String clientOrderId,
    required int guestCount,
    required List<OrderItem> items,
    required TableStatus tableStatus,
  }) async {
    _writeOrderWithItems(
      orderId: clientOrderId,
      tableId: tableId,
      orderType: 'dine_in',
      guestCount: guestCount,
      items: items,
    );
    // Optimistic: mark the table busy for every terminal on the LAN — the same
    // side effect the old path performed, now unconditional (the local commit
    // above already succeeded regardless of connectivity).
    _lanHub.tableStatusChanged(tableId, TableStatus.busy.name);
  }

  @override
  Future<void> createTakeawayOrder({
    required String clientOrderId,
    required int guestCount,
    required List<OrderItem> items,
  }) async {
    _writeOrderWithItems(
      orderId: clientOrderId,
      tableId: '',
      orderType: 'takeaway',
      guestCount: guestCount,
      items: items,
    );
  }

  /// Writes the order row + its line rows to the replica and enqueues the one
  /// `orders/create` op that carries them to the server. Item ids are minted
  /// once here and used for both the local rows and the create body, so the id
  /// the operator sees offline is the id the server keeps.
  void _writeOrderWithItems({
    required String orderId,
    required String tableId,
    required String orderType,
    required int guestCount,
    required List<OrderItem> items,
  }) {
    final base = DateTime.now().toUtc();
    final itemIds = [for (var i = 0; i < items.length; i++) generateUuidV4()];

    final orderRow = <String, dynamic>{
      'id': orderId,
      if (tableId.isNotEmpty) 'table_id': tableId,
      'bill_status': 'open',
      'status': OrderStatus.open.name,
      'order_type': orderType,
      'guest_count': guestCount,
      'comment': 'Very good',
      'created_at': base.toIso8601String(),
    };

    final body = <String, dynamic>{
      'id': orderId,
      if (tableId.isNotEmpty) 'table_id': tableId,
      'comment': 'Very good',
      'guest_count': guestCount,
      'status': 'open',
      'order_type': orderType,
      'items': [
        for (var i = 0; i < items.length; i++) _createItemBody(itemIds[i], items[i]),
      ],
    };

    // The order row is pending-guarded and clears when this op acks; the item
    // rows are unguarded (see the class doc) and ride inside `body`.
    _writer.write(
      entity: 'orders',
      id: orderId,
      action: 'create',
      row: orderRow,
      request: body,
    );
    for (var i = 0; i < items.length; i++) {
      _applier.applyOne(
        entity: 'order_items',
        action: 'create',
        payload: _itemRow(
          id: itemIds[i],
          orderId: orderId,
          item: items[i],
          // A per-line offset so the lines sort in the order they were rung in;
          // identical timestamps would fall back to random-uuid id order.
          createdAt: _seq(base, i),
        ),
      );
    }
  }

  @override
  Future<void> addItems({
    required String tableId,
    required String orderId,
    required List<OrderItem> items,
    List<String>? itemClientIds,
  }) async {
    final ids = itemClientIds ?? [for (var i = 0; i < items.length; i++) generateUuidV4()];
    final base = DateTime.now().toUtc();
    for (var i = 0; i < items.length; i++) {
      // One op per line: its entityId is the line id, so its pending clears on
      // ack; the handler chains it on `order_id` so it never overtakes the
      // order's create.
      _writer.write(
        entity: 'order_items',
        id: ids[i],
        action: 'create',
        row: _itemRow(
          id: ids[i],
          orderId: orderId,
          item: items[i],
          createdAt: _seq(base, i),
        ),
        request: {
          'order_id': orderId,
          'items': [_createItemBody(ids[i], items[i])],
        },
      );
    }
    if (tableId.isNotEmpty) {
      _lanHub.tableStatusChanged(tableId, TableStatus.busy.name);
    }
  }

  @override
  Future<void> cancelLineItems({
    required List<String> lineIds,
    String? comment,
  }) async {
    if (lineIds.isEmpty) return;
    final trimmed = comment?.trim();
    for (final lineId in lineIds) {
      // Read the line's order before removing it, so the cancel op can chain on
      // the same order and never replay ahead of the add that created the line.
      final orderId = _db.byId('order_items', lineId)?['order_id']?.toString();
      _writer.delete(
        entity: 'order_items',
        id: lineId,
        request: {
          if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
          if (trimmed != null && trimmed.isNotEmpty) 'comment': trimmed,
        },
      );
    }
  }

  @override
  Future<void> transferTable({
    required String orderId,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    final current = _db.byId('orders', orderId);
    if (current != null) {
      // Re-key the bill onto the target table in the replica, so the detail
      // screen (keyed by table) shows the order at its new table without any
      // refetch.
      final updated = Map<String, dynamic>.from(current)
        ..['table_id'] = targetTableId;
      _writer.write(
        entity: 'orders',
        id: orderId,
        action: 'transfer',
        row: updated,
        request: {'target_table_id': targetTableId},
      );
    } else {
      // The order is not in the replica yet (created on another terminal). Send
      // the transfer alone; the pull will deliver the re-keyed order.
      _writer.enqueueOnly(
        entity: 'orders',
        action: 'transfer',
        entityId: orderId,
        request: {'target_table_id': targetTableId},
      );
    }
    await _tables.updateTableStatus(sourceTableId, TableStatus.free);
    await _tables.updateTableStatus(targetTableId, TableStatus.busy);
    _lanHub.tableStatusChanged(sourceTableId, TableStatus.free.name);
    _lanHub.tableStatusChanged(targetTableId, TableStatus.busy.name);
  }

  // ── Row shapes ───────────────────────────────────────────────────────────

  /// A line's stored replica row. `good_name` is not stored — it is joined from
  /// `goods` on read — but everything the screen renders is here.
  Map<String, dynamic> _itemRow({
    required String id,
    required String orderId,
    required OrderItem item,
    required String createdAt,
  }) =>
      {
        'id': id,
        'order_id': orderId,
        'good_id': item.goods.id,
        'quantity': item.quantity,
        'price': (double.tryParse(item.goods.price) ?? 0).round(),
        'comment': item.comment,
        'status': 'pending',
        'created_at': createdAt,
      };

  /// One line in a create/add-items request body — carrying the client id the
  /// backend honours as the line's primary key.
  Map<String, dynamic> _createItemBody(String id, OrderItem item) => {
        'id': id,
        'good_id': item.goods.id,
        'quantity': item.quantity,
        'comment': item.comment,
      };

  /// [base] shifted by [i] milliseconds, ISO-8601 — a monotonic per-line
  /// timestamp so a batch of lines keeps its ring-in order on read.
  static String _seq(DateTime base, int i) =>
      base.add(Duration(milliseconds: i)).toIso8601String();
}
