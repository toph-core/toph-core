part of 'table_timer_cubit.dart';

class TableTimerState {
  final TableTimerResponse? timer;
  final bool isLoading;
  final bool isMutating;
  final String? errorMessage;
  /// UI blokini ko'rsatish: faqat `time_based` + muvaffaqiyatli javobdan keyin.
  final bool shouldShow;
  /// UI uchun lokal hisoblangan faol vaqt (sekund). `null` bo'lsa `timer.totalActiveSec` ishlatiladi.
  final int? displayActiveSec;
  /// Bill API-dan kelgan pause_periods ro'yxati.
  final List<PauseInterval> billPauses;

  const TableTimerState({
    this.timer,
    this.isLoading = false,
    this.isMutating = false,
    this.errorMessage,
    this.shouldShow = false,
    this.displayActiveSec,
    this.billPauses = const [],
  });

  /// `pricePerHour` va `displayActiveSec` dan hisoblangan joriy summa (so'm).
  /// Timer API `current_amount` qaytarmasa ishlatiladi.
  String? get computedCurrentAmount {
    final priceStr = timer?.pricePerHour;
    if (priceStr == null || priceStr.isEmpty) return null;
    final price = double.tryParse(priceStr);
    if (price == null || price == 0) return null;
    final sec = displayActiveSec ?? timer?.totalActiveSec ?? 0;
    final amount = (sec / 3600.0) * price;
    // "10.28" formatida — payment screen shu formatni kutadi
    return amount.toStringAsFixed(2);
  }

  /// `timer.currentAmount` yoki hisoblangan summa.
  String? get effectiveCurrentAmount =>
      (timer?.currentAmount?.isNotEmpty == true)
          ? timer!.currentAmount
          : computedCurrentAmount;

  TableTimerState copyWith({
    TableTimerResponse? timer,
    bool clearTimer = false,
    bool? isLoading,
    bool? isMutating,
    Object? errorMessage = _sentinel,
    bool? shouldShow,
    int? displayActiveSec,
    bool clearDisplayActiveSec = false,
    List<PauseInterval>? billPauses,
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
      billPauses: billPauses ?? this.billPauses,
    );
  }
}

const _sentinel = Object();
