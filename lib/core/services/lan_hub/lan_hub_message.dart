import 'dart:convert';

enum LanHubMessageType {
  tableStatus,
  ping,
  auth,
  authOk,
  authFail,
  relayOp,
  relayOpResult,
  printJobAnnounce,
  printJobClaim,
  printJobResult,
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

  /// [printJobAnnounce]/[printJobClaim]/[printJobResult]: the print job's own
  /// id (mirrors `PrintJob.id`) — correlates an announce with its eventual
  /// claim and result, the same role `opId` plays for `relayOp`. Kept as a
  /// separate field (not reusing `opId`) since a print-job relay is a
  /// structurally different broadcast-and-claim exchange, not a directed
  /// leader RPC — see offline-first-architecture-plan.md §11 Phase 5 for why
  /// `relayOp`'s leader-only shape doesn't fit peer-to-peer print relay.
  final String? printJobId;

  /// [printJobAnnounce] only: `PrintJob.jobType` ('cashier' so far).
  final String? printJobType;

  /// [printJobAnnounce] only: target `PrinterSettingEntry.id` — a receiving
  /// terminal claims iff it has a locally-saved Windows printer name for
  /// this exact id (`CacheService.getUsbPrinterName`).
  final String? printEntryId;

  /// [printJobAnnounce] only: pre-rendered ESC/POS bytes, base64-encoded —
  /// the claiming terminal only executes the transport step, never rebuilds
  /// the receipt (it has none of the originator's order/cache context to do
  /// so with).
  final String? printPayloadBase64;

  /// [printJobResult] only: `'printed'` or `'failed'`.
  final String? printResult;

  /// [printJobResult] only: human-readable failure detail, when present.
  final String? printError;

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
    this.printJobId,
    this.printJobType,
    this.printEntryId,
    this.printPayloadBase64,
    this.printResult,
    this.printError,
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

  /// Broadcast by a terminal that needs a print job executed but doesn't own
  /// the target USB printer itself (Phase 5 print relay). Every other
  /// terminal receives this (same broadcast-to-all-except-sender path
  /// `tableStatus` already rides on); only the one holding a matching
  /// `CacheService.getUsbPrinterName(printEntryId)` acts on it.
  factory LanHubMessage.printJobAnnounce({
    required String jobId,
    required String jobType,
    required String entryId,
    required String payloadBase64,
  }) => LanHubMessage(
        type: LanHubMessageType.printJobAnnounce,
        printJobId: jobId,
        printJobType: jobType,
        printEntryId: entryId,
        printPayloadBase64: payloadBase64,
      );

  /// Sent by whichever terminal decides it owns the announced printer —
  /// tells the originator to stop its claim-wait timer and start its lease
  /// timer instead.
  factory LanHubMessage.printJobClaim({required String jobId}) =>
      LanHubMessage(type: LanHubMessageType.printJobClaim, printJobId: jobId);

  /// Sent by the claiming terminal once its local print attempt finishes
  /// (either outcome) — the originator finalizes its `PrintJob` row on
  /// receipt of this.
  factory LanHubMessage.printJobResult({
    required String jobId,
    required String result,
    String? error,
  }) => LanHubMessage(
        type: LanHubMessageType.printJobResult,
        printJobId: jobId,
        printResult: result,
        printError: error,
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
        if (printJobId != null) 'print_job_id': printJobId,
        if (printJobType != null) 'print_job_type': printJobType,
        if (printEntryId != null) 'print_entry_id': printEntryId,
        if (printPayloadBase64 != null) 'print_payload_b64': printPayloadBase64,
        if (printResult != null) 'print_result': printResult,
        if (printError != null) 'print_error': printError,
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
        printJobId: map['print_job_id'] as String?,
        printJobType: map['print_job_type'] as String?,
        printEntryId: map['print_entry_id'] as String?,
        printPayloadBase64: map['print_payload_b64'] as String?,
        printResult: map['print_result'] as String?,
        printError: map['print_error'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
