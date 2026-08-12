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
class HallsTablesQuery {
  final LocalDatabase _db;

  const HallsTablesQuery(this._db);

  /// Changes to either table invalidate a rendered floor plan.
  static const watchedTables = {'halls', 'cafe_tables'};

  /// Every live hall, ordered by name so the list does not reshuffle between
  /// emissions. The Hive path returned insertion order, which moved whenever a
  /// hydration pass rewrote the box.
  List<Map<String, dynamic>> halls() => _db.selectData(
        'SELECT data FROM halls WHERE deleted_at IS NULL '
        'ORDER BY name COLLATE NOCASE, id',
      );

  /// Every live table, ordered by hall then number — the order the floor plan
  /// and the table list both want.
  List<Map<String, dynamic>> tables() => _withLiveStatus(_db.selectData(
        'SELECT data FROM cafe_tables WHERE deleted_at IS NULL '
        'ORDER BY hall_id, number',
      ));

  /// One hall's tables. An indexed lookup rather than the Hive path's
  /// filter-the-whole-list, though at this cardinality that is a tidiness
  /// argument, not a performance one.
  List<Map<String, dynamic>> tablesForHall(String hallId) =>
      _withLiveStatus(_db.selectData(
        'SELECT data FROM cafe_tables '
        'WHERE hall_id = ? AND deleted_at IS NULL ORDER BY number',
        [hallId],
      ));

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
