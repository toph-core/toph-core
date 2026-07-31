import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// Single source of truth for rendering a time-based order's "active
/// periods" (which physical table, how long active, that table's
/// price/hour, and the charge for that period) — replaces the old
/// pause-history UI. Fed by [TableSegment] lists that are themselves parsed
/// by the single shared `parseBillTableSessionsToSegments` (see
/// `table_segment_model.dart`) from either the live `TableTimerCubit`
/// (ticking) or `ArchiveDetailEntity` (frozen), so every screen that shows
/// this data renders it identically. See `docs/active_periods_view.md`.
///
/// [ActivePeriodsDialog] is the modal form (tap-to-open); [ActivePeriodsSection]
/// is the inline expandable form — both share the same row/footer widgets
/// below so the numbers can never drift between the two presentations.
class ActivePeriodsDialog extends StatelessWidget {
  final List<TableSegment> segments;
  final DateTime? startedAt;

  const ActivePeriodsDialog({super.key, required this.segments, this.startedAt});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      S.current.strActivePeriods,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: _kDark,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: _kGraySoft,
                    ),
                  ),
                ],
              ),
            ),
            if (startedAt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: _kGraySoft,
                    ),
                    6.wBox,
                    Text(
                      '${S.current.strOpenedAtLabel} ${_fmtClock(startedAt!)}',
                      style: const TextStyle(fontSize: 12.5, color: _kGraySoft),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Container(height: 1, color: _kConnectorLine),
            ),
            Flexible(
              child: _ActivePeriodsList(segments: segments, scrollable: true),
            ),
            if (segments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: _ActivePeriodsSummaryFooter(segments: segments),
              ),
          ],
        ),
      ),
    );
  }
}

class ActivePeriodsSection extends StatefulWidget {
  final List<TableSegment> segments;
  const ActivePeriodsSection({super.key, required this.segments});

  @override
  State<ActivePeriodsSection> createState() => _ActivePeriodsSectionState();
}

class _ActivePeriodsSectionState extends State<ActivePeriodsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments;
    return SizedBox(
      width: context.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: context.radius.buttonLg,
          color: context.colors.bgTritary,
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timelapse_rounded,
                      size: 16,
                      color: context.colors.bgBrand,
                    ),
                    8.wBox,
                    Expanded(
                      child: Text(
                        '${S.current.strActivePeriods} · ${segments.length}x',
                        style: context.textStyles.bodySm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (segments.isNotEmpty)
                      Text(
                        '${S.current.strTotalActiveTime} ${_totalAmount(segments).round().formatN}',
                        style: context.textStyles.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.colors.bgBrand,
                        ),
                      ),
                    4.wBox,
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                children: [
                  _ActivePeriodsList(segments: segments, scrollable: false),
                  if (segments.isNotEmpty)
                    _ActivePeriodsSummaryFooter(segments: segments),
                ],
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivePeriodsList extends StatelessWidget {
  final List<TableSegment> segments;
  final bool scrollable;
  const _ActivePeriodsList({required this.segments, required this.scrollable});

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Center(
          child: Text(
            S.current.strNoActivePeriods,
            style: context.textStyles.bodySm.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      );
    }
    final list = ListView.separated(
      shrinkWrap: true,
      physics: scrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      itemCount: segments.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: context.colors.border),
      itemBuilder: (_, i) => _ActivePeriodRow(segment: segments[i], index: i),
    );
    return scrollable
        ? Scrollbar(thumbVisibility: true, thickness: 4, child: list)
        : list;
  }
}

// Exact palette from the "Faol davrlar" design spec — kept hardcoded here
// (not the app's theme tokens) since this widget must match that mock 1:1.
const _kChipBg = Color(0xFFFFF1E6);
const _kOrange = Color(0xFFEA580C);
const _kDark = Color(0xFF111827);
const _kGraySoft = Color(0xFF9CA3AF);
const _kGrayMid = Color(0xFF6B7280);
const _kIntervalCost = Color(0xFFB45309);
const _kDotFaded = Color(0xFFFCD9B8);
const _kConnectorLine = Color(0xFFEEF0F2);

class _ActivePeriodRow extends StatelessWidget {
  final TableSegment segment;
  final int index;
  const _ActivePeriodRow({required this.segment, required this.index});

  @override
  Widget build(BuildContext context) {
    final tableLabel = segment.tableNumber != null
        ? 'Stol ${segment.tableNumber}'
        : '—';
    final price = double.tryParse(segment.pricePerHour ?? '');
    final amount = double.tryParse(segment.amount ?? '');
    final intervals = segment.activeIntervals;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _kChipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: _kOrange,
                    ),
                  ),
                ),
              ),
              10.wBox,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tableLabel,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: _kDark,
                      ),
                    ),
                    if (price != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          '${price.round().formatN}/soat',
                          style: const TextStyle(fontSize: 12, color: _kGraySoft),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtDur(segment.activeSeconds),
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF374151),
                    ),
                  ),
                  if (amount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        amount.round().formatN,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: _kOrange,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (intervals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 8),
              child: Stack(
                children: [
                  Positioned(
                    left: 5,
                    top: 2,
                    bottom: 10,
                    child: Container(width: 1, color: _kConnectorLine),
                  ),
                  Column(
                    children: [
                      for (var i = 0; i < intervals.length; i++)
                        _ActiveIntervalRow(
                          interval: intervals[i],
                          isLast: i == intervals.length - 1,
                          pricePerHour: price,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveIntervalRow extends StatelessWidget {
  final ActiveInterval interval;
  final bool isLast;
  final double? pricePerHour;

  const _ActiveIntervalRow({
    required this.interval,
    required this.isLast,
    required this.pricePerHour,
  });

  @override
  Widget build(BuildContext context) {
    final cost = pricePerHour != null
        ? (interval.durationSec / 3600.0) * pricePerHour!
        : null;
    final rangeLabel = interval.end != null
        ? '${_fmtClock(interval.start)} → ${_fmtClock(interval.end!)}'
        : '${_fmtClock(interval.start)} → ...';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 0, 6),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isLast ? _kOrange : _kDotFaded,
              shape: BoxShape.circle,
            ),
          ),
          10.wBox,
          Expanded(
            child: Text(
              rangeLabel,
              style: const TextStyle(fontSize: 12, color: _kGrayMid),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtDur(interval.durationSec),
                style: const TextStyle(fontSize: 11.5, color: _kGraySoft),
              ),
              if (cost != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    cost.round().formatN,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kIntervalCost,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `H:MM` — matches the design spec's duration format (no seconds), unlike
/// the app-wide `toHHMMSS` extension which shows `M:SS` under an hour.
String _fmtDur(int totalSeconds) {
  final totalMinutes = totalSeconds ~/ 60;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

/// Computes its own total from the passed-in [segments] — never takes a
/// separately-computed total as a parameter, so this footer can never
/// disagree with the rows rendered above it.
class _ActivePeriodsSummaryFooter extends StatelessWidget {
  final List<TableSegment> segments;
  const _ActivePeriodsSummaryFooter({required this.segments});

  @override
  Widget build(BuildContext context) {
    final totalSec = segments.fold<int>(0, (s, seg) => s + seg.activeSeconds);
    final totalAmount = _totalAmount(segments);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kConnectorLine)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${S.current.strTotalActiveTime} ${_fmtDur(totalSec)}',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: _kDark,
            ),
          ),
          Text(
            totalAmount.round().formatN,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: _kOrange,
            ),
          ),
        ],
      ),
    );
  }
}

double _totalAmount(List<TableSegment> segments) {
  return segments.fold<double>(
    0,
    (s, seg) => s + (double.tryParse(seg.amount ?? '') ?? 0),
  );
}

String _fmtClock(DateTime dt) {
  final l = dt.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
