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

  /// UI uchun lokal hisoblangan joriy summa (so'm), oxirgi server
  /// `current_amount`'iga langar solingan holda har sekundda yangilanadi
  /// (`TableTimerCubit._startUiTickIfRunning`). `displayActiveSec` kabi
  /// faqat *yangi* sekundlarni joriy stol narxida qo'shadi — sessiya
  /// transferdan keyingi ko'p segmentli bo'lsa ham, eski segmentlarning
  /// narxini "unutib" butun vaqtni joriy narxda hisoblamaydi. `null` bo'lsa
  /// `computedCurrentAmount` eski (segmentga e'tibor bermaydigan) formulaga
  /// tushadi.
  final double? displayAmount;

  /// Bill API-dan kelgan pause_periods ro'yxati.
  final List<PauseInterval> billPauses;

  /// `/bills/{id}`'ning `table_sessions[].segments`idan tekislangan,
  /// server-avtoritar (frozen) segmentlar ro'yxati — active periods
  /// dialogining yagona manbai (single source of truth).
  final List<TableSegment> billSegments;

  /// `billSegments`ning oxirgi (hali yopilmagan) elementiga har sekundda
  /// live tick qo'shilgan versiyasi (`TableTimerCubit._tickLastSegment`).
  /// `null` bo'lsa `billSegments` o'zi ko'rsatiladi (masalan hali fetch
  /// bo'lmagan yoki timer running emas holatda).
  final List<TableSegment>? displaySegments;

  const TableTimerState({
    this.timer,
    this.isLoading = false,
    this.isMutating = false,
    this.errorMessage,
    this.shouldShow = false,
    this.displayActiveSec,
    this.displayAmount,
    this.billPauses = const [],
    this.billSegments = const [],
    this.displaySegments,
  });

  /// Active periods dialogi uchun ko'rsatiladigan segmentlar — live tick
  /// mavjud bo'lsa shuni, aks holda server-frozen ro'yxatni qaytaradi.
  List<TableSegment> get effectiveSegments => displaySegments ?? billSegments;

  /// `displayAmount` mavjud bo'lsa — shu (server `current_amount`'iga
  /// langar solingan, segment narxlarini hisobga oladigan) qiymatni
  /// qaytaradi. Aks holda `pricePerHour` va `displayActiveSec` dan
  /// hisoblangan summaga tushadi — bu formula sessiya bitta segmentdan
  /// iborat bo'lgandagina to'g'ri (transferdan keyin ko'p segment bo'lsa,
  /// butun vaqtni joriy stol narxida hisoblab noto'g'ri natija beradi).
  String? get computedCurrentAmount {
    if (displayAmount != null) return displayAmount!.toStringAsFixed(2);
    final priceStr = timer?.pricePerHour;
    if (priceStr == null || priceStr.isEmpty) return null;
    final price = double.tryParse(priceStr);
    if (price == null || price == 0) return null;
    final sec = displayActiveSec ?? timer?.totalActiveSec ?? 0;
    final amount = (sec / 3600.0) * price;
    // "10.28" formatida — payment screen shu formatni kutadi
    return amount.toStringAsFixed(2);
  }

  /// Timer yopilgan (`closed`) va muzlatilgan summa mavjudmi.
  /// `true` bo'lsa UI yangi vaqt qo'shmasligi, lekin saqlangan summani
  /// statik ko'rsatishi kerak.
  ///
  /// Also treat closed sessions with `current_amount` / active seconds as
  /// frozen — a failed `/pay` can close the timer without `final_amount`.
  bool get isFrozen {
    final t = timer;
    if (t == null) return false;
    if (!t.isFrozenClosed) return false;
    if (parseAmountToInt(t.finalAmount) > 0) return true;
    if (parseAmountToInt(t.currentAmount) > 0) return true;
    return t.totalActiveSec > 0;
  }

  /// Muzlatilgan summa integer som sifatida (UI total uchun).
  int get frozenAmountInt {
    final t = timer;
    if (t == null) return 0;
    final fin = parseAmountToInt(t.finalAmount);
    if (fin > 0) return fin;
    return parseAmountToInt(t.currentAmount);
  }

  /// Ko'rsatish uchun samarali summa.
  /// Frozen bo'lsa `finalAmount`, running bo'lsa lokal hisoblangan (UI har
  /// sekundda yangilanishi uchun), aks holda server `currentAmount`.
  String? get effectiveCurrentAmount {
    final t = timer;
    if (t != null && t.isFrozenClosed) {
      final fin = t.finalAmount;
      if (fin != null && fin.isNotEmpty && parseAmountToInt(fin) > 0) return fin;
      if (t.currentAmount?.isNotEmpty == true) return t.currentAmount;
    }
    // Running paytda server `currentAmount` 60s syncgacha eskirib qoladi —
    // displayActiveSec asosida lokal hisoblanganini afzal ko'ramiz.
    if (t?.stateNormalized == 'running') {
      final computed = computedCurrentAmount;
      if (computed != null) return computed;
    }
    if (t?.currentAmount?.isNotEmpty == true) return t!.currentAmount;
    return computedCurrentAmount;
  }

  TableTimerState copyWith({
    TableTimerResponse? timer,
    bool clearTimer = false,
    bool? isLoading,
    bool? isMutating,
    Object? errorMessage = _sentinel,
    bool? shouldShow,
    int? displayActiveSec,
    bool clearDisplayActiveSec = false,
    double? displayAmount,
    bool clearDisplayAmount = false,
    List<PauseInterval>? billPauses,
    List<TableSegment>? billSegments,
    List<TableSegment>? displaySegments,
    bool clearDisplaySegments = false,
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
      displayAmount: clearDisplayAmount
          ? null
          : (displayAmount ?? this.displayAmount),
      billPauses: billPauses ?? this.billPauses,
      billSegments: billSegments ?? this.billSegments,
      displaySegments: clearDisplaySegments
          ? null
          : (displaySegments ?? this.displaySegments),
    );
  }
}

const _sentinel = Object();
