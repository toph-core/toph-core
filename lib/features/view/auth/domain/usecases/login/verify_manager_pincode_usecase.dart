import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/auth/domain/repository/auth_repository.dart';

class VerifyManagerPincodeUsecase extends UseCase<UserModel, String> {
  final AuthRepository _repository;
  VerifyManagerPincodeUsecase(this._repository);

  @override
  Future<Either<Failure, UserModel>> call(String pincode) =>
      _repository.verifyPincodeRole(pincode);
}
