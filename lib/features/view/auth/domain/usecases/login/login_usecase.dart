import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/features/view/auth/domain/repository/auth_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_usecase.freezed.dart';
part 'login_usecase.g.dart';

class LoginUsecase extends UseCase<bool, LoginRequest> {
  final AuthRepository _repository;
  LoginUsecase(this._repository);

  @override
  Future<Either<Failure, bool>> call(LoginRequest params) =>
      _repository.login(params);
}

@freezed
class LoginRequest with _$LoginRequest {
  const factory LoginRequest({
    required String password,
    @JsonKey(name: 'phone_number') required String phoneNumber,
  }) = _LoginRequestState;

  factory LoginRequest.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestFromJson(json);
}
