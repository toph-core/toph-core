import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the menu-admin screens' reads.
///
/// `goods` promotes `name`, `category_id` and `branch_id`, all indexed, which is
/// exactly the shape `/goods/search`'s admin listing needed. Filtering and
/// paging locally is not a workaround for the endpoint being gone; it is the
/// same query against a closer copy.
class MenuAdminQuery {
  final LocalDatabase _db;

  const MenuAdminQuery(this._db);

  /// The manage screen's picker lists live here too, so an ingredient added on
  /// another terminal appears without a reload.
  static const watchedTables = {
    'goods',
    'categories',
    'ingredients',
    'ingredient_visibility',
    'compounds',
  };

  /// One page of the admin goods list.
  ///
  /// [search] matches on name, case-insensitively, which is what the endpoint
  /// did. Ordering is by name so paging is stable — the server's order was
  /// whatever the query planner gave back, so a row could appear on two pages
  /// or none as other terminals edited the menu underneath.
  List<Map<String, dynamic>> goods({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  }) {
    final (where, params) = _goodsFilter(categoryId, search);
    return _db.selectData(
      'SELECT data FROM goods $where ORDER BY name COLLATE NOCASE, id '
      'LIMIT ? OFFSET ?',
      [...params, limit, offset],
    );
  }

  /// Total matching [categoryId]/[search], for the paginator.
  ///
  /// The old screen had no reliable source for this: the endpoint's envelope
  /// sometimes carried `count`, sometimes `total`, sometimes `meta.total`, and
  /// sometimes nothing — so the screen guessed across four shapes and hid the
  /// paginator whenever all four missed. Here it is a `COUNT(*)`.
  int goodsCount({String? categoryId, String? search}) {
    final (where, params) = _goodsFilter(categoryId, search);
    final rows = _db.select('SELECT COUNT(*) AS n FROM goods $where', params);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  (String, List<Object?>) _goodsFilter(String? categoryId, String? search) {
    final clauses = <String>['deleted_at IS NULL'];
    final params = <Object?>[];
    if (categoryId != null && categoryId.isNotEmpty) {
      clauses.add('category_id = ?');
      params.add(categoryId);
    }
    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      // `ESCAPE` is not optional here: without it SQLite has no escape
      // character, so the backslashes below would be matched literally rather
      // than neutralising the wildcard they precede.
      clauses.add(r"name LIKE ? ESCAPE '\'");
      params.add('%${_escapeLike(term)}%');
    }
    return ('WHERE ${clauses.join(' AND ')}', params);
  }

  /// A menu item legitimately named "100% Cacao" must not search as a wildcard.
  ///
  /// Case-insensitivity is SQLite's built-in `LIKE`, which folds ASCII only —
  /// the same limit the rest of this database has, and enough for Uzbek Latin.
  static String _escapeLike(String term) =>
      term.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  Map<String, dynamic>? goodById(String id) => _db.byId('goods', id);

  List<Map<String, dynamic>> categories() => _db.selectData(
        'SELECT data FROM categories WHERE deleted_at IS NULL '
        'ORDER BY name COLLATE NOCASE, id',
      );

  /// Only the ingredients this branch may see.
  ///
  /// Mirrors the backend exactly, which joins `ingredient_visibility` on
  /// `is_visible = true` as an INNER join in all six of its ingredient reads —
  /// so an ingredient with no visibility row is hidden here too. Absence is not
  /// permission, and getting that backwards would show a branch the whole
  /// brand's catalogue, which is the bug this replaced.
  ///
  /// The branch is not filtered here. That used to be justified by "the feed
  /// is branch-scoped upstream (`change_log.branch_id`)", which is not true and
  /// never was: `change_log` carries `brand_id`, and `SyncS.Pull` has no branch
  /// predicate — tenancy is by schema, which separates brands, not branches. So
  /// a terminal does receive every branch's visibility rows, and this read
  /// shows them. `HallsTablesQuery` now filters its own reads for exactly this
  /// reason; doing the same here is unfinished work, kept visible rather than
  /// papered over with a comment that reads as an assurance.
  ///
  /// EXISTS rather than the backend's INNER JOIN. The backend can join safely
  /// because its session pins one branch, so at most one visibility row can
  /// match an ingredient. A local database holds whatever the feed delivered,
  /// and a token that is not branch-scoped delivers a row per branch — a join
  /// would then list the same ingredient several times. EXISTS gives the same
  /// answer for a terminal and cannot duplicate for anyone else.
  List<Map<String, dynamic>> ingredients() => _db.selectData(
        'SELECT i.data FROM ingredients i '
        'WHERE i.deleted_at IS NULL '
        '  AND EXISTS ('
        '    SELECT 1 FROM ingredient_visibility v '
        '    WHERE v.ingredient_id = i.id AND v.is_visible = 1'
        '  ) '
        'ORDER BY i.name COLLATE NOCASE, i.id',
      );

  List<Map<String, dynamic>> compounds() => _db.selectData(
        'SELECT data FROM compounds WHERE deleted_at IS NULL '
        'ORDER BY name COLLATE NOCASE, id',
      );

  Stream<T> watch<T>(T Function() read) => _db.watch(watchedTables, read);
}
