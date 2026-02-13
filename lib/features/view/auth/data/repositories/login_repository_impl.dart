import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/data/data_sources/auth_datasource.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/request/login_request_model.dart';
import 'package:mary_ai_pos/features/view/auth/domain/repository/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  /// Data Source
  final AuthDatasource _datasources;
  final AppTokenStorage _tokenStorage;
  const AuthRepositoryImpl(this._tokenStorage, this._datasources);

  @override
  Future<Either<Failure, bool>> haveUserData() async {
    try {
      final BrandIdTokenPair? token = await _tokenStorage.readBrandIdToken();
      return Right(token != null);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> checkUserToAuth() async {
    try {
      final token = await _tokenStorage.readAccessToken();

      return Right(token != null);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> loginWithBrandId(BrandIdTokenPair req) async {
    try {
      await _tokenStorage.writeBrandIdToken(req);
      return const Right(true);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> logoutFromApp() async {
    try {
      await _tokenStorage.deleteAll();
      return const Right(true);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> logout() async {
    try {
      await _tokenStorage.deleteAuthToken();
      return const Right(true);
    } catch (e) {
      return const Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> login(LoginRequestModel req) async {
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
