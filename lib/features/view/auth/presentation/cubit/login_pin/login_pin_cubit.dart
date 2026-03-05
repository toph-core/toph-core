import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/request/login_request_model.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/login_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout_from_app_usecase.dart';

part 'login_pin_cubit.freezed.dart';
part 'login_pin_state.dart';

class LoginPinCubit extends Cubit<LoginPinState> {
  final LoginUsecase _loginUsecase;
  final LogoutFromAppUseCase _logoutUseCase;
  final AppTokenStorage _secureStorage;
  LoginPinCubit(this._loginUsecase, this._logoutUseCase, this._secureStorage)
    : super(const LoginPinState());

  void login({required String pincode, required Function() onSuccess}) async {
    emit(state.copyWith(status: Status.LOADING));

    // const String fcmToken = "await FirebaseMessaging.instance.getToken()";
    final BrandIdTokenPair? brandIdTokenPair = await _secureStorage
        .readBrandIdToken();

    if (brandIdTokenPair != null) {
      var result = await _loginUsecase.call(
        LoginRequestModel(
          // fcmToken: fcmToken,
          brandId: brandIdTokenPair.brandId,
          password: brandIdTokenPair.password,
          pincode: pincode,
        ),
      );

      result.fold(
        (failure) {
          emit(state.copyWith(failure: failure, status: Status.ERROR));
        },
        (response) {
          onSuccess();
          emit(state.copyWith(status: Status.SUCCESS));
        },
      );
    } else {
      emit(state.copyWith(status: Status.UNKNOWN));
    }
  }

  void setPin(String value) {
    String pinUpdated = state.pin ?? '';

    if (value == '⌫') {
      if (pinUpdated.isNotEmpty) {
        pinUpdated = pinUpdated.substring(0, pinUpdated.length - 1);
      }
    } else if (value != '✓' && value.length < 6) {
      pinUpdated += value;
    }
    emit(state.copyWith(pin: pinUpdated));

    if (pinUpdated.length >= 2 && value == '✓') {
      emit(state.copyWith(pin: null));
      login(
        pincode: pinUpdated,
        onSuccess: () {
          Navigator.pushNamedAndRemoveUntil(
            navigatorKey.currentContext!,
            AppRoutes.splashScreen,
            (route) => false,
          );
        },
      );
    }
  }

  void logoutFromApp(Function() onLogout) async {
    emit(state.copyWith(status: Status.LOADING));
    var result = await _logoutUseCase.call(NoParams());

    result.fold(
      (failure) {
        emit(state.copyWith(failure: failure, status: Status.ERROR));
      },
      (response) {
        onLogout();
        emit(state.copyWith(status: Status.SUCCESS));
      },
    );
  }
}
