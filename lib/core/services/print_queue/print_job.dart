import 'package:hive_flutter/hive_flutter.dart';

part 'print_job.g.dart';

/// `state`/`jobType` are stored as plain strings (not their own `@HiveType`
/// enums) and exposed via [PrintJobStateX] below — the same convention
/// `LanHubMessage`/`RelayOpResult` already use for enum-shaped values that
/// cross a persistence/wire boundary, so this doesn't need a second
/// generated Hive adapter just for a small closed set of string constants.
enum PrintJobState { queued, claimed, printed, failed }

@HiveType(typeId: 12)
class PrintJob extends HiveObject {
  @HiveField(0)
  final String id;

  /// 'cashier'/'shiftClose' (both target the same single `close_check`
  /// printer) or 'kitchen' (one `PrintJob` per destination category
  /// printer — `printKitchenReceiptFor` already groups items by resolved
  /// printer before submitting, one job per group).
  @HiveField(1)
  final String jobType;

  /// Target `PrinterSettingEntry.id` — empty for the hardcoded
  /// close-check-fallback config, which has no entry at all.
  @HiveField(2)
  final String entryId;

  /// Pre-rendered ESC/POS bytes, base64-encoded — the receipt is built once,
  /// wherever the job originates, and shipped as bytes so a claiming
  /// terminal never needs the originator's order/cache context to print it.
  @HiveField(3)
  final String payloadBase64;

  @HiveField(4)
  final String connectionType;

  @HiveField(5)
  final String ip;

  @HiveField(6)
  final int port;

  @HiveField(7)
  String state;

  @HiveField(8)
  final DateTime createdAt;

  @HiveField(9)
  DateTime? claimedAt;

  @HiveField(10)
  DateTime? printedAt;

  /// 0 or 1 — at most one automatic re-announce/re-claim before this job is
  /// left `failed` for good (bounded retries, never an unbounded loop that
  /// could risk a duplicate physical printout).
  @HiveField(11)
  int retryCount;

  @HiveField(12)
  String? lastError;

  /// Which terminal ultimately claimed and printed this job — `null` until
  /// claimed, and always this terminal's own id for a job printed locally
  /// (no relay involved).
  @HiveField(13)
  String? ownerTerminalId;

  PrintJob({
    required this.id,
    required this.jobType,
    required this.entryId,
    required this.payloadBase64,
    required this.connectionType,
    required this.ip,
    required this.port,
    this.state = 'queued',
    required this.createdAt,
    this.claimedAt,
    this.printedAt,
    this.retryCount = 0,
    this.lastError,
    this.ownerTerminalId,
  });
}

extension PrintJobStateX on PrintJob {
  PrintJobState get stateEnum => PrintJobState.values.firstWhere(
        (e) => e.name == state,
        orElse: () => PrintJobState.queued,
      );

  set stateEnum(PrintJobState v) => state = v.name;
}
