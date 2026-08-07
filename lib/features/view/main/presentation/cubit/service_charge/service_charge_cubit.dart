import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

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
  final MainRepository _repository;
  final ConnectivityCubit _connectivity;

  ServiceChargeCubit(this._repository, this._connectivity)
      : super(const ServiceChargeState());

  /// Reads cache-first (via `MainRepositoryImpl`) — a branch offline at boot
  /// can still see its last-known service charge instead of a blank field.
  Future<void> load(String branchId) async {
    if (branchId.isEmpty) return;
    emit(state.copyWith(loading: true, error: null));
    final result = await _repository.getServiceCharge(branchId);
    result.fold(
      (failure) => emit(state.copyWith(loading: false, error: failure.toString())),
      (value) => emit(state.copyWith(value: value, loading: false)),
    );
  }

  /// Deliberately online-only, not queued — a single low-volume config
  /// value with no reason to add offline-write complexity (see
  /// offline-first-remediation-plan.md, Phase 4e). Fails fast with a clear
  /// reason when offline instead of attempting the write and surfacing a
  /// raw network error.
  Future<bool> save(String branchId, double value) async {
    if (branchId.isEmpty) return false;
    if (!_connectivity.isOnline) {
      emit(state.copyWith(
        saving: false,
        error: "Ulanish yo'q — o'zgartirish uchun internet talab qilinadi.",
      ));
      return false;
    }
    emit(state.copyWith(saving: true, error: null));
    final result = await _repository.saveServiceCharge(branchId, value);
    return result.fold(
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
}
