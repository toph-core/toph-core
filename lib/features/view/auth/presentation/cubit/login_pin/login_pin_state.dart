part of 'login_pin_cubit.dart';

@freezed
class LoginPinState with _$LoginPinState {
  const factory LoginPinState({
    @Default(Status.UNKNOWN) Status status,
    @Default(UnknownFailure()) Failure failure,
    String? pin,
  }) = _LoginPinState;
}
