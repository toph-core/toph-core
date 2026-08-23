import 'package:mary_ai_pos/core/db/branch_query.dart';
import 'package:mary_ai_pos/core/outbox/failure_outcome.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

/// How a queued branch-config write reaches the server.
///
/// One action, `update`, and in practice one field: the service charge. The
/// endpoint behind it is a `PUT /branches/{id}` that takes a partial body, so
/// widening this later is a matter of what the payload carries, not of another
/// handler.
void registerBranchesOutboxHandlers(
  OutboxExecutors executors,
  MainRepository remote,
) {
  executors.register(
    BranchQuery.table,
    'update',
    OutboxHandler(send: (op) async {
      final id = op.entityId;
      if (id == null || id.isEmpty) {
        // Nothing to address, and a retry cannot invent a branch id.
        return const OutboxExecutionResult.permanent(
          'branch update without a branch id',
        );
      }
      final raw = op.payload['default_service_percent'];
      final percent = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (percent == null) {
        // The only field this handler knows how to send, and it is unreadable.
        // Retrying replays the same bad payload, so fail it now rather than
        // letting it occupy the queue until it is quarantined.
        return OutboxExecutionResult.permanent(
          'branch update carried an unparseable service percent: $raw',
        );
      }
      final result = await remote.saveServiceCharge(id, percent);
      return result.fold(
        (failure) {
          final message = failure.toString();
          return switch (outcomeForFailure(failure)) {
            OutboxOutcome.retry => OutboxExecutionResult.retry(message),
            OutboxOutcome.permanent => OutboxExecutionResult.permanent(message),
            OutboxOutcome.succeeded => const OutboxExecutionResult.succeeded(),
          };
        },
        // The server's own row arrives through replication like every other
        // change, so there is nothing here worth applying back.
        (_) => const OutboxExecutionResult.succeeded(),
      );
    }),
  );
}
