import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/extension/log.dart';
import 'package:mary_ai_pos/features/view/auth/data/data_sources/auth_datasource.dart';
import 'package:mary_ai_pos/features/view/auth/domain/repository/auth_repository.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/login_usecase.dart';
import 'package:dartz/dartz.dart';

class AuthRepositoryImpl implements AuthRepository {
  /// Data Source
  final AuthDatasource _datasources;
  final AppTokenStorage _tokenStorage;
  const AuthRepositoryImpl(this._tokenStorage, this._datasources);

  @override
  Future<Either<Failure, bool>> checkUserToAuth() async {
    try {
      String token = await _tokenStorage.readAccessToken() ?? '';
      return Right(token.isEmpty);
    } catch (e) {
      e.printf();
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> logout() async {
    final response = await _datasources.logout();
    return response.fold(
      (failure) => Left(failure),
      (response) => Right(response),
    );
  }

  @override
  Future<Either<Failure, bool>> login(LoginRequest req) async {
    final response = await _datasources.login(req);
    return response.fold(
      (failure) => Left(failure),
      (response) => Right(response),
    );
  }

  @override
  Future<Either<Failure, String>> setAppLang(String lang) async {
    try {
      await _tokenStorage.writeString(TokensStorageKeys.appLanguage, lang);
      return Right(lang);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, String>> getAppLang() async {
    try {
      String lang =
          await _tokenStorage.readString(TokensStorageKeys.appLanguage) ?? 'uz';
      return Right(lang);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }
}
