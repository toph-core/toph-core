part of 'table_timer_cubit.dart';

class TableTimerState {
  final TableTimerResponse? timer;
  final bool isLoading;
  final bool isMutating;
  final String? errorMessage;
  /// UI blokini ko‘rsatish: faqat `time_based` + muvaffaqiyatli javobdan keyin.
  final bool shouldShow;
  /// UI uchun lokal hisoblangan faol vaqt (sekund). `null` bo‘lsa `timer.totalActiveSec` ishlatiladi.
  final int? displayActiveSec;

  const TableTimerState({
    this.timer,
    this.isLoading = false,
    this.isMutating = false,
    this.errorMessage,
    this.shouldShow = false,
    this.displayActiveSec,
  });

  TableTimerState copyWith({
    TableTimerResponse? timer,
    bool clearTimer = false,
    bool? isLoading,
    bool? isMutating,
    Object? errorMessage = _sentinel,
    bool? shouldShow,
    int? displayActiveSec,
    bool clearDisplayActiveSec = false,
  }) {
    return TableTimerState(
      timer: clearTimer ? null : (timer ?? this.timer),
      isLoading: isLoading ?? this.isLoading,
      isMutating: isMutating ?? this.isMutating,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      shouldShow: shouldShow ?? this.shouldShow,
      displayActiveSec: clearDisplayActiveSec
          ? null
          : (displayActiveSec ?? this.displayActiveSec),
    );
  }
}

const _sentinel = Object();
