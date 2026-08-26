import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/failure_outcome.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — how a queued cash-ledger write
/// reaches the server.
///
/// Six handlers over two entities: `transactions` (the ledger itself) and
/// `group_transactions` (its category list). Not built from the shared CRUD
/// table `halls_tables_outbox.dart` uses, because the ledger's create is not
/// one endpoint — an income/expense movement and a register-to-register
/// transfer are separate POSTs with separate request models on the server
/// (`service/transaction.go`), and the group writes take a bare name rather
/// than a body.
///
/// These handlers are the only place a cash movement touches HTTP. The screen
/// calls a repository, the repository writes the local row and queues, and this
/// runs later — possibly much later, possibly after a restart. Nothing above
/// this line knows a request exists.
///
/// ## What "idempotent replay" does and does not mean here
///
/// The queue itself is exactly-once in the ways it can be: an operation is
/// keyed by a client-generated id, so re-issuing the same write cannot enqueue
/// it twice; a succeeded operation is marked and never resent; and a failed one
/// is resent with the byte-identical body it was captured with, never a body
/// re-derived from a row that may have changed since.
///
/// What it cannot do is survive a lost *response*. `POST /transactions/…`
/// assigns its own id and takes no client id or idempotency key, so a create
/// whose reply is dropped after the server committed will be retried and will
/// post a second movement. Nothing on this side can close that window — it
/// needs the endpoint to accept a client-supplied id, the way `CreateOrder`
/// already does (§5 item 4 asks for exactly this). Stated here rather than
/// implied, because a cash ledger is the worst place for a silent assumption.
void registerTransactionsOutboxHandlers(
  OutboxExecutors executors,
  MainRepository remote,
) {
  executors.register(
    'transactions',
    'create',
    OutboxHandler(
      // One action, two endpoints. The payload is the request the screen
      // composed, and the server's own two request models are what tell them
      // apart: an income/expense body names its `type` and one
      // `cash_register_id`; a transfer body names a `from_` and a `to_`
      // register and no type at all. Dispatching on that is reading the body
      // for what it is, rather than inventing a marker key beside it.
      send: (op) async {
        final payload = op.payload;
        if (_isTransfer(payload)) {
          return _created(await remote.createTransferTransaction(payload));
        }
        final type = payload['type'];
        if (type is! String || type.isEmpty) {
          // Neither shape. No retry can turn this into a valid request.
          return const OutboxExecutionResult.permanent(
            'transaction create is neither an income/expense (no type) nor a '
            'transfer (no from/to cash register)',
          );
        }
        return _created(await remote.createIncomeExpenseTransaction(payload));
      },
    ),
  );

  executors.register(
    'transactions',
    'update',
    OutboxHandler(
      send: (op) => _withId(
        op,
        (id) async => _resultOf(await remote.updateTransaction(id, op.payload)),
      ),
    ),
  );

  executors.register(
    'transactions',
    'delete',
    OutboxHandler(
      send: (op) => _withId(op, (id) async {
        final result = await remote.deleteTransaction(id);
        return _deleted(result);
      }),
    ),
  );

  executors.register(
    'group_transactions',
    'create',
    OutboxHandler(
      send: (op) => _withName(
        op,
        (name) async => _created(await remote.createTransactionGroup(name)),
      ),
    ),
  );

  executors.register(
    'group_transactions',
    'update',
    OutboxHandler(
      send: (op) => _withId(
        op,
        (id) => _withName(
          op,
          (name) async =>
              _resultOf(await remote.updateTransactionGroup(id, name)),
        ),
      ),
    ),
  );

  executors.register(
    'group_transactions',
    'delete',
    OutboxHandler(
      send: (op) => _withId(op, (id) async {
        final result = await remote.deleteTransactionGroup(id);
        return _deleted(result);
      }),
    ),
  );
}

/// Whether this create is a register-to-register transfer.
///
/// Both endpoints require their registers, so presence is a complete test —
/// `CreateCashTransferRequest` validates `from_cash_register_id` and
/// `to_cash_register_id` as required, and `CreateIncomeExpenseRequest` has
/// neither field.
bool _isTransfer(Map<String, dynamic> payload) =>
    _nonEmpty(payload['from_cash_register_id']) &&
    _nonEmpty(payload['to_cash_register_id']);

bool _nonEmpty(Object? value) => value is String && value.isNotEmpty;

Future<OutboxExecutionResult> _withId(
  OutboxOperation op,
  Future<OutboxExecutionResult> Function(String id) send,
) async {
  final id = op.entityId;
  if (id == null || id.isEmpty) {
    // Permanent by construction, not by the server's opinion: no retry can
    // supply an id the operation never carried.
    return OutboxExecutionResult.permanent(
      '${op.action} on ${op.entity} without an id',
    );
  }
  return send(id);
}

/// The group endpoints take a bare name, so an operation without one has
/// nothing to send.
Future<OutboxExecutionResult> _withName(
  OutboxOperation op,
  Future<OutboxExecutionResult> Function(String name) send,
) async {
  final name = op.payload['name'];
  if (name is! String || name.trim().isEmpty) {
    return OutboxExecutionResult.permanent(
      '${op.action} on ${op.entity} without a name',
    );
  }
  return send(name);
}

/// A delete whose target is already gone got what it wanted.
///
/// Scoped to delete rather than folded into the shared mapping: for an update
/// or a create, a 404 means the write was lost, which is the opposite of done.
OutboxExecutionResult _deleted(Either<Failure, bool> result) => result.fold(
      (failure) => failure is NotFoundFailure
          ? const OutboxExecutionResult.succeeded()
          : _outcome(failure),
      (_) => const OutboxExecutionResult.succeeded(),
    );

/// A create that came back with the row the server wrote.
///
/// The three create endpoints assign their own ids, so the local row is sitting
/// under a provisional one. Handing the response to the drainer is what lets it
/// swap that row for the server's in place — and, just as importantly, repoint
/// anything still queued that referenced the provisional id: a movement filed
/// under a transaction group that was itself created offline carries that
/// group's provisional id in `group_transaction_id`.
///
/// Until these methods returned a row, the drainer took its documented no-id
/// branch and simply deleted the local row on success, so a movement the
/// operator had just entered disappeared from the ledger until the next pull
/// delivered the server's copy.
///
/// What this still does not fix is a lost *response*: `POST /transactions/…`
/// takes no client-supplied id or idempotency key, so a create whose reply is
/// dropped after the server committed is retried and posts a second movement.
/// That needs the endpoint to accept a client id, the way `CreateOrder` does.
OutboxExecutionResult _created(Either<Failure, Map<String, dynamic>> result) =>
    result.fold(
      _outcome,
      (row) => OutboxExecutionResult.succeeded(serverRow: row),
    );

OutboxExecutionResult _resultOf(Either<Failure, bool> result) =>
    result.fold(_outcome, (_) => const OutboxExecutionResult.succeeded());

OutboxExecutionResult _outcome(Failure failure) {
  final message = failure.toString();
  return switch (outcomeForFailure(failure)) {
    OutboxOutcome.retry => OutboxExecutionResult.retry(message),
    OutboxOutcome.permanent => OutboxExecutionResult.permanent(message),
    OutboxOutcome.succeeded => const OutboxExecutionResult.succeeded(),
  };
}
