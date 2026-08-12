/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — one queued write.
library;

import 'dart:convert';

enum OutboxStatus {
  /// Waiting to be sent, or backing off after a retryable failure.
  pending,

  /// Given up on automatically. Requires a human decision — retry it or
  /// discard it — because replaying it again unattended would either keep
  /// failing forever or risk applying something the server rejected on its
  /// merits rather than by accident.
  quarantined;

  static OutboxStatus parse(String? raw) => switch (raw) {
        'quarantined' => OutboxStatus.quarantined,
        _ => OutboxStatus.pending,
      };
}

/// A write that happened locally and still owes the server a round trip.
///
/// The payload is the request body, captured at write time. It is deliberately
/// **not** re-derived from the local row at replay time: the row may have been
/// changed again since, and this operation describes the change that was made,
/// not the state that resulted from it.
class OutboxOperation {
  /// Client-generated. Also the idempotency handle for replays that carry it.
  final String id;

  /// Replicated entity name, matching the registry — `orders`, `users`, …
  final String entity;

  /// `create` / `update` / `delete`, or a domain verb the executor
  /// understands (`pay`, `cancel`, `transfer`).
  final String action;

  /// The affected row's primary key, where there is one.
  final String? entityId;

  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  /// Earliest time this may be sent again. Zero epoch means "now".
  final DateTime nextAttemptAt;

  final String? lastError;
  final OutboxStatus status;

  const OutboxOperation({
    required this.id,
    required this.entity,
    required this.action,
    required this.payload,
    required this.createdAt,
    this.entityId,
    this.attempts = 0,
    required this.nextAttemptAt,
    this.lastError,
    this.status = OutboxStatus.pending,
  });

  factory OutboxOperation.fromRow(Map<String, Object?> row) {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode((row['payload'] as String?) ?? '{}');
      payload = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      // A payload that will not decode cannot be replayed. It is kept as an
      // empty map so the row still surfaces in the quarantine UI rather than
      // crashing the drain that found it.
      payload = <String, dynamic>{};
    }
    return OutboxOperation(
      id: row['id'] as String,
      entity: row['entity'] as String,
      action: row['action'] as String,
      entityId: row['entity_id'] as String?,
      payload: payload,
      createdAt: _epoch(row['created_at']),
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: _epoch(row['next_attempt_at']),
      lastError: row['last_error'] as String?,
      status: OutboxStatus.parse(row['status'] as String?),
    );
  }

  static DateTime _epoch(Object? raw) => DateTime.fromMillisecondsSinceEpoch(
        (raw as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'OutboxOperation($entity/$action, id: $id, entityId: $entityId, '
      'attempts: $attempts, status: ${status.name})';
}
