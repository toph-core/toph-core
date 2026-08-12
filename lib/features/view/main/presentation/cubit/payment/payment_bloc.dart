import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
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

  void setServicePercent(double percent) => _servicePercent = percent;

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
  })  : _ordersRepository = ordersRepository,
        _paymentRepository = paymentRepository,
        _printerService = printerService,
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
    on<_ItemTimestampsLoaded>(_onItemTimestampsLoaded);
    on<_UpdateApplyService>(_updateApplyService);
  }

  void _onItemTimestampsLoaded(
    _ItemTimestampsLoaded event,
    Emitter<PaymentState> emit,
  ) {
    emit(state.copyWith(itemTimestamps: event.timestamps));
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
    if (state.detail == null) return;
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

    final effectiveTableId = state.tableId ?? state.detail!.tableId;

    // Total 0 bo'lsa — /pay emas /cancel. Local-first: bitta lokal yozuv,
    // hech qachon tarmoqni kutmaydi (§4).
    if (dueTot <= 0) {
      await _paymentRepository.cancelZeroTotalOrder(
        orderId: state.detail!.id,
        tableId: effectiveTableId,
      );
      _paymentSucceeded = true;
      _onPaymentSuccess();
      return;
    }

    final discountAmount = state.discountType == DiscountType.money
        ? (int.tryParse(state.discountAmount) ?? 0)
        : 0;
    final discountPercent = state.discountType == DiscountType.percent
        ? (int.tryParse(state.discountAmount) ?? 0)
        : 0;

    await _paymentRepository.pay(
      orderId: state.detail!.id,
      tableId: effectiveTableId,
      paidAmount: paidAmount,
      paymentType: state.paymentType.name,
      applyService: state.applyService,
      discountAmount: discountAmount,
      discountPercent: discountPercent,
      tableCharge: due.tableCharge,
    );
    showSuccessMessage(
      navigatorKey.currentContext!,
      "To'lov navbatga qo'shildi — internet kelganda yuboriladi",
    );
    _paymentSucceeded = true;
    _onPaymentSuccess();
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

  void _onPaymentSuccess() {
    final discPct = state.discountType == DiscountType.percent
        ? (int.tryParse(state.discountAmount) ?? 0).toDouble()
        : 0.0;
    final discAmt = state.discountType == DiscountType.money
        ? (int.tryParse(state.discountAmount) ?? 0).toDouble()
        : 0.0;
    _printerService.printCashierReceiptFromDetail(
      detail: state.detail!,
      hourAmount: state.hourPrice,
      discountPercent: discPct,
      discountAmount: discAmt,
      timerStartedAt: _timerStartedAt,
      timerPauses: _timerPauses,
      timerTotalSec: _timerTotalSec,
      timerPricePerHour: _timerPricePerHour,
    );
    // The order is closed — drop its local timer record so a stale timer
    // doesn't linger for the next order on this table (plan §2; the server
    // closes its own timer when the queued /pay lands).
    final paidOrderId = state.detail?.id;
    if (paidOrderId != null && paidOrderId.isNotEmpty) {
      unawaited(inject<TableTimerLocalRepository>().evictTimer(paidOrderId));
    }
    final mainCubit = navigatorKey.currentContext!.read<MainCubit>();
    final effectiveTableId = state.tableId ?? state.detail?.tableId;
    if (effectiveTableId != null && effectiveTableId.isNotEmpty) {
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

  /// Sums the cost of any not-yet-synced `addItems` ops queued for
  /// [tableId] — the due total must include items already committed locally
  /// (§4) even though the backend doesn't know about them yet.
  static int pendingOfflineExtra(String? tableId) {
    if (tableId == null) return 0;
    final queue = inject<OfflineQueueService>();
    final cachedGoods = inject<CacheService>().getGoods();
    int extra = 0;
    for (final op in queue.pending.where(
      (o) => o.tableId == tableId && o.type == PendingOperationType.addItems,
    )) {
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        final items = payload['items'] as List<dynamic>;
        for (final item in items) {
          final goodId = item['good_id'] as String;
          final qty = (item['quantity'] as num).toInt();
          final goodJson = cachedGoods.firstWhere(
            (g) => g['id'] == goodId,
            orElse: () => <String, dynamic>{},
          );
          if (goodJson.isEmpty) continue;
          final price =
              double.tryParse(goodJson['price']?.toString() ?? '0') ?? 0.0;
          extra += (price * qty).toInt();
        }
      } catch (_) {}
    }
    return extra;
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
      offlineExtra: pendingOfflineExtra(state.tableId).toDouble(),
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

  Future<void> _onGetDetail(
    _GetDetail event,
    Emitter<PaymentState> emit,
  ) async {
    final key = state.tableId ?? state.orderId;
    if (key == null) return;

    await _detailSub?.cancel();
    _detailSub = _ordersRepository.watchOrderDetail(key).listen((detail) {
      if (isClosed) return;
      add(PaymentEvent.detailUpdated(detail: detail));
    });
  }

  void _onDetailUpdated(_DetailUpdated event, Emitter<PaymentState> emit) {
    final detail = event.detail;
    if (detail == null) {
      // Nothing in LocalDatabase yet for this key — SyncEngine's hydration
      // pass (or this order's own local-first create) hasn't landed a row
      // here yet. Not an error: the stream will fire again the instant it
      // does.
      emit(state.copyWith(detailStatus: Status.LOADING, failure: null, detail: null));
      return;
    }
    final cachedTs = inject<CacheService>().getItemTimestamps(detail.id);
    final prefill = totals(detail: detail).grandTotal;
    final currentEntered = int.tryParse(state.enterSum) ?? 0;
    // Prefill when empty, OR when enterSum is still the stale under-total
    // (old formula omitted service on table charge).
    final shouldPrefill = currentEntered <= 0 ||
        currentEntered == prefill ||
        (state.hourPrice > 0.01 && currentEntered < prefill);
    // CLIENT_FACING_OFFLINE_PLAN.md §6: item timestamps are a pure local
    // read now — `OrdersRepositoryImpl` records `name -> earliestCreatedAt`
    // into the same cache at the moment items are committed locally, so the
    // unconditional `/order-items` network fetch that used to fire on every
    // detail update is gone. Items added by other terminals before that
    // capture existed simply show no timestamp until a future sync-side
    // hydration fills them (see EXECUTION_CONCERNS.md).
    emit(state.copyWith(
      status: Status.SUCCESS,
      detailStatus: Status.SUCCESS,
      detail: detail,
      itemTimestamps: cachedTs,
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
