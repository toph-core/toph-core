import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';

/// offline-first-target-architecture.md §9 (V4). Pure read-only reactive
/// view over `LocalDatabase` — every list here is kept current by
/// `SyncEngine`'s hydration pass (§8 Phase 1) and by [updateTableStatus]'s
/// own local write, never by a Bloc-triggered fetch. No throttle state
/// lives here or in any consumer: "how fresh" is entirely `SyncEngine`'s
/// concern now (§5).
abstract class TablesRepository {
  Stream<List<HallModel>> watchHalls();
  List<HallModel> getHalls();

  Stream<List<CafeTableModel>> watchAllTables();
  List<CafeTableModel> getAllTables();

  Stream<List<CafeTableModel>> watchTablesForHall(String hallId);

  /// Local, immediate, durable table-status patch — the read side of §6's
  /// Lease Manager durable check, and what keeps a LAN-broadcast table
  /// status update (or this terminal's own optimistic open/close) visible
  /// to every `watchAllTables`/`watchTablesForHall` subscriber without a
  /// round trip through the cloud.
  Future<void> updateTableStatus(String tableId, TableStatus status);
}
