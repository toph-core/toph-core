import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';

/// Bitta stol uchun timer segmenti (transferdan transfergacha).
/// `table_history` arrayidan parse qilinadi. Multi-switch (time → simple →
/// time → ...) holatlarida har bir bosqich alohida segment.
class TableSegment {
  final String? segmentId;
  final String? tableId;
  final DateTime? enteredAt;
  final DateTime? leftAt;
  final int activeSeconds;
  final int pausedSeconds;
  final String? movedFromTableId;
  final String? movedToTableId;
  final String? moveInReason;
  final String? moveOutReason;
  final List<PauseInterval> pauses;

  /// This segment's own table number, price/hour, and charge — frozen by
  /// the backend at the moment the segment closed (never re-derived from
  /// the table's current rate afterward), or live for the one still-open
  /// segment. `null` for a legacy pre-freeze segment or a table with no
  /// price set.
  final int? tableNumber;
  final String? pricePerHour;
  final String? amount;

  const TableSegment({
    this.segmentId,
    this.tableId,
    this.enteredAt,
    this.leftAt,
    this.activeSeconds = 0,
    this.pausedSeconds = 0,
    this.movedFromTableId,
    this.movedToTableId,
    this.moveInReason,
    this.moveOutReason,
    this.pauses = const [],
    this.tableNumber,
    this.pricePerHour,
    this.amount,
  });

  static DateTime? _parseDt(Object? v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static List<PauseInterval> _parsePauses(Object? v) {
    if (v is! List) return const [];
    return v
        .whereType<Map<String, dynamic>>()
        .map(PauseInterval.fromJson)
        .toList();
  }

  factory TableSegment.fromJson(Map<String, dynamic> json) {
    return TableSegment(
      segmentId: json['segment_id'] as String?,
      tableId: json['table_id'] as String?,
      enteredAt: _parseDt(json['entered_at']),
      leftAt: _parseDt(json['left_at']),
      activeSeconds: (json['active_seconds'] as num?)?.toInt() ?? 0,
      pausedSeconds: (json['paused_seconds'] as num?)?.toInt() ?? 0,
      movedFromTableId: json['moved_from_table_id'] as String?,
      movedToTableId: json['moved_to_table_id'] as String?,
      moveInReason: json['move_in_reason'] as String?,
      moveOutReason: json['move_out_reason'] as String?,
      pauses: _parsePauses(json['pause_intervals']),
      tableNumber: (json['table_number'] as num?)?.toInt(),
      pricePerHour: json['price_per_hour']?.toString(),
      amount: json['amount']?.toString(),
    );
  }

  TableSegment copyWith({int? activeSeconds, String? amount}) {
    return TableSegment(
      segmentId: segmentId,
      tableId: tableId,
      enteredAt: enteredAt,
      leftAt: leftAt,
      activeSeconds: activeSeconds ?? this.activeSeconds,
      pausedSeconds: pausedSeconds,
      movedFromTableId: movedFromTableId,
      movedToTableId: movedToTableId,
      moveInReason: moveInReason,
      moveOutReason: moveOutReason,
      pauses: pauses,
      tableNumber: tableNumber,
      pricePerHour: pricePerHour,
      amount: amount ?? this.amount,
    );
  }

  /// Stol shu segment davomida o'rtacha qancha vaqt ishlatilgan (sek).
  /// `active_seconds` server tomonda hisoblangan — pauselar chiqarib tashlangan.
  int get effectiveActiveSec => activeSeconds;

  /// Segment tugagan (boshqa stolga ko'chirilgan) bo'lsa true.
  bool get isClosed => leftAt != null;

  /// The continuous active stretches within this segment — the complement
  /// of [pauses] against [enteredAt]..[leftAt] (or "now" if still open and
  /// not currently paused). Derived client-side from timestamps already on
  /// this segment; matches the "Faol davrlar" dialog's per-interval rows
  /// (time range, duration, cost), nested under this segment's own row.
  List<ActiveInterval> get activeIntervals {
    final start = enteredAt;
    if (start == null) return const [];
    final sortedPauses = [...pauses]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final result = <ActiveInterval>[];
    var cursor = start;
    for (final p in sortedPauses) {
      if (p.startedAt.isAfter(cursor)) {
        result.add(
          ActiveInterval(
            start: cursor,
            end: p.startedAt,
            durationSec: p.startedAt.difference(cursor).inSeconds,
          ),
        );
      }
      if (p.endedAt == null) {
        // Still paused right now — no active interval continues after this.
        return result;
      }
      cursor = p.endedAt!;
    }
    if (leftAt != null) {
      if (leftAt!.isAfter(cursor)) {
        result.add(
          ActiveInterval(
            start: cursor,
            end: leftAt,
            durationSec: leftAt!.difference(cursor).inSeconds,
          ),
        );
      }
    } else {
      final now = DateTime.now();
      result.add(
        ActiveInterval(
          start: cursor,
          end: null,
          durationSec: now.difference(cursor).inSeconds,
        ),
      );
    }
    return result;
  }
}

/// One continuous active (non-paused) stretch within a [TableSegment].
/// `end == null` means it's still ongoing (the segment is currently running).
class ActiveInterval {
  final DateTime start;
  final DateTime? end;
  final int durationSec;

  const ActiveInterval({
    required this.start,
    this.end,
    required this.durationSec,
  });
}

/// Flattens `table_sessions[].segments` (from a `/bills/{id}` response) into
/// one chronological list — sessions are sequential for an order (at most
/// one open at a time), so straight concatenation (oldest session first,
/// segments already ascending within a session) preserves chronological
/// order without needing a session-wrapper type. This is the single source
/// of truth both `TableTimerCubit` (open orders, polls `/bills/{id}` every
/// 60s) and `ArchiveDetailEntity` (closed orders, fetched once) parse
/// through — see `docs/active_periods_view.md`.
List<TableSegment> parseBillTableSessionsToSegments(Object? tableSessionsJson) {
  if (tableSessionsJson is! List) return const [];
  final segments = <TableSegment>[];
  for (final session in tableSessionsJson) {
    if (session is! Map<String, dynamic>) continue;
    final rawSegments = session['segments'];
    if (rawSegments is! List) continue;
    segments.addAll(
      rawSegments
          .whereType<Map<String, dynamic>>()
          .map(TableSegment.fromJson),
    );
  }
  return segments;
}
