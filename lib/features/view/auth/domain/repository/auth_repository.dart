import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/request/login_request_model.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';

abstract class AuthRepository {
  Future<Either<Failure, bool>> checkUserToAuth();
  Future<Either<Failure, bool>> logoutFromApp();
  Future<Either<Failure, bool>> logout();
  Future<Either<Failure, bool>> haveUserData();
  Future<Either<Failure, bool>> login(LoginRequestModel req);
  Future<Either<Failure, bool>> loginWithBrandId(BrandIdTokenPair req);
  Future<Either<Failure, String>> setAppLang(String lang);
  Future<Either<Failure, String>> getAppLang();

  /// The full user the pincode belongs to (not just its role) — the
  /// privileged-action audit log (§11 Phase 6) needs to record *who*
  /// approved, not just that someone with the right role did.
  Future<Either<Failure, UserModel>> verifyPincodeRole(String pincode);
}
