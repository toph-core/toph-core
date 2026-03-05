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
import 'package:mary_ai_pos/features/view/main/domain/entities/payment_pay_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_payment_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_archive_with_id_usecase.dart';
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
  //
  PaymentBloc({
    required GetPaymentDetailWithTableIdUsecase
    getPaymentDetailWithTableIdUsecase,
    required CreatePaymentUsecase createPaymentUsecase,
    required GetPaymentDetailWithIdUsecase getPaymentDetailWithId,
  }) : _getPaymentDetailWithTableIdUsecase = getPaymentDetailWithTableIdUsecase,
       _createPaymentUsecase = createPaymentUsecase,
       _getPaymentDetailWithIdUsecase = getPaymentDetailWithId,
       super(const PaymentState()) {
    on<_Started>(_onStarted);
    on<_GetDetail>(_onGetDetail);
    on<_UpdatePaymentType>(_onUpdatePaymentType);
    on<_UpdateEnterSum>(_onUpdateEnterSum);
    on<_Payment>(_payment);
    on<_DiscountType>(_updateDiscountType);
    on<_UpdateDiscountAmount>(_updateDiscountAmount);
  }

  void _updateDiscountAmount(_UpdateDiscountAmount event, emit) => emit(
    state.copyWith(discountAmount: event.amount.isEmpty ? "0" : event.amount),
  );

  void _updateDiscountType(_DiscountType event, emit) =>
      emit(state.copyWith(discountType: event.dicountType));

  void _payment(_Payment event, Emitter<PaymentState> emit) async {
    if (state.detail != null && int.tryParse(state.enterSum) != null) {
      emit(state.copyWith(status: Status.LOADING));
      final response = await _createPaymentUsecase.call(
        PaymentPayRequestModel(
          orderId: state.detail!.id,
          cashRegisterId: "a195f647-8cf0-4132-8464-fdaaa2d77a68",
          cashierId: "4e25f6c1-68c0-43bd-bcb2-a130bde2e9e1",
          customPaidAmount: state.paymentType == PaymentType.cash
              ? int.parse(state.enterSum)
              : state.detail!.grandTotal,
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
        (l) {
          showErrorMessage(
            navigatorKey.currentContext!,
            l.getLocalizedMessage(navigatorKey.currentContext!),
          );
        },
        (r) {
          showSuccessMessage(
            navigatorKey.currentContext!,
            "Buyurtma muvafaqqiyatli to'landi",
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
        },
      );
    }
  }

  Future<void> _onStarted(_Started event, emit) async {
    emit(
      PaymentState(
        tableId: event.tableId,
        orderId: event.orderId,
        textController: TextEditingController(),
      ),
    );
    add(const PaymentEvent.getDetail());
  }

  Future<void> _onGetDetail(
    _GetDetail event,
    Emitter<PaymentState> emit,
  ) async {
    if (state.tableId != null) {
      emit(
        state.copyWith(
          detailStatus: Status.LOADING,
          failure: null,
          detail: null,
        ),
      );
      final response = await _getPaymentDetailWithTableIdUsecase.call(
        state.tableId!,
      );
      response.fold(
        (failure) {
          showErrorMessage(
            navigatorKey.currentContext!,
            failure.getLocalizedMessage(navigatorKey.currentContext!),
          );
          emit(
            state.copyWith(
              status: Status.ERROR,
              detailStatus: Status.ERROR,
              failure: failure,
            ),
          );
        },
        (detail) => emit(
          state.copyWith(
            status: Status.SUCCESS,
            detailStatus: Status.SUCCESS,
            detail: detail,
            failure: null,
          ),
        ),
      );
    } else if (state.orderId != null) {
      emit(
        state.copyWith(
          detailStatus: Status.LOADING,
          failure: null,
          detail: null,
        ),
      );
      final response = await _getPaymentDetailWithIdUsecase.call(
        state.orderId!,
      );
      response.fold(
        (failure) {
          showErrorMessage(
            navigatorKey.currentContext!,
            failure.getLocalizedMessage(navigatorKey.currentContext!),
          );
          emit(
            state.copyWith(
              status: Status.ERROR,
              detailStatus: Status.ERROR,
              failure: failure,
            ),
          );
        },
        (detail) => emit(
          state.copyWith(
            status: Status.SUCCESS,
            detailStatus: Status.SUCCESS,
            detail: detail,
            failure: null,
          ),
        ),
      );
    }
  }

  void _onUpdatePaymentType(
    _UpdatePaymentType event,
    Emitter<PaymentState> emit,
  ) => emit(state.copyWith(paymentType: event.paymentType));

  void _onUpdateEnterSum(_UpdateEnterSum event, Emitter<PaymentState> emit) {
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
