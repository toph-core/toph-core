import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/table_timer/table_timer_sync_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';

part 'table_timer_state.dart';

class TableTimerCubit extends Cubit<TableTimerState> {
  TableTimerCubit(this._repository, this._syncService)
    : super(const TableTimerState());

  final TableTimerLocalRepository _repository;
  final TableTimerSyncService _syncService;
  Timer? _serverSyncTimer;
  Timer? _uiTickTimer;
  String? _activeOrderId;

  int _baseTotalActiveSec = 0;
  double _baseAmount = 0;
  DateTime? _lastSyncAt;
  DateTime? _lastBillDetailsFetchAt;
  String? _lastBillDetailsOrderId;

  static const Duration _serverSyncInterval = Duration(seconds: 60);
  static const Duration _billPausesThrottle = Duration(seconds: 60);

  /// Backend message when present (`MessageFailure`), else a fixed fallback —
  /// same "backend text if we have it, else a friendly default" behavior the
  /// old direct-Dio code approximated via `e.message ?? fallback`, except this
  /// surfaces the server's actual `error`/`message` body instead of Dio's own
  /// generic exception description.
  String _messageFor(Failure failure, {required String fallback}) {
    if (failure is MessageFailure) return failure.message;
    return fallback;
  }

  void _cancelTimers() {
    _serverSyncTimer?.cancel();
    _serverSyncTimer = null;
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
  }

  void _ensureServerSync() {
    final id = _activeOrderId;
    if (id == null) return;
    _serverSyncTimer ??= Timer.periodic(_serverSyncInterval, (_) {
      final oid = _activeOrderId;
      if (oid != null) {
        fetchTimer(orderId: oid);
      }
    });
  }

  void _startUiTickIfRunning(TableTimerResponse? t) {
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
    // Clear any previously-ticked segment overlay so `effectiveSegments`
    // falls back to the fresh, server-frozen `billSegments` instead of a
    // stale live value frozen at the moment ticking stopped (e.g. right
    // before a pause) — `billSegments` itself is refreshed independently by
    // `_fetchBillDetails` and must not stay shadowed once ticking stops.
    if (!isClosed) {
      emit(state.copyWith(clearDisplaySegments: true));
    }
    if (t == null) return;
    if (t.stateNormalized != 'running') return;

    // Current segment's rate — only applied to seconds accrued *since* the
    // last sync, on top of `_baseAmount` (the server's already segment-priced
    // current_amount as of that sync). Never re-multiplies the whole
    // multi-segment elapsed time by this single rate.
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
  /// its server-frozen amount untouched. Anchored on `_lastBillDetailsFetchAt`
  /// (when segments were last fetched from `/bills/{id}`), reusing the same
  /// `computeAnchoredLiveAmount` helper as the total-amount tick above, just
  /// scoped to one row. Returns `null` when there's nothing to overlay
  /// (segments not loaded yet, or the last segment is already closed).
  List<TableSegment>? _tickLastSegment(double currentPrice) {
    final segs = state.billSegments;
    if (segs.isEmpty) return null;
    final last = segs.last;
    if (last.leftAt != null) return null;

    final syncAt = _lastBillDetailsFetchAt;
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

  void _applyTimer(TableTimerResponse t, {bool forceBillPauses = false}) {
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
        // Seed segments from `/table-timer`'s own `table_history` right away
        // — available on every poll with no extra round trip, unlike
        // `billSegments` which depends on the throttled `/bills/{id}` call
        // below succeeding. `_fetchBillDetails` overwrites this with the
        // fuller (possibly multi-session) breakdown once it lands; if that
        // call fails or returns nothing, this seed keeps the active-periods
        // dialog non-empty instead of showing nothing.
        billSegments: t.tableHistory.isNotEmpty ? t.tableHistory : null,
      ),
    );
    // Terminal yopiq holatda 60s polling shart emas — timer endi o'zgarmaydi.
    // Frozen state-ni faqat tasodifiy server tomonida tiklash uchun emas,
    // resurslarni tejash uchun ham polling to'xtatamiz.
    if (t.stateNormalized == 'closed') {
      _serverSyncTimer?.cancel();
      _serverSyncTimer = null;
    } else {
      _ensureServerSync();
    }
    _startUiTickIfRunning(t);
    // Bill API-dan pause_periods va table_sessions (active periods)ni yangilash
    _fetchBillDetails(force: forceBillPauses);
    // Table-map kartochkasi (TimeBasedTableBadge) shu yerdan darhol
    // xabardor bo'lishi uchun umumiy keshga yozamiz.
    final tid = (t.currentTableId?.isNotEmpty ?? false)
        ? t.currentTableId!
        : t.tableId;
    _syncService.publish(tid, t);
  }

  /// Bill API-dan pause_periods va table_sessions (active periods)ni olib
  /// state-ga yozadi. DetailBloc ham `/bills/{id}` chaqiradi — duplikat
  /// bo'lmasin uchun bir xil orderId uchun 60s ichida takroriy chaqiriq
  /// bloklanadi. `table_sessions[].segments` — bitta chronological ro'yxatga
  /// tekislanadi (`parseBillTableSessionsToSegments`, inside the repository),
  /// shu ro'yxat active periods dialogining yagona manbai (single source of
  /// truth): frozen segmentlar to'g'ridan-to'g'ri, oxirgi (ochiq) segment esa
  /// `_startUiTickIfRunning`'da live tick qo'shiladi.
  Future<void> _fetchBillDetails({bool force = false}) async {
    final orderId = _activeOrderId;
    if (orderId == null || orderId.isEmpty) return;

    // Throttle: oxirgi chaqiriq shu orderId uchun 60s ichida bo'lsa — o'tkazamiz
    if (!force &&
        _lastBillDetailsOrderId == orderId &&
        _lastBillDetailsFetchAt != null &&
        DateTime.now().difference(_lastBillDetailsFetchAt!) <
            _billPausesThrottle) {
      return;
    }
    _lastBillDetailsOrderId = orderId;
    _lastBillDetailsFetchAt = DateTime.now();

    final result = await _repository.getBillDetails(orderId);
    if (isClosed) return;
    // Stale: order almashgan bo'lsa — eski javobni tashlaymiz
    if (_activeOrderId != orderId) return;
    // Xatolik bo'lsa — jimgina o'tib ketamiz (mirrors the old silent catch-all)
    result.fold((_) {}, (details) {
      if (!isClosed) {
        emit(
          state.copyWith(
            billPauses: details.pauses ?? state.billPauses,
            // Only overwrite when the bill actually returned segments — an
            // empty/failed response must not wipe out the `table_history`
            // seed already emitted by `_applyTimer`.
            billSegments: details.segments.isNotEmpty
                ? details.segments
                : null,
          ),
        );
      }
    });
  }

  /// Buyurtma almashganda chaqiriladi. Timer faqat `dine_in` (yoki tur noma’lum) uchun so‘raladi.
  Future<void> bindOrder(OpenOrderModel? order) async {
    _cancelTimers();
    _activeOrderId = null;
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

    // `GET/POST .../table-timer` ikki holatda chaqiriladi:
    //   1) Stol time_based — live timer ko'rsatish uchun.
    //   2) Order time-based stoldan simple stolga ko'chirilgan va
    //      `table_amount` muzlatilgan — frozen UI ko'rsatish uchun.
    // Ikkalasi ham bo'lmasa, GET yubormaymiz (400 spam yo'q).
    if (!order.isTimeBasedTable && !order.hasFrozenTableAmount) {
      emit(const TableTimerState(shouldShow: false));
      return;
    }

    _activeOrderId = order.id;
    // Darhol 0:00 ko'rsat — API javobini kutmasdan
    emit(state.copyWith(shouldShow: true, displayActiveSec: 0));
    await fetchTimer(orderId: order.id, showLoading: false);
  }

  Future<void> fetchTimer({
    required String orderId,
    bool showLoading = false,
  }) async {
    _activeOrderId = orderId;
    // Pre-emit 0:00 immediately so UI shows something while waiting for API
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
        // Mirrors the old `e.response?.statusCode == 400 || 404` branch:
        // treated as "no timer here", not an error — hide silently.
        if (failure is NotFoundFailure || failure is ValidationFailure) {
          _cancelTimers();
          _activeOrderId = null;
          emit(
            state.copyWith(
              isLoading: false,
              shouldShow: false,
              clearTimer: true,
              clearDisplayActiveSec: true,
            ),
          );
          return;
        }
        // Mirrors the old non-DioException catch-all: malformed/unexpected
        // data is untrustworthy enough to hide the block, not just show an
        // inline error over stale state.
        if (failure is ParsingFailure || failure is UnknownFailure) {
          emit(
            state.copyWith(
              isLoading: false,
              shouldShow: false,
              clearTimer: true,
              clearDisplayActiveSec: true,
              errorMessage: _messageFor(
                failure,
                fallback: 'Table timer xatosi',
              ),
            ),
          );
          return;
        }
        // Other failures (connection/timeout/server/...): transient — keep
        // whatever's currently shown, just surface the error inline.
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: _messageFor(failure, fallback: 'Table timer xatosi'),
          ),
        );
      },
      (t) {
        if (t == null) {
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
        // Order time-based stoldan simple-ga ko'chirilgan bo'lsa, hozirgi
        // `table_type` `simple` keladi, lekin `state == closed` + `final_amount`
        // muzlatilgan summani saqlaydi. Bu holatda block-ni yashirmasdan
        // frozen UI ko'rsatish kerak.
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
      },
    );
  }

  /// Bo'sh order yaratadi va timerni boshlaydi (time-based free stol uchun).
  /// Returns orderId on success, null on failure.
  /// Agar server 409 qaytarsa ("stol allaqachon faol buyurtmaga ega"),
  /// xato xabaridan mavjud orderId'ni ajratib olib, shu ID bilan davom etadi —
  /// shunda foydalanuvchi takroriy 409 olmaydi.
  Future<String?> createTimedOrderAndStart({
    required String tableId,
    required int guestCount,
  }) async {
    _cancelTimers();
    _activeOrderId = null;
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
        // Missing orderId on an otherwise-successful create previously
        // failed silently (no error message) — `EmptyFailure` preserves that.
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
          // Timer holatini sinxronlaymiz — allaqachon ishlayotgan bo'lishi mumkin
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
    final result = await _repository.startTimer(id);
    if (isClosed || _activeOrderId != id) return;
    await result.fold(
      (failure) async {
        emit(
          state.copyWith(
            isMutating: false,
            errorMessage: _messageFor(failure, fallback: 'Start xatosi'),
          ),
        );
      },
      (t) async {
        if (t != null) {
          emit(state.copyWith(isMutating: false));
          _applyTimer(t, forceBillPauses: true);
        } else {
          await fetchTimer(orderId: id);
          await _fetchBillDetails(force: true);
        }
      },
    );
  }

  Future<void> pauseTimer() async {
    final id = _activeOrderId;
    if (id == null) return;
    emit(state.copyWith(isMutating: true, errorMessage: null));
    final result = await _repository.pauseTimer(id);
    if (isClosed || _activeOrderId != id) return;
    await result.fold(
      (failure) async {
        emit(
          state.copyWith(
            isMutating: false,
            errorMessage: _messageFor(failure, fallback: 'Pause xatosi'),
          ),
        );
      },
      (t) async {
        if (t != null) {
          emit(state.copyWith(isMutating: false));
          _applyTimer(t, forceBillPauses: true);
        } else {
          await fetchTimer(orderId: id);
          await _fetchBillDetails(force: true);
        }
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
    // Timer hali boshlanmagan → /start chaqiramiz
    if (state.timer == null || state.timer!.stateNormalized == 'none') {
      await startTimer();
      return;
    }
    emit(state.copyWith(isMutating: true, errorMessage: null));
    final result = await _repository.resumeTimer(id);
    if (isClosed || _activeOrderId != id) return;
    await result.fold(
      (failure) async {
        emit(
          state.copyWith(
            isMutating: false,
            errorMessage: _messageFor(failure, fallback: 'Resume xatosi'),
          ),
        );
      },
      (t) async {
        if (t != null) {
          emit(state.copyWith(isMutating: false));
          _applyTimer(t, forceBillPauses: true);
        } else {
          await fetchTimer(orderId: id);
          await _fetchBillDetails(force: true);
        }
      },
    );
  }

  @override
  Future<void> close() {
    _cancelTimers();
    return super.close();
  }
}
