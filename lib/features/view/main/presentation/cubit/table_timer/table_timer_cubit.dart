import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';

part 'table_timer_state.dart';

class TableTimerCubit extends Cubit<TableTimerState> {
  TableTimerCubit(this._client) : super(const TableTimerState());

  final DioClient _client;
  Timer? _serverSyncTimer;
  Timer? _uiTickTimer;
  String? _activeOrderId;
  int _baseTotalActiveSec = 0;
  DateTime? _lastSyncAt;

  static const Duration _serverSyncInterval = Duration(seconds: 60);

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
    if (t == null) return;
    if (t.stateNormalized != 'running') return;

    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final syncAt = _lastSyncAt;
      if (syncAt == null) return;
      final elapsed = DateTime.now().difference(syncAt).inSeconds;
      final display = _baseTotalActiveSec + (elapsed < 0 ? 0 : elapsed);
      if (!isClosed) {
        emit(state.copyWith(displayActiveSec: display));
      }
    });
  }

  void _applyTimer(TableTimerResponse t) {
    _lastSyncAt = DateTime.now();
    _baseTotalActiveSec = t.totalActiveSec;
    emit(state.copyWith(
      isLoading: false,
      shouldShow: true,
      timer: t,
      displayActiveSec: t.totalActiveSec,
      errorMessage: null,
    ));
    _ensureServerSync();
    _startUiTickIfRunning(t);
  }

  /// Buyurtma almashganda chaqiriladi. Timer faqat `dine_in` (yoki tur noma’lum) uchun so‘raladi.
  Future<void> bindOrder(OpenOrderModel? order) async {
    _cancelTimers();
    _activeOrderId = null;
    _lastSyncAt = null;
    _baseTotalActiveSec = 0;

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

    // `GET/POST .../table-timer` faqat `table_type == time_based` uchun.
    // `table_type` kelmasa yoki boshqa qiymat bo‘lsa — hech qanday murojaat qilinmaydi.
    if (!order.isTimeBasedTable) {
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
    if (showLoading) {
      emit(state.copyWith(isLoading: true, errorMessage: null));
    }
    try {
      final res = await _client.get(ListAPI.orderTableTimer(orderId));
      if (isClosed) return;
      final raw = res.data['data'];
      if (raw is! Map<String, dynamic>) {
        emit(state.copyWith(
          isLoading: false,
          shouldShow: false,
          clearTimer: true,
          clearDisplayActiveSec: true,
        ));
        return;
      }
      final t = TableTimerResponse.fromJson(raw);
      if (!t.isTimeBasedTable) {
        emit(state.copyWith(
          isLoading: false,
          shouldShow: false,
          clearTimer: true,
          clearDisplayActiveSec: true,
        ));
        _cancelTimers();
        return;
      }
      _applyTimer(t);
    } on DioException catch (e) {
      if (isClosed) return;
      if (e.response?.statusCode == 400 || e.response?.statusCode == 404) {
        // Timer hali boshlanmagan — 0:00 + Resume tugmani ko'rsat
        if (!isClosed) {
          emit(state.copyWith(
            isLoading: false,
            shouldShow: true,
            clearTimer: true,
            displayActiveSec: 0,
          ));
        }
        return;
      }
      emit(state.copyWith(
        isLoading: false,
        errorMessage: e.message ?? 'Table timer xatosi',
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        isLoading: false,
        shouldShow: false,
        clearTimer: true,
        clearDisplayActiveSec: true,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> startTimer() async {
    final id = _activeOrderId;
    if (id == null) return;
    emit(state.copyWith(isMutating: true, errorMessage: null));
    try {
      final res = await _client.post(ListAPI.orderTableTimerStart(id));
      if (isClosed) return;
      final raw = res.data['data'];
      if (raw is Map<String, dynamic>) {
        final t = TableTimerResponse.fromJson(raw);
        emit(state.copyWith(isMutating: false));
        _applyTimer(t);
      } else {
        await fetchTimer(orderId: id);
      }
    } on DioException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          isMutating: false,
          errorMessage: e.message ?? 'Start xatosi',
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(isMutating: false, errorMessage: e.toString()));
      }
    }
  }

  Future<void> pauseTimer() async {
    final id = _activeOrderId;
    if (id == null) return;
    emit(state.copyWith(isMutating: true, errorMessage: null));
    try {
      final res = await _client.post(ListAPI.orderTableTimerPause(id));
      if (isClosed) return;
      final raw = res.data['data'];
      if (raw is Map<String, dynamic>) {
        final t = TableTimerResponse.fromJson(raw);
        emit(state.copyWith(isMutating: false));
        _applyTimer(t);
      } else {
        await fetchTimer(orderId: id);
      }
    } on DioException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          isMutating: false,
          errorMessage: e.message ?? 'Pause xatosi',
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(isMutating: false, errorMessage: e.toString()));
      }
    }
  }

  Future<void> resumeTimer() async {
    final id = _activeOrderId;
    if (id == null) return;
    // Timer hali boshlanmagan → /start chaqiramiz
    if (state.timer == null || state.timer!.stateNormalized == 'none') {
      await startTimer();
      return;
    }
    emit(state.copyWith(isMutating: true, errorMessage: null));
    try {
      final res = await _client.post(ListAPI.orderTableTimerResume(id));
      if (isClosed) return;
      final raw = res.data['data'];
      if (raw is Map<String, dynamic>) {
        final t = TableTimerResponse.fromJson(raw);
        emit(state.copyWith(isMutating: false));
        _applyTimer(t);
      } else {
        await fetchTimer(orderId: id);
      }
    } on DioException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          isMutating: false,
          errorMessage: e.message ?? 'Resume xatosi',
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(isMutating: false, errorMessage: e.toString()));
      }
    }
  }

  @override
  Future<void> close() {
    _cancelTimers();
    return super.close();
  }
}
