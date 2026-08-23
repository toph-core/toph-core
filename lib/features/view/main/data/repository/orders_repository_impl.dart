import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart'
    show TableStatus;
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

  /// Occupancy is the replica's local-authority overlay, set through the
  /// repository that owns it rather than by rewriting a cached row here.
  final TablesRepository _tables;

  OrdersRepositoryImpl({
    required LocalDatabase db,
    required ChangeApplier applier,
    required LocalWriter writer,
    required OrderDetailQuery detail,
    required LanHubService lanHub,
    required TablesRepository tables,
  }) : _db = db,
       _applier = applier,
       _writer = writer,
       _detail = detail,
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
  Stream<ArchiveDetailModel?> watchOrderDetail(String key) => _db
      .watch(OrderDetailQuery.watchedTables, () => _resolve(key))
      .map(_decode);

  @override
  ArchiveDetailModel? getOrderDetail(String key) => _decode(_resolve(key));

  @override
  Future<void> evictOrderDetail(String key) async {
    // Nothing to do on the replica — a bill leaves the open-order read the
    // moment it stops being live, and `PaymentRepository` writes that onto the
    // row itself now: `bill_status = 'paid'` for a settled check,
    // `status = 'cancelled'` for a comped one. Both are what
    // [OrderDetailQuery]'s live-bill predicate filters on. Kept to satisfy the
    // interface; the Hive box it used to clear is no longer read.
  }

  /// Projection field names that are not `orders` columns.
  ///
  /// The snapshot callers hand in an `ArchiveDetailModel` — the REST *bill*
  /// shape, assembled from joins — not a row of the `orders` table. It calls
  /// the open time `opened_at`, the settle time `closed_at` and the table
  /// charge `table_amount`, and it carries `table_number`, `hall_name` and
  /// `cashier_name`, which live on other tables entirely.
  static const _projectionOnlyKeys = {
    'items',
    'opened_at',
    'closed_at',
    'table_amount',
    'table_number',
    'hall_name',
    'cashier_name',
    'pause_periods',
    'table_sessions',
  };

  /// A projection timestamp as a UTC instant.
  ///
  /// `ArchiveDetailModel` stamps `DateTime.now()` — device-local, and
  /// serialised with no offset. Stored verbatim, SQLite reads a bare
  /// `2026-08-23T13:33:20` as UTC, which puts a bill five hours into the
  /// future in a UTC+5 venue and takes it straight back out of the window it
  /// was just written into.
  static String? _utcIso(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toUtc().toIso8601String();
  }

  @override
  Future<void> saveOrderDetailSnapshot(
    String key,
    Map<String, dynamic> json,
  ) async {
    // Merged onto the stored row, never written over it.
    //
    // This used to `applyOne(action: 'create')` with the projection map as the
    // whole payload, and a replicated row is one JSON blob replaced wholesale
    // — so every field the projection does not have was erased, `created_at`
    // and `paid_at` among them. `ArchivesQuery` filters and orders on
    // `COALESCE(paid_at, created_at)`, so a bill whose timestamps had been
    // blanked matched *no* date window at all: gone from Today, Week, Month,
    // Year and any picked range, present only under "All", and still perfectly
    // intact on the server. That is what made paid checks look deleted.
    //
    // The old note here claimed the `_pending` guard prevented this. It does
    // not: the guard covers the window between a local write and its
    // acknowledgement, and every snapshot written after that lands unopposed.
    final orderId = json['id']?.toString() ?? '';
    if (orderId.isEmpty) return;
    // key != id ⇒ key is a table id (dine-in); key == id ⇒ takeaway, no table.
    final tableId = key != orderId ? key : (json['table_id']?.toString() ?? '');
    final stored = _db.byId('orders', orderId) ?? const <String, dynamic>{};

    final row = <String, dynamic>{
      ...stored,
      for (final e in json.entries)
        if (!_projectionOnlyKeys.contains(e.key) && e.value != null)
          e.key: e.value,
      'id': orderId,
    };
    if (tableId.isNotEmpty) row['table_id'] = tableId;
    row['bill_status'] =
        (json['bill_status'] ?? stored['bill_status'] ?? 'opened').toString();
    // The feed's own value always wins; the projection only ever fills a gap.
    row['created_at'] = stored['created_at'] ?? _utcIso(json['opened_at']);
    row['paid_at'] = stored['paid_at'] ?? _utcIso(json['closed_at']);
    final tableCharge = stored['table_charge'] ?? json['table_amount'];
    if (tableCharge != null) row['table_charge'] = tableCharge;

    _applier.applyOne(entity: 'orders', action: 'update', payload: row);

    final items = json['items'];
    if (items is List) {
      for (final raw in items.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final id = item['id']?.toString() ?? '';
        // No id ⇒ cannot place the line without risking a duplicate once the
        // server assigns its own; skip it. The create path always supplies ids.
        if (id.isEmpty) continue;
        item['order_id'] = orderId;
        _applier.applyOne(
          entity: 'order_items',
          action: 'create',
          payload: item,
        );
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
    String? waiterId,
  }) async {
    _writeOrderWithItems(
      orderId: clientOrderId,
      tableId: tableId,
      orderType: 'dine_in',
      guestCount: guestCount,
      items: items,
      waiterId: waiterId,
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
    String? waiterId,
  }) {
    final base = DateTime.now().toUtc();
    final itemIds = [for (var i = 0; i < items.length; i++) generateUuidV4()];
    final hasWaiter = waiterId != null && waiterId.isNotEmpty;

    final orderRow = <String, dynamic>{
      'id': orderId,
      if (tableId.isNotEmpty) 'table_id': tableId,
      if (hasWaiter) 'waiter_id': waiterId,
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
      if (hasWaiter) 'waiter_id': waiterId,
      'comment': 'Very good',
      'guest_count': guestCount,
      'status': 'open',
      'order_type': orderType,
      'items': [
        for (var i = 0; i < items.length; i++)
          _createItemBody(itemIds[i], items[i]),
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
    final ids =
        itemClientIds ??
        [for (var i = 0; i < items.length; i++) generateUuidV4()];
    final base = DateTime.now().toUtc();
    for (var i = 0; i < items.length; i++) {
      // One op per line: its entityId is the line id, so its pending clears on
      // ack; the handler chains it on `order_id` so it never overtakes the
      // order's create.
      //
      // `create`, not `write`: the backend mints an order item's primary key
      // itself and ignores the one we send (`AddOrderItems`, service/order.go),
      // so this id is provisional by definition. `write` would assert the
      // opposite — that the id survives the round trip — and leave the local
      // row standing next to the server's when the feed delivered it, which is
      // exactly how one physical line came to be stored twice. Marking it
      // provisional hands the swap to `OutboxDrainer._reconcile`, which also
      // repoints anything still queued against the old id: a cancel of a line
      // added offline used to post the client uuid, 404, and be swallowed as
      // success.
      _writer.create(
        entity: 'order_items',
        id: ids[i],
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
  }) => {
    'id': id,
    // The same value the request sends as `client_item_id`, stored so a local
    // row is self-describing: this is the key the server will echo back, and
    // the one `ChangeApplier._retireClientTwin` matches the arriving row on.
    'client_item_id': id,
    'order_id': orderId,
    'good_id': item.goods.id,
    'quantity': item.quantity,
    'price': (double.tryParse(item.goods.price) ?? 0).round(),
    'comment': item.comment,
    'status': 'pending',
    'created_at': createdAt,
  };

  /// One line in a create/add-items request body.
  ///
  /// [id] goes out as `client_item_id`, **not** as `id`. The backend assigns
  /// an order item its own primary key (`uuid.New()` in both `CreateOrder` and
  /// `AddOrderItems`) and ignores an `id` in the item body entirely — the
  /// client-id-as-PK dedup that `orders` enjoys does not extend to its lines.
  /// `client_item_id` is the key it does honour
  /// (`migrations/tenants/70_order_items_client_id.up.sql`), and it earns two
  /// separate things:
  ///
  ///  * **Replay idempotency.** A lost response after the insert committed —
  ///    a dropped LAN relay, a request timeout — used to make the outbox retry
  ///    create a second, fully real set of lines on the server: double
  ///    quantity, double stock deduction, double totals. The partial unique
  ///    index on `(order_id, client_item_id)` is what stops that, and it only
  ///    constrains rows that supply the key.
  ///  * **Twin retirement.** The server echoes the key back on the change
  ///    feed, which is how [ChangeApplier] recognises the local row this line
  ///    was optimistically written under and removes it instead of leaving one
  ///    physical line stored twice.
  ///
  /// Sending it costs nothing when the write succeeds first time; not sending
  /// it is what made every locally-rung line count twice in the replica.
  Map<String, dynamic> _createItemBody(String id, OrderItem item) => {
    'client_item_id': id,
    'good_id': item.goods.id,
    'quantity': item.quantity,
    'comment': item.comment,
  };

  /// [base] shifted by [i] milliseconds, ISO-8601 — a monotonic per-line
  /// timestamp so a batch of lines keeps its ring-in order on read.
  static String _seq(DateTime base, int i) =>
      base.add(Duration(milliseconds: i)).toIso8601String();
}
