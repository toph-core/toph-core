import 'local_database.dart';

/// Which rows belong to this terminal's branch.
///
/// The replica holds the whole brand. `change_log` carries `brand_id` and no
/// branch column, and `SyncS.Pull` selects `WHERE id > $1` with no branch
/// predicate — tenancy is by schema, which separates brands, not branches. So
/// every terminal replicates every branch its brand has, and the only place the
/// branch filter can happen is here, on the read.
///
/// The rule is **mirror the backend, table by table**. Where the backend's own
/// list query is branch-scoped the local read must be too, or the terminal
/// shows another venue's data; where the backend deliberately serves the whole
/// brand — `ingredient_groups`, `modifiers`, `translations`, `branches` — the
/// local read must not filter, or it hides rows that are genuinely shared. The
/// per-entity map lives at each call site, next to the query it governs.
///
/// ## The safety valve
///
/// A branch filter that is wrong empties a screen, and an empty menu or an
/// empty floor plan stops a venue trading. So [of] refuses to filter a table
/// that has no rows in this branch at all: that is the signature of a
/// misconfiguration — rows created against a different branch id, or predating
/// branches entirely — and a superset is a far better answer for a cashier than
/// nothing. A branch with genuinely zero rows in that table renders empty
/// either way, so the valve costs nothing where the data is right.
class BranchScope {
  final LocalDatabase _db;

  /// This terminal's branch, resolved per read. Empty before anyone logs in,
  /// which reads as "no filter" rather than "no rows".
  final String Function()? _branchId;

  const BranchScope(this._db, {String Function()? branchId})
    : _branchId = branchId;

  /// The channel a branch change is published on, so reads held by a
  /// long-lived stream re-run when the session's branch changes.
  static const channel = '_branch_scope';

  /// The session's branch, or empty when there is none.
  String get current => _branchId?.call() ?? '';

  /// The branch to filter [table] by on its own `branch_id`, or empty for
  /// "show everything" — see the safety valve above.
  ///
  /// [column] names the branch column when it is promoted; pass [jsonPath] for
  /// a table whose branch lives only inside the `data` blob.
  String of(String table, {String column = 'branch_id', bool json = false}) {
    final branch = current;
    if (branch.isEmpty) return '';
    final predicate = json
        ? "json_extract(data, '\$.$column')"
        : column;
    final matching = _db.select(
      'SELECT 1 FROM $table WHERE $predicate = ? AND deleted_at IS NULL LIMIT 1',
      [branch],
    );
    return matching.isEmpty ? '' : branch;
  }

  /// A `WHERE` fragment and its argument for [table], or empty strings when
  /// this read is not scoped.
  ///
  /// Returned as a pair so a caller can splice it into a larger query without
  /// each one re-deriving the same `AND branch_id = ?`.
  ({String sql, List<Object?> args}) clause(
    String table, {
    String column = 'branch_id',
    bool json = false,
    String prefix = 'AND',
    String? alias,
  }) {
    final branch = of(table, column: column, json: json);
    if (branch.isEmpty) return (sql: '', args: const []);
    final qualified = alias == null ? column : '$alias.$column';
    final target = json
        ? "json_extract(${alias == null ? 'data' : '$alias.data'}, '\$.$column')"
        : qualified;
    return (sql: '$prefix $target = ? ', args: [branch]);
  }
}
