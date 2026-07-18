import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/utils/order_totals.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/payment_pay_request/payment_pay_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_payment_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_payment_detail_with_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_payment_detail_with_table_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';

part 'payment_event.dart';
part 'payment_state.dart';
part 'payment_bloc.freezed.dart';

class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  final GetPaymentDetailWithTableIdUsecase _getPaymentDetailWithTableIdUsecase;
  final CreatePaymentUsecase _createPaymentUsecase;
  final GetPaymentDetailWithIdUsecase _getPaymentDetailWithIdUsecase;
  final PrinterService _printerService;

  DateTime? _timerStartedAt;
  List<PauseInterval> _timerPauses = const [];
  int _timerTotalSec = 0;
  String? _timerPricePerHour;

  // Public read-only getters for UI (preview modal)
  DateTime? get timerStartedAt => _timerStartedAt;
  List<PauseInterval> get timerPauses => _timerPauses;
  int get timerTotalSec => _timerTotalSec;
  String? get timerPricePerHour => _timerPricePerHour;

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
    required GetPaymentDetailWithTableIdUsecase getPaymentDetailWithTableIdUsecase,
    required CreatePaymentUsecase createPaymentUsecase,
    required GetPaymentDetailWithIdUsecase getPaymentDetailWithId,
    required PrinterService printerService,
  }) : _getPaymentDetailWithTableIdUsecase = getPaymentDetailWithTableIdUsecase,
       _createPaymentUsecase = createPaymentUsecase,
       _getPaymentDetailWithIdUsecase = getPaymentDetailWithId,
       _printerService = printerService,
       super(const PaymentState()) {
    on<_Started>(_onStarted);
    on<_GetDetail>(_onGetDetail);
    on<_UpdatePaymentType>(_onUpdatePaymentType);
    on<_UpdateEnterSum>(_onUpdateEnterSum);
    on<_Payment>(_payment);
    on<_DiscountType>(_updateDiscountType);
    on<_UpdateDiscountAmount>(_updateDiscountAmount);
    on<_UpdateHourPrice>(_updateHourPrice);
    on<_ItemTimestampsLoaded>(_onItemTimestampsLoaded);
  }

  void _onItemTimestampsLoaded(
    _ItemTimestampsLoaded event,
    Emitter<PaymentState> emit,
  ) {
    emit(state.copyWith(itemTimestamps: event.timestamps));
  }

  void _updateHourPrice(_UpdateHourPrice event, emit) {
    // enterSum ni ham yangilash — agar kassir hali o'zgartirmagan bo'lsa
    final detail = state.detail;
    String? newEnterSum;
    if (detail != null) {
      final oldExpected = effectiveTotal(detail, tableCharge: state.hourPrice);
      final newExpected = effectiveTotal(detail, tableCharge: event.hourPrice);
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
    final enteredAmt = int.tryParse(state.enterSum) ?? 0;
    final dueTot = state.detail != null
        ? effectiveTotal(state.detail!, tableCharge: state.hourPrice) +
            pendingOfflineExtra(state.tableId)
        : 1;
    final cashNeedsAmount =
        state.paymentType == PaymentType.cash && enteredAmt <= 0 && dueTot > 0;
    if (state.detail != null && !cashNeedsAmount) {
      // Cash sends entered amount; card/qr send the computed due total.
      final paidAmount = state.paymentType == PaymentType.cash
          ? enteredAmt
          : dueTot;

      // Never call /pay underpaid — backend closes the table timer during /pay
      // even when it then rejects with "insufficient payment", wiping accrued time.
      if (dueTot > 0 && paidAmount < dueTot) {
        showErrorMessage(
          navigatorKey.currentContext!,
          'Yetarli emas: $paidAmount to\'landi, $dueTot kerak',
        );
        return;
      }

      emit(state.copyWith(status: Status.LOADING));

      // Total 0 bo'lsa — /pay emas /cancel
      if (dueTot <= 0) {
        try {
          await inject<DioClient>().dio.post(
            ListAPI.cancelOrder(state.detail!.id),
          );
          _paymentSucceeded = true;
          _onPaymentSuccess();
        } catch (e) {
          if (!isClosed) emit(state.copyWith(status: Status.ERROR));
          showErrorMessage(
            navigatorKey.currentContext!,
            e.toString(),
          );
        }
        return;
      }

      final tableChargeSom = state.hourPrice.round();
      final response = await _createPaymentUsecase.call(
        PaymentPayRequestModel(
          orderId: state.detail!.id,
          customPaidAmount: paidAmount,
          discountAmount: state.discountType == DiscountType.money
              ? int.tryParse(state.discountAmount) != null
                    ? int.parse(state.discountAmount)
                    : 0
              : 0,
          discountPercent: state.discountType == DiscountType.percent
              ? int.tryParse(state.discountAmount) != null
                    ? int.parse(state.discountAmount)
                    : 0
              : 0,
          paymentType: state.paymentType,
          tableCharge: tableChargeSom > 0 ? tableChargeSom : 0,
        ),
      );
      response.fold(
        (l) async {
          if (l is ConnectionFailure) {
            // Internet yo'q — to'lovni offline queue ga saqla
            await _enqueuePayment();
            if (isClosed) return;
            _paymentSucceeded = true;
            _onPaymentSuccess();
            return;
          }
          // Failed /pay may have closed the timer server-side — resume if possible.
          await resumeTimerAfterFailedPay();
          if (!isClosed) emit(state.copyWith(status: Status.ERROR));
          showErrorMessage(
            navigatorKey.currentContext!,
            l.getLocalizedMessage(navigatorKey.currentContext!),
          );
        },
        (r) {
          _paymentSucceeded = true;
          _onPaymentSuccess();
        },
      );
    }
  }

  bool _paymentSucceeded = false;
  bool get paymentSucceeded => _paymentSucceeded;

  /// After a failed/cancelled pay attempt, resume the table timer so accrued
  /// time is not left paused. Never start a fresh session — that would reset
  /// accrued time to 0 (backend may close the session on a failed /pay).
  Future<void> resumeTimerAfterFailedPay() async {
    if (_paymentSucceeded) return;
    final orderId = state.detail?.id ?? state.orderId;
    if (orderId == null || orderId.isEmpty) return;
    if (state.hourPrice <= 0 && _timerTotalSec <= 0 && _timerStartedAt == null) {
      return;
    }
    try {
      final client = inject<DioClient>();
      final res = await client.get(ListAPI.orderTableTimer(orderId));
      final raw = res.data['data'];
      if (raw is! Map) return;
      final timerState =
          (raw['state'] ?? raw['timer_state'])?.toString().toLowerCase() ?? '';
      if (timerState == 'paused') {
        await client.post(ListAPI.orderTableTimerResume(orderId));
      }
      // closed / none / running — leave as-is; starting fresh would wipe time.
    } catch (_) {
      // Best-effort — detail screen will refetch timer on return.
    }
  }

  void _onPaymentSuccess() {
    showSuccessMessage(
      navigatorKey.currentContext!,
      "Buyurtma muvafaqqiyatli to'landi",
    );
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
    final mainCubit = navigatorKey.currentContext!.read<MainCubit>();
    final effectiveTableId = state.tableId ?? state.detail?.tableId;
    if (effectiveTableId != null && effectiveTableId.isNotEmpty) {
      mainCubit.broadcastTableStatus(effectiveTableId, TableStatus.free);
    }
    Navigator.pushNamedAndRemoveUntil(
      navigatorKey.currentContext!,
      AppRoutes.mainScreen,
      (value) => true,
    );
    // To'lovdan keyin backend holatini yangilaymiz — local status yangilandi,
    // lekin boshqa stollar yoki serverdagi o'zgarishlar eskirgan bo'lishi mumkin.
    mainCubit.refreshTables(force: true);
  }

  Future<void> _enqueuePayment() async {
    final offlineExtra = pendingOfflineExtra(state.tableId);
    final effectiveAmt =
        effectiveTotal(state.detail!, tableCharge: state.hourPrice) + offlineExtra;
    final enteredAmt = int.tryParse(state.enterSum) ?? 0;
    final paidAmount =
        state.paymentType == PaymentType.cash ? enteredAmt : effectiveAmt;
    final payload = jsonEncode({
      'order_id': state.detail!.id,
      'customer_paid_amount': paidAmount.toString(),
      'payment_type': state.paymentType.name,
      if ((int.tryParse(state.discountAmount) ?? 0) > 0 &&
          state.discountType == DiscountType.money)
        'discount_amount': int.parse(state.discountAmount),
      if ((int.tryParse(state.discountAmount) ?? 0) > 0 &&
          state.discountType == DiscountType.percent)
        'discount_percent': int.parse(state.discountAmount),
    });
    await inject<OfflineQueueService>().enqueue(
      PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.payOrder,
        payload: payload,
        tableId: state.tableId ?? state.detail!.tableId,
        createdAt: DateTime.now(),
      ),
    );
    showSuccessMessage(
      navigatorKey.currentContext!,
      "To'lov navbatga qo'shildi — internet kelganda yuboriladi",
    );
  }

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

  /// Authoritative payment total — delegates to [OrderTotals] (main formula).
  static int effectiveTotal(
    ArchiveDetailEntity detail, {
    double tableCharge = 0,
  }) {
    return OrderTotals.fromDetail(detail, tableCharge: tableCharge).grandTotal;
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
    final cache = inject<CacheService>();

    if (state.tableId != null) {
      // Cache-first: avval saqlangan detalni ko'rsat
      final cached = cache.getOrderDetail(state.tableId!);
      if (cached != null) {
        final cachedDetail = ArchiveDetailModel.fromJson(cached);
        // Avvalgi sessiyada cache'lab qo'yilgan timestamplarni ham qo'llaymiz
        final cachedTs = cache.getItemTimestamps(cachedDetail.id);
        emit(state.copyWith(
          detailStatus: Status.SUCCESS,
          status: Status.SUCCESS,
          detail: cachedDetail,
          itemTimestamps: cachedTs,
          failure: null,
        ));
      } else {
        emit(state.copyWith(detailStatus: Status.LOADING, failure: null, detail: null));
      }

      if (!inject<ConnectivityCubit>().isOnline) return;

      final response = await _getPaymentDetailWithTableIdUsecase.call(state.tableId!);
      response.fold(
        (failure) {
          if (cached == null) {
            showErrorMessage(
              navigatorKey.currentContext!,
              failure.getLocalizedMessage(navigatorKey.currentContext!),
            );
            emit(state.copyWith(status: Status.ERROR, detailStatus: Status.ERROR, failure: failure));
          }
        },
        (detail) {
          cache.saveOrderDetail(state.tableId!, (detail as ArchiveDetailModel).toJson());
          // Dastlabki to'lov oynasida "Qabul qilingan" ni aniq summa bilan
          // avtomatik to'ldirib qo'yamiz (agar kassir hali hech nima kiritmagan bo'lsa).
          final prefill = PaymentBloc.effectiveTotal(detail, tableCharge: state.hourPrice);
          final currentEntered = int.tryParse(state.enterSum) ?? 0;
          // Prefill when empty, OR when enterSum is still the stale under-total
          // (old formula omitted service on table charge).
          final shouldPrefill = currentEntered <= 0 ||
              currentEntered == prefill ||
              (state.hourPrice > 0.01 && currentEntered < prefill);
          emit(state.copyWith(
            status: Status.SUCCESS,
            detailStatus: Status.SUCCESS,
            detail: detail,
            enterSum: shouldPrefill ? prefill.toString() : state.enterSum,
            failure: null,
          ));
          // Item timestamps — bills javobida yo'q, /order-items/order/{id}
          // dan olib alohida fetch qilamiz (UI vaqtni ko'rsatishi uchun).
          if (detail.id.isNotEmpty) {
            _fetchItemTimestamps(detail.id);
          }
        },
      );
    } else if (state.orderId != null) {
      emit(state.copyWith(detailStatus: Status.LOADING, failure: null, detail: null));
      final response = await _getPaymentDetailWithIdUsecase.call(state.orderId!);
      response.fold(
        (failure) {
          showErrorMessage(
            navigatorKey.currentContext!,
            failure.getLocalizedMessage(navigatorKey.currentContext!),
          );
          emit(state.copyWith(status: Status.ERROR, detailStatus: Status.ERROR, failure: failure));
        },
        (detail) {
          final prefill = PaymentBloc.effectiveTotal(detail, tableCharge: state.hourPrice);
          final currentEntered = int.tryParse(state.enterSum) ?? 0;
          final shouldPrefill = currentEntered <= 0 ||
              currentEntered == prefill ||
              (state.hourPrice > 0.01 && currentEntered < prefill);
          emit(state.copyWith(
            status: Status.SUCCESS,
            detailStatus: Status.SUCCESS,
            detail: detail,
            enterSum: shouldPrefill ? prefill.toString() : state.enterSum,
            failure: null,
          ));
          if (detail.id.isNotEmpty) {
            _fetchItemTimestamps(detail.id);
          }
        },
      );
    }
  }

  /// `/api/v1/order-items/order/{orderId}` orqali har bir itemning
  /// `created_at` vaqtini olib, `state.itemTimestamps` (name -> earliest)
  /// ga yozadi. Bills javobida bu maydon yo'q.
  Future<void> _fetchItemTimestamps(String orderId) async {
    try {
      final res = await inject<DioClient>().get(
        ListAPI.orderItemsListByOrder(orderId),
      );
      if (isClosed) return;
      final raw = res.data['data'];
      final List<dynamic> list = raw is List
          ? raw
          : (raw is Map<String, dynamic> && raw['items'] is List
              ? raw['items'] as List
              : const []);
      final tsByName = <String, DateTime>{};
      for (final entry in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(entry);
        final name = (m['good_name'] ?? m['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final rawDate = m['created_at'] ?? m['createdAt'];
        DateTime? created;
        if (rawDate is String && rawDate.isNotEmpty) {
          created = DateTime.tryParse(rawDate)?.toLocal();
        }
        if (created == null) continue;
        final existing = tsByName[name];
        if (existing == null || created.isBefore(existing)) {
          tsByName[name] = created;
        }
      }
      if (tsByName.isEmpty || isClosed) return;
      // Cache — offline'da ham ko'rinadi
      await inject<CacheService>().saveItemTimestamps(orderId, tsByName);
      // emit'ni BLoC pattern qoidasiga muvofiq event orqali yuboramiz
      add(PaymentEvent.itemTimestampsLoaded(timestamps: tsByName));
    } catch (_) {
      // Endpoint xatosi sukut bilan o'tib ketadi
    }
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
    state.textController?.dispose();
    return super.close();
  }
}
