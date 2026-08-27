/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §2/§7 — how a queued table-timer action
/// and a queued shift open/close reach the server.
///
/// These are the last two write paths on the retiring Hive
/// `OfflineQueueService` after the order aggregate and payment moved across.
/// Both keep their local half exactly where it was — the timer record engine
/// in `LocalTables.tableTimers`, the active-shift record in
/// `SharedPreferences` — and change only which queue carries the remote half.
///
/// **Two handler shapes in one file, on purpose.**
///
/// *Timers speak Dio*, the way `orders_outbox.dart` does, because they are the
/// order aggregate's transport: the endpoints are `/orders/{id}/table-timer/*`,
/// they chain on the order id like `order_items` do, and `MainRepository`
/// carries only a `pause`/`resume` pair — there is no `start` on it, and the
/// three verbs belong together rather than split across two mechanisms for the
/// sake of an interface the plan is retiring anyway. This is a verbatim port of
/// `OfflineQueueService._execTimerAction`, not a reinvention.
///
/// *Shift open/close delegate to `MainRepository`*, the way `users_outbox.dart`
/// does, because the repository already owns the two things a money-critical
/// replay needs and both are proven code: `openShift` turns the backend's
/// "cash register already has an open shift" into a fetch of the existing
/// shift and a success, and `checkShift` is the active-shift-by-register
/// lookup `_execCloseShift` had to hand-roll. Re-implementing either over Dio
/// would duplicate working logic in the one place where a mistake double-counts
/// a till.
///
/// **Replay safety, verified against the backend** (`mary-ai-backend`,
/// `service/table_timer.go`, `service/cash_register_shift.go`):
///
/// * `StartTableTimerIfNeeded` returns the existing open session instead of
///   creating a second one; `PauseTableTimer` on an already-paused session and
///   `ResumeTableTimer` on an already-running one are documented no-op
///   successes. All three verbs are therefore idempotent on replay.
/// * `CloseShift` returns the existing record unchanged when the shift is
///   already closed — explicitly so an offline replay whose response was lost
///   resolves instead of retrying forever. It cannot double-count.
/// * `OpenShift` is guarded by a unique partial index on the active shift, so a
///   duplicate open is refused rather than duplicated.
///
/// Every timer endpoint answers a service error with **400**, so the shared
/// 4xx-is-a-verdict rule quarantines it rather than burning the attempt budget.
/// The shift endpoints answer with **500** for everything including "already
/// has an open shift", which is why the open handler leans on the repository's
/// message-based recovery rather than on a status code.
library;

import 'package:dio/dio.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/close_shift/close_shift_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_shift/open_shift_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

import 'failure_outcome.dart';
import 'outbox_executor.dart';
import 'outbox_operation.dart';

/// The outbox `entity` a table-timer action is filed under.
///
/// The backend table name, not a registry entry: `table_time_sessions` carries
/// no change-log trigger (plan §5 item 1), so nothing replicates under this
/// name and the local record lives in `LocalTables.tableTimers` instead. It is
/// used here only as the routing key the executor registry resolves on, and as
/// the key `hasPendingLocalTimerOps` scans for.
const String kTimerSessionEntity = 'table_time_sessions';

/// The outbox `entity` a shift open/close is filed under. Also not replicated —
/// the active shift is a `SharedPreferences` record, per the plan's one
/// deliberate non-database exception.
const String kShiftEntity = 'cash_register_shifts';

/// Timer actions, in the vocabulary `TableTimerLocalRepositoryImpl` enqueues.
const String kTimerStart = 'start';
const String kTimerPause = 'pause';
const String kTimerResume = 'resume';

const String kShiftOpen = 'open';
const String kShiftClose = 'close';

void registerTimerShiftOutboxHandlers(
  OutboxExecutors executors,
  DioClient dio,
  MainRepository remote,
) {
  _registerTimerHandlers(executors, dio);
  _registerShiftHandlers(executors, remote);
}

// ── Table timers ────────────────────────────────────────────────────────────

void _registerTimerHandlers(OutboxExecutors executors, DioClient dio) {
  const paths = <String, String Function(String)>{
    kTimerStart: ListAPI.orderTableTimerStart,
    kTimerPause: ListAPI.orderTableTimerPause,
    kTimerResume: ListAPI.orderTableTimerResume,
  };
  for (final entry in paths.entries) {
    executors.register(
      kTimerSessionEntity,
      entry.key,
      // chainKey is the *order* id, exactly as `order_items` returns its
      // `order_id`. Without it a start could reach a server that has never
      // heard of the order — a 400, which this outbox treats as a verdict, so
      // the timer action would be quarantined and the cashier's start lost.
      // With it, a timer op waits behind the order's own create (and behind
      // any earlier timer op on the same order, since a failure blocks the
      // whole chain for the pass).
      OutboxHandler(
        chainKey: timerOrderIdOf,
        send: (op) async {
          final orderId = timerOrderIdOf(op);
          if (orderId.isEmpty) {
            return const OutboxExecutionResult.permanent(
              'timer action without an order id',
            );
          }
          try {
            await dio.post(entry.value(orderId));
            return const OutboxExecutionResult.succeeded();
          } on DioException catch (e) {
            return _mapDioError(e);
          } catch (e) {
            return OutboxExecutionResult.retry(e.toString());
          }
        },
      ),
    );
  }
}

/// The order a timer op addresses — its `entityId` (the timer record's key is
/// the order id, since a terminal never learns the server's session id),
/// falling back to `order_id` in the payload.
String timerOrderIdOf(OutboxOperation op) {
  final id = op.entityId;
  if (id != null && id.isNotEmpty) return id;
  return op.payload['order_id'] as String? ?? '';
}

/// Maps a raw `DioException` to the shared retry/quarantine rule
/// ([outcomeForStatusCode]) — the same decision `outcomeForFailure` makes for
/// `Failure`-typed handlers. A transient 401/408/429 retries; any other 4xx is
/// a verdict and quarantines.
OutboxExecutionResult _mapDioError(DioException e) {
  final code = e.response?.statusCode;
  final message =
      code != null ? 'HTTP $code: ${e.message ?? ''}' : (e.message ?? 'network error');
  return switch (outcomeForStatusCode(code)) {
    OutboxOutcome.retry => OutboxExecutionResult.retry(message),
    OutboxOutcome.permanent => OutboxExecutionResult.permanent(message),
    OutboxOutcome.succeeded => const OutboxExecutionResult.succeeded(),
  };
}

// ── Shift open / close ──────────────────────────────────────────────────────

void _registerShiftHandlers(OutboxExecutors executors, MainRepository remote) {
  // cash_register_shifts/open — POST /cash-register-shifts.
  //
  // `cashier_id` is deliberately not sent: the backend reads it from the JWT
  // (`OpenCashRegisterShift` handler), so a replay attributes the shift to
  // whoever's token drains it. That is the behaviour the legacy queue had and
  // it is unchanged here.
  //
  // Idempotent by way of the repository: a second open for a register that
  // already has one comes back as a 500 whose body says "already", which
  // `MainDataSources.openShift` turns into a fetch of the existing shift and a
  // `Right`. So a replay after an ack that never arrived is a success, not a
  // quarantined operator-facing failure.
  executors.register(
    kShiftEntity,
    kShiftOpen,
    OutboxHandler(send: (op) async {
      final cashRegisterId = _cashRegisterIdOf(op);
      if (cashRegisterId.isEmpty) {
        return const OutboxExecutionResult.permanent(
          'open shift without a cash_register_id',
        );
      }
      final result = await remote.openShift(
        request: OpenShiftModel(
          cashRegisterId: cashRegisterId,
          openCashSum: _amountOf(op.payload['opening_cash']),
          openCardSum: _amountOf(op.payload['opening_card']),
        ),
      );
      // No `serverRow`: `cash_register_shifts` is not a replicated entity, so
      // there is no local row for the drainer to converge.
      return result.fold(_outcome, (_) => const OutboxExecutionResult.succeeded());
    }),
  );

  // cash_register_shifts/close — POST /cash-register-shifts/{id}/close.
  //
  // The shift's own id is not usable here. A shift opened offline carries a
  // `local_...` placeholder, and even a real id may be stale by the time
  // connectivity returns, so the close resolves the register's *currently
  // active* shift first and closes that — the same two-step
  // `OfflineQueueService._execCloseShift` performed, now over the repository.
  //
  // Ordering is what makes the lookup safe: this op shares its chain key (the
  // cash register id, which is both ops' `entityId`) with the open, so a close
  // can never overtake the open it belongs to. Within a pass they drain in
  // enqueue order; across passes a failed open blocks the chain.
  executors.register(
    kShiftEntity,
    kShiftClose,
    OutboxHandler(send: (op) async {
      final cashRegisterId = _cashRegisterIdOf(op);
      if (cashRegisterId.isEmpty) {
        return const OutboxExecutionResult.permanent(
          'close shift without a cash_register_id',
        );
      }
      final active = await remote.checkShift(id: cashRegisterId);
      // A lookup that *failed* is not an answer. `checkShift` returns `Left`
      // for a network error and `Right(null)` only for a genuinely empty
      // answer, so the two are kept apart here rather than collapsed.
      final lookupFailure = active.fold<Failure?>((f) => f, (_) => null);
      if (lookupFailure != null) return _outcome(lookupFailure);

      final shiftId = active.fold<String>((_) => '', (shift) => shift?.id ?? '');
      if (shiftId.isEmpty) {
        // No active shift on this register, and the open that would have
        // created one has already drained (chain key) or been quarantined.
        // So the desired state — this register has no open shift — already
        // holds, which is what `OutboxOutcome.succeeded` means here.
        //
        // The three ways to get here are all resolved by succeeding: the
        // close already landed and its response was lost; another terminal
        // closed the same shift first; or the open never landed, so there is
        // nothing to close. Retrying instead would spend the attempt budget
        // and put a money-critical operation in front of a human for a till
        // that is already reconciled.
        return const OutboxExecutionResult.succeeded();
      }

      final closed = await remote.closeShift(
        request: CloseShiftRequestModel(
          shiftId: shiftId,
          closingCash: _amountOf(op.payload['closing_cash']),
          closingCard: _amountOf(op.payload['closing_card']),
        ),
      );
      // Closing an already-closed shift is idempotent server-side: it returns
      // the existing record without re-running the update, so a replay cannot
      // double-count the till.
      return closed.fold(
        _outcome,
        (_) => const OutboxExecutionResult.succeeded(),
      );
    }),
  );
}

String _cashRegisterIdOf(OutboxOperation op) {
  final id = op.entityId;
  if (id != null && id.isNotEmpty) return id;
  return op.payload['cash_register_id'] as String? ?? '';
}

/// Shift sums cross the queue as strings (that is the wire shape) but the
/// request models take ints. A value that will not parse is zero, which is
/// what the screens already send.
int _amountOf(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

OutboxExecutionResult _outcome(Failure failure) {
  final message = failure.toString();
  return switch (outcomeForFailure(failure)) {
    OutboxOutcome.retry => OutboxExecutionResult.retry(message),
    OutboxOutcome.permanent => OutboxExecutionResult.permanent(message),
    OutboxOutcome.succeeded => const OutboxExecutionResult.succeeded(),
  };
}
