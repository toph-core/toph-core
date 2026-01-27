import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/login_response.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/login_usecase.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

abstract class AuthDatasource {
  Future<Either<Failure, bool>> login(LoginRequest req);
  Future<Either<Failure, bool>> logout();
}

class AuthDatasourceImpl implements AuthDatasource {
  final DioClient _client;
  final AppTokenStorage _tokenStorage;

  AuthDatasourceImpl(this._client, this._tokenStorage);

  @override
  Future<Either<Failure, bool>> login(LoginRequest req) async {
    try {
      final Response response = await _client.post(
        ListAPI.login,
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
  Future<Either<Failure, bool>> logout() async {
    try {
      await _client.post(ListAPI.logout);

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
