import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/failure_outcome.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — how queued menu-admin writes
/// reach the server.
///
/// Not built from the shared CRUD table the halls/tables handlers use: every
/// one of these has its own endpoint shape. `saveGoodWithCalculations` takes
/// the whole nested body for both create and update, categories create from a
/// bare name, and translations split create/update across two verbs. Forcing
/// them into one shape would cost more than it saves.
void registerMenuAdminOutboxHandlers(
  OutboxExecutors executors,
  MainRepository remote,
) {
  executors.register(
    'goods',
    'create',
    OutboxHandler(
      send: (op) async => _resultOf(
        await remote.saveGoodWithCalculations(body: op.payload),
      ),
    ),
  );

  executors.register(
    'goods',
    'update',
    OutboxHandler(
      send: (op) => _withId(
        op,
        (id) async => _resultOf(
          await remote.saveGoodWithCalculations(mealId: id, body: op.payload),
        ),
      ),
    ),
  );

  executors.register(
    'goods',
    'delete',
    OutboxHandler(
      send: (op) => _withId(op, (id) async {
        final result = await remote.deleteGood(id);
        return result.fold(
          (failure) => failure is NotFoundFailure
              ? const OutboxExecutionResult.succeeded()
              : _outcome(failure),
          (_) => const OutboxExecutionResult.succeeded(),
        );
      }),
    ),
  );

  executors.register(
    'categories',
    'create',
    OutboxHandler(
      send: (op) async {
        final name = op.payload['name'];
        if (name is! String || name.isEmpty) {
          return const OutboxExecutionResult.permanent(
            'category create without a name',
          );
        }
        return _resultOf(await remote.createCategory(name));
      },
    ),
  );

  executors.register(
    'translations',
    'create',
    OutboxHandler(
      send: (op) async {
        final result = await remote.createTranslation(op.payload);
        return result.fold(_outcome, (_) => const OutboxExecutionResult.succeeded());
      },
    ),
  );

  executors.register(
    'translations',
    'update',
    OutboxHandler(
      send: (op) => _withId(
        op,
        (id) async => _resultOf(await remote.updateTranslation(id, op.payload)),
      ),
    ),
  );
}

Future<OutboxExecutionResult> _withId(
  OutboxOperation op,
  Future<OutboxExecutionResult> Function(String id) send,
) async {
  final id = op.entityId;
  if (id == null || id.isEmpty) {
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
