import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';

class TablesRepositoryImpl implements TablesRepository {
  final LocalDatabase _localDb;

  TablesRepositoryImpl({required LocalDatabase localDb}) : _localDb = localDb;

  @override
  Stream<List<HallModel>> watchHalls() => _localDb.watchHalls();

  @override
  List<HallModel> getHalls() => _localDb.getHalls();

  @override
  Stream<List<CafeTableModel>> watchAllTables() => _localDb.watchTables();

  @override
  List<CafeTableModel> getAllTables() => _localDb.getTables();

  @override
  Stream<List<CafeTableModel>> watchTablesForHall(String hallId) =>
      _localDb.watchTablesForHall(hallId);

  @override
  Future<void> updateTableStatus(String tableId, TableStatus status) =>
      _localDb.updateTableStatus(tableId, status);
}
