import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/services/table_timer/table_timer_sync_service.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

const _indigo = Color(0xFFFB6633);
const _kGreen = Color(0xFF16A34A);
const _kBarFill = Color(0xFFFFE4D6);
const _kFooterIcon = Color(0xFF94A3B8);
const _kFooterText = Color(0xFF64748B);
// Paused look is deliberately far from the running one (muted gray vs.
// vivid orange) so the state reads at a glance from across the room,
// not just up close.
const _kPausedBg = Color(0xFFE9EDF2);
const _kPausedBorder = Color(0xFFCBD5E1);
const _kPausedText = Color(0xFF64748B);

/// Rendering mode for the redesigned table-card chrome. Takes precedence
/// over [TimeBasedTableBadge.compact] when set, so existing call sites
/// that only pass `compact` keep behaving exactly as before.
enum TimeBasedBadgeMode { bar, footer }

class TimeBasedTableBadge extends StatefulWidget {
  final CafeTableModel table;
  final bool compact;
  final bool showControls;
  final TimeBasedBadgeMode? mode;

  const TimeBasedTableBadge({
    super.key,
    required this.table,
    this.compact = false,
    this.showControls = false,
    this.mode,
  });

  @override
  State<TimeBasedTableBadge> createState() => _TimeBasedTableBadgeState();
}

class _TimeBasedTableBadgeState extends State<TimeBasedTableBadge> {
  int _elapsedSec = 0;
  int _baseElapsedSec = 0;
  double _baseAmount = 0;
  DateTime? _lastSyncAt;
  String _amount = '';
  String _pricePerHour = '';
  String _timerState = 'none';
  bool _loaded = false;
  bool _actionLoading = false;
  String _orderId = '';

  Timer? _tickTimer;
  Timer? _syncTimer;
  StreamSubscription<String>? _syncSub;

  bool get _isBusy => widget.table.status == TableStatus.busy;

  void _seedPriceFromTable() {
    _pricePerHour = widget.table.pricePerHour ?? '';
  }

  @override
  void initState() {
    super.initState();
    _seedPriceFromTable();
    // Cross-screen sync: another widget (order screen's TableTimerCubit,
    // or another badge instance) may already know this table's live
    // timer state — hydrate from it immediately instead of waiting for
    // our own first poll.
    final cached = inject<TableTimerSyncService>().forTable(widget.table.id);
    if (cached != null) _absorbTimer(cached);
    _syncSub = inject<TableTimerSyncService>().updates.listen(
      _onExternalTimerUpdate,
    );
    if (_isBusy) _startPolling();
  }

  void _onExternalTimerUpdate(String tableId) {
    if (tableId != widget.table.id || !mounted) return;
    final t = inject<TableTimerSyncService>().forTable(tableId);
    if (t == null) return;
    setState(() => _absorbTimer(t));
  }

  /// Adopts a [TableTimerResponse] (from our own poll or from another
  /// screen via [TableTimerSyncService]) into local display state.
  void _absorbTimer(TableTimerResponse t) {
    if (t.orderId.isNotEmpty) _orderId = t.orderId;
    _elapsedSec = t.totalActiveSec;
    _baseElapsedSec = t.totalActiveSec;
    _baseAmount =
        double.tryParse(t.currentAmount ?? '') ??
        double.tryParse(t.finalAmount ?? '') ??
        0;
    _lastSyncAt = DateTime.now();
    _timerState = t.stateNormalized;
    _amount = t.currentAmount ?? t.finalAmount ?? '';
    if ((t.pricePerHour ?? '').isNotEmpty) _pricePerHour = t.pricePerHour!;
    _loaded = true;

    _tickTimer?.cancel();
    _tickTimer = null;
    if (_timerState == 'running') {
      // Recompute from the wall-clock anchor every tick instead of a raw
      // `_elapsedSec++` — Timer.periodic doesn't compensate for
      // delayed/dropped ticks (busy isolate, backgrounded tab), so a raw
      // increment silently drifts behind the true elapsed time.
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final syncAt = _lastSyncAt;
        final elapsed = syncAt == null
            ? 0
            : DateTime.now().difference(syncAt).inSeconds;
        setState(
          () => _elapsedSec = _baseElapsedSec + (elapsed < 0 ? 0 : elapsed),
        );
      });
    }
  }

  void _publish(TableTimerResponse t) {
    final tid = (t.currentTableId?.isNotEmpty ?? false)
        ? t.currentTableId!
        : (t.tableId.isNotEmpty ? t.tableId : widget.table.id);
    inject<TableTimerSyncService>().publish(tid, t);
  }

  @override
  void didUpdateWidget(TimeBasedTableBadge old) {
    super.didUpdateWidget(old);
    final wasBusy = old.table.status == TableStatus.busy;

    if (!wasBusy && _isBusy) {
      _startPolling();
    } else if (wasBusy && !_isBusy) {
      _stopPolling();
      if (mounted) {
        setState(() {
          _loaded = false;
          _elapsedSec = 0;
          _baseElapsedSec = 0;
          _baseAmount = 0;
          _lastSyncAt = null;
          _amount = '';
          _seedPriceFromTable();
          _timerState = 'none';
          _orderId = '';
        });
      }
    } else if (!_isBusy &&
        widget.table.pricePerHour != old.table.pricePerHour) {
      if (mounted) {
        setState(_seedPriceFromTable);
      } else {
        _seedPriceFromTable();
      }
    }
  }

  void _startPolling() {
    _sync();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sync());
  }

  void _stopPolling() {
    _tickTimer?.cancel();
    _syncTimer?.cancel();
    _tickTimer = null;
    _syncTimer = null;
  }

  Future<void> _sync() async {
    try {
      final repo = inject<MainRepository>();
      final orderId = await repo.getOrderIdWithTableId(widget.table.id);
      if (orderId.isEmpty) return;

      final timerResult = await repo.getOrderTableTimer(orderId);
      final raw = timerResult.fold((_) => null, (r) => r);
      if (raw == null) return;
      final t = TableTimerResponse.fromJson(raw);

      if (!mounted) return;
      setState(() => _absorbTimer(t));
      _publish(t);
    } catch (_) {}
  }

  Future<void> _togglePause() async {
    if (_orderId.isEmpty || _actionLoading) return;

    setState(() => _actionLoading = true);
    try {
      final repo = inject<MainRepository>();
      if (_timerState == 'running') {
        await repo.pauseOrderTableTimer(_orderId);
      } else if (_timerState == 'paused') {
        await repo.resumeOrderTableTimer(_orderId);
      }
      await _sync();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _stopPolling();
    super.dispose();
  }

  static String fmtTime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
  }

  static String fmtAmount(String raw) {
    final d = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (d == null) return raw;
    return d.round().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  Widget _buildFooter() {
    if (_pricePerHour.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.access_time_rounded, size: 14, color: _kFooterIcon),
        const SizedBox(width: 4),
        Text(
          '${fmtAmount(_pricePerHour)} so\'m/soat',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _kFooterText,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  /// Charge to display for the current tick. While the timer is `running`,
  /// the server's `current_amount` only refreshes every 60s (our sync
  /// interval), so it visibly lags the ticking clock — here we tick it
  /// locally via the shared `computeAnchoredLiveAmount` (same helper
  /// `TableTimerCubit` uses), anchored on `_baseAmount` (the last
  /// server-computed, already segment-priced amount) plus only the seconds
  /// elapsed since that sync at the *current* price. This must not multiply
  /// the whole `_elapsedSec` (which can span a prior, differently-priced
  /// segment after a transfer) by the current price — that would silently
  /// re-price already-billed time. Paused/closed amounts are authoritative
  /// from the server and aren't recomputed.
  int _liveAmount() {
    if (_timerState == 'running') {
      final price = double.tryParse(_pricePerHour) ?? 0;
      return computeAnchoredLiveAmount(
        baseAmount: _baseAmount,
        elapsedSinceSyncSec: _elapsedSec - _baseElapsedSec,
        currentPricePerHour: price,
      ).round();
    }
    return parseAmountToInt(_amount);
  }

  Widget _buildBar() {
    if (!_isBusy || !_loaded) return const SizedBox.shrink();
    final amount = _liveAmount();
    final showAmount = amount != 0;
    final isRunning = _timerState == 'running';
    // Running vs. paused must read from across the room, not just up
    // close — so the whole chip flips between a vivid orange (money is
    // accruing) and a flat gray (it isn't), on top of the icon swap.
    final fg = isRunning ? _indigo : _kPausedText;
    final bg = isRunning ? _kBarFill : _kPausedBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: isRunning ? null : Border.all(color: _kPausedBorder, width: 1),
      ),
      child: Row(
        children: [
          if (isRunning)
            _PulsingDot(color: fg, active: true)
          else
            Icon(Icons.pause_circle_filled_rounded, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            fmtTime(_elapsedSec),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: fg,
              fontFamily: 'Inter',
            ),
          ),
          const Spacer(),
          if (showAmount)
            Text(
              '${fmtAmount('$amount')} so\'m',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
                fontFamily: 'Inter',
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == TimeBasedBadgeMode.bar) return _buildBar();
    if (widget.mode == TimeBasedBadgeMode.footer) return _buildFooter();

    // ── Canvas Compact View ────────────────────────────────────────────
    if (widget.compact) {
      final priceStr = _pricePerHour.isNotEmpty
          ? '${fmtAmount(_pricePerHour)} so\'m/soat'
          : 'Bepul';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _kGreen.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.symmetric(
            horizontal: BorderSide(color: _kGreen.withOpacity(0.3)),
          ),
        ),
        child: Text(
          priceStr,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _kGreen,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Small dot that pulses while [active] (timer running) and sits static
/// otherwise — makes a running timer visibly distinct from a paused one
/// at a glance, without needing to read the clock text.
class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool active;
  const _PulsingDot({required this.color, required this.active});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && old.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(1 - (t * 0.75)),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.45 * (1 - t)),
                blurRadius: 5,
                spreadRadius: 1.5 * (1 - t),
              ),
            ],
          ),
        );
      },
    );
  }
}
