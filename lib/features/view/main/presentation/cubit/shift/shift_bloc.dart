import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/models/close_shift/close_shift_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_shift/open_shift_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/shift/shift_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/check_shift_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/close_shift_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/open_shift_usecase.dart';

part 'shift_event.dart';
part 'shift_state.dart';
part 'shift_bloc.freezed.dart';

class ShiftBloc extends Bloc<ShiftEvent, ShiftState> {
  late final CheckShiftUsecase _checkShiftUsecase;
  late final OpenShiftUsecase _openShiftUsecase;
  late final CloseShiftUsecase _closeShiftUsecase;
  //
  ShiftBloc({
    required CheckShiftUsecase checkShiftUsecase,
    required OpenShiftUsecase openShiftUsecase,
    required CloseShiftUsecase closeShiftUsecase,
  }) : _checkShiftUsecase = checkShiftUsecase,
       _openShiftUsecase = openShiftUsecase,
       _closeShiftUsecase = closeShiftUsecase,
       super(const ShiftState()) {
    on<_Started>(_started);
    on<_CheckShift>(_checkShift);
    on<_UpdateCashSum>(_updateCashSum);
    on<_UpdateCardSum>(_updateCardSum);
    on<_UpdateSumType>(_updateSumType);
    on<_OpenShift>(_openShift);
    on<_CloseShift>(_closeShift);
  }

  void _closeShift(_CloseShift event, emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final response = await _closeShiftUsecase.call(
      CloseShiftRequestModel(
        shiftId: state.shift?.id ?? '',
        closingCard: int.parse(state.cardSum),
        closingCash: int.parse(state.cashSum),
      ),
    );
    response.fold(
      (l) {
        showErrorMessage(
          navigatorKey.currentContext!,
          l.getLocalizedMessage(navigatorKey.currentContext!),
        );
        emit(state.copyWith(status: Status.ERROR, failure: l));
      },
      (r) async {
        navigatorKey.currentContext!.read<AuthCubit>().logout(
          onSuccess: () => Navigator.pushNamedAndRemoveUntil(
            navigatorKey.currentContext!,
            AppRoutes.loginPinScreen,
            (router) => true,
          ),
        );
        showSuccessMessage(
          navigatorKey.currentContext!,
          "Smena muvafaqqiyatli yopildi",
        );
        emit(
          state.copyWith(
            status: Status.SUCCESS,
            shift: null,
            cardSum: '0',
            cashSum: '0',
          ),
        );
      },
    );
  }

  void _openShift(_OpenShift evente, emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final response = await _openShiftUsecase.call(
      OpenShiftModel(
        cashRegisterId: "de9354d4-f7e4-4317-a3c6-3b06b6045fd1",
        cashierId: "4e25f6c1-68c0-43bd-bcb2-a130bde2e9e1",
        openCardSum: int.parse(state.cardSum),
        openCashSum: int.parse(state.cashSum),
      ),
    );
    response.fold(
      (l) {
        showErrorMessage(
          navigatorKey.currentContext!,
          l.getLocalizedMessage(navigatorKey.currentContext!),
        );
        emit(state.copyWith(status: Status.ERROR, failure: l));
      },
      (r) {
        Navigator.pushNamedAndRemoveUntil(
          navigatorKey.currentContext!,
          AppRoutes.mainScreen,
          (router) => true,
        );
        showSuccessMessage(
          navigatorKey.currentContext!,
          "Smena muvafaqqiyatli ochildi",
        );
        emit(
          state.copyWith(
            status: Status.SUCCESS,
            shift: r,
            cardSum: '0',
            cashSum: '0',
          ),
        );
      },
    );
  }

  void _updateCardSum(_UpdateCardSum event, emit) {
    if (int.tryParse(event.value) != null) {
      String value = state.cardSum == '0'
          ? event.value
          : state.cardSum + event.value;
      emit(state.copyWith(cardSum: value));
    } else if (event.value == "delete") {
      String value = state.cardSum.length == 1
          ? '0'
          : state.cardSum.substring(0, state.cardSum.length - 1);
      emit(state.copyWith(cardSum: value));
    }
  }

  void _updateCashSum(_UpdateCashSum event, emit) {
    if (int.tryParse(event.value) != null) {
      String value = state.cashSum == '0'
          ? event.value
          : state.cashSum + event.value;
      emit(state.copyWith(cashSum: value));
    } else if (event.value == "delete") {
      String value = state.cashSum.length == 1
          ? '0'
          : state.cashSum.substring(0, state.cashSum.length - 1);
      emit(state.copyWith(cashSum: value));
    }
  }

  void _updateSumType(_UpdateSumType event, emit) {
    if (state.sum != event.type) {
      emit(state.copyWith(sum: event.type));
    }
  }

  void _checkShift(_CheckShift event, emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final response = await _checkShiftUsecase.call(
      "de9354d4-f7e4-4317-a3c6-3b06b6045fd1",
    );
    response.fold(
      (l) {
        emit(state.copyWith(status: Status.ERROR, failure: l));
      },
      (r) {
        if (r == null) {
          Navigator.pushNamed(
            navigatorKey.currentContext!,
            AppRoutes.closeShiftScreen,
          );
        }
        emit(state.copyWith(status: Status.SUCCESS, shift: r));
      },
    );
  }

  void _started(_Started event, emit) {
    emit(const ShiftState());
  }
}
