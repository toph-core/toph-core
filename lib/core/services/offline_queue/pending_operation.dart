import 'package:hive_flutter/hive_flutter.dart';

part 'pending_operation.g.dart';

@HiveType(typeId: 10)
enum PendingOperationType {
  @HiveField(0)
  createOrder,
  @HiveField(1)
  addItems,
  @HiveField(2)
  payOrder,
  @HiveField(3)
  openShift,
  @HiveField(4)
  closeShift,
  @HiveField(5)
  cancelLineItems,
  @HiveField(6)
  cancelOrder,

  /// CLIENT_FACING_OFFLINE_PLAN.md §7 — "transfer to another table",
  /// previously a direct awaited network call in `transfer_table_dialog`.
  @HiveField(7)
  transferTable,

  /// CLIENT_FACING_OFFLINE_PLAN.md §2 — table-timer start/pause/resume,
  /// previously direct network calls in `TableTimerCubit`/
  /// `TimeBasedTableBadge`. One type for all three actions (payload carries
  /// `action`) so an offline pause→resume→pause sequence replays in its
  /// original order — `syncAll` groups ops by type, which would reorder
  /// them if each action were its own type. Timed-order *creation* reuses
  /// the existing [createOrder] type (same endpoint, empty items).
  @HiveField(8)
  timerAction,
}

@HiveType(typeId: 11)
class PendingOperation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final PendingOperationType type;

  /// JSON-encoded request payload
  @HiveField(2)
  final String payload;

  /// tableId — sync vaqtida orderId topish uchun
  @HiveField(3)
  final String tableId;

  @HiveField(4)
  final DateTime createdAt;

  /// BACKEND_SYNC_PLAN.md §12 rule 4 — optional deterministic coalescing
  /// key (e.g. `"timer:{orderId}"`). When set, `OfflineQueueService.enqueue`
  /// REPLACES any still-queued op carrying the same key instead of
  /// appending, so repeated rapid edits of the same logical thing collapse
  /// to one op. `null` (every current call site) keeps the historical
  /// append-always behavior — the mechanism ships ahead of any user, per
  /// the plan's recommendation, and per product decision the timer ops
  /// deliberately do NOT use it yet (every tap replays).
  @HiveField(5)
  final String? coalesceKey;

  /// BACKEND_SYNC_PLAN.md §12 — per-op retry observability, so a single
  /// stuck op is distinguishable from a healthy queue. Incremented by
  /// `syncAll` on each retryable failure; deliberately NOT a quarantine
  /// trigger (per product decision — a long server outage must not silently
  /// stop payments from retrying). Mutable + persisted via HiveObject.save.
  @HiveField(6)
  int retryCount;

  @HiveField(7)
  DateTime? lastAttemptAt;

  PendingOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.tableId,
    required this.createdAt,
    this.coalesceKey,
    this.retryCount = 0,
    this.lastAttemptAt,
  });
}
