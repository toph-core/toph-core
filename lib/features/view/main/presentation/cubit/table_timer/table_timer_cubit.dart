import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/table_timer/table_timer_sync_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';

part 'table_timer_state.dart';

/// CLIENT_FACING_OFFLINE_PLAN.md §2: fully local-first. Every read is a
/// `LocalDatabase`-backed snapshot/subscription through
/// `TableTimerLocalRepository`, every mutation is a local state transition +
/// outbox enqueue — no Dio await anywhere, and the old 60s
/// `Timer.periodic` server poll (`_ensureServerSync`) is gone outright:
/// server reconciliation is `SyncEngine`'s hydration job now. The 1s UI
/// tick remains, and the locally-anchored elapsed-time math
/// (`computeAnchoredLiveAmount`) is the sole source of truth between
/// hydrations instead of a cosmetic overlay between polls.
class TableTimerCubit extends Cubit<TableTimerState> {
  TableTimerCubit(this._repository, this._syncService)
    : super(const TableTimerState());

  final TableTimerLocalRepository _repository;
  final TableTimerSyncService _syncService;
  Timer? _uiTickTimer;
  StreamSubscription<TableTimerResponse?>? _timerSub;
  String? _activeOrderId;
  String? _activeTableId;

  int _baseTotalActiveSec = 0;
  double _baseAmount = 0;
  DateTime? _lastSyncAt;

  /// Backend message when present (`MessageFailure`), else a fixed fallback.
  String _messageFor(Failure failure, {required String fallback}) {
    if (failure is MessageFailure) return failure.message;
    return fallback;
  }

  void _cancelTimers() {
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
  }

  Future<void> _cancelSubscription() async {
    await _timerSub?.cancel();
    _timerSub = null;
  }

  /// Live subscription to this order's local timer record — fires on every
  /// local write (this cubit, the table-map badge, PaymentBloc's resume) and
  /// on every SyncEngine hydration, replacing the old 60s poll.
  void _subscribeTimer(String orderId) {
    _timerSub?.cancel();
    _timerSub = _repository.watchTimer(orderId).listen((t) {
      if (isClosed || _activeOrderId != orderId) return;
      if (t == null) return; // record evicted — bindOrder/fetchTimer decide
      _applyTimer(t);
    });
  }

  void _startUiTickIfRunning(TableTimerResponse? t) {
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
    // Clear any previously-ticked segment overlay so `effectiveSegments`
    // falls back to the fresh `billSegments` instead of a stale live value
    // frozen at the moment ticking stopped (e.g. right before a pause).
    if (!isClosed) {
      emit(state.copyWith(clearDisplaySegments: true));
    }
    if (t == null) return;
    if (t.stateNormalized != 'running') return;

    // Current segment's rate — only applied to seconds accrued *since* the
    // last applied snapshot, on top of `_baseAmount` (the already
    // segment-priced amount as of that snapshot). Never re-multiplies the
    // whole multi-segment elapsed time by this single rate.
    final currentPrice = double.tryParse(t.pricePerHour ?? '') ?? 0;

    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final syncAt = _lastSyncAt;
      if (syncAt == null) return;
      final elapsed = DateTime.now().difference(syncAt).inSeconds;
      final safeElapsed = elapsed < 0 ? 0 : elapsed;
      final display = _baseTotalActiveSec + safeElapsed;
      final amount = computeAnchoredLiveAmount(
        baseAmount: _baseAmount,
        elapsedSinceSyncSec: safeElapsed,
        currentPricePerHour: currentPrice,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            displayActiveSec: display,
            displayAmount: amount,
            displaySegments: _tickLastSegment(currentPrice),
          ),
        );
      }
    });
  }

  /// Overlays a live tick onto only the LAST segment of `state.billSegments`
  /// (the currently-open one, if any) — every closed segment before it keeps
  /// its frozen amount untouched.
  List<TableSegment>? _tickLastSegment(double currentPrice) {
    final segs = state.billSegments;
    if (segs.isEmpty) return null;
    final last = segs.last;
    if (last.leftAt != null) return null;

    final syncAt = _lastSyncAt;
    final elapsed = syncAt == null
        ? 0
        : DateTime.now().difference(syncAt).inSeconds;
    final safeElapsed = elapsed < 0 ? 0 : elapsed;
    final liveSec = last.activeSeconds + safeElapsed;
    final liveAmount = computeAnchoredLiveAmount(
      baseAmount: double.tryParse(last.amount ?? '') ?? 0,
      elapsedSinceSyncSec: safeElapsed,
      currentPricePerHour: currentPrice,
    );
    return [
      ...segs.sublist(0, segs.length - 1),
      last.copyWith(
        activeSeconds: liveSec,
        amount: liveAmount.toStringAsFixed(2),
      ),
    ];
  }

  void _applyTimer(TableTimerResponse t) {
    _lastSyncAt = DateTime.now();
    _baseTotalActiveSec = t.totalActiveSec;
    _baseAmount =
        double.tryParse(t.currentAmount ?? '') ??
        double.tryParse(t.finalAmount ?? '') ??
        0;
    emit(
      state.copyWith(
        isLoading: false,
        shouldShow: true,
        timer: t,
        displayActiveSec: t.totalActiveSec,
        displayAmount: _baseAmount,
        errorMessage: null,
        // The local record's synthesized history (or the server's fuller
        // multi-session breakdown once a hydration pass has landed one) —
        // both arrive through the same snapshot now, no second round trip.
        billSegments: t.tableHistory.isNotEmpty ? t.tableHistory : null,
        billPauses: t.pauses.isNotEmpty ? t.pauses : null,
      ),
    );
    _startUiTickIfRunning(t);
    // Table-map kartochkasi (TimeBasedTableBadge) shu yerdan darhol
    // xabardor bo'lishi uchun umumiy keshga yozamiz.
    final tid = (t.currentTableId?.isNotEmpty ?? false)
        ? t.currentTableId!
        : t.tableId;
    _syncService.publish(tid, t);
  }

  /// Buyurtma almashganda chaqiriladi. Timer faqat `dine_in` (yoki tur noma’lum) uchun so‘raladi.
  Future<void> bindOrder(OpenOrderModel? order) async {
    _cancelTimers();
    await _cancelSubscription();
    _activeOrderId = null;
    _activeTableId = null;
    _lastSyncAt = null;
    _baseTotalActiveSec = 0;
    _baseAmount = 0;

    if (order == null || order.id.isEmpty) {
      emit(const TableTimerState());
      return;
    }

    if (order.isTerminalOrderStatus) {
      emit(const TableTimerState());
      return;
    }

    final ot = order.orderType?.trim().toLowerCase();
    if (ot != null && ot.isNotEmpty && ot != 'dine_in') {
      emit(const TableTimerState(shouldShow: false));
      return;
    }

    // Timer ikki holatda ko'rsatiladi (eski GET bilan bir xil mezon):
    //   1) Stol time_based — live timer.
    //   2) Order time-based stoldan simple stolga ko'chirilgan va summa
    //      muzlatilgan — frozen UI.
    if (!order.isTimeBasedTable && !order.hasFrozenTableAmount) {
      emit(const TableTimerState(shouldShow: false));
      return;
    }

    _activeOrderId = order.id;
    _activeTableId = order.tableId;
    // Darhol 0:00 ko'rsat — lokal o'qish deyarli bir zumda keladi
    emit(state.copyWith(shouldShow: true, displayActiveSec: 0));
    await fetchTimer(orderId: order.id, showLoading: false);
  }

  /// Local snapshot read + live subscription — no network, ever.
  Future<void> fetchTimer({
    required String orderId,
    bool showLoading = false,
  }) async {
    _activeOrderId = orderId;
    if (!state.shouldShow) {
      emit(state.copyWith(shouldShow: true, displayActiveSec: 0));
    }
    if (showLoading) {
      emit(state.copyWith(isLoading: true, errorMessage: null));
    }

    final result = await _repository.getTimer(orderId);
    if (isClosed) return;
    if (_activeOrderId != orderId) return;

    result.fold(
      (failure) {
        // Local reads shouldn't fail; kept for interface completeness.
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: _messageFor(failure, fallback: 'Table timer xatosi'),
          ),
        );
      },
      (t) {
        if (t == null) {
          // No local record — nothing to show (yet). SyncEngine's hydration
          // or a local start writes one, and the subscription below picks
          // it up the moment it lands.
          emit(
            state.copyWith(
              isLoading: false,
              shouldShow: false,
              clearTimer: true,
              clearDisplayActiveSec: true,
            ),
          );
          _cancelTimers();
          _subscribeTimer(orderId);
          return;
        }
        final hasFrozenAmount =
            t.isFrozenClosed && parseAmountToInt(t.finalAmount) > 0;
        if (!t.isTimeBasedTable && !hasFrozenAmount) {
          emit(
            state.copyWith(
              isLoading: false,
              shouldShow: false,
              clearTimer: true,
              clearDisplayActiveSec: true,
            ),
          );
          _cancelTimers();
          return;
        }
        _applyTimer(t);
        _subscribeTimer(orderId);
      },
    );
  }

  /// Bo'sh order yaratadi va timerni boshlaydi (time-based free stol uchun).
  /// Returns orderId on success, null on failure. Both steps are local
  /// commits — a genuine cross-terminal conflict is merged at outbox replay
  /// time, not surfaced here.
  Future<String?> createTimedOrderAndStart({
    required String tableId,
    required int guestCount,
  }) async {
    _cancelTimers();
    await _cancelSubscription();
    _activeOrderId = null;
    _activeTableId = tableId;
    _lastSyncAt = null;
    _baseTotalActiveSec = 0;
    _baseAmount = 0;
    emit(
      state.copyWith(shouldShow: true, isLoading: true, displayActiveSec: 0),
    );

    final result = await _repository.createTimedOrder(
      tableId: tableId,
      guestCount: guestCount,
    );
    if (isClosed) return null;

    return result.fold(
      (failure) async {
        if (failure is EmptyFailure) {
          emit(state.copyWith(isLoading: false, shouldShow: false));
        } else {
          emit(
            state.copyWith(
              isLoading: false,
              shouldShow: false,
              errorMessage: _messageFor(
                failure,
                fallback: 'Order yaratishda xato',
              ),
            ),
          );
        }
        return null;
      },
      (created) async {
        _activeOrderId = created.orderId;
        emit(state.copyWith(isLoading: false));
        if (created.wasExisting) {
          // Shu stolda allaqachon lokal timer bor — holatini o'qib davom
          // etamiz (ishlayotgan bo'lishi mumkin).
          await fetchTimer(orderId: created.orderId);
        } else {
          await startTimer();
        }
        return created.orderId;
      },
    );
  }

  Future<void> startTimer() async {
    final id = _activeOrderId;
    if (id == null) return;
    emit(state.copyWith(isMutating: true, errorMessage: null));
    final result = await _repository.startTimer(id, tableId: _activeTableId);
    if (isClosed || _activeOrderId != id) return;
    result.fold(
      (failure) {
        emit(
          state.copyWith(
            isMutating: false,
            errorMessage: _messageFor(failure, fallback: 'Start xatosi'),
          ),
        );
      },
      (t) {
        emit(state.copyWith(isMutating: false));
        if (t != null) _applyTimer(t);
        _subscribeTimer(id);
      },
    );
  }

  Future<void> pauseTimer() async {
    final id = _activeOrderId;
    if (id == null) return;
    emit(state.copyWith(isMutating: true, errorMessage: null));
    final result = await _repository.pauseTimer(id);
    if (isClosed || _activeOrderId != id) return;
    result.fold(
      (failure) {
        emit(
          state.copyWith(
            isMutating: false,
            errorMessage: _messageFor(failure, fallback: 'Pause xatosi'),
          ),
        );
      },
      (t) {
        emit(state.copyWith(isMutating: false));
        if (t != null) _applyTimer(t);
      },
    );
  }

  Future<void> resumeTimer() async {
    final id = _activeOrderId;
    if (id == null) return;
    // Closed session holds accrued charge — never start a fresh timer (resets to 0).
    if (state.timer != null && state.timer!.isFrozenClosed) {
      return;
    }
    // Timer hali boshlanmagan → start
    if (state.timer == null || state.timer!.stateNormalized == 'none') {
      await startTimer();
      return;
    }
    emit(state.copyWith(isMutating: true, errorMessage: null));
    final result = await _repository.resumeTimer(id);
    if (isClosed || _activeOrderId != id) return;
    result.fold(
      (failure) {
        emit(
          state.copyWith(
            isMutating: false,
            errorMessage: _messageFor(failure, fallback: 'Resume xatosi'),
          ),
        );
      },
      (t) {
        emit(state.copyWith(isMutating: false));
        if (t != null) _applyTimer(t);
      },
    );
  }

  @override
  Future<void> close() {
    _cancelTimers();
    _timerSub?.cancel();
    return super.close();
  }
}
