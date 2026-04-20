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
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/payment_pay_request/payment_pay_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
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
  }

  void _updateHourPrice(_UpdateHourPrice event, emit) {
    emit(state.copyWith(hourPrice: event.hourPrice));
  }

  void _updateDiscountAmount(_UpdateDiscountAmount event, emit) => emit(
    state.copyWith(discountAmount: event.amount.isEmpty ? "0" : event.amount),
  );

  void _updateDiscountType(_DiscountType event, emit) =>
      emit(state.copyWith(discountType: event.dicountType));

  void _payment(_Payment event, Emitter<PaymentState> emit) async {
    final enteredAmt = int.tryParse(state.enterSum) ?? 0;
    final effectiveTot = state.detail != null
        ? effectiveTotal(state.detail!) + state.hourPrice.toInt() + pendingOfflineExtra(state.tableId)
        : 1;
    final cashNeedsAmount = state.paymentType == PaymentType.cash && enteredAmt <= 0 && effectiveTot > 0;
    if (state.detail != null && !cashNeedsAmount) {
      emit(state.copyWith(status: Status.LOADING));
      final response = await _createPaymentUsecase.call(
        PaymentPayRequestModel(
          orderId: state.detail!.id,
          // cashRegisterId: "a195f647-8cf0-4132-8464-fdaaa2d77a68",
          // cashierId: "4e25f6c1-68c0-43bd-bcb2-a130bde2e9e1",
          // Chegirmadan oldingi jami (discount_* alohida); naqd kiritilgan sum qayta emas.
          customPaidAmount: state.paymentType == PaymentType.cash
              ? enteredAmt
              : effectiveTotal(state.detail!) +
                    state.hourPrice.toInt() +
                    pendingOfflineExtra(state.tableId),
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
        ),
      );
      response.fold(
        (l) async {
          if (l is ConnectionFailure) {
            // Internet yo'q — to'lovni offline queue ga saqla
            await _enqueuePayment();
            if (isClosed) return;
            _onPaymentSuccess();
            return;
          }
          if (!isClosed) emit(state.copyWith(status: Status.ERROR));
          showErrorMessage(
            navigatorKey.currentContext!,
            l.getLocalizedMessage(navigatorKey.currentContext!),
          );
        },
        (r) => _onPaymentSuccess(),
      );
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
    if (state.tableId != null) {
      navigatorKey.currentContext!.read<MainCubit>().updateTableStatus(
        state.tableId!,
        TableStatus.free,
      );
    }
    Navigator.pushNamedAndRemoveUntil(
      navigatorKey.currentContext!,
      AppRoutes.mainScreen,
      (value) => true,
    );
  }

  Future<void> _enqueuePayment() async {
    final offlineExtra = pendingOfflineExtra(state.tableId);
    final effectiveAmt =
        effectiveTotal(state.detail!) + state.hourPrice.toInt() + offlineExtra;
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

  static int effectiveTotal(ArchiveDetailEntity detail) {
    final hasCancelled = detail.goods.any((g) => g.status == 'cancelled');
    if (!hasCancelled && detail.grandTotal > 0.01) {
      return detail.grandTotal.toInt();
    }
    final foodSum = detail.goods
        .where((g) => g.status != 'cancelled')
        .fold(0.0, (s, g) => s + g.price * g.quantity);
    final service = detail.serviceAmount > 0.01
        ? detail.serviceAmount
        : foodSum * detail.servicePercent / 100;
    return (foodSum + service).toInt();
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
        emit(state.copyWith(
          detailStatus: Status.SUCCESS,
          status: Status.SUCCESS,
          detail: ArchiveDetailModel.fromJson(cached),
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
          emit(state.copyWith(status: Status.SUCCESS, detailStatus: Status.SUCCESS, detail: detail, failure: null));
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
        (detail) => emit(state.copyWith(
          status: Status.SUCCESS,
          detailStatus: Status.SUCCESS,
          detail: detail,
          failure: null,
        )),
      );
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
