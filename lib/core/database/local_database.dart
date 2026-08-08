import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';

/// offline-first-target-architecture.md §1.2 / §8 Phase 0.
///
/// The evolved `CacheService` — same Hive-backed storage engine (per the
/// design doc's explicit recommendation not to swap to Drift/Isar, since
/// nothing here needs a relational join), but reorganized as **typed,
/// reactive, one-Box-per-entity** storage instead of one flat blob box, with
/// a uniform `watchX()` / `getX()` / `saveX()` surface built on
/// `Box.watch()` — the primitive `OfflineQueueService.listenable` and the
/// print-queue/LAN client-count notifiers already use elsewhere in this
/// codebase, just not yet exposed as a `Stream<List<T>>` a Bloc can
/// subscribe to.
///
/// **Purely additive (Phase 0):** `CacheService`'s existing blob methods
/// keep working unchanged. Nothing reads from `LocalDatabase` yet — that
/// wiring is Phase 2 (per-domain `LocalRepository`s) and Phase 1 (Sync
/// Engine hydration writes into it). No Bloc in this codebase references
/// this class yet.
///
/// The outbox (`PendingOperation`/`QuarantinedOperation`, in
/// `OfflineQueueService`) is conceptually part of the same "one Local
/// Database" per §0/§1.2 of the design doc — it already lives in its own
/// Hive boxes with its own reactive `listenable()` surface, so it isn't
/// duplicated or wrapped here; `LocalDatabase` and `OfflineQueueService`
/// together are what §1.2 means by "one Hive instance, many typed boxes,
/// one facade."
///
/// Each unkeyed list entity (categories, departments, halls, tables, users,
/// goods, ingredients, compounds, transaction groups) is stored as one
/// JSON-encoded value under a fixed key in its own `Box<String>` — a schema
/// change from `CacheService`'s single flat box, not a storage-engine
/// migration. Keyed entities (goods-by-category, service charge, order/bill
/// detail, menu images) use the entity's own id as the Hive key, so
/// `Box.watch(key: id)` gives per-id reactivity without decoding every
/// other entry.
class LocalDatabase {
  static const _listKey = 'all';

  final Box<String> _categories;
  final Box<String> _departments;
  final Box<String> _halls;
  final Box<String> _tables;
  final Box<String> _users;
  final Box<String> _goods;
  final Box<String> _goodsByCategory;
  final Box<String> _ingredients;
  final Box<String> _compounds;
  final Box<String> _transactionGroups;
  final Box<String> _cashRegisters;
  final Box<String> _serviceCharge;
  final Box<String> _printerSettings;
  final Box<String> _orderDetail;
  final Box<String> _menuImages;
  final Box<String> _archives;

  LocalDatabase({
    required Box<String> categories,
    required Box<String> departments,
    required Box<String> halls,
    required Box<String> tables,
    required Box<String> users,
    required Box<String> goods,
    required Box<String> goodsByCategory,
    required Box<String> ingredients,
    required Box<String> compounds,
    required Box<String> transactionGroups,
    required Box<String> cashRegisters,
    required Box<String> serviceCharge,
    required Box<String> printerSettings,
    required Box<String> orderDetail,
    required Box<String> menuImages,
    required Box<String> archives,
  })  : _categories = categories,
        _departments = departments,
        _halls = halls,
        _tables = tables,
        _users = users,
        _goods = goods,
        _goodsByCategory = goodsByCategory,
        _ingredients = ingredients,
        _compounds = compounds,
        _transactionGroups = transactionGroups,
        _cashRegisters = cashRegisters,
        _serviceCharge = serviceCharge,
        _printerSettings = printerSettings,
        _orderDetail = orderDetail,
        _menuImages = menuImages,
        _archives = archives;

  static Future<LocalDatabase> init() async {
    Future<Box<String>> open(String name) => Hive.openBox<String>(name);
    return LocalDatabase(
      categories: await open('local_db_categories'),
      departments: await open('local_db_departments'),
      halls: await open('local_db_halls'),
      tables: await open('local_db_tables'),
      users: await open('local_db_users'),
      goods: await open('local_db_goods'),
      goodsByCategory: await open('local_db_goods_by_category'),
      ingredients: await open('local_db_ingredients'),
      compounds: await open('local_db_compounds'),
      transactionGroups: await open('local_db_transaction_groups'),
      cashRegisters: await open('local_db_cash_registers'),
      serviceCharge: await open('local_db_service_charge'),
      printerSettings: await open('local_db_printer_settings'),
      orderDetail: await open('local_db_order_detail'),
      menuImages: await open('local_db_menu_images'),
      archives: await open('local_db_archives'),
    );
  }

  // ── Generic JSON-list primitives (unkeyed — one entry per box) ─────────
  Stream<List<Map<String, dynamic>>> _watchList(Box<String> box) => Stream
      .multi((controller) {
        controller.add(_decodeList(box.get(_listKey)));
        final sub = box.watch(key: _listKey).listen(
          (_) => controller.add(_decodeList(box.get(_listKey))),
        );
        controller.onCancel = sub.cancel;
      });

  List<Map<String, dynamic>> _getList(Box<String> box) =>
      _decodeList(box.get(_listKey));

  Future<void> _saveList(Box<String> box, List<Map<String, dynamic>> items) =>
      box.put(_listKey, jsonEncode(items));

  // ── Generic JSON-by-key primitives (keyed entities) ─────────────────────
  Stream<Map<String, dynamic>?> _watchByKey(Box<String> box, String key) =>
      Stream.multi((controller) {
        controller.add(_decodeMap(box.get(key)));
        final sub = box
            .watch(key: key)
            .listen((_) => controller.add(_decodeMap(box.get(key))));
        controller.onCancel = sub.cancel;
      });

  Map<String, dynamic>? _getByKey(Box<String> box, String key) =>
      _decodeMap(box.get(key));

  Future<void> _saveByKey(
    Box<String> box,
    String key,
    Map<String, dynamic> value,
  ) =>
      box.put(key, jsonEncode(value));

  // ── Categories ───────────────────────────────────────────────────────
  Stream<List<CategoryModel>> watchCategories() =>
      _watchList(_categories).map(_mapCategories);

  List<CategoryModel> getCategories() => _mapCategories(_getList(_categories));

  Future<void> saveCategories(List<CategoryModel> items) =>
      _saveList(_categories, items.map((e) => e.toJson()).toList());

  List<CategoryModel> _mapCategories(List<Map<String, dynamic>> raw) =>
      raw.map(CategoryModel.fromJson).toList();

  // ── Departments ──────────────────────────────────────────────────────
  Stream<List<DepartmentModel>> watchDepartments() =>
      _watchList(_departments).map((raw) => raw.map(DepartmentModel.fromJson).toList());

  List<DepartmentModel> getDepartments() =>
      _getList(_departments).map(DepartmentModel.fromJson).toList();

  Future<void> saveDepartments(List<DepartmentModel> items) =>
      _saveList(_departments, items.map((e) => e.toJson()).toList());

  // ── Halls ────────────────────────────────────────────────────────────
  Stream<List<HallModel>> watchHalls() =>
      _watchList(_halls).map((raw) => raw.map(HallModel.fromJson).toList());

  List<HallModel> getHalls() => _getList(_halls).map(HallModel.fromJson).toList();

  Future<void> saveHalls(List<HallModel> items) =>
      _saveList(_halls, items.map((e) => e.toJson()).toList());

  // ── Tables ───────────────────────────────────────────────────────────
  Stream<List<CafeTableModel>> watchTables() =>
      _watchList(_tables).map((raw) => raw.map(CafeTableModel.fromJson).toList());

  List<CafeTableModel> getTables() =>
      _getList(_tables).map(CafeTableModel.fromJson).toList();

  Future<void> saveTables(List<CafeTableModel> items) =>
      _saveList(_tables, items.map((e) => e.toJson()).toList());

  /// Derived, not separately stored — same source list as [watchTables],
  /// filtered client-side. A single indexed lookup over an already-small
  /// list, not the kind of join the design doc reserves for a relational
  /// engine.
  Stream<List<CafeTableModel>> watchTablesForHall(String hallId) =>
      watchTables().map((all) => all.where((t) => t.hallId == hallId).toList());

  /// Local, immediate, durable table-status patch (§6/§9's `TablesRepository
  /// .updateTableStatus`) — read-modify-write over the same list
  /// [watchTables] serves, so every subscriber sees it on the next event
  /// loop turn. A no-op if [tableId] isn't in the current list (e.g. a stale
  /// LAN broadcast for a table deleted since).
  Future<void> updateTableStatus(String tableId, TableStatus status) async {
    final all = getTables();
    final index = all.indexWhere((t) => t.id == tableId);
    if (index == -1) return;
    final updated = List<CafeTableModel>.from(all);
    updated[index] = updated[index].copyWith(status: status);
    await saveTables(updated);
  }

  // ── Users / staff ────────────────────────────────────────────────────
  Stream<List<UserModel>> watchUsers() =>
      _watchList(_users).map((raw) => raw.map(UserModel.fromJson).toList());

  List<UserModel> getUsers() => _getList(_users).map(UserModel.fromJson).toList();

  Future<void> saveUsers(List<UserModel> items) =>
      _saveList(_users, items.map((e) => e.toJson()).toList());

  // ── Goods (all) ──────────────────────────────────────────────────────
  Stream<List<GoodsModel>> watchGoods() =>
      _watchList(_goods).map((raw) => raw.map(GoodsModel.fromJson).toList());

  List<GoodsModel> getGoods() => _getList(_goods).map(GoodsModel.fromJson).toList();

  Future<void> saveGoods(List<GoodsModel> items) =>
      _saveList(_goods, items.map((e) => e.toJson()).toList());

  // ── Goods, per category (keyed — real per-category cache, not a
  // client-side filter of the "all" list; see CacheService's own note on
  // why that used to show a flash of stale data on every category switch)
  Stream<List<GoodsModel>> watchGoodsForCategory(String categoryId) {
    if (categoryId == 'all') return watchGoods();
    return _watchByKey(_goodsByCategory, categoryId).map(
      (raw) => (raw?['items'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map(GoodsModel.fromJson)
              .toList() ??
          const [],
    );
  }

  List<GoodsModel> getGoodsForCategory(String categoryId) {
    if (categoryId == 'all') return getGoods();
    final raw = _getByKey(_goodsByCategory, categoryId);
    return (raw?['items'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(GoodsModel.fromJson)
            .toList() ??
        const [];
  }

  Future<void> saveGoodsForCategory(String categoryId, List<GoodsModel> items) {
    if (categoryId == 'all') return saveGoods(items);
    return _saveByKey(_goodsByCategory, categoryId, {
      'items': items.map((e) => e.toJson()).toList(),
    });
  }

  // ── Ingredients / compounds (no dedicated model upstream — raw maps,
  // same as MainRepository.getIngredients()/getCompounds() today) ───────
  Stream<List<Map<String, dynamic>>> watchIngredients() => _watchList(_ingredients);

  List<Map<String, dynamic>> getIngredients() => _getList(_ingredients);

  Future<void> saveIngredients(List<Map<String, dynamic>> items) =>
      _saveList(_ingredients, items);

  Stream<List<Map<String, dynamic>>> watchCompounds() => _watchList(_compounds);

  List<Map<String, dynamic>> getCompounds() => _getList(_compounds);

  Future<void> saveCompounds(List<Map<String, dynamic>> items) =>
      _saveList(_compounds, items);

  // ── Transaction groups (raw maps, same as MainRepository today) ───────
  Stream<List<Map<String, dynamic>>> watchTransactionGroups() =>
      _watchList(_transactionGroups);

  List<Map<String, dynamic>> getTransactionGroups() => _getList(_transactionGroups);

  Future<void> saveTransactionGroups(List<Map<String, dynamic>> items) =>
      _saveList(_transactionGroups, items);

  // ── Cash registers (raw maps, §8 Phase 5 back-office tier) ────────────
  Stream<List<Map<String, dynamic>>> watchCashRegisters() => _watchList(_cashRegisters);

  List<Map<String, dynamic>> getCashRegisters() => _getList(_cashRegisters);

  Future<void> saveCashRegisters(List<Map<String, dynamic>> items) =>
      _saveList(_cashRegisters, items);

  // ── Service charge (per-branch bare percent, keyed by branchId) ───────
  Stream<double?> watchServiceCharge(String branchId) =>
      _watchByKey(_serviceCharge, branchId)
          .map((raw) => (raw?['value'] as num?)?.toDouble());

  double? getServiceCharge(String branchId) =>
      (_getByKey(_serviceCharge, branchId)?['value'] as num?)?.toDouble();

  Future<void> saveServiceCharge(String branchId, double value) =>
      _saveByKey(_serviceCharge, branchId, {'value': value});

  // ── Printer settings (entries list, unkeyed — mirrors
  // MainRepository.getPrinterSettings()) ────────────────────────────────
  Stream<List<PrinterSettingEntry>> watchPrinterSettings() =>
      _watchList(_printerSettings).map(PrinterSettingEntry.listFromJsonList);

  List<PrinterSettingEntry> getPrinterSettings() =>
      PrinterSettingEntry.listFromJsonList(_getList(_printerSettings));

  Future<void> savePrinterSettings(List<PrinterSettingEntry> items) =>
      _saveList(_printerSettings, items.map((e) => e.toJson()).toList());

  // ── Order / bill detail — first-class table, keyed by tableId. §0: today
  // this is CacheService.saveOrderDetail's ad hoc blob plus DetailBloc's own
  // in-memory `existingGoods`, three different sources of truth for the same
  // bill. This is the single durable one Phase 2 rewires everything onto —
  // raw JSON, matching the existing wire shape, since callers already know
  // how to decode a `GET /order-items/order/{id}`-shaped map.
  Stream<Map<String, dynamic>?> watchOrderDetail(String tableId) =>
      _watchByKey(_orderDetail, tableId);

  Map<String, dynamic>? getOrderDetail(String tableId) =>
      _getByKey(_orderDetail, tableId);

  Future<void> saveOrderDetail(String tableId, Map<String, dynamic> json) =>
      _saveByKey(_orderDetail, tableId, json);

  Future<void> evictOrderDetail(String tableId) => _orderDetail.delete(tableId);

  // ── Menu images (keyed by Minio object name, base64-encoded bytes — a
  // Box<String> stays the one storage shape this facade needs, rather than
  // adding a second Hive value type just for this one entity) ───────────
  Stream<List<int>?> watchImage(String objectName) => Stream.multi((controller) {
        controller.add(_decodeImage(_menuImages.get(objectName)));
        final sub = _menuImages
            .watch(key: objectName)
            .listen((_) => controller.add(_decodeImage(_menuImages.get(objectName))));
        controller.onCancel = sub.cancel;
      });

  List<int>? getImage(String objectName) => _decodeImage(_menuImages.get(objectName));

  Future<void> saveImage(String objectName, List<int> bytes) =>
      _menuImages.put(objectName, base64Encode(bytes));

  List<int>? _decodeImage(String? raw) {
    if (raw == null) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Archives (§8 Phase 6 / V8) — mirrors only the default "first page,
  // unfiltered, today" view `ArchivesLocalRepositoryImpl` already blob-caches
  // via `CacheService` for offline reads, as one JSON object under a fixed
  // key (same shape as `ArchivesResponseModel.toJson()`). Filtered/searched/
  // paginated-beyond-page-1 queries still go straight to the network — no
  // bounded local mirror exists for those, same reasoning as the three
  // paginated back-office reads in §9's back-office row. This box exists so
  // the archive screen's default view is `SyncEngine`-hydrated and reactive
  // instead of driven by its own `Timer.periodic` silent refresh.
  Stream<Map<String, dynamic>?> watchArchives() => _watchByKey(_archives, _listKey);

  Map<String, dynamic>? getArchives() => _getByKey(_archives, _listKey);

  Future<void> saveArchives(Map<String, dynamic> json) =>
      _saveByKey(_archives, _listKey, json);

  // ── Helpers ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
