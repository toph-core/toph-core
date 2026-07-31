import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/request/login_request_model.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/response/login_response.dart';

abstract class AuthDatasource {
  Future<Either<Failure, bool>> login(LoginRequestModel req);
  Future<Either<Failure, bool>> logout();

  /// Checks the pincode against the login-pincode endpoint WITHOUT persisting
  /// any tokens, so the currently active session is left untouched. Returns
  /// the role of the user the pincode belongs to (for a role gate check by
  /// the caller), or a failure if the pincode itself is invalid.
  Future<Either<Failure, UserRole>> verifyPincodeRole(String pincode);
}

class AuthDatasourceImpl implements AuthDatasource {
  final DioClient _client;
  final AppTokenStorage _tokenStorage;

  AuthDatasourceImpl(this._client, this._tokenStorage);

  @override
  Future<Either<Failure, bool>> login(LoginRequestModel req) async {
    try {
      final Response response = await _client.post(
        ListAPI.loginPinCode,
        data: req.toJson(),
      );

      final LoginResponse model = LoginResponse.fromJson(response.data['data']);

      final tokenPair = AuthTokenPair(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
      );
      await _tokenStorage.writeAuthToken(tokenPair);

      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, UserRole>> verifyPincodeRole(String pincode) async {
    try {
      final BrandIdTokenPair? brandIdToken =
          await _tokenStorage.readBrandIdToken();
      if (brandIdToken == null) return const Left(UnknownFailure());

      final Response response = await _client.post(
        ListAPI.loginPinCode,
        data: LoginRequestModel(
          brandId: brandIdToken.brandId,
          password: brandIdToken.password,
          pincode: pincode,
        ).toJson(),
      );

      // Intentionally does NOT call `_tokenStorage.writeAuthToken` — this is
      // a role check only, the active session must stay untouched.
      final LoginResponse model = LoginResponse.fromJson(response.data['data']);
      return Right(model.user?.role ?? UserRole.none);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> logout() async {
    try {
      await _tokenStorage.deleteAll();

      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }
}
