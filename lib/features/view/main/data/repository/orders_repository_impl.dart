import 'dart:convert';

import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart' show OrderItem;

class OrdersRepositoryImpl implements OrdersRepository {
  final LocalDatabase _localDb;
  final OfflineQueueService _queue;
  final LanHubService _lanHub;
  final CacheService _cache;

  OrdersRepositoryImpl({
    required LocalDatabase localDb,
    required OfflineQueueService queue,
    required LanHubService lanHub,
    required CacheService cache,
  })  : _localDb = localDb,
        _queue = queue,
        _lanHub = lanHub,
        _cache = cache;

  /// CLIENT_FACING_OFFLINE_PLAN.md §6: the add-item timestamp is captured
  /// here, at the moment items are committed locally — the same
  /// `name -> earliestCreatedAt` cache `PaymentBloc` used to fill from a
  /// network `order-items` fetch on every detail update. Earliest wins, so
  /// re-adding an item never moves its original time.
  Future<void> _recordItemTimestamps(String orderId, List<OrderItem> items) async {
    if (orderId.isEmpty || items.isEmpty) return;
    final now = DateTime.now();
    final merged = Map<String, DateTime>.from(_cache.getItemTimestamps(orderId));
    for (final item in items) {
      merged.putIfAbsent(item.goods.name, () => now);
    }
    await _cache.saveItemTimestamps(orderId, merged);
  }

  ArchiveDetailModel? _decode(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return ArchiveDetailModel.fromJson(json);
    } catch (_) {
      // Malformed/partial cached JSON — treated the same as "nothing cached
      // yet" rather than crashing a Bloc's stream subscription.
      return null;
    }
  }

  @override
  Stream<ArchiveDetailModel?> watchOrderDetail(String key) =>
      _localDb.watchOrderDetail(key).map(_decode);

  @override
  ArchiveDetailModel? getOrderDetail(String key) => _decode(_localDb.getOrderDetail(key));

  @override
  Future<void> evictOrderDetail(String key) => _localDb.evictOrderDetail(key);

  @override
  Future<void> saveOrderDetailSnapshot(String key, Map<String, dynamic> json) =>
      _localDb.saveOrderDetail(key, json);

  @override
  Future<void> createOrder({
    required String tableId,
    required String clientOrderId,
    required int guestCount,
    required List<OrderItem> items,
    required TableStatus tableStatus,
  }) async {
    final request = CreateOrderRequestModel(
      id: clientOrderId,
      tableId: tableId,
      comment: "Very good",
      guestCount: guestCount,
      foods: items,
      status: OrderStatus.open,
      tableStatus: tableStatus,
      orderType: "dine_in",
    );
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.createOrder,
      payload: jsonEncode(request.request()),
      tableId: tableId,
      createdAt: DateTime.now(),
    ));
    await _recordItemTimestamps(clientOrderId, items);
    // Optimistic: mark the table busy for every terminal on the LAN — the
    // same side effect the old online/offline-forked code performed on
    // either path, now unconditional (§4: the local commit above already
    // succeeded regardless of connectivity).
    _lanHub.tableStatusChanged(tableId, TableStatus.busy.name);
  }

  @override
  Future<void> createTakeawayOrder({
    required String clientOrderId,
    required int guestCount,
    required List<OrderItem> items,
  }) async {
    final request = CreateOrderRequestModel(
      id: clientOrderId,
      orderType: "takeaway",
      foods: items,
    );
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.createOrder,
      payload: jsonEncode(request.createOrder()),
      tableId: '',
      createdAt: DateTime.now(),
    ));
    await _recordItemTimestamps(clientOrderId, items);
  }

  @override
  Future<void> addItems({
    required String tableId,
    required String orderId,
    required List<OrderItem> items,
    List<String>? itemClientIds,
  }) async {
    final ids = itemClientIds ?? List.generate(items.length, (_) => generateUuidV4());
    final payload = {
      'items': [
        for (var i = 0; i < items.length; i++)
          {
            'comment': items[i].comment,
            'good_id': items[i].goods.id,
            'quantity': items[i].quantity,
            'client_item_id': ids[i],
          },
      ],
    };
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.addItems,
      payload: jsonEncode(payload),
      tableId: tableId,
      createdAt: DateTime.now(),
    ));
    await _recordItemTimestamps(orderId, items);
    _lanHub.tableStatusChanged(tableId, TableStatus.busy.name);
  }

  @override
  Future<void> cancelLineItems({
    required List<String> lineIds,
    String? comment,
  }) async {
    if (lineIds.isEmpty) return;
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.cancelLineItems,
      payload: jsonEncode({
        'line_ids': lineIds,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }),
      // Matches the pre-existing DetailBloc._enqueueCancelLineItems
      // behavior — this op resolves purely by line id
      // (OfflineQueueService._execCancelLineItems never reads op.tableId),
      // so there's no real table id to attach here.
      tableId: '',
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> transferTable({
    required String orderId,
    required String sourceTableId,
    required String targetTableId,
  }) async {
    // Re-key the local bill row so the detail screen (keyed by tableId)
    // keeps showing this order at its new table without any refetch.
    final detail = _localDb.getOrderDetail(sourceTableId);
    if (detail != null) {
      await _localDb.saveOrderDetail(targetTableId, detail);
      await _localDb.evictOrderDetail(sourceTableId);
    }
    await _localDb.updateTableStatus(sourceTableId, TableStatus.free);
    await _localDb.updateTableStatus(targetTableId, TableStatus.busy);
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.transferTable,
      payload: jsonEncode({
        'order_id': orderId,
        'target_table_id': targetTableId,
      }),
      tableId: sourceTableId,
      createdAt: DateTime.now(),
    ));
    _lanHub.tableStatusChanged(sourceTableId, TableStatus.free.name);
    _lanHub.tableStatusChanged(targetTableId, TableStatus.busy.name);
  }
}
