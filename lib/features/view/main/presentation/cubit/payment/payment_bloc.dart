import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_archive_with_id_usecase.dart';

part 'payment_event.dart';
part 'payment_state.dart';
part 'payment_bloc.freezed.dart';

class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  final GetArchiveWithIdUsecase _getArchiveWithIdUsecase;
  //
  PaymentBloc({required GetArchiveWithIdUsecase getArchiveWithIdUsecase})
    : _getArchiveWithIdUsecase = getArchiveWithIdUsecase,
      super(const PaymentState()) {
    on<_Started>(_onStarted);
    on<_GetDetail>(_onGetDetail);
    on<_UpdatePaymentType>(_onUpdatePaymentType);
  }

  Future<void> _onStarted(_Started event, emit) async {
    emit(
      PaymentState(
        tableId: event.tableId,
        textController: TextEditingController()
      ),
    );
    add(const PaymentEvent.getDetail());
  }

  Future<void> _onGetDetail(_GetDetail event, Emitter<PaymentState> emit) async {
    emit(state.copyWith(detailStatus: Status.LOADING, failure: null,detail: null));
    final response = await _getArchiveWithIdUsecase.call(state.tableId);
    response.fold(
      (failure) => emit(
        state.copyWith(
          status: Status.ERROR,
          detailStatus: Status.ERROR,
          failure: failure,
        ),
      ),
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

  void _onUpdatePaymentType(
    _UpdatePaymentType event,
    Emitter<PaymentState> emit,
  ) => emit(state.copyWith(paymentType: event.paymentType));

  @override
  Future<void> close() {
    state.textController?.dispose();
    return super.close();
  }
}

