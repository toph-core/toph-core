import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/request/login_request_model.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/response/login_response.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';

abstract class AuthDatasource {
  Future<Either<Failure, bool>> login(LoginRequestModel req);
  Future<Either<Failure, bool>> logout();

  /// Checks the pincode against the login-pincode endpoint WITHOUT persisting
  /// any tokens, so the currently active session is left untouched. Returns
  /// the full user the pincode belongs to (role gate + audit-log identity
  /// for the caller), or a failure if the pincode itself is invalid.
  Future<Either<Failure, UserModel>> verifyPincodeRole(String pincode);
}

class AuthDatasourceImpl implements AuthDatasource {
  final DioClient _client;
  final AppTokenStorage _tokenStorage;
  final OfflineAuthCache _offlineAuthCache;

  AuthDatasourceImpl(this._client, this._tokenStorage, this._offlineAuthCache);

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

      // CLIENT_FACING_OFFLINE_PLAN.md §1: the login response already carries
      // the user — cache it here (brand-level + per-pincode, same shape
      // verifyPincodeRole caches) so the profile is locally readable
      // immediately after a first-ever online login, without waiting for a
      // background getUser round-trip.
      final user = model.user;
      if (user != null) {
        await _offlineAuthCache.saveUser(
          brandId: req.brandId,
          password: req.password,
          user: user,
          accessToken: model.accessToken,
          refreshToken: model.refreshToken,
        );
        await _offlineAuthCache.saveForPin(
          brandId: req.brandId,
          pincode: req.pincode,
          user: user,
          accessToken: model.accessToken,
          refreshToken: model.refreshToken,
        );
      }

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
  Future<Either<Failure, UserModel>> verifyPincodeRole(String pincode) async {
    final BrandIdTokenPair? brandIdToken = await _tokenStorage.readBrandIdToken();
    if (brandIdToken == null) return const Left(UnknownFailure());

    // Offline-first: internet yo'q bo'lsa API ga murojaat qilib vaqt
    // sarflamasdan darhol cache dan (LoginPinCubit.login() bilan bir xil
    // naqsh — §11 Phase 6, offline manager-pincode tekshiruvi).
    if (!_client.isOnline) {
      return _verifyFromCache(brandIdToken.brandId, pincode);
    }

    try {
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
      final user = model.user;
      if (user == null) return const Left(UnknownFailure());
      // Keyingi safar aloqa bo'lmasa ham shu pincode offline tekshirilishi
      // uchun keshlaymiz — `OfflineAuthCache`ning aynan shu per-pincode
      // qismi, oddiy PIN-login bilan bir xil (bitta umumiy cache).
      await _offlineAuthCache.saveForPin(
        brandId: brandIdToken.brandId,
        pincode: pincode,
        user: user,
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
      );
      return Right(user);
    } on DioException catch (exception) {
      final failure = handleDioException(exception);
      if (failure.isDefiniteAuthRejection) {
        // Server aniq javob berdi: bu pincode endi yaroqsiz — cache'dan ham
        // o'chiramiz, muddat asosidagi tugash yo'q (Phase 6ning umumiy
        // qoidasi — bu yerda ham xuddi shunday qo'llanadi).
        await _offlineAuthCache.removeForPin(brandIdToken.brandId, pincode);
        return Left(failure);
      }
      // Ulanish/timeout/server xatosi — aniq javob yo'q, cache'dan urinib
      // ko'ramiz.
      return _verifyFromCache(
        brandIdToken.brandId,
        pincode,
        fallbackFailure: failure,
      );
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

  Future<Either<Failure, UserModel>> _verifyFromCache(
    String brandId,
    String pincode, {
    Failure fallbackFailure = const ConnectionFailure(),
  }) async {
    final cached = await _offlineAuthCache.getForPin(brandId, pincode);
    if (cached == null) return Left(fallbackFailure);
    return Right(UserModel.fromJson(cached.userModelJson));
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
