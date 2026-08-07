import 'package:hive_flutter/hive_flutter.dart';

import 'pending_operation.dart';

part 'quarantined_operation.g.dart';

/// Where a [PendingOperation] goes instead of vanishing when the backend
/// gives it a definitive 4xx rejection (or, for the LAN-relay path, when the
/// cluster leader reports `terminalFailure`). Before this existed, both
/// `OfflineQueueService.syncAll`/`relayViaLan` just deleted the op on a
/// terminal outcome — silently, with no record of what was dropped or why —
/// see offline-first-architecture-plan.md §11 Phase 6, "quarantine list with
/// manual resolution". Reuses [PendingOperationType] (already `@HiveType`)
/// rather than duplicating it.
@HiveType(typeId: 13)
class QuarantinedOperation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final PendingOperationType type;

  @HiveField(2)
  final String payload;

  @HiveField(3)
  final String tableId;

  /// When the operation was originally enqueued (mirrors `PendingOperation
  /// .createdAt`).
  @HiveField(4)
  final DateTime createdAt;

  /// When it was dropped and moved here.
  @HiveField(5)
  final DateTime quarantinedAt;

  /// Human-readable reason it was dropped — the server's error text for a
  /// direct-to-cloud drop, or a generic message for a LAN-relay
  /// `terminalFailure` (the wire protocol only carries a bare result enum,
  /// not an error string — see `RelayOpResult`/`LanHubMessage.relayOpResult`).
  @HiveField(6)
  final String reason;

  QuarantinedOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.tableId,
    required this.createdAt,
    required this.quarantinedAt,
    required this.reason,
  });

  factory QuarantinedOperation.fromDropped(PendingOperation op, String reason) =>
      QuarantinedOperation(
        id: op.id,
        type: op.type,
        payload: op.payload,
        tableId: op.tableId,
        createdAt: op.createdAt,
        quarantinedAt: DateTime.now(),
        reason: reason,
      );

  /// Rebuilds a fresh, re-enqueueable [PendingOperation] for a manual retry
  /// — same id, so if it fails again it quarantines cleanly in the same slot
  /// rather than accumulating duplicates.
  PendingOperation toRetryable() => PendingOperation(
        id: id,
        type: type,
        payload: payload,
        tableId: tableId,
        createdAt: createdAt,
      );
}
