import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the halls & tables settings
/// screen's whole data surface, with no network call on either side.
///
/// Mutations are synchronous for the same reason they are on the staff screen:
/// the local row and the queued send commit together and the call returns, so
/// there is no future for the UI to await and no window in which a floor-plan
/// drag is waiting on a socket.
abstract class HallsTablesLocalRepository {
  Stream<List<HallModel>> watchHalls();
  List<HallModel> getHalls();

  Stream<List<CafeTableModel>> watchTablesForHall(String hallId);
  List<CafeTableModel> getTablesForHall(String hallId);

  /// Queues a new hall. No local row: the endpoint assigns the id, and
  /// inventing one locally would leave a ghost beside the server's row when
  /// replication delivered it. Same trade, and same follow-up, as
  /// `UsersLocalRepository.createUser`.
  Either<Failure, Unit> createHall(Map<String, dynamic> body);

  Either<Failure, Unit> updateHall(
    String id,
    Map<String, dynamic> changes,
  );

  Either<Failure, Unit> deleteHall(String id);

  /// Queues a new table. Same server-assigned-id caveat as [createHall].
  ///
  /// Returns the provisional local id the row was written under, so a caller
  /// can address the new table before the server's id arrives — [setTableStatus]
  /// is the one that needs it.
  Either<Failure, String> createTable(Map<String, dynamic> body);

  /// Applies [changes] to the table locally and queues the `PUT`.
  ///
  /// This is the hot path on this screen — every drag, every auto-layout pass,
  /// every resize is one of these. Each becomes an immediate local write and a
  /// durable queued send, which is the whole point: a moved table stays moved
  /// across a restart, and a floor plan rearranged with the venue's uplink down
  /// is not lost work.
  Either<Failure, Unit> updateTable(
    String id,
    Map<String, dynamic> changes,
  );

  Either<Failure, Unit> deleteTable(String id);

  /// Sets a table's occupancy, locally and only locally.
  ///
  /// Occupancy is local authority — it lives in `_table_status` and is overlaid
  /// on every table read (`HallsTablesQuery._withLiveStatus`), precisely so a
  /// replication pass cannot overwrite the venue's live answer with whatever
  /// the server last logged. So it does not travel in a table `PUT`, and this
  /// queues nothing.
  ///
  /// It also cannot: `away` ("Closed") is a status this app has and the API
  /// does not — `table_status` is a two-value Postgres enum. Sending it made
  /// the update endpoint 400, and the outbox quarantines a 4xx permanently, so
  /// the whole edit was lost with nothing said.
  Either<Failure, Unit> setTableStatus(String id, TableStatus status);
}
