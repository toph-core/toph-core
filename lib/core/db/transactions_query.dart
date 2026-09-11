import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/branch_scope.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the transactions list screen's
/// reads, moved off `MainRepository.getTransactions` onto the local replica.
///
/// Pagination, search and the type/cash-register filters were query parameters
/// on a REST call; here they are SQL over `transactions`. The screen keeps the
/// same `(items, total)` shape, so only its data source changes.
///
/// Search mirrors the server's `GetAllTransactions`, which matches
/// `description ILIKE %q%` OR `amount::text ILIKE %q%`. One deliberate
/// divergence: `amount` is stored canonicalised (`"15000"`, not `"15000.00"`),
/// so a search for the trailing-zero form matches on the server and not here.
/// Amount search is a convenience over a fuzzy field; the exact figure a
/// cashier types matches, and description search is identical.
class TransactionsQuery {
  final LocalDatabase _db;

  /// The ledger is branch-scoped on the backend — `GetAllTransactions` filters
  /// `branch_id`, and with `IS NOT DISTINCT FROM`, so a row whose branch is
  /// NULL is visible only to a session that has no branch. A terminal always
  /// has one, so plain equality here reproduces that exactly: a null-branch row
  /// stays hidden rather than being shown as "unassigned".
  final BranchScope _scope;

  TransactionsQuery(this._db, {String Function()? branchId})
    : _scope = BranchScope(_db, branchId: branchId);

  /// The list rebuilds when any transaction changes, so a sale rung on another
  /// terminal appears without a reload — and when the session's branch changes.
  static const watchedTables = {'transactions', BranchScope.channel};

  static const _table = 'transactions';

  /// True while the ledger cannot receive a row from `/sync/pull`.
  ///
  /// Same question, same shape, same reason as
  /// `TransactionPickersQuery.awaitingBackendReplication`: a screen showing an
  /// empty ledger needs to know whether it is looking at "no cash has moved" or
  /// "the server is not sending the ledger yet", and those deserve different
  /// words. It reads the registry rather than counting rows, so it is honest
  /// even on a venue that genuinely has no transactions, and it flips to
  /// `false` on its own once the entry is marked live —
  /// `test/registry_backend_pin_test.dart` forces that to happen as soon as the
  /// backend trigger exists.
  bool get awaitingBackendReplication => !isFedByChangeLog(_table);

  /// One page of the ledger, newest first — the order the server returned.
  List<Map<String, dynamic>> transactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) {
    final (where, params) = _filter(search, type, cashRegisterId);
    return _db.selectData(
      'SELECT data FROM transactions $where ORDER BY date DESC, id '
      'LIMIT ? OFFSET ?',
      [...params, limit, offset],
    );
  }

  /// Total matching the same filters, for the paginator — a real `COUNT(*)`
  /// rather than the endpoint's several inconsistent envelope shapes.
  int transactionsCount({
    String? search,
    String? type,
    String? cashRegisterId,
  }) {
    final (where, params) = _filter(search, type, cashRegisterId);
    final rows =
        _db.select('SELECT COUNT(*) AS n FROM transactions $where', params);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  (String, List<Object?>) _filter(
    String? search,
    String? type,
    String? cashRegisterId,
  ) {
    // deleted_at IS NULL is live: the tenant schema's deleted_at is BIGINT
    // DEFAULT 0, and the applier maps that 0 to NULL on the way in. A row with
    // a real epoch here is soft-deleted, exactly as the server's deleted_at = 0
    // filter intends.
    final clauses = <String>['deleted_at IS NULL'];
    final params = <Object?>[];

    final branch = _scope.of(_table);
    if (branch.isNotEmpty) {
      clauses.add('branch_id = ?');
      params.add(branch);
    }

    if (type != null && type.isNotEmpty) {
      clauses.add('type = ?');
      params.add(type);
    }
    if (cashRegisterId != null && cashRegisterId.isNotEmpty) {
      clauses.add('cash_register_id = ?');
      params.add(cashRegisterId);
    }

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      // description is not promoted, so it is read out of the JSON. amount is a
      // numericKey, stored as a canonical string, so LIKE over it works without
      // a cast. ESCAPE is required or SQLite treats the backslashes literally.
      clauses.add(
        r"(json_extract(data, '$.description') LIKE ? ESCAPE '\' "
        r"OR json_extract(data, '$.amount') LIKE ? ESCAPE '\')",
      );
      final like = '%${_escapeLike(term)}%';
      params.add(like);
      params.add(like);
    }

    return ('WHERE ${clauses.join(' AND ')}', params);
  }

  /// A description containing `%` or `_` must search literally, not as a
  /// wildcard. Mirrors the escaping in `MenuAdminQuery`.
  static String _escapeLike(String term) =>
      term.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  Stream<T> watch<T>(T Function() read) => _db.watch(watchedTables, read);
}
