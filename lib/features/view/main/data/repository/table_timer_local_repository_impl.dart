import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';

/// CLIENT_FACING_OFFLINE_PLAN.md §2 — the biggest architectural reversal in
/// that plan. The previous implementation here was a deliberate pure network
/// passthrough ("cloud is the metering source of truth"); that guarantee has
/// been consciously traded away with product sign-off. Every method is now a
/// `LocalDatabase` read/write over a normalized per-order timer record plus
/// an outbox `timerAction` enqueue. The record engine below is the sole
/// runtime source of elapsed time / amount due on this terminal; the server
/// snapshot only re-enters through `SyncEngine`'s hydration pass (via
/// [absorbServerSnapshot]-shaped normalization there), and until it does the
/// two can disagree — see EXECUTION_CONCERNS.md.
///
/// Record shape (kept close to the `GET /orders/{id}/table-timer` wire
/// shape so a hydrated server snapshot and a local write decode the same
/// way):
/// ```json
/// {
///   "order_id": "...", "table_id": "...", "table_type": "time_based",
///   "state": "none|running|paused|closed",
///   "started_at": iso, "active_started_at": iso?, "paused_at": iso?,
///   "accumulated_active_sec": n,      // active seconds up to the last write
///   "price_per_hour": "60000",
///   "current_amount": "12500.00",     // amount up to the last write
///   "final_amount": "...",            // only when closed
///   "pauses": [{"started_at": iso, "ended_at": iso?, "duration_sec": n}]
/// }
/// ```
/// Live totals are always recomputed at read time: while `running`, seconds
/// since `active_started_at` are added to `accumulated_active_sec`, and the
/// amount is anchored via the shared `computeAnchoredLiveAmount` — the same
/// "never re-price already-billed time" rule the old poll-based UI tick
/// followed between server syncs.
class TableTimerLocalRepositoryImpl implements TableTimerLocalRepository {
  final LocalDatabase _localDb;
  final OfflineQueueService _queue;
  final OrdersRepository _orders;
  final LeaseManager _lease;

  TableTimerLocalRepositoryImpl(
    this._localDb,
    this._queue,
    this._orders,
    this._lease,
  );

  // ── Record engine ───────────────────────────────────────────────────────

  static DateTime? _dt(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

  static int _elapsedRunningSec(Map<String, dynamic> rec, DateTime now) {
    if ((rec['state'] as String?)?.toLowerCase() != 'running') return 0;
    final anchor = _dt(rec['active_started_at']);
    if (anchor == null) return 0;
    final sec = now.difference(anchor).inSeconds;
    return sec < 0 ? 0 : sec;
  }

  static List<PauseInterval> _pausesOf(Map<String, dynamic> rec) {
    final raw = rec['pauses'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PauseInterval.fromJson)
        .toList();
  }

  /// Computes a full [TableTimerResponse] snapshot from a stored record —
  /// the local equivalent of what a server poll used to return.
  TableTimerResponse? _compute(Map<String, dynamic>? rec) {
    if (rec == null) return null;
    final now = DateTime.now();
    final state = (rec['state'] as String? ?? 'none').toLowerCase();
    final accumulated = (rec['accumulated_active_sec'] as num?)?.toInt() ?? 0;
    final live = _elapsedRunningSec(rec, now);
    final total = accumulated + live;
    final price = double.tryParse(rec['price_per_hour']?.toString() ?? '') ?? 0;
    final baseAmount =
        double.tryParse(rec['current_amount']?.toString() ?? '') ??
            double.tryParse(rec['final_amount']?.toString() ?? '') ??
            0;
    final amount = computeAnchoredLiveAmount(
      baseAmount: baseAmount,
      elapsedSinceSyncSec: live,
      currentPricePerHour: price,
    );
    final pauses = _pausesOf(rec);
    final startedAt = _dt(rec['started_at']);
    final tableId = rec['table_id'] as String? ?? '';
    final priceStr = rec['price_per_hour']?.toString();
    return TableTimerResponse(
      orderId: rec['order_id'] as String? ?? '',
      tableId: tableId,
      currentTableId: rec['current_table_id'] as String? ?? tableId,
      tableType: rec['table_type'] as String? ?? 'time_based',
      state: state,
      startedAt: startedAt,
      activeStartedAt: _dt(rec['active_started_at']),
      pausedAt: _dt(rec['paused_at']),
      pricePerHour: priceStr,
      accumulatedActiveSec: accumulated,
      currentActiveSec: live,
      totalActiveSec: total,
      currentAmount: state == 'closed' ? null : amount.toStringAsFixed(2),
      finalAmount: rec['final_amount']?.toString(),
      isRunning: state == 'running',
      isPaused: state == 'paused',
      isClosed: state == 'closed',
      pauses: pauses,
      tableHistory: [
        TableSegment(
          tableId: tableId,
          enteredAt: startedAt,
          activeSeconds: total,
          pausedSeconds: pauses.fold(0, (s, p) => s + p.durationSec),
          pauses: pauses,
          pricePerHour: priceStr,
          amount: amount.toStringAsFixed(2),
        ),
      ],
    );
  }

  /// Freezes the running interval into `accumulated_active_sec` /
  /// `current_amount` so the record is normalized "as of now" before a state
  /// transition mutates it.
  Map<String, dynamic> _settleToNow(Map<String, dynamic> rec) {
    final now = DateTime.now();
    final live = _elapsedRunningSec(rec, now);
    final accumulated =
        ((rec['accumulated_active_sec'] as num?)?.toInt() ?? 0) + live;
    final price = double.tryParse(rec['price_per_hour']?.toString() ?? '') ?? 0;
    final base = double.tryParse(rec['current_amount']?.toString() ?? '') ?? 0;
    final amount = computeAnchoredLiveAmount(
      baseAmount: base,
      elapsedSinceSyncSec: live,
      currentPricePerHour: price,
    );
    return {
      ...rec,
      'accumulated_active_sec': accumulated,
      'current_amount': amount.toStringAsFixed(2),
    };
  }

  String _tablePriceFor(String tableId) {
    if (tableId.isEmpty) return '';
    for (final t in _localDb.getTables()) {
      if (t.id == tableId) return t.pricePerHour ?? '';
    }
    return '';
  }

  Future<void> _enqueueTimerAction(
    String orderId,
    String action,
    String tableId,
  ) =>
      _queue.enqueue(PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.timerAction,
        payload: jsonEncode({'order_id': orderId, 'action': action}),
        tableId: tableId,
        createdAt: DateTime.now(),
      ));

  // ── Reads ───────────────────────────────────────────────────────────────

  @override
  Stream<TableTimerResponse?> watchTimer(String orderId) =>
      _localDb.watchTableTimer(orderId).map(_compute);

  @override
  Stream<TableTimerResponse?> watchTimerForTable(String tableId) =>
      _localDb.watchTableTimers().map((all) {
        Map<String, dynamic>? match;
        for (final rec in all) {
          final tid =
              (rec['current_table_id'] as String?)?.isNotEmpty ?? false
                  ? rec['current_table_id'] as String
                  : rec['table_id'] as String? ?? '';
          if (tid != tableId) continue;
          // Prefer the newest non-closed record if several ever coexist.
          if (match == null ||
              (match['state'] == 'closed' && rec['state'] != 'closed')) {
            match = rec;
          }
        }
        return _compute(match);
      });

  @override
  Future<Either<Failure, TableTimerResponse?>> getTimer(String orderId) async {
    return Right(_compute(_localDb.getTableTimer(orderId)));
  }

  @override
  Future<Either<Failure, TableBillDetails>> getBillDetails(
    String orderId,
  ) async {
    final t = _compute(_localDb.getTableTimer(orderId));
    if (t == null) return const Right(TableBillDetails());
    return Right(TableBillDetails(pauses: t.pauses, segments: t.tableHistory));
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  @override
  Future<Either<Failure, TimedOrderCreateResult>> createTimedOrder({
    required String tableId,
    required int guestCount,
  }) async {
    // Local double-tap guard, replacing the old server-409 recovery: if a
    // non-closed timer record already exists for this table, reuse its
    // order instead of enqueueing a duplicate empty create. A genuine
    // cross-terminal conflict is merged at replay time by
    // `OfflineQueueService._mergeCreateOrderConflict`.
    for (final rec in _localDb.getTableTimers()) {
      final tid = (rec['current_table_id'] as String?)?.isNotEmpty ?? false
          ? rec['current_table_id'] as String
          : rec['table_id'] as String? ?? '';
      final stateName = (rec['state'] as String? ?? 'none').toLowerCase();
      final existingOrderId = rec['order_id'] as String? ?? '';
      if (tid == tableId && stateName != 'closed' && existingOrderId.isNotEmpty) {
        return Right(TimedOrderCreateResult(existingOrderId, wasExisting: true));
      }
    }

    // LAN_HUB_AND_LEASING_PLAN.md §5/§8: the timed-order create is a
    // table-open too — same lease gate as the other two paths, same §9.3
    // policy (rejection blocks, unreachable allows with a visible flag).
    final lease = await _lease.acquireTableLease(tableId);
    if (!lease.isGranted && !lease.isUnreachable) {
      return const Left(
        MessageFailure("Bu stol allaqachon boshqa terminalda ochilgan."),
      );
    }

    final clientOrderId = generateUuidV4();
    // Same endpoint/payload the old direct call used (`POST /orders`, empty
    // items) — reuses the existing createOrder outbox op and its replay
    // machinery, including the 409 merge. Marks the table busy + LAN
    // broadcast inside the repository.
    await _orders.createOrder(
      tableId: tableId,
      clientOrderId: clientOrderId,
      guestCount: guestCount,
      items: const [],
      tableStatus: TableStatus.busy,
    );
    // Minimal local bill snapshot so DetailBloc/PaymentBloc (keyed by
    // tableId) resolve the active order id immediately, offline or not —
    // same reasoning as CreateOrderBloc's dine-in snapshot.
    await _orders.saveOrderDetailSnapshot(
      tableId,
      ArchiveDetailModel(
        id: clientOrderId,
        status: OrderStatus.open,
        opened: DateTime.now(),
        tableId: tableId,
        guestCount: guestCount.toDouble(),
      ).toJson(),
    );
    final now = DateTime.now().toIso8601String();
    await _localDb.saveTableTimer(clientOrderId, {
      'order_id': clientOrderId,
      'table_id': tableId,
      'table_type': 'time_based',
      'state': 'none',
      'created_at': now,
      'accumulated_active_sec': 0,
      'price_per_hour': _tablePriceFor(tableId),
      'pauses': <Map<String, dynamic>>[],
    });
    // Local commit done — clear the ephemeral claim (only a grant held one).
    if (lease.isGranted) {
      _lease.releaseTableLease(tableId);
    }
    return Right(TimedOrderCreateResult(
      clientOrderId,
      leaseUnverified: lease.isUnreachable,
    ));
  }

  @override
  Future<Either<Failure, TableTimerResponse?>> startTimer(
    String orderId, {
    String? tableId,
  }) async {
    var rec = _localDb.getTableTimer(orderId);
    final now = DateTime.now();
    if (rec == null) {
      final tid = tableId ?? '';
      rec = {
        'order_id': orderId,
        'table_id': tid,
        'table_type': 'time_based',
        'state': 'none',
        'accumulated_active_sec': 0,
        'price_per_hour': _tablePriceFor(tid),
        'pauses': <Map<String, dynamic>>[],
      };
    }
    final state = (rec['state'] as String? ?? 'none').toLowerCase();
    if (state == 'closed') return Right(_compute(rec));
    if (state != 'running') {
      rec = {
        ...rec,
        'state': 'running',
        'started_at': rec['started_at'] ?? now.toIso8601String(),
        'active_started_at': now.toIso8601String(),
        'paused_at': null,
      };
      await _localDb.saveTableTimer(orderId, rec);
      await _enqueueTimerAction(orderId, 'start', rec['table_id'] as String? ?? '');
    }
    return Right(_compute(rec));
  }

  @override
  Future<Either<Failure, TableTimerResponse?>> pauseTimer(String orderId) async {
    final rec = _localDb.getTableTimer(orderId);
    if (rec == null) return const Right(null);
    if ((rec['state'] as String? ?? '').toLowerCase() != 'running') {
      return Right(_compute(rec));
    }
    final now = DateTime.now();
    final settled = _settleToNow(rec);
    final pauses = (settled['pauses'] is List)
        ? List<Map<String, dynamic>>.from(
            (settled['pauses'] as List).whereType<Map<String, dynamic>>())
        : <Map<String, dynamic>>[];
    pauses.add({'started_at': now.toIso8601String(), 'duration_sec': 0});
    final updated = {
      ...settled,
      'state': 'paused',
      'paused_at': now.toIso8601String(),
      'active_started_at': null,
      'pauses': pauses,
    };
    await _localDb.saveTableTimer(orderId, updated);
    await _enqueueTimerAction(orderId, 'pause', updated['table_id'] as String? ?? '');
    return Right(_compute(updated));
  }

  @override
  Future<Either<Failure, TableTimerResponse?>> resumeTimer(String orderId) async {
    final rec = _localDb.getTableTimer(orderId);
    if (rec == null) return const Right(null);
    final state = (rec['state'] as String? ?? '').toLowerCase();
    if (state != 'paused') return Right(_compute(rec));
    final now = DateTime.now();
    final pauses = (rec['pauses'] is List)
        ? List<Map<String, dynamic>>.from(
            (rec['pauses'] as List).whereType<Map<String, dynamic>>())
        : <Map<String, dynamic>>[];
    if (pauses.isNotEmpty && pauses.last['ended_at'] == null) {
      final started = _dt(pauses.last['started_at']) ?? now;
      final dur = now.difference(started).inSeconds;
      pauses[pauses.length - 1] = {
        ...pauses.last,
        'ended_at': now.toIso8601String(),
        'duration_sec': dur < 0 ? 0 : dur,
      };
    }
    final updated = {
      ...rec,
      'state': 'running',
      'active_started_at': now.toIso8601String(),
      'paused_at': null,
      'pauses': pauses,
    };
    await _localDb.saveTableTimer(orderId, updated);
    await _enqueueTimerAction(orderId, 'resume', updated['table_id'] as String? ?? '');
    return Right(_compute(updated));
  }

  @override
  Future<void> evictTimer(String orderId) => _localDb.evictTableTimer(orderId);

  // ── Server-snapshot normalization (used by SyncEngine's hydration) ──────

  /// Normalizes a raw `GET /orders/{id}/table-timer` response into the
  /// record shape above, "as of now": the server's `total_active_sec`
  /// becomes the accumulated base and, when running, the live anchor
  /// restarts at the moment of hydration. Server truth overwrites local
  /// drift by design — the hydration caller must skip orders that still
  /// have queued local `timerAction`s, or it would stomp unsynced local
  /// changes.
  static Map<String, dynamic> normalizeServerSnapshot(Map<String, dynamic> raw) {
    final t = TableTimerResponse.fromJson(raw);
    final now = DateTime.now().toIso8601String();
    return {
      'order_id': t.orderId,
      'table_id': t.tableId,
      'current_table_id': t.currentTableId,
      'table_type': t.tableType.isNotEmpty ? t.tableType : 'time_based',
      'state': t.stateNormalized,
      'started_at': t.startedAt?.toIso8601String(),
      'active_started_at': t.stateNormalized == 'running' ? now : null,
      'paused_at': t.pausedAt?.toIso8601String(),
      'accumulated_active_sec': t.totalActiveSec,
      'price_per_hour': t.pricePerHour ?? '',
      'current_amount': t.currentAmount,
      'final_amount': t.finalAmount,
      'pauses': [
        for (final p in t.pauses)
          {
            'started_at': p.startedAt.toIso8601String(),
            'ended_at': p.endedAt?.toIso8601String(),
            'duration_sec': p.durationSec,
          },
      ],
    };
  }

  /// Whether [orderId] has locally-queued timer/create ops that a server
  /// hydration pass must not overwrite yet.
  static bool hasPendingLocalTimerOps(OfflineQueueService queue, String orderId) {
    for (final op in queue.pending) {
      if (op.type != PendingOperationType.timerAction &&
          op.type != PendingOperationType.createOrder) {
        continue;
      }
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        final id = payload['order_id'] ?? payload['id'];
        if (id == orderId) return true;
      } catch (_) {}
    }
    return false;
  }
}
