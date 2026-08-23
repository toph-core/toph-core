import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/service_charge_repository.dart';

class ServiceChargeState {
  final double? value;
  final bool loading;
  final bool saving;
  final String? error;

  const ServiceChargeState({
    this.value,
    this.loading = false,
    this.saving = false,
    this.error,
  });

  ServiceChargeState copyWith({
    Object? value = _sentinel,
    bool? loading,
    bool? saving,
    Object? error = _sentinel,
  }) {
    return ServiceChargeState(
      value: identical(value, _sentinel) ? this.value : value as double?,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

class ServiceChargeCubit extends Cubit<ServiceChargeState> {
  final ServiceChargeRepository _repository;
  StreamSubscription<double?>? _sub;

  ServiceChargeCubit(this._repository) : super(const ServiceChargeState());

  /// Local, and then live. The first value is a synchronous replica read, so
  /// the field is filled on the first frame with no spinner; the subscription
  /// keeps it current when the branch row is replicated in — an edit made on
  /// another terminal now lands here without a reload.
  Future<void> load(String branchId) async {
    if (branchId.isEmpty) return;
    emit(state.copyWith(value: _repository.getServicePercent(branchId), error: null));
    await _sub?.cancel();
    _sub = _repository.watchServicePercent(branchId).listen((value) {
      if (isClosed) return;
      // A save emits its own value below; this is for changes arriving from
      // elsewhere. Re-emitting an unchanged value would be harmless but noisy.
      if (value == state.value) return;
      emit(state.copyWith(value: value));
    });
  }

  /// Local write plus an outbox row, exactly like every other write in the app.
  ///
  /// This used to open with `if (!_connectivity.isOnline)` and refuse the edit
  /// — the one place in the product that made an operator find internet before
  /// they could change a setting. The justification was that a single config
  /// value did not merit offline-write machinery; the machinery already exists
  /// and this is one call into it, so the value stayed online-only out of
  /// habit rather than cost. `branches` replicates, so the edit is visible
  /// here immediately and reaches the server whenever the terminal next syncs.
  Future<bool> save(String branchId, double value) async {
    if (branchId.isEmpty) return false;
    emit(state.copyWith(saving: true, error: null));
    return _repository.saveServicePercent(branchId, value).fold(
      (failure) {
        emit(state.copyWith(saving: false, error: failure.toString()));
        return false;
      },
      (_) {
        emit(state.copyWith(value: value, saving: false));
        return true;
      },
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
