import 'dart:convert';

enum LanHubMessageType {
  tableStatus,
  ping,
  auth,
  authOk,
  authFail,
  relayOp,
  relayOpResult,
}

class LanHubMessage {
  final LanHubMessageType type;
  final String? tableId;
  final String? status; // 'free' | 'busy' | 'away'

  /// [auth] only: the connecting terminal's current staff session JWT.
  final String? token;

  /// [auth] only: the connecting terminal's current staff branch id — the
  /// leader rejects anything that doesn't match its own branch.
  final String? branchId;

  /// [authFail] only: short machine-readable rejection reason (e.g.
  /// `'unauthorized'`, `'timeout'`) — shown as-is in the settings status
  /// card, not user-facing copy.
  final String? reason;

  /// [relayOp]/[relayOpResult]: the queued operation's own id (mirrors
  /// `PendingOperation.id`) — correlates a follower's request with the
  /// leader's eventual reply.
  final String? opId;

  /// [relayOp] only: `PendingOperationType.name` — which of the outbox's
  /// six op kinds this is.
  final String? opType;

  /// [relayOp] only: the same JSON-encoded payload string
  /// `PendingOperation.payload` already carries.
  final String? opPayload;

  /// [relayOp] only: mirrors `PendingOperation.tableId`.
  final String? opTableId;

  /// [relayOp] only: mirrors `PendingOperation.createdAt`, ISO-8601 UTC.
  final String? opCreatedAt;

  /// [relayOpResult] only: `RelayOpResult.name`.
  final String? result;

  const LanHubMessage({
    required this.type,
    this.tableId,
    this.status,
    this.token,
    this.branchId,
    this.reason,
    this.opId,
    this.opType,
    this.opPayload,
    this.opTableId,
    this.opCreatedAt,
    this.result,
  });

  factory LanHubMessage.tableStatus({
    required String tableId,
    required String status,
  }) => LanHubMessage(
        type: LanHubMessageType.tableStatus,
        tableId: tableId,
        status: status,
      );

  factory LanHubMessage.ping() =>
      const LanHubMessage(type: LanHubMessageType.ping);

  /// Must be the first message sent on every new connection — the server
  /// holds the socket out of broadcast until this is validated.
  factory LanHubMessage.auth({
    required String token,
    required String branchId,
  }) => LanHubMessage(
        type: LanHubMessageType.auth,
        token: token,
        branchId: branchId,
      );

  factory LanHubMessage.authOk() =>
      const LanHubMessage(type: LanHubMessageType.authOk);

  factory LanHubMessage.authFail({required String reason}) =>
      LanHubMessage(type: LanHubMessageType.authFail, reason: reason);

  /// Sent by a follower to ask the leader to execute one queued operation
  /// against the cloud on its behalf (Phase 4 sole-uplink relay).
  factory LanHubMessage.relayOp({
    required String opId,
    required String opType,
    required String opPayload,
    required String opTableId,
    required String opCreatedAt,
  }) => LanHubMessage(
        type: LanHubMessageType.relayOp,
        opId: opId,
        opType: opType,
        opPayload: opPayload,
        opTableId: opTableId,
        opCreatedAt: opCreatedAt,
      );

  factory LanHubMessage.relayOpResult({
    required String opId,
    required String result,
  }) => LanHubMessage(
        type: LanHubMessageType.relayOpResult,
        opId: opId,
        result: result,
      );

  String toJson() => jsonEncode({
        'type': type.name,
        'table_id': tableId,
        'status': status,
        if (token != null) 'token': token,
        if (branchId != null) 'branch_id': branchId,
        if (reason != null) 'reason': reason,
        if (opId != null) 'op_id': opId,
        if (opType != null) 'op_type': opType,
        if (opPayload != null) 'op_payload': opPayload,
        if (opTableId != null) 'op_table_id': opTableId,
        if (opCreatedAt != null) 'op_created_at': opCreatedAt,
        if (result != null) 'result': result,
      });

  static LanHubMessage? tryParse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = LanHubMessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => LanHubMessageType.ping,
      );
      return LanHubMessage(
        type: type,
        tableId: map['table_id'] as String?,
        status: map['status'] as String?,
        token: map['token'] as String?,
        branchId: map['branch_id'] as String?,
        reason: map['reason'] as String?,
        opId: map['op_id'] as String?,
        opType: map['op_type'] as String?,
        opPayload: map['op_payload'] as String?,
        opTableId: map['op_table_id'] as String?,
        opCreatedAt: map['op_created_at'] as String?,
        result: map['result'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
