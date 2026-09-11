import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — halls and tables read from the
/// replica.
///
/// The settings screen was already reactive, but over the Hive `LocalDatabase`
/// that SyncEngine hydrates — a second store, refreshed by a full re-fetch, and
/// one of the two databases §2 exists to collapse into one. Its writes still
/// went straight to the network and then asked for a re-hydration to see their
/// own result.
///
/// Reading here instead matters for more than tidiness: once the writes go
/// through the outbox they land in *this* database, so a screen reading the
/// Hive copy would not see the operator's own edit until a sync pass brought it
/// back. Read and write have to move together, which is why they do.
///
/// ## Branch scope
///
/// These reads are branch-filtered, and for a while the comments here and in
/// three other query classes said they did not have to be: "the feed is
/// branch-scoped on the backend (`change_log.branch_id`)". There is no such
/// column. `change_log` carries `brand_id`, and `SyncS.Pull` selects
/// `WHERE id > $1` with no branch predicate at all — tenancy is by schema,
/// which separates *brands*, not branches. So a terminal replicates every
/// branch in its brand, and a two-branch brand put both branches' halls on one
/// floor plan, with the tables to match.
class HallsTablesQuery {
  final LocalDatabase _db;

  /// The branch this terminal belongs to, resolved per read rather than
  /// captured: it is empty until the operator logs in, and this object is
  /// built once, at DI time, well before that.
  final String Function()? _branchId;

  const HallsTablesQuery(this._db, {String Function()? branchId})
    : _branchId = branchId;

  /// The channel a branch change is published on — see
  /// [LocalDatabase.touchChannel]. Not a table; nothing writes to it.
  static const branchScopeChannel = '_branch_scope';

  /// Changes to either table invalidate a rendered floor plan — and so does a
  /// change of branch, which is why the session channel is in here. These
  /// streams are held by a singleton cubit that outlives a login, so without it
  /// a floor plan built before anyone signed in never re-ran its branch filter.
  static const watchedTables = {'halls', 'cafe_tables', branchScopeChannel};

  /// The branch to filter by, or empty for "show everything".
  ///
  /// Empty in two cases, both of which must leave the floor plan working:
  ///
  /// * **Nobody is logged in yet**, so there is no branch to filter by.
  /// * **No hall belongs to this branch.** Filtering then would render an
  ///   empty floor plan on a terminal whose venue plainly has halls — the
  ///   failure mode of a brand whose halls predate its branches, or were
  ///   created against a different branch id. A superset is a far better
  ///   answer for a cashier than nothing at all, so the filter yields rather
  ///   than empties the screen.
  String get _branch {
    final branch = _branchId?.call() ?? '';
    if (branch.isEmpty) return '';
    final matching = _db.select(
      'SELECT 1 FROM halls WHERE branch_id = ? AND deleted_at IS NULL LIMIT 1',
      [branch],
    );
    return matching.isEmpty ? '' : branch;
  }

  /// Every live hall in this terminal's branch, ordered by name so the list
  /// does not reshuffle between emissions. The Hive path returned insertion
  /// order, which moved whenever a hydration pass rewrote the box.
  List<Map<String, dynamic>> halls() {
    final branch = _branch;
    return _db.selectData(
      'SELECT data FROM halls WHERE deleted_at IS NULL '
      '${branch.isEmpty ? '' : 'AND branch_id = ? '}'
      'ORDER BY name COLLATE NOCASE, id',
      [if (branch.isNotEmpty) branch],
    );
  }

  /// Every live table in this terminal's branch, ordered by hall then number —
  /// the order the floor plan and the table list both want.
  List<Map<String, dynamic>> tables() {
    final branch = _branch;
    return _withLiveStatus(
      _db.selectData(
        'SELECT data FROM cafe_tables WHERE deleted_at IS NULL '
        '${branch.isEmpty ? '' : 'AND hall_id IN (SELECT id FROM halls '
                  'WHERE branch_id = ? AND deleted_at IS NULL) '}'
        'ORDER BY hall_id, number',
        [if (branch.isNotEmpty) branch],
      ),
    );
  }

  /// One hall's tables. An indexed lookup rather than the Hive path's
  /// filter-the-whole-list, though at this cardinality that is a tidiness
  /// argument, not a performance one.
  ///
  /// Not branch-filtered: the caller named a hall, which is a narrower question
  /// than "which halls are mine", and answering it with nothing because of a
  /// branch mismatch would break a screen the operator navigated to on purpose.
  List<Map<String, dynamic>> tablesForHall(String hallId) => _withLiveStatus(
    _db.selectData(
      'SELECT data FROM cafe_tables '
      'WHERE hall_id = ? AND deleted_at IS NULL ORDER BY number',
      [hallId],
    ),
  );

  /// Replaces each row's replicated `status` with the venue's live occupancy.
  ///
  /// This is the whole reason occupancy is stored separately. The `status` in a
  /// replicated row is whatever the server last logged, which lags a cashier
  /// opening an order and, with the uplink down, never moves at all. Every
  /// screen that asks "is this table free?" — the floor plan, the waiter view,
  /// the transfer dialog, which will refuse to let you move an order onto an
  /// occupied table — needs the local answer, and gets it here rather than each
  /// remembering to merge it.
  List<Map<String, dynamic>> _withLiveStatus(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return rows;
    final live = _db.tableStatuses();
    if (live.isEmpty) return rows;
    for (final row in rows) {
      final status = live[row['id']];
      if (status != null) row['status'] = status;
    }
    return rows;
  }

  Stream<List<Map<String, dynamic>>> watchHalls() =>
      _db.watch(watchedTables, halls);

  Stream<List<Map<String, dynamic>>> watchTables() =>
      _db.watch(watchedTables, tables);

  Stream<List<Map<String, dynamic>>> watchTablesForHall(String hallId) =>
      _db.watch(watchedTables, () => tablesForHall(hallId));
}
