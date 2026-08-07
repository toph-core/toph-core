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

  // ─── Goods, per category ────────────────────────────────────────
  // `_goods` above only ever holds the "all categories" list
  // (`prefetchAllGoods`/`DetailBloc`'s own "all" fetch). Filtering that list
  // client-side to approximate a single category's contents (what
  // `DetailBloc._onSetSelectedCategoryId` used to do) shows a plausible but
  // wrong slice the moment that list is stale relative to what the
  // per-category endpoint actually returns — visible as a flash of the
  // wrong items on every category switch, even a category visited moments
  // earlier, since there was never a real per-category cache to hit. These
  // methods give each category (including "all", aliased to the existing
  // key above so `prefetchAllGoods` stays the single writer for it) its own
  // genuine last-known-good cache entry.
  static const _goodsByCategoryPrefix = 'cache_goods_cat:';

  Future<void> saveGoodsForCategory(
    String categoryId,
    List<Map<String, dynamic>> items,
  ) async {
    if (categoryId == 'all') return saveGoods(items);
    await _box.put('$_goodsByCategoryPrefix$categoryId', jsonEncode(items));
  }

  List<Map<String, dynamic>> getGoodsForCategory(String categoryId) {
    if (categoryId == 'all') return getGoods();
    return _decode(_box.get('$_goodsByCategoryPrefix$categoryId'));
  }

  // ─── Departments ──────────────────────────────────────────────
  static const _departments = 'cache_departments';

  Future<void> saveDepartments(List<Map<String, dynamic>> items) async =>
      _box.put(_departments, jsonEncode(items));

  List<Map<String, dynamic>> getDepartments() => _decode(_box.get(_departments));

  // ─── Users / staff ────────────────────────────────────────────
  // Populated by `SyncEngine`'s login-time/periodic hydration pass so the
  // waiter-assignment dropdown (and any other staff-list consumer) has
  // something to show offline instead of an empty list.
  static const _users = 'cache_users';

  Future<void> saveUsers(List<Map<String, dynamic>> items) async =>
      _box.put(_users, jsonEncode(items));

  List<Map<String, dynamic>> getUsers() => _decode(_box.get(_users));

  // ─── Transaction groups ("categories" for transactions) ────────
  // Same "what's on screen when connectivity drops" scope as archives/
  // waiter-open-orders above — only the unfiltered default list is cached,
  // not every search-query variant.
  static const _transactionGroups = 'cache_transaction_groups';

  Future<void> saveTransactionGroups(List<Map<String, dynamic>> items) async =>
      _box.put(_transactionGroups, jsonEncode(items));

  List<Map<String, dynamic>> getTransactionGroups() =>
      _decode(_box.get(_transactionGroups));

  // ─── Ingredients / compounds (recipe-editor reference data) ────
  // Only consumed by the menu-management screen's ingredient/semi-finished
  // picker — same "unfiltered default list" scope as transaction groups.
  static const _ingredients = 'cache_ingredients';
  static const _compounds = 'cache_compounds';

  Future<void> saveIngredients(List<Map<String, dynamic>> items) async =>
      _box.put(_ingredients, jsonEncode(items));

  List<Map<String, dynamic>> getIngredients() => _decode(_box.get(_ingredients));

  Future<void> saveCompounds(List<Map<String, dynamic>> items) async =>
      _box.put(_compounds, jsonEncode(items));

  List<Map<String, dynamic>> getCompounds() => _decode(_box.get(_compounds));

  // ─── Service charge (per-branch config) ────────────────────────
  static const _serviceChargePrefix = 'cache_service_charge:';

  Future<void> saveServiceCharge(
    String branchId,
    Map<String, dynamic> json,
  ) async => _box.put('$_serviceChargePrefix$branchId', jsonEncode(json));

  Map<String, dynamic>? getServiceCharge(String branchId) {
    final raw = _box.get('$_serviceChargePrefix$branchId');
    if (raw == null) return null;
    try {
      return jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

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

  // ─── Reference-data hydration staleness (categories/departments/halls/
  // tables/users) ──────────────────────────────────────────────────────
  // One shared timestamp for the whole bundle `SyncEngine` hydrates together
  // — these are all small lists, so there's no value in a per-entity TTL
  // the way goods' pagination-driven fetch needs one.
  static const _referenceDataFetchedAt = 'cache_reference_data_fetched_at';
  static const _referenceDataStale = Duration(minutes: 5);

  bool isReferenceDataFresh() {
    final raw = _box.get(_referenceDataFetchedAt) as String?;
    if (raw == null) return false;
    final ts = DateTime.tryParse(raw);
    if (ts == null) return false;
    return DateTime.now().difference(ts) < _referenceDataStale;
  }

  Future<void> markReferenceDataFetched() =>
      _box.put(_referenceDataFetchedAt, DateTime.now().toIso8601String());

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

  /// Wipes every cached entity — categories, goods, halls, tables, users,
  /// ingredients, compounds, service charge, order details, archives, waiter
  /// open-orders, item timestamps, USB printer names, all of it. Only for a
  /// full app re-provision (logout-from-app,
  /// which also drops brand_id/pos_password — see `AuthRepositoryImpl
  /// .logoutFromApp`): this box has no per-brand/per-branch scoping at all,
  /// so switching this terminal to a different restaurant without wiping it
  /// first would leave the old tenant's halls/tables sitting in cache,
  /// silently mixed into (or blocking) the new tenant's data — e.g. a
  /// stale table whose `hall_id` no longer matches any current hall just
  /// vanishes from every filtered view, and a hall reused across tenants by
  /// coincidence would show the wrong tables under the right name. Regular
  /// staff `logout()` (same brand, same branch) must NOT call this — the
  /// cache is still valid for that tenant and losing it would mean an
  /// unnecessary full re-fetch on the next login.
  Future<void> clearAll() => _box.clear();

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
