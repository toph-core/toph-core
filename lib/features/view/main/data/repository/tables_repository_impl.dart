import 'package:mary_ai_pos/core/db/halls_tables_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/halls_tables_local_repository_impl.dart'
    show decodeRows;
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — halls and tables now come from
/// the replica, not the Hive store.
///
/// Same rows, one database. What changes is where occupancy lives: it is no
/// longer a field this repository rewrites inside a cached table row, but a
/// local-authority record beside the replicated one, overlaid on every read
/// (see [LocalTables.tableStatus]). A replication pass can now refresh a table's
/// geometry without stepping on whether it is busy.
class TablesRepositoryImpl implements TablesRepository {
  final LocalDatabase _db;
  final HallsTablesQuery _query;

  /// [branchId] resolves this terminal's branch on every read — see
  /// [HallsTablesQuery]'s branch-scope note. Optional so a test (or any caller
  /// with no session) gets the unfiltered floor plan rather than an empty one.
  TablesRepositoryImpl({
    required LocalDatabase localDb,
    String Function()? branchId,
  }) : _db = localDb,
       _query = HallsTablesQuery(localDb, branchId: branchId);

  @override
  Stream<List<HallModel>> watchHalls() =>
      _query.watchHalls().map((rows) => decodeRows(rows, HallModel.fromJson));

  @override
  List<HallModel> getHalls() => decodeRows(_query.halls(), HallModel.fromJson);

  @override
  Stream<List<CafeTableModel>> watchAllTables() => _query.watchTables().map(
    (rows) => decodeRows(rows, CafeTableModel.fromJson),
  );

  @override
  List<CafeTableModel> getAllTables() =>
      decodeRows(_query.tables(), CafeTableModel.fromJson);

  @override
  Stream<List<CafeTableModel>> watchTablesForHall(String hallId) => _query
      .watchTablesForHall(hallId)
      .map((rows) => decodeRows(rows, CafeTableModel.fromJson));

  @override
  Future<void> updateTableStatus(String tableId, TableStatus status) async {
    // Synchronous underneath; the Future stays for the callers that await it.
    _db.setTableStatus(tableId, status.name);
  }
}
