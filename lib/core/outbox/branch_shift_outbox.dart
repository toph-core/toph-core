/// How a queued branch-shift open or close reaches the server.
///
/// The shift used to be a per-terminal `SharedPreferences` record replayed
/// against `/cash-register-shifts`, which meant every till in a venue opened,
/// counted and closed a shift of its own with nothing reconciling them. The
/// shift is now one replicated row per branch, so these handlers carry an
/// ordinary entity write rather than a bespoke two-step lookup: the row is
/// already in the replica and already on every peer's screen by the time
/// anything here runs.
///
/// **Why this file speaks HTTP directly.** Same reason `orders_outbox.dart`
/// does, and the same allowlist entry covers it: the branch-shift endpoints
/// exist for this queue and nothing else, and there is no CRUD repository whose
/// shape they would fit. The replaced path (`timer_shift_outbox.dart`'s shift
/// handlers) delegated to `MainRepository` only because it needed that
/// repository's message-based "already has an open shift" recovery — a
/// workaround for a backend that answered 500 for a conflict. The branch
/// endpoint answers a conflict by returning the winning shift, so there is
/// nothing left to work around.
///
/// **Replay safety, verified against the backend** (`back`,
/// `service/branch_shift.go`, pinned by `branch_shift_test.go`):
///
/// * `OpenShift` reads the branch's active shift before inserting, so a replay
///   of an open whose response was lost returns the same shift rather than a
///   second one. Where two terminals genuinely raced, it returns the shift that
///   *won*, under the winner's id — see [_openHandler] for what that costs the
///   loser, which is nothing.
/// * `CloseShift` returns an already-closed shift untouched. The counts the
///   cashier made are written once; a replay cannot overwrite them with a later
///   figure. This is the property that matters most here — everything else in
///   this app can be re-derived, a till count cannot.
/// * A close addressed to a shift the server does not have answers **404**, so
///   the shared 4xx-is-a-verdict rule quarantines it in front of an operator
///   instead of retrying it silently forever. That only happens when the open
///   was itself rejected, in which case both halves belong in the same place.
library;

import 'package:dio/dio.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';

import 'failure_outcome.dart';
import 'outbox_executor.dart';
import 'outbox_operation.dart';

/// The outbox `entity` a branch-shift write is filed under.
///
/// A real registry entry this time, unlike [kShiftEntity] in
/// `timer_shift_outbox.dart`: `branch_shifts` is replicated, so the local row
/// the operator sees and the operation that carries it to the server are the
/// same thing, committed together by `LocalWriter`.
const String kBranchShiftEntity = 'branch_shifts';

/// Opening writes a row, so it is a `create` in the outbox's vocabulary — the
/// action `LocalWriter.create` enqueues.
const String kBranchShiftOpen = 'create';

/// Closing is a state change on a row that already exists, and its request body
/// is not the row, so it is enqueued by `LocalWriter.write` with an explicit
/// action rather than the default `update`.
const String kBranchShiftClose = 'close';

void registerBranchShiftOutboxHandlers(OutboxExecutors executors, DioClient dio) {
  _registerOpen(executors, dio);
  _registerClose(executors, dio);
}

// ── Open ────────────────────────────────────────────────────────────────────

void _registerOpen(OutboxExecutors executors, DioClient dio) {
  executors.register(
    kBranchShiftEntity,
    kBranchShiftOpen,
    OutboxHandler(send: (op) async {
      final shiftId = _shiftIdOf(op);
      if (shiftId.isEmpty) {
        return const OutboxExecutionResult.permanent(
          'open branch shift without an id',
        );
      }
      final payload = <String, dynamic>{
        ...op.payload,
        'id': shiftId,
        // The cashier's clock at the moment they opened, not the drainer's at
        // the moment the network came back. A shift opened at 08:00 and
        // replayed at 14:00 has to read 08:00 — the receipts printed under it
        // already say so, and the day's takings are reconciled against it.
        'opened_at': op.createdAt.toUtc().toIso8601String(),
      };
      try {
        final response = await dio.post(ListAPI.branchShifts, data: payload);
        // Handed back as the server row so the drainer converges the local copy
        // onto it. This is the entire conflict-resolution mechanism for two
        // terminals that opened offline at once: the loser's response carries
        // the *winner's* id, `_reconcile` drops the loser's provisional row,
        // repoints anything still queued against it (including this terminal's
        // own close), and writes the winner's row in its place. The cashier
        // sees the venue's shift; nothing tells them a swap happened, because
        // nothing they did was wrong.
        return OutboxExecutionResult.succeeded(serverRow: _bodyOf(response));
      } on DioException catch (e) {
        return _mapDioError(e);
      } catch (e) {
        return OutboxExecutionResult.retry(e.toString());
      }
    }),
  );
}

// ── Close ───────────────────────────────────────────────────────────────────

void _registerClose(OutboxExecutors executors, DioClient dio) {
  executors.register(
    kBranchShiftEntity,
    kBranchShiftClose,
    OutboxHandler(send: (op) async {
      final shiftId = _shiftIdOf(op);
      if (shiftId.isEmpty) {
        return const OutboxExecutionResult.permanent(
          'close branch shift without an id',
        );
      }
      final payload = <String, dynamic>{
        ...op.payload,
        // Same reasoning as `opened_at` above: the moment the cashier counted
        // the drawer, not the moment the queue drained.
        'closed_at': op.createdAt.toUtc().toIso8601String(),
      };
      try {
        final response = await dio.post(
          ListAPI.closeBranchShift(shiftId),
          data: payload,
        );
        return OutboxExecutionResult.succeeded(serverRow: _bodyOf(response));
      } on DioException catch (e) {
        // A 404 here means the server has no such shift *yet*, and in a venue
        // that is usually transient rather than a verdict: the shift can be
        // opened on one till and closed on another, and the chain key only
        // orders operations within a single terminal's outbox. If the till that
        // opened the shift is still draining, this close arrives first and the
        // shared 4xx rule would quarantine it permanently — leaving a shift
        // open on the server that nothing will ever close.
        //
        // Retrying is bounded, so this cannot spin: `OutboxStore.maxAttempts`
        // is 8, after which the operation quarantines anyway and an operator
        // sees it. That is the right outcome for the case where the open
        // genuinely never lands.
        if (e.response?.statusCode == 404) {
          return const OutboxExecutionResult.retry(
            'HTTP 404: shift not on the server yet — the terminal that opened '
            'it may still be draining',
          );
        }
        return _mapDioError(e);
      } catch (e) {
        return OutboxExecutionResult.retry(e.toString());
      }
    }),
    // No `chainKey` override: both handlers file their operation under the
    // shift's own id as `entityId`, which is what `chainKeyOf` falls back to,
    // so the close already shares the open's chain and cannot overtake it. A
    // failed open holds the close back for the whole pass, and within a pass
    // they drain in enqueue order.
  );
}

/// The shift an operation addresses — its `entityId`, falling back to `id` in
/// the payload.
///
/// `entityId` is authoritative because it is the field `rewriteReferences`
/// repoints when a provisional id is reconciled away. A close queued against a
/// shift id that lost the arbitration is rewritten to the winner's id there,
/// before this ever runs.
String _shiftIdOf(OutboxOperation op) {
  final id = op.entityId;
  if (id != null && id.isNotEmpty) return id;
  return op.payload['id'] as String? ?? '';
}

/// The shift row out of a response, unwrapped from the `{status, message, data}`
/// envelope these endpoints answer with.
///
/// Unwrapped **here**, not left to the drainer. `OutboxDrainer._rowOf` does
/// unwrap a `data` key, but only on the provisional path (`_reconcile`); the
/// ordinary success path hands `serverRow` straight to `ChangeApplier.applyOne`.
/// So an envelope returned from the close handler reached `_applyUpsert`, which
/// looked for `id` at the top level, did not find one, and counted the row as
/// `failed` — the server's closed row was silently discarded on every close.
/// Returning the row itself is correct for both paths, since `_rowOf` passes a
/// row that already has an `id` through untouched.
Map<String, dynamic>? _bodyOf(Response<dynamic> response) {
  final raw = response.data;
  if (raw is! Map) return null;
  final body = Map<String, dynamic>.from(raw);
  final data = body['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  // No envelope (or an endpoint that stopped using one) — only usable as a row
  // if it actually is one.
  return body['id'] is String ? body : null;
}

/// Maps a raw `DioException` to the shared retry/quarantine rule
/// ([outcomeForStatusCode]) — identical to `timer_shift_outbox.dart`'s, and
/// meaningful here in a way it was not there: these endpoints answer a genuine
/// rejection with a real 4xx, so the rule actually discriminates.
OutboxExecutionResult _mapDioError(DioException e) {
  final code = e.response?.statusCode;
  final message = code != null
      ? 'HTTP $code: ${e.message ?? ''}'
      : (e.message ?? 'network error');
  return switch (outcomeForStatusCode(code)) {
    OutboxOutcome.retry => OutboxExecutionResult.retry(message),
    OutboxOutcome.permanent => OutboxExecutionResult.permanent(message),
    OutboxOutcome.succeeded => const OutboxExecutionResult.succeeded(),
  };
}
