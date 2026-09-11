import 'package:mary_ai_pos/core/db/branch_scope.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the customer-facing menu's reads,
/// moved off the Hive `LocalDatabase` onto the SQLite replica.
///
/// categories, departments, goods, ingredients and compounds all replicate, so
/// each read is a live-rows query (soft-deleted excluded) ordered the way the
/// admin menu already orders them — `name COLLATE NOCASE, id` — and decoded
/// through the model the screen consumes. goods-per-category filters on the
/// promoted `category_id` column: on the replica that is exact and flash-free,
/// so the Hive path's separate per-category cache (kept only to avoid a stale
/// flash on category switch) is gone.
///
/// Decoding skips a row it cannot parse rather than throwing, matching
/// MenuAdminQuery: one server row missing a column GoodsModel needs drops that
/// item, never the whole menu.
class MenuQuery {
  final LocalDatabase _db;

  /// Which rows belong to this terminal's branch.
  ///
  /// `goods` and `compounds` carry a `branch_id` and the backend's own list
  /// queries filter on it (`goods.sql.go` GetAllGoods, `compound.sql.go`
  /// GetAllCompounds), so these reads do too — the replica holds every branch
  /// in the brand. `ingredients`, `ingredient_groups` and `translations` are
  /// deliberately NOT filtered: the backend serves those brand-wide, and
  /// ingredients are narrowed by `ingredient_visibility` instead.
  final BranchScope _scope;

  MenuQuery(this._db, {String Function()? branchId})
    : _scope = BranchScope(_db, branchId: branchId);

  List<CategoryModel> categories() =>
      _decode(_live('categories'), CategoryModel.fromJson);

  Stream<List<CategoryModel>> watchCategories() =>
      _db.watch({'categories'}, categories);

  List<DepartmentModel> departments() =>
      _decode(_live('departments'), DepartmentModel.fromJson);

  Stream<List<DepartmentModel>> watchDepartments() =>
      _db.watch({'departments'}, departments);

  List<GoodsModel> goods() => _decode(_scoped('goods'), GoodsModel.fromJson);

  Stream<List<GoodsModel>> watchGoods() =>
      _db.watch({'goods', BranchScope.channel}, goods);

  /// One good by id, or null when the catalog has no such row.
  ///
  /// A primary-key lookup rather than a scan of the whole catalog, which is
  /// what the receipt builders did against the Hive blob. Soft-deleted rows
  /// still resolve: a line item can name a good that has since been removed
  /// from the menu, and a reprint of that bill must still find its name and
  /// category.
  GoodsModel? goodById(String id) {
    if (id.isEmpty) return null;
    final rows = _db.selectData('SELECT data FROM goods WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    try {
      return GoodsModel.fromJson(rows.first);
    } catch (_) {
      return null;
    }
  }

  List<GoodsModel> goodsForCategory(String categoryId) {
    if (categoryId == 'all') return goods();
    final branch = _scope.clause('goods');
    return _decode(
      _db.selectData(
        'SELECT data FROM goods WHERE deleted_at IS NULL '
        'AND category_id = ? ${branch.sql}ORDER BY name COLLATE NOCASE, id',
        [categoryId, ...branch.args],
      ),
      GoodsModel.fromJson,
    );
  }

  Stream<List<GoodsModel>> watchGoodsForCategory(String categoryId) => _db.watch(
    {'goods', BranchScope.channel},
    () => goodsForCategory(categoryId),
  );

  List<Map<String, dynamic>> ingredients() => _live('ingredients');

  Stream<List<Map<String, dynamic>>> watchIngredients() =>
      _db.watch({'ingredients'}, ingredients);

  List<Map<String, dynamic>> compounds() => _scoped('compounds');

  Stream<List<Map<String, dynamic>>> watchCompounds() =>
      _db.watch({'compounds', BranchScope.channel}, compounds);

  List<Map<String, dynamic>> _live(String table) => _db.selectData(
        'SELECT data FROM $table WHERE deleted_at IS NULL '
        'ORDER BY name COLLATE NOCASE, id',
      );

  /// [_live], narrowed to this terminal's branch.
  List<Map<String, dynamic>> _scoped(String table) {
    final branch = _scope.clause(table);
    return _db.selectData(
      'SELECT data FROM $table WHERE deleted_at IS NULL '
      '${branch.sql}ORDER BY name COLLATE NOCASE, id',
      branch.args,
    );
  }

  static List<T> _decode<T>(
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final out = <T>[];
    for (final row in rows) {
      try {
        out.add(fromJson(row));
      } catch (_) {
        // A row the model can't parse (a server column it needs is absent)
        // drops out, exactly as MenuAdminQuery does — one bad item, not a
        // blank menu.
      }
    }
    return out;
  }
}
