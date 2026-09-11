import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/pricing/order_totals.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/payment_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/service_charge_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';

part 'payment_event.dart';
part 'payment_state.dart';
part 'payment_bloc.freezed.dart';

/// offline-first-target-architecture.md §4/§9 (V2/V6) + §12 rule 1.
///
/// Every write here (`pay`/cancel-zero-total) is a single local commit
/// through `PaymentRepository` (outbox enqueue) that returns without ever
/// awaiting the network — the highest-stakes write in this app gets the
/// same shape every other local-first write does, no `ConnectionFailure`
/// fork. Reads (`_onGetDetail`) are a pure `OrdersRepository.watchOrderDetail`
/// projection — no throttle, no `ConnectivityCubit` gate, no awaited
/// fetch usecase; whatever `SyncEngine`'s hydration pass or this terminal's
/// own local writes last put in `LocalDatabase` is what's shown, online or
/// offline alike.
class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  final OrdersRepository _ordersRepository;
  final PaymentRepository _paymentRepository;
  final PrinterService _printerService;
  final ServiceChargeRepository _serviceChargeRepository;

  StreamSubscription<ArchiveDetailModel?>? _detailSub;

  DateTime? _timerStartedAt;
  List<PauseInterval> _timerPauses = const [];
  int _timerTotalSec = 0;
  String? _timerPricePerHour;

  /// Branch service percent handed over at navigation time, used when the
  /// order detail itself reports 0. Carried as a plain field rather than in
  /// `PaymentState` for the same reason the timer info above is: adding a
  /// freezed field would mean regenerating `payment_bloc.freezed.dart`.
  double _servicePercent = 0;

  // Public read-only getters for UI (preview modal)
  DateTime? get timerStartedAt => _timerStartedAt;
  List<PauseInterval> get timerPauses => _timerPauses;
  int get timerTotalSec => _timerTotalSec;
  String? get timerPricePerHour => _timerPricePerHour;
  double get servicePercent => _servicePercent;

  /// The percent applied when neither the bill nor the branch names one, so a
  /// service fee is always present and charged rather than silently dropped.
  static const double kDefaultServicePercent = 20;

  /// Resolves the service percent for this bill and stores it on the bloc.
  ///
  /// Three tiers, in the order the money actually depends on: the percent
  /// frozen onto the bill when it was created ([fromArgs]) wins, because a bill
  /// must keep charging what it was opened at even if the branch setting
  /// changes underneath it; then the branch's configured percent; then
  /// [kDefaultServicePercent].
  ///
  /// This lived in `PaymentScreen`, which reached `ServiceChargeRepository`
  /// out of the service locator from inside a widget — the §7 guardrail
  /// `architecture_guard_test.dart` exists to prevent. [branchId] is passed in
  /// rather than resolved here because the bloc has no session of its own, and
  /// a bloc that reads the repository is the point of the rule; a bloc that
  /// takes an id is not.
  void resolveServicePercent({
    required double fromArgs,
    required String branchId,
  }) {
    if (fromArgs > 0) {
      _servicePercent = fromArgs;
      return;
    }
    final configured = branchId.isEmpty
        ? 0.0
        : (_serviceChargeRepository.getServicePercent(branchId) ?? 0.0);
    _servicePercent = configured > 0 ? configured : kDefaultServicePercent;
  }

  void setTimerInfo({
    DateTime? startedAt,
    List<PauseInterval> pauses = const [],
    int totalSec = 0,
    String? pricePerHour,
  }) {
    _timerStartedAt = startedAt;
    _timerPauses = pauses;
    _timerTotalSec = totalSec;
    _timerPricePerHour = pricePerHour;
  }

  PaymentBloc({
    required OrdersRepository ordersRepository,
    required PaymentRepository paymentRepository,
    required PrinterService printerService,
    required ServiceChargeRepository serviceChargeRepository,
  })  : _ordersRepository = ordersRepository,
        _paymentRepository = paymentRepository,
        _printerService = printerService,
        _serviceChargeRepository = serviceChargeRepository,
        super(const PaymentState()) {
    on<_Started>(_onStarted);
    on<_GetDetail>(_onGetDetail);
    on<_DetailUpdated>(_onDetailUpdated);
    on<_UpdatePaymentType>(_onUpdatePaymentType);
    on<_UpdateEnterSum>(_onUpdateEnterSum);
    on<_Payment>(_payment);
    on<_DiscountType>(_updateDiscountType);
    on<_UpdateDiscountAmount>(_updateDiscountAmount);
    on<_UpdateHourPrice>(_updateHourPrice);
    on<_UpdateApplyService>(_updateApplyService);
  }

  void _updateApplyService(_UpdateApplyService event, emit) {
    emit(state.copyWith(applyService: event.applyService));
  }

  void _updateHourPrice(_UpdateHourPrice event, emit) {
    // enterSum ni ham yangilash — agar kassir hali o'zgartirmagan bo'lsa
    final detail = state.detail;
    String? newEnterSum;
    if (detail != null) {
      final oldExpected = totals(detail: detail).grandTotal;
      final newExpected =
          totals(detail: detail, tableCharge: event.hourPrice).grandTotal;
      final currentEntered = int.tryParse(state.enterSum) ?? 0;
      if (currentEntered == 0 || currentEntered == oldExpected) {
        newEnterSum = newExpected.toString();
      }
    }
    emit(state.copyWith(
      hourPrice: event.hourPrice,
      enterSum: newEnterSum ?? state.enterSum,
    ));
  }

  void _updateDiscountAmount(_UpdateDiscountAmount event, emit) {
    final raw = event.amount;
    if (raw.startsWith('numpad:')) {
      final symbol = raw.substring(7);
      String current = state.discountAmount == '0' ? '' : state.discountAmount;
      if (symbol == '⌫') {
        current = current.isEmpty ? '' : current.substring(0, current.length - 1);
      } else if (symbol == '00') {
        if (current.isNotEmpty) current += '00';
      } else if (current.isEmpty && symbol == '0') {
        current = '';
      } else {
        current += symbol;
      }
      emit(state.copyWith(discountAmount: current.isEmpty ? '0' : current));
    } else {
      emit(state.copyWith(discountAmount: raw.isEmpty ? '0' : raw));
    }
  }

  void _updateDiscountType(_DiscountType event, emit) =>
      emit(state.copyWith(discountType: event.dicountType));

  void _payment(_Payment event, Emitter<PaymentState> emit) async {
    final detail = state.detail;
    if (detail == null) return;
    final enteredAmt = int.tryParse(state.enterSum) ?? 0;
    // Exactly the number the cashier is looking at — see [totals].
    final due = totals();
    final dueTot = due.grandTotal;
    final cashNeedsAmount =
        state.paymentType == PaymentType.cash && enteredAmt <= 0 && dueTot > 0;
    if (cashNeedsAmount) return;

    // Cash sends entered amount; card/qr send the computed due total.
    final paidAmount =
        state.paymentType == PaymentType.cash ? enteredAmt : dueTot;

    emit(state.copyWith(status: Status.LOADING));

    final effectiveTableId = state.tableId ?? detail.tableId;

    // Total 0 bo'lsa — /pay emas /cancel. Local-first: bitta lokal yozuv,
    // hech qachon tarmoqni kutmaydi (§4).
    if (dueTot <= 0) {
      // A 0 total is a comp only when the bill genuinely has nothing on it.
      // Reaching 0 because a charge failed to *load* is indistinguishable
      // from a real comp by the time we get here, and the difference is a
      // whole session's revenue: a time-billed table pushed from the archive
      // sider arrives with no `hour_amount`, so a pure-time bill priced at 0
      // and was written off silently, receipt and all. Anything indicating
      // billable content therefore refuses rather than comps.
      final hasLiveGoods = detail.goods.any((g) => g.status != 'cancelled');
      final hasTableTime = state.hourPrice > 0.01 ||
          _timerTotalSec > 0 ||
          _timerStartedAt != null;
      if (hasLiveGoods || hasTableTime) {
        emit(state.copyWith(status: Status.ERROR));
        showErrorMessage(
          navigatorKey.currentContext!,
          "Chek summasi 0 ko'rinmoqda, lekin unda hisoblanadigan pozitsiya "
          "yoki stol vaqti bor. Ekranni yangilab qayta urinib ko'ring.",
        );
        return;
      }
      await _paymentRepository.cancelZeroTotalOrder(
        orderId: detail.id,
        tableId: effectiveTableId,
      );
      _paymentSucceeded = true;
      _onPaymentSuccess(detail, due);
      return;
    }

    final discountAmount = state.discountType == DiscountType.money
        ? (int.tryParse(state.discountAmount) ?? 0)
        : 0;
    final discountPercent = state.discountType == DiscountType.percent
        ? (int.tryParse(state.discountAmount) ?? 0)
        : 0;

    await _paymentRepository.pay(
      orderId: detail.id,
      tableId: effectiveTableId,
      paidAmount: paidAmount,
      paymentType: state.paymentType.name,
      applyService: state.applyService,
      discountAmount: discountAmount,
      discountPercent: discountPercent,
      tableCharge: due.tableCharge,
      // The same object the receipt below is printed from, so the row the
      // repository closes the bill on carries the figures the customer was
      // just handed rather than zeros until the payment syncs.
      settled: due,
    );
    showSuccessMessage(
      navigatorKey.currentContext!,
      "To'lov navbatga qo'shildi — internet kelganda yuboriladi",
    );
    _paymentSucceeded = true;
    _onPaymentSuccess(detail, due);
  }

  bool _paymentSucceeded = false;
  bool get paymentSucceeded => _paymentSucceeded;

  /// After a cancelled pay attempt (leaving the screen without paying),
  /// resume the table timer so accrued time is not left paused. Never start
  /// a fresh session — that would reset accrued time to 0.
  /// CLIENT_FACING_OFFLINE_PLAN.md §2/§6: a pure local operation now — the
  /// local timer record is read and, if paused, resumed through the same
  /// local-write-plus-outbox path every other timer mutation uses.
  Future<void> resumeTimerAfterFailedPay() async {
    if (_paymentSucceeded) return;
    final orderId = state.detail?.id ?? state.orderId;
    if (orderId == null || orderId.isEmpty) return;
    if (state.hourPrice <= 0 && _timerTotalSec <= 0 && _timerStartedAt == null) {
      return;
    }
    try {
      final timerRepo = inject<TableTimerLocalRepository>();
      final t = (await timerRepo.getTimer(orderId)).fold((_) => null, (r) => r);
      if (t?.stateNormalized == 'paused') {
        await timerRepo.resumeTimer(orderId);
      }
      // closed / none / running — leave as-is; starting fresh would wipe time.
    } catch (_) {
      // Best-effort — detail screen re-reads the local timer on return.
    }
  }

  /// [detail] is the bill as it stood when the cashier pressed pay, captured by
  /// [_payment] before the write rather than re-read from state here.
  ///
  /// The write closes the bill in the replica synchronously, and the detail
  /// subscription re-reads immediately — so `state.detail` is no longer a safe
  /// source for the receipt on this path. (`_onDetailUpdated` also holds the
  /// last known bill for the screen's sake; this makes the receipt independent
  /// of that, because a receipt printed from the wrong bill is not a cosmetic
  /// failure.)
  ///
  /// [due] is the same `OrderTotals` the payment was charged from, handed to
  /// the receipt so the paper shows the figures the customer just paid —
  /// service fee included. Re-deriving them from [detail] printed a receipt
  /// with no service line, because the fee is written onto the order row by
  /// the backend at settle time and this row has not been settled yet.
  void _onPaymentSuccess(ArchiveDetailEntity detail, OrderTotals due) {
    final discPct = state.discountType == DiscountType.percent
        ? (int.tryParse(state.discountAmount) ?? 0).toDouble()
        : 0.0;
    final discAmt = state.discountType == DiscountType.money
        ? (int.tryParse(state.discountAmount) ?? 0).toDouble()
        : 0.0;
    _printerService.printCashierReceiptFromDetail(
      detail: detail,
      hourAmount: state.hourPrice,
      discountPercent: discPct,
      discountAmount: discAmt,
      totals: due,
      servicePercent: _servicePercent,
      timerStartedAt: _timerStartedAt,
      timerPauses: _timerPauses,
      timerTotalSec: _timerTotalSec,
      timerPricePerHour: _timerPricePerHour,
    );
    // The order is closed — drop its local timer record so a stale timer
    // doesn't linger for the next order on this table (plan §2; the server
    // closes its own timer when the queued /pay lands).
    final paidOrderId = detail.id;
    if (paidOrderId.isNotEmpty) {
      unawaited(inject<TableTimerLocalRepository>().evictTimer(paidOrderId));
    }
    final mainCubit = navigatorKey.currentContext!.read<MainCubit>();
    // Occupancy stays where it already lived: the `_table_status` overlay, via
    // MainCubit → TablesRepository. It is local authority and durable, so the
    // table is free across a restart — and it is deliberately NOT rewritten by
    // the payment repository, which would put a second writer on the same fact.
    // What changed is that the `orders` row now agrees with it.
    final effectiveTableId = state.tableId ?? detail.tableId;
    if (effectiveTableId.isNotEmpty) {
      mainCubit.broadcastTableStatus(effectiveTableId, TableStatus.free);
      // Order is fully paid off — any leftover local draft for this table
      // (uncommitted cart items) is stale now and must not resurface next
      // time the table is opened.
      navigatorKey.currentContext!.read<SavedOrdersBloc>().add(
        SavedOrdersEvent.removeOrder(tableId: effectiveTableId),
      );
    }
    Navigator.pushNamedAndRemoveUntil(
      navigatorKey.currentContext!,
      AppRoutes.mainScreen,
      (value) => true,
    );
    // §5: fire-and-forget — an explicit "make sure this is fresh" nudge,
    // not something this success path waits on.
    mainCubit.refreshTables(force: true);
  }

  /// The authoritative payment total, assembled in exactly one place.
  ///
  /// The payment screen renders this and [_payment] charges it. They used to
  /// build their own totals from different subsets of the same state — the
  /// screen passed the discount, the service toggle and the branch service
  /// percent; the pay path passed none of them — so a card or QR payment
  /// charged the *undiscounted, service-included* amount while the cashier
  /// looked at the discounted one. One assembly point makes that class of
  /// divergence unrepresentable rather than merely fixed.
  ///
  /// [detail] and [tableCharge] override state only for callers that need to
  /// price a value not committed to state yet (a detail still in flight, or a
  /// prospective table charge being compared against the current one).
  OrderTotals totals({ArchiveDetailEntity? detail, double? tableCharge}) {
    final target = detail ?? state.detail;
    if (target == null) return OrderTotals.compute(itemsAmount: 0);
    return OrderTotals.forPayment(
      detail: target,
      tableCharge: tableCharge ?? state.hourPrice,
      servicePercent: _servicePercent,
      discountType: state.discountType,
      discountRaw: state.discountAmount,
      includeService: state.applyService,
    );
  }

  Future<void> _onStarted(_Started event, emit) async {
    emit(
      PaymentState(
        tableId: event.tableId,
        orderId: event.orderId,
        textController: TextEditingController(),
        status: Status.LOADING,
        detailStatus: Status.LOADING,
      ),
    );
    add(const PaymentEvent.getDetail());
  }

  /// Both halves of the bill's identity, in the order they are tried.
  ///
  /// The table key was the only one used here, and it resolves through
  /// `OrderDetailQuery.liveOrderForTable` — the *live*-bill predicate. So any
  /// bill that had already left that predicate (settled on this terminal,
  /// settled on another terminal and pulled in, or comped) resolved to null
  /// on every emission, and this screen's only render gate is
  /// `state.detail != null`: the cashier got a spinner that could never
  /// finish, on a check they were trying to close. The order key resolves
  /// through `liveOrderById`, which deliberately applies no bill-status
  /// filter, so it still finds that row.
  List<String?> get _detailKeys => [state.tableId, state.orderId];

  Future<void> _onGetDetail(
    _GetDetail event,
    Emitter<PaymentState> emit,
  ) async {
    final keys = _detailKeys.where((k) => k != null && k.isNotEmpty).toList();
    if (keys.isEmpty) {
      // Neither key was handed over — nothing to watch, and no later
      // emission will change that. Say so rather than spinning forever.
      emit(state.copyWith(status: Status.ERROR, detailStatus: Status.ERROR));
      return;
    }

    await _detailSub?.cancel();
    _detailSub = _ordersRepository.watchOrderDetailForAny(keys).listen((detail) {
      if (isClosed) return;
      add(PaymentEvent.detailUpdated(detail: detail));
    });
    unawaited(_hydrateTableChargeFromLocalTimer());
  }

  /// The table charge, recovered from the local timer when the caller did not
  /// hand one over.
  ///
  /// Only `order_actions_bar` passes `hour_amount`; the archive sider and
  /// `create_order_bloc` push this screen with `order_id` alone. The fallback
  /// that was supposed to cover them is dead code — `HourPriceEvent.started`
  /// is declared and handled but dispatched from nowhere in `lib/`, so the
  /// listener in `payment_screen` never fires and the charge stayed 0.
  ///
  /// Stored amounts only: `finalAmount` once the timer is frozen, otherwise
  /// `currentAmount`. The per-second accrual `TableTimerState` renders is a
  /// display refinement and is deliberately not reproduced here — this needs
  /// to be right, not live.
  Future<void> _hydrateTableChargeFromLocalTimer() async {
    if (state.hourPrice > 0.01) return;
    final orderId = state.orderId ?? state.detail?.id;
    if (orderId == null || orderId.isEmpty) return;
    try {
      final timerRepo = inject<TableTimerLocalRepository>();
      final t = (await timerRepo.getTimer(orderId)).fold((_) => null, (r) => r);
      if (t == null || isClosed) return;
      final frozen = parseAmountToInt(t.finalAmount);
      final amount = frozen > 0 ? frozen : parseAmountToInt(t.currentAmount);
      if (amount <= 0) return;
      add(PaymentEvent.upadeHourPrice(hourPrice: amount.toDouble()));
    } catch (_) {
      // Best-effort — a missing local timer must never block settling a bill.
    }
  }

  void _onDetailUpdated(_DetailUpdated event, Emitter<PaymentState> emit) {
    final detail = event.detail;
    if (detail == null) {
      // Two different nulls, and only one of them means "nothing yet".
      //
      // Before the bill exists locally, null is exactly that: the replica has
      // no row for this key and the stream will fire again the instant it
      // does. But a dine-in payment screen watches by *table id*, and
      // `liveOrderForTable` stops matching the moment the bill closes — which
      // is now the moment the cashier pays, not a pull later. So a null that
      // arrives after a bill was already on screen is the settled bill leaving
      // the open-bill read, and blanking the screen on it would take the
      // receipt away from under the cashier mid-payment. The last known bill
      // is held instead; it is the one this screen exists to settle, and the
      // screen is about to be popped anyway.
      if (state.detail != null) return;
      // Nothing is in flight to wait for. This is a synchronous read of the
      // local replica, which is this app's authority on what bills exist, so
      // a null on the first emission is an answer — "no bill under either
      // key" — not a stage on the way to one. Rendering it as LOADING is what
      // turned a missing bill into a spinner with no end and no way out; the
      // subscription stays open, so a bill that does turn up later still
      // lands on screen.
      emit(state.copyWith(
        status: Status.ERROR,
        detailStatus: Status.ERROR,
        failure: null,
        detail: null,
      ));
      return;
    }
    final prefill = totals(detail: detail).grandTotal;
    final currentEntered = int.tryParse(state.enterSum) ?? 0;
    // Prefill when empty, OR when enterSum is still the stale under-total
    // (old formula omitted service on table charge).
    final shouldPrefill = currentEntered <= 0 ||
        currentEntered == prefill ||
        (state.hourPrice > 0.01 && currentEntered < prefill);
    // Item timestamps are no longer carried in state: every replica
    // `order_items` row has its own `created_at` — the server's for a synced
    // line, the terminal's for one rung in offline — so the screen reads it
    // off the line itself instead of a name-keyed side map.
    emit(state.copyWith(
      status: Status.SUCCESS,
      detailStatus: Status.SUCCESS,
      detail: detail,
      enterSum: shouldPrefill ? prefill.toString() : state.enterSum,
      failure: null,
    ));
  }

  void _onUpdatePaymentType(
    _UpdatePaymentType event,
    Emitter<PaymentState> emit,
  ) => emit(state.copyWith(paymentType: event.paymentType));

  void _onUpdateEnterSum(_UpdateEnterSum event, Emitter<PaymentState> emit) {
    // "set:12345" — to'g'ridan-to'g'ri qiymat o'rnatish
    if (event.symbol.startsWith('set:')) {
      emit(state.copyWith(enterSum: event.symbol.substring(4)));
      return;
    }

    String newEnterSum = state.enterSum;
    if (event.symbol == "⌫") {
      if (newEnterSum.isNotEmpty) {
        newEnterSum = newEnterSum.substring(0, newEnterSum.length - 1);
      }
    } else {
      if (newEnterSum == "0" && event.symbol == "00") {
        newEnterSum = "0";
      } else if (newEnterSum == "0" && event.symbol != "0") {
        newEnterSum = event.symbol;
      } else {
        newEnterSum += event.symbol;
      }
    }
    emit(state.copyWith(enterSum: newEnterSum));
  }

  @override
  Future<void> close() {
    _detailSub?.cancel();
    state.textController?.dispose();
    return super.close();
  }
}
