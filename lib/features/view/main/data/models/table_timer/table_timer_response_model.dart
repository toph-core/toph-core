/// Bitta pause sessiyasi — boshlanish, tugash vaqti va davomiyligi.
class PauseInterval {
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSec;

  const PauseInterval({
    required this.startedAt,
    this.endedAt,
    required this.durationSec,
  });

  factory PauseInterval.fromJson(Map<String, dynamic> json) {
    return PauseInterval(
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.now(),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.tryParse(json['ended_at'] as String),
      durationSec: (json['duration_sec'] as num?)?.toInt() ??
          (json['pause_sec'] as num?)?.toInt() ??
          0,
    );
  }
}

/// `GET/POST /api/v1/orders/{id}/table-timer*` javobi (`data` obyekti).
class TableTimerResponse {
  final String orderId;
  final String tableId;
  final String tableType;
  /// none | running | paused | closed
  final String state;
  final DateTime? startedAt;
  final DateTime? activeStartedAt;
  final DateTime? endedAt;
  final DateTime? pausedAt;
  final String? pricePerHour;
  final int accumulatedActiveSec;
  final int currentActiveSec;
  final int totalActiveSec;
  final String? currentAmount;
  final String? finalAmount;
  final bool isRunning;
  final bool isPaused;
  final bool isClosed;
  final List<PauseInterval> pauses;

  const TableTimerResponse({
    required this.orderId,
    required this.tableId,
    required this.tableType,
    required this.state,
    this.startedAt,
    this.activeStartedAt,
    this.endedAt,
    this.pausedAt,
    this.pricePerHour,
    this.accumulatedActiveSec = 0,
    this.currentActiveSec = 0,
    this.totalActiveSec = 0,
    this.currentAmount,
    this.finalAmount,
    this.isRunning = false,
    this.isPaused = false,
    this.isClosed = false,
    this.pauses = const [],
  });

  static DateTime? _parseDt(Object? v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static List<PauseInterval> _parsePauses(Object? v) {
    if (v == null) return const [];
    if (v is! List) return const [];
    return v
        .whereType<Map<String, dynamic>>()
        .map(PauseInterval.fromJson)
        .toList();
  }

  factory TableTimerResponse.fromJson(Map<String, dynamic> json) {
    return TableTimerResponse(
      orderId: json['order_id'] as String? ?? '',
      tableId: json['table_id'] as String? ?? '',
      tableType: json['table_type'] as String? ?? '',
      state: json['state'] as String? ?? 'none',
      startedAt: _parseDt(json['started_at']),
      activeStartedAt: _parseDt(json['active_started_at']),
      endedAt: _parseDt(json['ended_at']),
      pausedAt: _parseDt(json['paused_at'] ?? json['last_paused_at']),
      pricePerHour: json['price_per_hour']?.toString(),
      accumulatedActiveSec: (json['accumulated_active_sec'] as num?)?.toInt() ?? 0,
      currentActiveSec: (json['current_active_sec'] as num?)?.toInt() ?? 0,
      totalActiveSec: (json['total_active_sec'] as num?)?.toInt() ?? 0,
      currentAmount: json['current_amount']?.toString(),
      finalAmount: json['final_amount']?.toString(),
      isRunning: json['is_running'] as bool? ?? false,
      isPaused: json['is_paused'] as bool? ?? false,
      isClosed: json['is_closed'] as bool? ?? false,
      pauses: _parsePauses(
        json['pauses'] ?? json['pause_intervals'] ?? json['pause_sessions'],
      ),
    );
  }

  bool get isTimeBasedTable => tableType.toLowerCase() == 'time_based';

  String get stateNormalized => state.toLowerCase();

  int get totalPauseSec => pauses.fold(0, (s, p) => s + p.durationSec);
}
