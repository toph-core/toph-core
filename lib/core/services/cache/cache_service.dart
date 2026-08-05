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

  // ─── Departments ──────────────────────────────────────────────
  static const _departments = 'cache_departments';

  Future<void> saveDepartments(List<Map<String, dynamic>> items) async =>
      _box.put(_departments, jsonEncode(items));

  List<Map<String, dynamic>> getDepartments() => _decode(_box.get(_departments));

  // ─── USB printer names (per-device, never synced to backend) ──
  // A `connection_type: usb` printer-settings entry is shared/synced across
  // the team, but the actual Windows-installed printer name it should target
  // only makes sense on the one PC its USB cable is plugged into — so the
  // entry.id -> Windows printer name mapping lives only in this local box.
  static const _usbPrinterNames = 'cache_usb_printer_names';

  Future<void> saveUsbPrinterName(String entryId, String printerName) async {
    final map = _decodeMap(_box.get(_usbPrinterNames));
    map[entryId] = printerName;
    await _box.put(_usbPrinterNames, jsonEncode(map));
  }

  String? getUsbPrinterName(String entryId) =>
      _decodeMap(_box.get(_usbPrinterNames))[entryId];

  Future<void> removeUsbPrinterName(String entryId) async {
    final map = _decodeMap(_box.get(_usbPrinterNames));
    if (map.remove(entryId) != null) {
      await _box.put(_usbPrinterNames, jsonEncode(map));
    }
  }

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

  // ─── Archives (history) ─────────────────────────────────────────
  // Only the most recent unfiltered/first-page list is cached — archive
  // history can be large and query-shaped (date range, status, search), so
  // this isn't meant to mirror every filter combination, just what's on
  // screen the moment connectivity drops.
  static const _archivesList = 'cache_archives_list';
  static const _archiveDetailPrefix = 'cache_archive_detail:';

  Future<void> saveArchivesList(Map<String, dynamic> json) async =>
      _box.put(_archivesList, jsonEncode(json));

  Map<String, dynamic>? getArchivesList() {
    final raw = _box.get(_archivesList);
    if (raw == null) return null;
    try {
      return jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveArchiveDetail(String id, Map<String, dynamic> json) async =>
      _box.put('$_archiveDetailPrefix$id', jsonEncode(json));

  Map<String, dynamic>? getArchiveDetail(String id) {
    final raw = _box.get('$_archiveDetailPrefix$id');
    if (raw == null) return null;
    try {
      return jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Waiter open orders ───────────────────────────────────────
  // Keyed by list mode ("myOrders" / "branchOrders") — only the default
  // first-page view is cached, same "what's on screen when connectivity
  // drops" scope as the archives list above.
  static const _waiterOpenOrdersPrefix = 'cache_waiter_open_orders:';

  Future<void> saveWaiterOpenOrders(
    String mode,
    List<Map<String, dynamic>> items,
  ) async => _box.put('$_waiterOpenOrdersPrefix$mode', jsonEncode(items));

  List<Map<String, dynamic>> getWaiterOpenOrders(String mode) =>
      _decode(_box.get('$_waiterOpenOrdersPrefix$mode'));

  /// Transfer yoki checkout keyin stol cache-ni o'chiradi.
  /// Keyingi `fetchBillOrders` chaqiruvi throttle'ni chetlab o'tib
  /// serverdan yangi ma'lumot oladi.
  Future<void> evictOrderDetail(String tableId) async {
    await _box.delete('$_orderDetailPrefix$tableId');
  }

  // ─── Order Item Timestamps ────────────────────────────────────
  // `name -> earliestCreatedAt` map'i orderId bo'yicha cache'lanadi.
  // Offline'da bill ekrani ochilganda ham vaqtlar ko'rinishi uchun.
  static const _itemTsPrefix = 'cache_order_item_ts:';

  Future<void> saveItemTimestamps(
    String orderId,
    Map<String, DateTime> ts,
  ) async {
    if (ts.isEmpty) return;
    final encoded = ts.map((k, v) => MapEntry(k, v.toIso8601String()));
    await _box.put('$_itemTsPrefix$orderId', jsonEncode(encoded));
  }

  Map<String, DateTime> getItemTimestamps(String orderId) {
    final raw = _box.get('$_itemTsPrefix$orderId');
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final out = <String, DateTime>{};
      map.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          final dt = DateTime.tryParse(v);
          if (dt != null) out[k] = dt.toLocal();
        }
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static const _goodsFetchedAt = 'cache_goods_fetched_at';
  static const _goodsStale = Duration(minutes: 30);

  // In-memory flag: prevents concurrent fetches within a single app session
  static bool _isFetchingGoods = false;

  bool isGoodsFresh() {
    final raw = _box.get(_goodsFetchedAt) as String?;
    if (raw == null) return false;
    final ts = DateTime.tryParse(raw);
    if (ts == null) return false;
    return DateTime.now().difference(ts) < _goodsStale;
  }

  /// Barcha goodslarni pagination bilan orqa fonda yuklab saqlab qo'yadi.
  /// Har bir batch 500 ta; bo'sh javob kelsa yoki batchdan kam javob kelsa to'xtaydi.
  /// [force] = true bo'lsa throttle tekshirilmaydi.
  Future<void> prefetchAllGoods(DioClient client, {bool force = false}) async {
    if (!force && isGoodsFresh()) return;
    if (_isFetchingGoods) return;
    _isFetchingGoods = true;
    const batchSize = 500;
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
      if (all.isNotEmpty) {
        await saveGoods(all);
        await _box.put(_goodsFetchedAt, DateTime.now().toIso8601String());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CacheService] prefetchAllGoods: $e');
    } finally {
      _isFetchingGoods = false;
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

  Map<String, String> _decodeMap(dynamic raw) {
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw as String) as Map;
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }
}
