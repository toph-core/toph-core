import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';

class TableBillDetails {
  /// `null` when the response had no parseable `pause_periods` — caller
  /// should keep whatever pauses it already had, not clear them.
  final List<PauseInterval>? pauses;

  /// Empty when the response had no (or empty) `table_sessions` — caller
  /// should keep whatever segments it already had, not clear them.
  final List<TableSegment> segments;

  const TableBillDetails({this.pauses, this.segments = const []});
}

class TimedOrderCreateResult {
  final String orderId;

  /// `true` when this order wasn't newly created — the server returned 409
  /// because the table already had one, and [orderId] was recovered from the
  /// conflict response instead.
  final bool wasExisting;

  const TimedOrderCreateResult(this.orderId, {this.wasExisting = false});
}

/// What `TableTimerCubit` depends on instead of calling `DioClient` directly.
///
/// Unlike `ArchivesLocalRepository`/`MenuLocalRepository`, this is a thin
/// passthrough with **no cache-first fallback and no offline queueing** —
/// deliberate, not an oversight. Per offline-first-architecture-plan.md §5's
/// conflict matrix, table-timer sessions are "shared mutable state" for
/// which "cloud is the metering source of truth": start/pause/resume change
/// what the guest owes based on elapsed *server* time, so replaying a queued
/// action later (once connectivity returns) would bill for the wrong
/// interval. Offline here correctly means "can't control the timer right
/// now," not "queue it and pretend it worked."
abstract class TableTimerLocalRepository {
  /// `Right(null)` covers both "no timer for this order" (400/404) and a
  /// malformed/empty response — both are treated as "nothing to show," not
  /// an error, matching the Cubit's pre-existing behavior.
  Future<Either<Failure, TableTimerResponse?>> getTimer(String orderId);

  /// Never fails loudly by design (mirrors the Cubit's original silent
  /// catch-all) — callers should only act on the `Right` case.
  Future<Either<Failure, TableBillDetails>> getBillDetails(String orderId);

  Future<Either<Failure, TimedOrderCreateResult>> createTimedOrder({
    required String tableId,
    required int guestCount,
  });

  /// `Right(null)` means the mutation succeeded server-side but the response
  /// carried no inline timer snapshot — caller should re-fetch via
  /// [getTimer] instead, matching the Cubit's original fallback.
  Future<Either<Failure, TableTimerResponse?>> startTimer(String orderId);

  Future<Either<Failure, TableTimerResponse?>> pauseTimer(String orderId);

  Future<Either<Failure, TableTimerResponse?>> resumeTimer(String orderId);
}
