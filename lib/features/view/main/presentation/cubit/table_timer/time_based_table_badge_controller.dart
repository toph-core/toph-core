import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the time-based table badge reads
/// through this instead of resolving the repository itself (§9.2 guard: widgets
/// under presentation/pages must not inject repositories).
///
/// Thin by design: the timer state is still [TableTimerLocalRepository]'s, and
/// moving that store onto the replica is DoD #4 (separate, app-gated). This only
/// takes the repository resolution out of the widget — the live
/// `watchTimerForTable` subscription and the pause/resume writes are delegated
/// unchanged.
class TimeBasedTableBadgeController {
  final TableTimerLocalRepository _timers;

  const TimeBasedTableBadgeController(this._timers);

  /// The live timer for a table — the same stream the badge subscribes to.
  Stream<TableTimerResponse?> watchTimerForTable(String tableId) =>
      _timers.watchTimerForTable(tableId);

  Future<Either<Failure, TableTimerResponse?>> pauseTimer(String orderId) =>
      _timers.pauseTimer(orderId);

  Future<Either<Failure, TableTimerResponse?>> resumeTimer(String orderId) =>
      _timers.resumeTimer(orderId);
}
