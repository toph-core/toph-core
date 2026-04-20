import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';

class CacheService {
  static const _categories = 'cache_categories';
  static const _goods = 'cache_goods';
  static const _halls = 'cache_halls';
  static const _tables = 'cache_tables';
  static const _orderDetailPrefix = 'cache_order_detail:';

  late final Box _box;

  CacheService(this._box);

  static Future<CacheService> init() async {
    final box = await Hive.openBox('pos_cache');
    return CacheService(box);
  }

  // ─── Categories ───────────────────────────────────────────────
  Future<void> saveCategories(List<Map<String, dynamic>> items) async =>
      _box.put(_categories, jsonEncode(items));

  List<Map<String, dynamic>> getCategories() => _decode(_box.get(_categories));

  // ─── Goods ────────────────────────────────────────────────────
  Future<void> saveGoods(List<Map<String, dynamic>> items) async =>
      _box.put(_goods, jsonEncode(items));

  List<Map<String, dynamic>> getGoods() => _decode(_box.get(_goods));

  // ─── Halls ────────────────────────────────────────────────────
  Future<void> saveHalls(List<Map<String, dynamic>> items) async =>
      _box.put(_halls, jsonEncode(items));

  List<Map<String, dynamic>> getHalls() => _decode(_box.get(_halls));

  // ─── Tables ───────────────────────────────────────────────────
  Future<void> saveTables(List<Map<String, dynamic>> items) async =>
      _box.put(_tables, jsonEncode(items));

  List<Map<String, dynamic>> getTables() => _decode(_box.get(_tables));

  // ─── Order Detail ─────────────────────────────────────────────
  Future<void> saveOrderDetail(String tableId, Map<String, dynamic> json) async =>
      _box.put('$_orderDetailPrefix$tableId', jsonEncode(json));

  Map<String, dynamic>? getOrderDetail(String tableId) {
    final raw = _box.get('$_orderDetailPrefix$tableId');
    if (raw == null) return null;
    try {
      return jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Barcha goodslarni pagination bilan orqa fonda yuklab saqlab qo'yadi.
  /// Har bir batch 100 ta; bo'sh javob kelsa to'xtaydi.
  Future<void> prefetchAllGoods(DioClient client) async {
    const batchSize = 100;
    int offset = 0;
    final all = <Map<String, dynamic>>[];
    try {
      while (true) {
        final res = await client.get(
          ListAPI.goodsPaginated(limit: batchSize, offset: offset),
        );
        final data = res.data['data'];
        final List<dynamic> items = data is List
            ? data
            : (data is Map ? (data['data'] as List? ?? []) : []);
        if (items.isEmpty) break;
        all.addAll(items.cast<Map<String, dynamic>>());
        if (items.length < batchSize) break;
        offset += batchSize;
      }
      if (all.isNotEmpty) await saveGoods(all);
    } catch (e) {
      if (kDebugMode) debugPrint('[CacheService] prefetchAllGoods: $e');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _decode(dynamic raw) {
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw as String) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
