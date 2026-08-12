import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_line_item/order_line_item_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/payment_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/waiter_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart' show OrderItem;

/// CLIENT_FACING_OFFLINE_PLAN.md §5 — the rebuild of the plan's "largest
/// single item." The previous implementation was, by its own doc comment,
/// "a pure online transport": every read a live GET, every write a direct
/// POST, outbox only as the Cubit's failure fallback. This one is the
/// inverse and adds no second plumbing of its own:
///
/// - Reads are synthesized from `LocalDatabase` — the order-detail box
///   (SyncEngine-hydrated + written by every local create), joined with the
///   tables/halls boxes for numbers/names, and the users box for staff.
/// - Writes delegate to the repositories that were already correct:
///   `OrdersRepository.addItems`/`cancelLineItems` (same ops, same
///   idempotency keys, same LAN broadcasts the cashier flow uses) and
///   `PaymentRepository.pay` — one pay path, not the parallel `/pay` POST
///   this class used to carry.
class WaiterLocalRepositoryImpl implements WaiterLocalRepository {
  final LocalDatabase _localDb;
  final OfflineQueueService _queue;
  final OrdersRepository _orders;
  final PaymentRepository _payment;
  final LanHubService _lanHub;
  final LeaseManager _lease;

  WaiterLocalRepositoryImpl(
    this._localDb,
    this._queue,
    this._orders,
    this._payment,
    this._lanHub,
    this._lease,
  );

  // ── Local synthesis helpers ─────────────────────────────────────────────

  ArchiveDetailModel? _decodeDetail(Map<String, dynamic> raw) {
    try {
      return ArchiveDetailModel.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// The local bills that are genuinely "open" right now: dine-in entries
  /// (box key = tableId) only while their table is still busy — which also
  /// ages out stale rows from before an offline pay — and takeaway entries
  /// (box key = the order's own id) only while their status is open.
  List<({String key, ArchiveDetailModel detail, CafeTableModel? table})>
      _openLocalBills() {
    final tablesById = {for (final t in _localDb.getTables()) t.id: t};
    final result =
        <({String key, ArchiveDetailModel detail, CafeTableModel? table})>[];
    for (final entry in _localDb.getOrderDetailEntries().entries) {
      final detail = _decodeDetail(entry.value);
      if (detail == null || detail.id.isEmpty) continue;
      final table = tablesById[entry.key];
      if (table != null) {
        if (table.status != TableStatus.busy) continue;
      } else {
        // Takeaway (key == order id) or an unknown table — status-gated.
        if (detail.status != OrderStatus.open) continue;
      }
      result.add((key: entry.key, detail: detail, table: table));
    }
    return result;
  }

  OpenOrderModel _toOpenOrder(
    ArchiveDetailModel detail,
    CafeTableModel? table,
    Map<String, HallModel> hallsById,
  ) {
    final total = detail.grandTotal > 0 ? detail.grandTotal : detail.foodTotal;
    return OpenOrderModel(
      id: detail.id,
      tableId: table?.id ?? (detail.tableId.isNotEmpty ? detail.tableId : null),
      tableNumber: table?.number ?? detail.tableNumber.toInt(),
      hallName: table != null
          ? (hallsById[table.hallId]?.name ?? detail.hallName)
          : detail.hallName,
      guestCount: detail.guestCount.toInt(),
      openedAt: detail.opened,
      status: 'open',
      totalAmount: total.round().toString(),
      displayTotalAmount: total.round().toString(),
      serviceAmount: detail.serviceAmount > 0
          ? detail.serviceAmount.round().toString()
          : null,
      servicePercent: detail.servicePercent > 0 ? detail.servicePercent : null,
      orderType: table == null ? 'takeaway' : 'dine_in',
      tableType: table?.tableType,
      tableAmount:
          detail.tableAmount > 0 ? detail.tableAmount.toString() : null,
    );
  }

  ({String key, ArchiveDetailModel detail, CafeTableModel? table})?
      _findByOrderId(String orderId) {
    for (final bill in _openLocalBills()) {
      if (bill.detail.id == orderId) return bill;
    }
    return null;
  }

  // ── Reads ───────────────────────────────────────────────────────────────

  @override
  Future<Either<Failure, List<OpenOrderModel>>> getOpenOrders({
    required WaiterOrdersListMode mode,
    String lang = 'uz',
    String scope = 'active',
    int limit = 50,
    int offset = 0,
  }) async {
    final hallsById = {for (final h in _localDb.getHalls()) h.id: h};
    final orders = _openLocalBills()
        .map((b) => _toOpenOrder(b.detail, b.table, hallsById))
        .toList()
      ..sort((a, b) {
        final ao = a.openedAt, bo = b.openedAt;
        if (ao == null && bo == null) return 0;
        if (ao == null) return 1;
        if (bo == null) return -1;
        return bo.compareTo(ao);
      });
    return Right(orders);
  }

  @override
  Future<Either<Failure, OpenOrderModel?>> getOrderDetail(
    String orderId,
  ) async {
    if (orderId.isEmpty) return const Right(null);
    final bill = _findByOrderId(orderId);
    if (bill == null) return const Right(null);
    final hallsById = {for (final h in _localDb.getHalls()) h.id: h};
    return Right(_toOpenOrder(bill.detail, bill.table, hallsById));
  }

  @override
  Future<Either<Failure, List<OrderLineItemModel>>> getOrderItems(
    String orderId,
  ) async {
    if (orderId.isEmpty) return const Right([]);
    final bill = _findByOrderId(orderId);
    if (bill == null) return const Right([]);
    return Right([
      for (final g in bill.detail.goods)
        OrderLineItemModel(
          id: g.id,
          goodId: g.goodId,
          quantity: g.quantity,
          price: g.price.toString(),
          comment: g.comment.isEmpty ? null : g.comment,
          goodName: g.name,
          status: g.status,
          createdAt: g.createdAt,
        ),
    ]);
  }

  @override
  Future<Either<Failure, List<UserModel>>> getStaffWaiters() async {
    final waiters = _localDb
        .getUsers()
        .where((u) => u.role == UserRole.waiter)
        .toList();
    return Right(waiters);
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  /// Patches the raw stored bill JSON for the entry containing [orderItemId]
  /// so every local watcher sees the cancel immediately.
  Future<void> _markLineCancelledLocally(String orderItemId) async {
    for (final entry in _localDb.getOrderDetailEntries().entries) {
      final items = entry.value['items'];
      if (items is! List) continue;
      var touched = false;
      for (final item in items) {
        if (item is Map && item['id'] == orderItemId) {
          item['status'] = 'cancelled';
          touched = true;
        }
      }
      if (touched) {
        await _localDb.saveOrderDetail(entry.key, entry.value);
        return;
      }
    }
  }

  @override
  Future<Either<Failure, bool>> cancelOrderItem({
    required String orderItemId,
    String? comment,
  }) async {
    await _orders.cancelLineItems(lineIds: [orderItemId], comment: comment);
    await _markLineCancelledLocally(orderItemId);
    return const Right(true);
  }

  @override
  Future<Either<Failure, bool>> sendItems({
    required String orderId,
    required String tableId,
    required List<OrderItem> items,
  }) async {
    await _orders.addItems(tableId: tableId, orderId: orderId, items: items);
    // Durable local bill patch — the same wire item shape the box already
    // stores, so the reads above pick the new lines up on the next decode.
    final bill = _findByOrderId(orderId);
    if (bill != null) {
      final raw = _localDb.getOrderDetail(bill.key);
      if (raw != null) {
        final list = raw['items'] is List
            ? List<dynamic>.from(raw['items'] as List)
            : <dynamic>[];
        final now = DateTime.now().toIso8601String();
        for (final item in items) {
          list.add({
            'id': generateUuidV4(),
            'good_id': item.goods.id,
            'good_name': item.goods.name,
            'quantity': item.quantity,
            'price': item.goods.price,
            'comment': item.comment,
            'status': 'pending',
            'created_at': now,
          });
        }
        raw['items'] = list;
        await _localDb.saveOrderDetail(bill.key, raw);
      }
    }
    return const Right(true);
  }

  @override
  Future<Either<Failure, bool>> closeOrder({
    required String orderId,
    required String tableId,
    required int paidAmount,
    required String paymentType,
    double discountPercent = 0,
    double discountAmount = 0,
    int tableCharge = 0,
  }) async {
    await _payment.pay(
      orderId: orderId,
      tableId: tableId,
      paidAmount: paidAmount,
      paymentType: paymentType,
      applyService: true,
      discountAmount: discountAmount > 0 ? discountAmount.round() : null,
      discountPercent: discountPercent > 0 ? discountPercent.round() : null,
      tableCharge: tableCharge,
    );
    // Finish locally: the bill row is closed, the table is free — same side
    // effects the cashier pay flow performs, kept here so the waiter screen
    // doesn't need its own second copy. The local timer record goes too:
    // SyncEngine only reconciles timers for *busy* tables, so a record left
    // behind here would never age out and the next timed order on this
    // table would reuse the paid order via createTimedOrder's guard.
    final bill = _findByOrderId(orderId);
    if (bill != null) await _localDb.evictOrderDetail(bill.key);
    await _localDb.evictTableTimer(orderId);
    if (tableId.isNotEmpty) {
      await _localDb.updateTableStatus(tableId, TableStatus.free);
      _lanHub.tableStatusChanged(tableId, TableStatus.free.name);
    }
    return const Right(true);
  }

  @override
  Future<Either<Failure, WaiterCreateOrderResult>> createOrder({
    required String tableId,
    required int guestCount,
    String? waiterId,
  }) async {
    // Local double-open guard, replacing the old server-409 recovery: an
    // open local bill already on this table is reused instead of enqueueing
    // a duplicate create. A genuine cross-terminal race still merges at
    // replay time via OfflineQueueService's 409 branch.
    final existingRaw = _localDb.getOrderDetail(tableId);
    if (existingRaw != null) {
      final existing = _decodeDetail(existingRaw);
      if (existing != null &&
          existing.id.isNotEmpty &&
          existing.status == OrderStatus.open) {
        return Right(WaiterCreateOrderResult(existing.id, wasExisting: true));
      }
    }

    // LAN_HUB_AND_LEASING_PLAN.md §5/§8: this second table-open path goes
    // through the same lease gate CreateOrderBloc awaits — the recurring
    // "fix landed on one path, not its duplicate" gap, closed. Same §9.3
    // policy: rejection blocks, unreachable allows with a visible flag.
    final lease = await _lease.acquireTableLease(tableId);
    if (!lease.isGranted && !lease.isUnreachable) {
      return const Left(
        MessageFailure("Bu stol allaqachon boshqa terminalda ochilgan."),
      );
    }

    final clientOrderId = generateUuidV4();
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.createOrder,
      // Same body the old direct POST sent — including the waiter binding,
      // which CreateOrderRequestModel doesn't model, hence the hand-built
      // payload instead of OrdersRepository.createOrder here.
      payload: jsonEncode({
        'id': clientOrderId,
        'table_id': tableId,
        'guest_count': guestCount,
        'status': 'open',
        'order_type': 'dine_in',
        'comment': '',
        'items': <dynamic>[],
        if (waiterId != null && waiterId.isNotEmpty) 'waiter_id': waiterId,
      }),
      tableId: tableId,
      createdAt: DateTime.now(),
    ));
    await _orders.saveOrderDetailSnapshot(
      tableId,
      ArchiveDetailModel(
        id: clientOrderId,
        status: OrderStatus.open,
        opened: DateTime.now(),
        tableId: tableId,
        guestCount: guestCount.toDouble(),
      ).toJson(),
    );
    await _localDb.updateTableStatus(tableId, TableStatus.busy);
    _lanHub.tableStatusChanged(tableId, TableStatus.busy.name);
    // Local commit done — clear the ephemeral claim (only a grant held one).
    if (lease.isGranted) {
      _lease.releaseTableLease(tableId);
    }
    return Right(WaiterCreateOrderResult(
      clientOrderId,
      orderType: 'dine_in',
      leaseUnverified: lease.isUnreachable,
    ));
  }
}
