import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/halls_tables_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/halls_tables_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/local_write_result.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — halls & tables settings, off the
/// network on both sides.
class HallsTablesLocalRepositoryImpl implements HallsTablesLocalRepository {
  final LocalDatabase _db;
  final LocalWriter _writer;
  final HallsTablesQuery _query;

  HallsTablesLocalRepositoryImpl(this._db, this._writer)
      : _query = HallsTablesQuery(_db);

  static const _halls = 'halls';
  static const _tables = 'cafe_tables';

  // ── Reads ────────────────────────────────────────────────────────────

  @override
  Stream<List<HallModel>> watchHalls() =>
      _query.watchHalls().map((rows) => _decode(rows, HallModel.fromJson));

  @override
  List<HallModel> getHalls() => _decode(_query.halls(), HallModel.fromJson);

  @override
  Stream<List<CafeTableModel>> watchTablesForHall(String hallId) => _query
      .watchTablesForHall(hallId)
      .map((rows) => _decode(rows, CafeTableModel.fromJson));

  @override
  List<CafeTableModel> getTablesForHall(String hallId) =>
      _decode(_query.tablesForHall(hallId), CafeTableModel.fromJson);

  /// Skips rows the model cannot parse instead of failing the whole list.
  ///
  /// Both models declare geometry (`width`, `pos_x`, …) non-nullable, so one
  /// row missing a field would otherwise throw and blank the entire floor plan.
  /// A replica is fed by whatever the server logged; one malformed row should
  /// cost that row, not the screen.
  static List<T> _decode<T>(
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final out = <T>[];
    for (final row in rows) {
      try {
        out.add(fromJson(row));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // ── Writes ───────────────────────────────────────────────────────────

  @override
  Either<Failure, LocalWriteResult> createHall(Map<String, dynamic> body) =>
      _queueCreate(_halls, body);

  @override
  Either<Failure, LocalWriteResult> updateHall(
    String id,
    Map<String, dynamic> changes,
  ) =>
      _applyUpdate(_halls, id, changes);

  @override
  Either<Failure, LocalWriteResult> deleteHall(String id) =>
      _applyDelete(_halls, id);

  @override
  Either<Failure, LocalWriteResult> createTable(Map<String, dynamic> body) =>
      _queueCreate(_tables, body);

  @override
  Either<Failure, LocalWriteResult> updateTable(
    String id,
    Map<String, dynamic> changes,
  ) =>
      _applyUpdate(_tables, id, changes);

  @override
  Either<Failure, LocalWriteResult> deleteTable(String id) =>
      _applyDelete(_tables, id);

  Either<Failure, LocalWriteResult> _queueCreate(
    String entity,
    Map<String, dynamic> body,
  ) =>
      _guard(() {
        _writer.enqueueOnly(entity: entity, action: 'create', request: body);
        return LocalWriteResult.queued;
      });

  Either<Failure, LocalWriteResult> _applyUpdate(
    String entity,
    String id,
    Map<String, dynamic> changes,
  ) =>
      _guard(() {
        // Merged over the stored row so the replica keeps a whole entity — the
        // table PUT body is nearly complete already, but a hall rename sends
        // three fields and must not erase the rest.
        final existing = _db.byId(entity, id) ?? const <String, dynamic>{};
        _writer.write(
          entity: entity,
          id: id,
          row: {...existing, ...changes, 'id': id},
          request: changes,
        );
        return LocalWriteResult.applied;
      });

  Either<Failure, LocalWriteResult> _applyDelete(String entity, String id) =>
      _guard(() {
        _writer.delete(entity: entity, id: id);
        return LocalWriteResult.applied;
      });

  Either<Failure, LocalWriteResult> _guard(LocalWriteResult Function() body) {
    try {
      return Right(body());
    } catch (e) {
      return Left(MessageFailure('$e'));
    }
  }
}
