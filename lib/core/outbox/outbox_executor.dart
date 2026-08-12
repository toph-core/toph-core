/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — how a queued write reaches the server.
///
/// The drainer knows about ordering, retries and quarantine. It knows nothing
/// about HTTP. Each entity registers a handler here saying how *its* write is
/// sent, which keeps every endpoint detail out of the queue machinery and lets
/// the whole drain path be tested without a socket.
library;

import 'outbox_operation.dart';

enum OutboxOutcome {
  /// The server has the write. Applies equally to a fresh success and to a
  /// replay the server recognised as already-applied — `CreateOrder` returns
  /// the existing order for a known client id, and `PayOrder` returns the
  /// order unchanged when it is already paid. Both are successes: the desired
  /// state holds.
  succeeded,

  /// Transient — no connectivity, a timeout, a 5xx. Try again later.
  retry,

  /// The server refused on the merits — a validation error, a 4xx that will
  /// recur identically. Retrying wastes the attempt budget and delays every
  /// write queued behind it.
  permanent,
}

class OutboxExecutionResult {
  final OutboxOutcome outcome;
  final String? error;

  /// The server's version of the row, when the response carries it. Applied to
  /// the replica so the local copy converges immediately rather than waiting
  /// for the next replication pass to correct server-assigned fields — a bill
  /// number, a computed total, a `paid_at`.
  final Map<String, dynamic>? serverRow;

  const OutboxExecutionResult._(this.outcome, {this.error, this.serverRow});

  const OutboxExecutionResult.succeeded({Map<String, dynamic>? serverRow})
      : this._(OutboxOutcome.succeeded, serverRow: serverRow);

  const OutboxExecutionResult.retry(String error)
      : this._(OutboxOutcome.retry, error: error);

  const OutboxExecutionResult.permanent(String error)
      : this._(OutboxOutcome.permanent, error: error);
}

/// Sends one operation. Implementations must be safe to call more than once
/// with the same operation: a drain interrupted after the request left but
/// before the result was recorded will replay it.
typedef OutboxSend = Future<OutboxExecutionResult> Function(OutboxOperation op);

class OutboxHandler {
  final OutboxSend send;

  /// Groups operations that must not overtake one another.
  ///
  /// Defaults to the operation's own entity id, which is right for
  /// independent rows. Operations that belong to a larger aggregate override
  /// it — an `order_items` write returns its `order_id`, so that if the order's
  /// own create is still failing, its items wait rather than racing ahead to a
  /// server that has never heard of the order.
  final String Function(OutboxOperation op)? chainKey;

  const OutboxHandler({required this.send, this.chainKey});
}

class OutboxExecutors {
  final Map<String, OutboxHandler> _handlers = {};

  static String key(String entity, String action) => '$entity/$action';

  void register(String entity, String action, OutboxHandler handler) {
    _handlers[key(entity, action)] = handler;
  }

  OutboxHandler? resolve(OutboxOperation op) => _handlers[key(op.entity, op.action)];

  bool get isEmpty => _handlers.isEmpty;

  /// Which causal chain [op] belongs to. Falls back to the entity id, then to
  /// the operation's own id — an operation with no identity of its own blocks
  /// nothing but itself.
  ///
  /// Deliberately **not** namespaced by entity. A chain spans entities: an
  /// `order_items` write returns its `order_id` here so it lands on the same
  /// chain as the `orders` write that created it. Prefixing with the entity
  /// name would put them in different chains and let the item overtake the
  /// order it depends on — which is the exact failure this mechanism exists to
  /// prevent. Ids are server UUIDs, so a collision between two entities is not
  /// a practical concern, and would only make ordering more conservative
  /// rather than incorrect.
  String chainKeyOf(OutboxOperation op) {
    final custom = resolve(op)?.chainKey?.call(op);
    if (custom != null && custom.isNotEmpty) return custom;
    final entityId = op.entityId;
    if (entityId != null && entityId.isNotEmpty) return entityId;
    return 'op/${op.id}';
  }
}
