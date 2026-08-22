import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the admin staff list as a local
/// query.
///
/// The screen used to call `GET /users` (or `GET /users/search`) on every
/// filter change, page turn and keystroke-after-debounce. `users` replicates,
/// so all three are answerable from the replica, and the answer is the same
/// projection the list endpoint returned — key-for-key, so `_AdminUser.fromJson`
/// parses it unchanged.
///
/// Migrating this list also closes a filter bug the split endpoints made
/// unavoidable. The search endpoint does not accept `role`, so the old screen
/// fetched one page and filtered it client-side: a role filter combined with a
/// search silently dropped every match that happened to fall outside the
/// fetched page, and pagination was hidden entirely while searching because the
/// search response carried no total. Locally there is one query, so search,
/// role and paging compose — and the count is the real one.
class UsersQuery {
  final LocalDatabase _db;

  const UsersQuery(this._db);

  /// Changes to these tables invalidate a rendered page — the watch set.
  static const watchedTables = {'users'};

  /// One page of staff, in the shape `getAdminUsers` returned.
  ///
  /// [search] matches `full_name` or `username` as a case-insensitive
  /// substring, the same fields the server's search endpoint covered.
  ({List<Map<String, dynamic>> items, int total}) page({
    required int limit,
    required int offset,
    String? search,
    String? role,
  }) {
    final where = <String>['deleted_at IS NULL'];
    final params = <Object?>[];

    if (role != null && role.isNotEmpty) {
      where.add('role = ?');
      params.add(role);
    }

    // Role and soft-delete filter in SQL — both are indexed columns. Search
    // deliberately does not: SQLite's `LIKE` and `lower()` fold ASCII only, so
    // a Cyrillic or accented name would match case-sensitively and a cashier
    // searching "шерзод" would not find "Шерзод". Dart's `toLowerCase()` is
    // Unicode-aware, and the staff table is tens of rows, so filtering it here
    // is both correct and instant. If this table ever grows enough to matter,
    // the fix is a normalized `search_key` column, not an ASCII `LIKE`.
    final rows = _db.selectData(
      'SELECT data FROM users WHERE ${where.join(' AND ')}',
      params,
    );

    final term = search?.trim().toLowerCase() ?? '';
    final matched = term.isEmpty
        ? rows
        : rows.where((r) {
            final name = (r['full_name'] ?? '').toString().toLowerCase();
            final username = (r['username'] ?? '').toString().toLowerCase();
            return name.contains(term) || username.contains(term);
          }).toList();

    // Stable order, so page 2 cannot repeat a row from page 1. `full_name` is
    // nullable on the server, hence the fallback to username and then id —
    // every row sorts by something, and ties break deterministically.
    matched.sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));

    final start = offset < 0 ? 0 : offset;
    final page = start >= matched.length
        ? const <Map<String, dynamic>>[]
        : matched.sublist(start, (start + limit).clamp(0, matched.length));

    return (items: page, total: matched.length);
  }

  /// Every non-deleted staff row, sorted the way [page] sorts but unpaginated —
  /// for callers that need the whole list at once. The waiter picker asks "who
  /// are the waiters?", not "page 1 of waiters", so it reads this and filters in
  /// Dart; [page] is this same list, searched and windowed for a screen.
  List<Map<String, dynamic>> all() {
    final rows =
        _db.selectData('SELECT data FROM users WHERE deleted_at IS NULL');
    rows.sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    return rows;
  }

  static String _sortKey(Map<String, dynamic> row) {
    final name = (row['full_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name.toLowerCase();
    final username = (row['username'] ?? '').toString().trim();
    if (username.isNotEmpty) return username.toLowerCase();
    return (row['id'] ?? '').toString();
  }

  /// Emits the current page immediately, then again whenever `users` changes —
  /// including when this terminal's own edit lands locally, which is what makes
  /// the write path visible without a refetch.
  Stream<({List<Map<String, dynamic>> items, int total})> watch({
    required int limit,
    required int offset,
    String? search,
    String? role,
  }) =>
      _db.watch(
        watchedTables,
        () => page(limit: limit, offset: offset, search: search, role: role),
      );
}
