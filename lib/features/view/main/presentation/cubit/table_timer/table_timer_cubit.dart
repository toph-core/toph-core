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
  Timer? _pollTimer;
  String? _activeOrderId;

  void _cancelPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _schedulePollIfRunning(TableTimerResponse? t) {
    _cancelPoll();
    if (t == null) return;
    if (t.stateNormalized != 'running') return;
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      final id = _activeOrderId;
      if (id != null) {
        fetchTimer(orderId: id);
      }
    });
  }

  /// Buyurtma almashganda chaqiriladi. Timer faqat `dine_in` (yoki tur noma’lum) uchun so‘raladi.
  Future<void> bindOrder(OpenOrderModel? order) async {
    _cancelPoll();
    _activeOrderId = null;

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

    _activeOrderId = order.id;
    await fetchTimer(orderId: order.id, showLoading: true);
  }

  Future<void> fetchTimer({
    required String orderId,
    bool showLoading = false,
  }) async {
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
        ));
        return;
      }
      final t = TableTimerResponse.fromJson(raw);
      if (!t.isTimeBasedTable) {
        emit(state.copyWith(
          isLoading: false,
          shouldShow: false,
          clearTimer: true,
        ));
        _cancelPoll();
        return;
      }
      emit(state.copyWith(
        isLoading: false,
        shouldShow: true,
        timer: t,
        errorMessage: null,
      ));
      _schedulePollIfRunning(t);
    } on DioException catch (e) {
      if (isClosed) return;
      if (e.response?.statusCode == 400 || e.response?.statusCode == 404) {
        emit(state.copyWith(
          isLoading: false,
          shouldShow: false,
          clearTimer: true,
        ));
        _cancelPoll();
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
        emit(state.copyWith(isMutating: false, timer: t, shouldShow: true));
        _schedulePollIfRunning(t);
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
        emit(state.copyWith(isMutating: false, timer: t));
        _schedulePollIfRunning(t);
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
    emit(state.copyWith(isMutating: true, errorMessage: null));
    try {
      final res = await _client.post(ListAPI.orderTableTimerResume(id));
      if (isClosed) return;
      final raw = res.data['data'];
      if (raw is Map<String, dynamic>) {
        final t = TableTimerResponse.fromJson(raw);
        emit(state.copyWith(isMutating: false, timer: t));
        _schedulePollIfRunning(t);
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
    _cancelPoll();
    return super.close();
  }
}
