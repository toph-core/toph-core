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
    final BrandIdTokenPair? brandIdToken;
    try {
      brandIdToken = await _tokenStorage.readBrandIdToken();
    } catch (e, st) {
      if (kDebugMode) print('Pincode role check storage error: $e\n$st');
      return const Left(CacheFailure());
    }
    if (brandIdToken == null) return const Left(UnknownFailure());

    // Local first, and not only when offline. This used to consult the cache
    // only after a failed request, so an authorization prompt in the middle of
    // an order — a void, a discount — waited on the network every time the
    // terminal happened to have connectivity. A PIN this terminal has already
    // verified is answered here, with no request; the same inversion
    // `LoginPinCubit.login` makes, for the same reason.
    //
    // Revocation still works, one attempt later: [_revalidateInBackground]
    // purges a PIN the server has since rejected, so the next prompt refuses
    // it. Offline that was already the behaviour.
    // Guarded: a corrupt cache row must surface as a refusal the prompt can
    // show, not as an exception thrown past the `Either` contract.
    try {
      final cached = await _offlineAuthCache.getForPin(
        brandIdToken.brandId,
        pincode,
      );
      if (cached != null) {
        final cachedUser = UserModel.fromJson(cached.userModelJson);
        _revalidateInBackground(brandIdToken, pincode);
        return Right(cachedUser);
      }
    } catch (e, st) {
      if (kDebugMode) print('Pincode role cache read error: $e\n$st');
      return const Left(CacheFailure());
    }

    // No local answer — this PIN has not been verified on this terminal, or it
    // was revoked and purged. Only the server can settle it.
    if (!_client.isOnline) {
      return const Left(ConnectionFailure());
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
      // Ulanish/timeout/server xatosi — aniq javob yo'q. Cache'ga qaytib
      // urinishning ma'nosi yo'q: bu yerga faqat cache'da javob topilmagani
      // uchun kelinadi, shuning uchun xatoni o'zini qaytaramiz.
      return Left(failure);
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

  /// Re-checks a cache-served role PIN against the server, after the caller
  /// has already been answered.
  ///
  /// Not awaited and silent by design: its only effect is to purge a PIN the
  /// server now rejects, so the next authorization prompt refuses it. A
  /// transport failure means nothing was learned, so nothing is done — and it
  /// never writes tokens, because this is a role check, not a session.
  void _revalidateInBackground(BrandIdTokenPair brandIdToken, String pincode) {
    if (!_client.isOnline) return;
    unawaited(() async {
      try {
        final response = await _client.post(
          ListAPI.loginPinCode,
          data: LoginRequestModel(
            brandId: brandIdToken.brandId,
            password: brandIdToken.password,
            pincode: pincode,
          ).toJson(),
        );
        final LoginResponse model = LoginResponse.fromJson(response.data['data']);
        final user = model.user;
        if (user == null) return;
        // Keep the cached role current too — a waiter promoted to manager on
        // another terminal should not have to wait for a cache miss.
        await _offlineAuthCache.saveForPin(
          brandId: brandIdToken.brandId,
          pincode: pincode,
          user: user,
          accessToken: model.accessToken,
          refreshToken: model.refreshToken,
        );
      } on DioException catch (exception) {
        if (handleDioException(exception).isDefiniteAuthRejection) {
          await _offlineAuthCache.removeForPin(brandIdToken.brandId, pincode);
        }
      } catch (_) {
        // Background hygiene; a throw here must not surface anywhere.
      }
    }());
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
