import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'pending_operation.dart';

class OfflineQueueService {
  static const _boxName = 'offline_queue';
  late final Box<PendingOperation> _box;

  OfflineQueueService(this._box);

  static Future<OfflineQueueService> init() async {
    final box = await Hive.openBox<PendingOperation>(_boxName);
    return OfflineQueueService(box);
  }

  List<PendingOperation> get pending => _box.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool get hasItems => _box.isNotEmpty;

  Future<void> enqueue(PendingOperation op) => _box.put(op.id, op);

  Future<void> syncAll(DioClient dio) async {
    final ops = pending;
    if (ops.isEmpty) return;

    // 1. create_order ops
    for (final op in ops.where((o) => o.type == PendingOperationType.createOrder)) {
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        // UTC + 'Z' suffix — backend RFC3339 formatini talab qiladi
        payload['client_created_at'] = op.createdAt.toUtc().toIso8601String();
        await dio.post(ListAPI.orders, data: payload);
        await _box.delete(op.id);
      } catch (e) {
        if (kDebugMode) print('[OfflineQueue] createOrder sync error: $e');
        // Terminal xato (server tomonidan rad) → queue dan o'chiriladi
        if (_isTerminalError(e)) await _box.delete(op.id);
      }
    }

    // 2. add_items ops — faqat ochiq (open) orderga qo'shiladi
    for (final op in ops.where((o) => o.type == PendingOperationType.addItems)) {
      try {
        final orderId = await _getOpenOrderIdByTable(dio, op.tableId);
        if (orderId.isEmpty) {
          // Ochiq order yo'q — bu operatsiya eskirgan, queue dan o'chiramiz
          await _box.delete(op.id);
          if (kDebugMode) print('[OfflineQueue] addItems skipped (no open order for table ${op.tableId})');
          continue;
        }
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        await dio.post(
          ListAPI.orderItems(orderId),
          queryParameters: {'lang': 'uz'},
          data: payload,
        );
        await _box.delete(op.id);
      } catch (e) {
        if (kDebugMode) print('[OfflineQueue] addItems sync error: $e');
        if (_isTerminalError(e)) await _box.delete(op.id);
      }
    }

    // 3. pay_order ops — order_id payload da saqlangan
    for (final op in ops.where((o) => o.type == PendingOperationType.payOrder)) {
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        final orderId = payload['order_id'] as String? ?? '';
        if (orderId.isEmpty) {
          await _box.delete(op.id);
          continue;
        }
        await dio.post(ListAPI.payToOrder(orderId), data: payload);
        await _box.delete(op.id);
      } catch (e) {
        if (kDebugMode) print('[OfflineQueue] payOrder sync error: $e');
        if (_isTerminalError(e)) await _box.delete(op.id);
      }
    }
  }

  /// Faqat ochiq (status: open) orderni qaytaradi.
  /// Agar stol to'langan yoki boshqa statusda bo'lsa — '' qaytaradi.
  Future<String> _getOpenOrderIdByTable(DioClient dio, String tableId) async {
    try {
      final res = await dio.dio.get(ListAPI.orderWithTableId(tableId));
      final data = res.data['data'];
      if (data is! List || data.isEmpty) return '';
      final order = data[0] as Map<String, dynamic>;
      final status = order['status']?.toString() ?? '';
      // Faqat ochiq orderga item qo'shish mumkin
      if (status != 'open') return '';
      return order['id'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Server tomonidan rad etilgan xatolar (qayta urinish kerak emas).
  bool _isTerminalError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      // 4xx — client xato (eskirgan ma'lumot, noto'g'ri so'rov)
      if (code != null && code >= 400 && code < 500) return true;
    }
    return false;
  }

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Object().hashCode.abs()}';
}
