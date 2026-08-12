import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/failure_outcome.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — how a queued `users` write
/// reaches the server.
///
/// The first handlers registered on the outbox. Phase 2 shipped the executor
/// registry empty on purpose, so this is also the moment the drainer stops
/// being dormant: from here on it has something it knows how to send.
///
/// The handlers are the *only* place a staff mutation touches HTTP. The screen
/// calls a repository, the repository writes locally and queues, and this runs
/// later — possibly much later, possibly on a different network, possibly after
/// a restart. Nothing above this line knows a request exists.
void registerUsersOutboxHandlers(
  OutboxExecutors executors,
  MainRepository remote,
) {
  executors.register(
    'users',
    'create',
    OutboxHandler(send: (op) async {
      final result = await remote.createUser(op.payload);
      return _resultOf(result);
    }),
  );

  executors.register(
    'users',
    'update',
    OutboxHandler(send: (op) async {
      final id = op.entityId;
      if (id == null || id.isEmpty) {
        // Nothing to address. Retrying cannot supply the id, so this is
        // permanent by construction rather than by the server's opinion.
        return const OutboxExecutionResult.permanent('update without a user id');
      }
      final result = await remote.updateUser(id, op.payload);
      return _resultOf(result);
    }),
  );

  executors.register(
    'users',
    'delete',
    OutboxHandler(send: (op) async {
      final id = op.entityId;
      if (id == null || id.isEmpty) {
        return const OutboxExecutionResult.permanent('delete without a user id');
      }
      final result = await remote.deleteUser(id);
      return result.fold(
        (failure) {
          // A delete whose target is already gone got what it wanted. Treating
          // 404 as success here — rather than in the shared mapping — is safe
          // precisely because it is scoped to delete: for an update, a 404 means
          // the write was lost, which is the opposite of done.
          if (failure is NotFoundFailure) {
            return const OutboxExecutionResult.succeeded();
          }
          return _outcome(failure);
        },
        (_) => const OutboxExecutionResult.succeeded(),
      );
    }),
  );
}

/// The endpoints behind these three return no body worth applying — the server
/// row arrives through replication like every other change. So a success is
/// just a success, with no `serverRow` to converge on.
OutboxExecutionResult _resultOf(Either<Failure, bool> result) => result.fold(
      _outcome,
      (_) => const OutboxExecutionResult.succeeded(),
    );

OutboxExecutionResult _outcome(Failure failure) {
  final message = failure.toString();
  return switch (outcomeForFailure(failure)) {
    OutboxOutcome.retry => OutboxExecutionResult.retry(message),
    OutboxOutcome.permanent => OutboxExecutionResult.permanent(message),
    OutboxOutcome.succeeded => const OutboxExecutionResult.succeeded(),
  };
}
