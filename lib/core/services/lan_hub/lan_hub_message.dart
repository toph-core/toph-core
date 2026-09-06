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
  printJobGrant,
  printJobResult,
  leaseRequest,
  leaseGranted,
  leaseRejected,
  leaseRelease,
  changeFeed,
  localChange,
  timerAction,
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

  /// [printJobClaim]/[printJobGrant]: which terminal is claiming, and which
  /// one the originator picked.
  ///
  /// A claim used to be advisory — a terminal decided the printer was its own,
  /// said so, and printed straight away. With two terminals answering the same
  /// announcement (an unowned entry that both have a local USB name for) that
  /// meant two receipts: the originator ignored the second claim, but the
  /// second terminal had already put paper through. Naming the claimant lets
  /// the originator grant exactly one of them, and nobody prints unsolicited.
  final String? printTerminalId;

  /// [leaseRequest]/[leaseGranted]/[leaseRejected]/[leaseRelease]: the
  /// requesting terminal's own id — correlates a follower's request with the
  /// leader's eventual reply, same role `opId` plays for `relayOp`. Reuses
  /// [tableId] for the table being leased rather than a new field, since
  /// every lease message concerns exactly one table.
  final String? leaseTerminalId;

  /// [changeFeed] only: the leader's pull-response body verbatim, JSON —
  /// `{changes, next_sync_cursor}`, exactly what the cloud returned and
  /// exactly what `ChangeApplier.applyPullResponse` consumes. Deliberately not
  /// re-shaped into a LAN-specific format: a follower applying the leader's
  /// feed runs the same function on the same bytes as a terminal pulling from
  /// the cloud, so there is no second parser to keep in step.
  final String? feedBody;

  /// [changeFeed] only: the cursor the leader was at *before* applying this
  /// batch. A follower whose own cursor is behind this knows it missed
  /// something — see `ChangeFeedRelay`.
  final int? feedFromCursor;

  /// [localChange] only: which replicated entity the row belongs to
  /// (`orders`, `order_items`, `transactions`, …) — an `EntitySpec.name`.
  final String? changeEntity;

  /// [localChange] only: `'create'`, `'update'` or `'delete'`. Creates and
  /// updates are both applied as upserts on the way in, so the distinction is
  /// carried for readability and logging rather than branching.
  final String? changeAction;

  /// [localChange] only: the row's primary key. Present even for a delete,
  /// where it is the only thing identifying what to remove.
  final String? changeEntityId;

  /// [localChange] only: the row as its writer supplied it, JSON-encoded.
  /// Null for a delete. Carried as a string rather than a nested object for
  /// the same reason [feedBody] is — the receiver hands it to the identical
  /// applier the cloud path uses, and a string cannot be half-decoded by an
  /// intermediate that has no business reading it.
  final String? changePayload;

  /// [localChange] only: the originating terminal's id, for diagnostics. Never
  /// used to decide whether to apply — the hub already excludes the sender
  /// from its fan-out, and `ChangeApplier.applyFromPeer` stops the echo.
  final String? changeOrigin;

  /// [timerAction] only: the order whose table timer moved.
  final String? timerOrderId;

  /// [timerAction] only: `start`, `pause`, `resume` (the `kTimer*` constants
  /// the outbox already uses) or `evict` when the order closed and its record
  /// should go.
  final String? timerActionName;

  /// [timerAction] only: the settled timer record the transition produced,
  /// JSON-encoded, exactly as it was written to `LocalTables.tableTimers`.
  /// Null for `evict`, which removes rather than writes.
  ///
  /// Carrying the *result* rather than only the verb is deliberate. A receiver
  /// that recomputed the transition itself would need its own copy of the
  /// billing engine's settle/accumulate arithmetic, and two copies of that is
  /// precisely the "fixes landed on one path and not its duplicate" failure
  /// this codebase's guardrails exist to prevent. The message is still an
  /// event — it fires on a transition, never on a tick — it simply carries the
  /// state that event produced, so every terminal shows the same seconds and
  /// the same money without a second implementation deciding what those are.
  final String? timerRecord;

  /// [leaseRejected] only: which terminal currently holds the table, when
  /// known (offline-first-target-architecture.md §6) — surfaced to the
  /// cashier as "already opened on another terminal", not required for the
  /// arbitration logic itself.
  final String? leaseHeldBy;

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
    this.leaseTerminalId,
    this.leaseHeldBy,
    this.feedBody,
    this.feedFromCursor,
    this.printResult,
    this.printError,
    this.printTerminalId,
    this.changeEntity,
    this.changeAction,
    this.changeEntityId,
    this.changePayload,
    this.changeOrigin,
    this.timerOrderId,
    this.timerActionName,
    this.timerRecord,
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
  factory LanHubMessage.printJobClaim({
    required String jobId,
    required String terminalId,
  }) =>
      LanHubMessage(
        type: LanHubMessageType.printJobClaim,
        printJobId: jobId,
        printTerminalId: terminalId,
      );

  /// The originator's answer to the first claim it receives: [terminalId] may
  /// print, everyone else must not. Later claims for the same job get no grant
  /// at all, so a loser simply never starts.
  factory LanHubMessage.printJobGrant({
    required String jobId,
    required String terminalId,
  }) =>
      LanHubMessage(
        type: LanHubMessageType.printJobGrant,
        printJobId: jobId,
        printTerminalId: terminalId,
      );

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

  /// §6: sent by a follower's `LeaseManager.acquireTableLease` to ask the
  /// leader to arbitrate a table open — a directed leader RPC, same shape as
  /// `relayOp` above (single request, single correlated reply, never
  /// broadcast to other followers).
  factory LanHubMessage.leaseRequest({
    required String tableId,
    required String terminalId,
  }) => LanHubMessage(
        type: LanHubMessageType.leaseRequest,
        tableId: tableId,
        leaseTerminalId: terminalId,
      );

  factory LanHubMessage.leaseGranted({required String tableId}) =>
      LanHubMessage(type: LanHubMessageType.leaseGranted, tableId: tableId);

  factory LanHubMessage.leaseRejected({
    required String tableId,
    String? heldBy,
  }) => LanHubMessage(
        type: LanHubMessageType.leaseRejected,
        tableId: tableId,
        leaseHeldBy: heldBy,
      );

  /// Sent by a follower once its lease-holding UI action (the create-order
  /// write, per §6) has either committed or been abandoned — lets the leader
  /// evict its ephemeral claim before the TTL backstop would. Best-effort:
  /// losing this message changes nothing (the TTL still evicts it), so it's
  /// fire-and-forget, unlike `leaseRequest`.
  factory LanHubMessage.leaseRelease({
    required String tableId,
    required String terminalId,
  }) => LanHubMessage(
        type: LanHubMessageType.leaseRelease,
        tableId: tableId,
        leaseTerminalId: terminalId,
      );

  /// Broadcast by the leader after it applies a pull batch, so every follower
  /// converges on the same rows without its own cloud connection.
  factory LanHubMessage.changeFeed({
    required String body,
    required int fromCursor,
  }) => LanHubMessage(
        type: LanHubMessageType.changeFeed,
        feedBody: body,
        feedFromCursor: fromCursor,
      );

  /// Broadcast by *any* terminal the moment it commits a write of its own, so
  /// the rest of the venue sees the row without waiting for a round trip
  /// through the cloud — the one thing [changeFeed] cannot do, because a
  /// leader with no internet has no batch to relay.
  ///
  /// Peer-to-peer rather than leader-directed, deliberately. A follower's
  /// write matters to the other followers as much as to the leader, and the
  /// hub already fans a client's message out to every other client
  /// (`LanHubServer._broadcastExcept`) while handing it to its own app layer.
  /// That makes one message enough for a full venue, whoever wrote it.
  factory LanHubMessage.localChange({
    required String entity,
    required String action,
    required String entityId,
    String? payloadJson,
    String? origin,
  }) => LanHubMessage(
        type: LanHubMessageType.localChange,
        changeEntity: entity,
        changeAction: action,
        changeEntityId: entityId,
        changePayload: payloadJson,
        changeOrigin: origin,
      );

  /// Broadcast when a table timer starts, pauses, resumes, or is dropped.
  ///
  /// Table timers are local-authority state — `table_time_sessions` is not a
  /// replicated entity (see `kIntentionallyNotReplicated`), so [localChange]
  /// cannot carry them and a paused table stayed paused on exactly one
  /// terminal. That is the confusing case this closes: a waiter pausing a
  /// table on one till, and the till beside it still counting.
  factory LanHubMessage.timerAction({
    required String orderId,
    required String action,
    String? recordJson,
    String? origin,
  }) => LanHubMessage(
        type: LanHubMessageType.timerAction,
        timerOrderId: orderId,
        timerActionName: action,
        timerRecord: recordJson,
        changeOrigin: origin,
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
        if (printTerminalId != null) 'print_terminal_id': printTerminalId,
        if (leaseTerminalId != null) 'lease_terminal_id': leaseTerminalId,
        if (leaseHeldBy != null) 'lease_held_by': leaseHeldBy,
        if (feedBody != null) 'feed_body': feedBody,
        if (feedFromCursor != null) 'feed_from_cursor': feedFromCursor,
        if (changeEntity != null) 'change_entity': changeEntity,
        if (changeAction != null) 'change_action': changeAction,
        if (changeEntityId != null) 'change_entity_id': changeEntityId,
        if (changePayload != null) 'change_payload': changePayload,
        if (changeOrigin != null) 'change_origin': changeOrigin,
        if (timerOrderId != null) 'timer_order_id': timerOrderId,
        if (timerActionName != null) 'timer_action': timerActionName,
        if (timerRecord != null) 'timer_record': timerRecord,
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
        printTerminalId: map['print_terminal_id'] as String?,
        leaseTerminalId: map['lease_terminal_id'] as String?,
        leaseHeldBy: map['lease_held_by'] as String?,
        feedBody: map['feed_body'] as String?,
        feedFromCursor: (map['feed_from_cursor'] as num?)?.toInt(),
        changeEntity: map['change_entity'] as String?,
        changeAction: map['change_action'] as String?,
        changeEntityId: map['change_entity_id'] as String?,
        changePayload: map['change_payload'] as String?,
        changeOrigin: map['change_origin'] as String?,
        timerOrderId: map['timer_order_id'] as String?,
        timerActionName: map['timer_action'] as String?,
        timerRecord: map['timer_record'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
