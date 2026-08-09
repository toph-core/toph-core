import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';

class TableBillDetails {
  /// `null` when there were no parseable pauses — caller should keep
  /// whatever pauses it already had, not clear them.
  final List<PauseInterval>? pauses;

  /// Empty when there were no segments — caller should keep whatever
  /// segments it already had, not clear them.
  final List<TableSegment> segments;

  const TableBillDetails({this.pauses, this.segments = const []});
}

class TimedOrderCreateResult {
  final String orderId;

  /// `true` when this order wasn't newly created — a previous local record
  /// for the same table already existed and [orderId] was recovered from it
  /// instead. (The old network path recovered it from a server 409; a
  /// replay-time 409 is now merged by `OfflineQueueService`'s existing
  /// conflict branch.)
  final bool wasExisting;

  /// LAN_HUB_AND_LEASING_PLAN.md §9.3: `true` when the table-open went
  /// ahead without lease arbitration (LAN leader unreachable) — surface a
  /// visible warning, don't treat it as a clean grant.
  final bool leaseUnverified;

  const TimedOrderCreateResult(
    this.orderId, {
    this.wasExisting = false,
    this.leaseUnverified = false,
  });
}

/// What `TableTimerCubit`/`TimeBasedTableBadge` depend on for table-timer
/// state.
///
/// CLIENT_FACING_OFFLINE_PLAN.md §2: this used to be a deliberate pure
/// network passthrough ("cloud is the metering source of truth" — see the
/// impl's previous doc comment). That guarantee has been consciously traded
/// away, with product sign-off: every method is now a local
/// `LocalDatabase` read/write plus an outbox enqueue, and the elapsed
/// time/amount a terminal shows can disagree with the server (and other
/// terminals) until sync catches up. The local elapsed-time math
/// (`computeAnchoredLiveAmount` and the record engine in the impl) is the
/// sole runtime source of truth; `SyncEngine` reconciles server snapshots
/// into the same box in the background.
abstract class TableTimerLocalRepository {
  /// Reactive local timer state for one order — fires on every local write
  /// and on every SyncEngine hydration of this order's record. `null` means
  /// no timer record exists locally.
  Stream<TableTimerResponse?> watchTimer(String orderId);

  /// Same, keyed by the table currently holding the order — for the
  /// table-map badge, which knows its tableId but not its orderId.
  Stream<TableTimerResponse?> watchTimerForTable(String tableId);

  /// `Right(null)` means "no timer for this order" — nothing to show, not
  /// an error, matching the Cubit's pre-existing behavior.
  Future<Either<Failure, TableTimerResponse?>> getTimer(String orderId);

  /// Pause/segment breakdown for the active-periods dialog — synthesized
  /// from the local timer record (a single local segment; the server's
  /// richer multi-session history reappears whenever SyncEngine hydrates a
  /// server snapshot over this record).
  Future<Either<Failure, TableBillDetails>> getBillDetails(String orderId);

  /// Creates an empty timed order locally (outbox `createOrder`, same
  /// endpoint/payload shape as the old direct call) and an initial local
  /// timer record carrying the table's price-per-hour.
  Future<Either<Failure, TimedOrderCreateResult>> createTimedOrder({
    required String tableId,
    required int guestCount,
  });

  /// Local state transition + outbox enqueue. [tableId] is an optional hint
  /// used only when no local record exists yet for [orderId] (e.g. an order
  /// opened before this terminal ever saw its timer).
  Future<Either<Failure, TableTimerResponse?>> startTimer(
    String orderId, {
    String? tableId,
  });

  Future<Either<Failure, TableTimerResponse?>> pauseTimer(String orderId);

  Future<Either<Failure, TableTimerResponse?>> resumeTimer(String orderId);

  /// Drops the local record — called when the order is paid/closed so a
  /// stale timer doesn't linger for the next order on this table.
  Future<void> evictTimer(String orderId);
}
