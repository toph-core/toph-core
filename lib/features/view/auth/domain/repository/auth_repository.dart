import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/login_usecase.dart';
import 'package:dartz/dartz.dart';

abstract class AuthRepository {
  Future<Either<Failure, bool>> checkUserToAuth();
  Future<Either<Failure, bool>> logout();
  Future<Either<Failure, bool>> login(LoginRequest req);
  Future<Either<Failure, String>> setAppLang(String lang);
  Future<Either<Failure, String>> getAppLang();
}
