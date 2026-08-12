import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/failure_outcome.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — how queued `halls` and
/// `cafe_tables` writes reach the server.
///
/// Six handlers over one shape, so they are built from a table rather than
/// written out six times: every one of them takes an id and a body, or just a
/// body, and maps the resulting [Failure] through the shared retry/quarantine
/// rule. Spelling them out individually would be six chances to get that
/// mapping subtly different.
void registerHallsTablesOutboxHandlers(
  OutboxExecutors executors,
  MainRepository remote,
) {
  _registerCrud(
    executors,
    entity: 'halls',
    create: remote.createHall,
    update: remote.updateHall,
    remove: remote.deleteHall,
  );
  _registerCrud(
    executors,
    entity: 'cafe_tables',
    create: remote.createTable,
    update: remote.updateTable,
    remove: remote.deleteTable,
  );
}

typedef _Create = Future<Either<Failure, bool>> Function(
    Map<String, dynamic> body);
typedef _Update = Future<Either<Failure, bool>> Function(
    String id, Map<String, dynamic> body);
typedef _Remove = Future<Either<Failure, bool>> Function(String id);

void _registerCrud(
  OutboxExecutors executors, {
  required String entity,
  required _Create create,
  required _Update update,
  required _Remove remove,
}) {
  executors.register(
    entity,
    'create',
    OutboxHandler(send: (op) async => _resultOf(await create(op.payload))),
  );

  executors.register(
    entity,
    'update',
    OutboxHandler(
      send: (op) => _withId(
        op,
        (id) async => _resultOf(await update(id, op.payload)),
      ),
      // A table belongs to its hall's chain. If the hall's own create is still
      // failing, its tables wait rather than racing ahead to a server that has
      // never heard of the hall — the same reason order items chain to their
      // order.
      chainKey: entity == 'cafe_tables' ? _hallChain : null,
    ),
  );

  executors.register(
    entity,
    'delete',
    OutboxHandler(
      send: (op) => _withId(op, (id) async {
        final result = await remove(id);
        return result.fold(
          // Already gone is what the delete wanted. Scoped to delete: for an
          // update a 404 means the write was lost, which is the opposite.
          (failure) => failure is NotFoundFailure
              ? const OutboxExecutionResult.succeeded()
              : _outcome(failure),
          (_) => const OutboxExecutionResult.succeeded(),
        );
      }),
      chainKey: entity == 'cafe_tables' ? _hallChain : null,
    ),
  );
}

/// A `cafe_tables` operation's chain is its hall, falling back to the table
/// itself when the payload does not name one.
String _hallChain(OutboxOperation op) {
  final hallId = op.payload['hall_id'];
  if (hallId is String && hallId.isNotEmpty) return hallId;
  return op.entityId ?? op.id;
}

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
