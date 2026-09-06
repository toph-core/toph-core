import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/services/auth/login_data_scope_service.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/login/request/login_request_model.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/login_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout_from_app_usecase.dart';

part 'login_pin_cubit.freezed.dart';
part 'login_pin_state.dart';

// ─────────────────────────────────────────────────────────────────────────
// DEBUG LICENSE GATE — TEMPORARY, REMOVE BEFORE RELEASE
//
// While [_kDebugPinGateEnabled] is true, only [_kDebugPinGateCode] is allowed
// to log in; every other PIN is rejected up front, before any real
// authentication (cache or server) runs. This locks a demo/handed-out build to
// a single known account so it can't be used freely.
//
// To disable: flip [_kDebugPinGateEnabled] to false. To remove entirely:
// delete this block and the single guard at the top of [LoginPinCubit.login].
const bool _kDebugPinGateEnabled = false;
const String _kDebugPinGateCode = '5192';
// ─────────────────────────────────────────────────────────────────────────

class LoginPinCubit extends Cubit<LoginPinState> {
  final LoginUsecase _loginUsecase;
  final LogoutFromAppUseCase _logoutUseCase;
  final AppTokenStorage _secureStorage;
  final OfflineAuthCache _offlineCache;
  final ConnectivityCubit _connectivity;
  final LoginDataScopeService _dataScope;

  LoginPinCubit(
    this._loginUsecase,
    this._logoutUseCase,
    this._secureStorage,
    this._offlineCache,
    this._connectivity,
    this._dataScope,
  ) : super(const LoginPinState());

  /// PIN login, local-first.
  ///
  /// This used to be online-first: when the terminal had connectivity it
  /// awaited `POST /login/pincode` on every entry and only consulted the
  /// offline cache once the request had failed. So a cashier's shift change
  /// waited on the network even though the terminal already held the answer,
  /// and a *slow but reachable* server — the case neither the connectivity
  /// probe nor the failure path treats as offline — delayed every login by
  /// however long the server took.
  ///
  /// The order is inverted now. A PIN this terminal has verified before is
  /// answered from the cache with no request at all, and the server is asked
  /// only for a PIN with no local answer: the first use of that PIN on this
  /// terminal, which is part of the initial setup the pull is for.
  ///
  /// **Revocation is now asynchronous, and that is the trade.** A PIN
  /// deactivated on the server is still accepted once here, and
  /// [_revalidateInBackground] purges it immediately afterwards so the next
  /// attempt fails. The previous code caught that on the first attempt, but
  /// only while online — offline it behaved exactly as this does now, so this
  /// widens an existing window rather than opening a new one.
  void login({required String pincode, required Function() onSuccess}) async {
    // DEBUG LICENSE GATE — remove before release (see [_kDebugPinGateEnabled]).
    // Runs before the offline-cache path below on purpose, so a PIN this
    // terminal has cached from an earlier build cannot slip past the gate.
    if (_kDebugPinGateEnabled && pincode != _kDebugPinGateCode) {
      emit(state.copyWith(
        failure: const MessageFailure('Noto\'g\'ri PIN-kod'),
        status: Status.ERROR,
        pin: '',
      ));
      return;
    }

    emit(state.copyWith(status: Status.LOADING));

    final BrandIdTokenPair? brandIdTokenPair =
        await _secureStorage.readBrandIdToken();
    if (brandIdTokenPair == null) {
      emit(state.copyWith(status: Status.UNKNOWN));
      return;
    }
    final brandId = brandIdTokenPair.brandId;

    // The local answer, first and without a connectivity check: whether this
    // terminal can reach the server has no bearing on whether it already
    // knows this PIN.
    final cached = await _offlineCache.getForPin(brandId, pincode);
    if (cached != null) {
      await _enterSession(
        pincode: pincode,
        accessToken: cached.accessToken,
        refreshToken: cached.refreshToken,
        onSuccess: onSuccess,
      );
      _revalidateInBackground(
        brandId: brandId,
        password: brandIdTokenPair.password,
        pincode: pincode,
      );
      return;
    }

    // No local answer. Either this PIN has never been used on this terminal,
    // or it was revoked and purged — both need the server to decide.
    if (!_connectivity.isOnline) {
      emit(state.copyWith(
        failure: const ConnectionFailure(),
        status: Status.ERROR,
        pin: '',
      ));
      return;
    }

    final result = await _loginUsecase.call(
      LoginRequestModel(
        brandId: brandId,
        password: brandIdTokenPair.password,
        pincode: pincode,
      ),
    );

    result.fold(
      (failure) async {
        if (failure.isDefiniteAuthRejection) {
          // Server aniq javob berdi: bu pincode yaroqsiz. Cache'da nima
          // bo'lsa ham o'chiramiz — muddat asosidagi tugash yo'q, bu yagona
          // bekor qilish yo'li.
          await _offlineCache.removeForPin(brandId, pincode);
        }
        emit(state.copyWith(failure: failure, status: Status.ERROR, pin: ''));
      },
      (_) async {
        // `LoginUsecase` writes the token pair and caches this PIN, so the
        // next login on this terminal takes the local path above.
        await _enterSession(pincode: pincode, onSuccess: onSuccess);
      },
    );
  }

  /// Everything a successful login does once the credentials are settled.
  ///
  /// [accessToken]/[refreshToken] are passed only on the cached path, where
  /// this cubit owns writing them; the online path's usecase has already done
  /// so by the time it gets here.
  Future<void> _enterSession({
    required String pincode,
    required Function() onSuccess,
    String? accessToken,
    String? refreshToken,
  }) async {
    if (accessToken != null && refreshToken != null) {
      await _secureStorage.writeAuthToken(
        AuthTokenPair(accessToken: accessToken, refreshToken: refreshToken),
      );
    }
    // Offline login ham "oxirgi pincode" hisoblanadi — UserBloc'ning lokal
    // profil o'qishi aynan shu pincode bo'yicha to'g'ri ofitsiantni topishi
    // uchun (CLIENT_FACING_OFFLINE_PLAN.md §1).
    await _secureStorage.writeLastPincode(pincode);
    // Brand/branch retention rule: shu yerda — token yozilgandan keyin,
    // navigatsiyadan oldin — oxirgi brand+kassa juftligi bilan solishtiriladi.
    final scope = await _dataScope.onSuccessfulLogin();
    emit(state.copyWith(status: Status.SUCCESS));

    if (scope == LoginDataScope.initialSetup) {
      // A terminal with no usable replica goes to the setup screen instead of
      // into the app. This used to be `unawaited(...)` inside the call above,
      // so login landed on the floor plan while the menu, halls and tables
      // were still downloading — or, offline, were never going to arrive.
      // `InitialSetupScreen` owns the wait, the progress and the way out of
      // it, and continues to [onSuccess]'s destination when it is done.
      Navigator.pushNamedAndRemoveUntil(
        navigatorKey.currentContext!,
        AppRoutes.initialSetupScreen,
        (route) => false,
      );
      return;
    }
    onSuccess();
  }

  /// Re-checks a cache-served PIN against the server, after the cashier is
  /// already in.
  ///
  /// Deliberately not awaited and deliberately silent: its only job is to
  /// purge a PIN the server has since rejected, so the *next* login fails.
  /// It never touches the running session — a cashier is not thrown out
  /// mid-order because a background request came back badly, and a transport
  /// failure means nothing was learned and so nothing is done.
  void _revalidateInBackground({
    required String brandId,
    required String password,
    required String pincode,
  }) {
    if (!_connectivity.isOnline) return;
    unawaited(() async {
      try {
        final result = await _loginUsecase.call(
          LoginRequestModel(
            brandId: brandId,
            password: password,
            pincode: pincode,
          ),
        );
        await result.fold(
          (failure) async {
            if (failure.isDefiniteAuthRejection) {
              await _offlineCache.removeForPin(brandId, pincode);
            }
          },
          (_) async {},
        );
      } catch (_) {
        // Background hygiene; a throw here must not surface anywhere.
      }
    }());
  }

  void setPin(String value) {
    if (state.status == Status.LOADING) return;

    String pinUpdated = state.pin ?? '';
    final int maxLength = state.pinLength;

    if (value == '⌫') {
      if (pinUpdated.isNotEmpty) {
        pinUpdated = pinUpdated.substring(0, pinUpdated.length - 1);
      }
      emit(state.copyWith(pin: pinUpdated));
      return;
    }

    if (value == '✓') return;

    if (pinUpdated.length >= maxLength) return;

    pinUpdated += value;
    emit(state.copyWith(pin: pinUpdated));

    if (pinUpdated.length == maxLength) {
      final pincode = pinUpdated;
      login(
        pincode: pincode,
        onSuccess: () {
          Navigator.pushNamedAndRemoveUntil(
            navigatorKey.currentContext!,
            AppRoutes.splashScreen,
            (route) => false,
          );
        },
      );
    }
  }

  void togglePinLength() {
    if (state.status == Status.LOADING) return;
    final next = state.pinLength == 4 ? 6 : 4;
    emit(state.copyWith(pinLength: next, pin: ''));
  }

  void logoutFromApp(Function() onLogout) async {
    emit(state.copyWith(status: Status.LOADING));
    var result = await _logoutUseCase.call(NoParams());

    result.fold(
      (failure) {
        emit(state.copyWith(failure: failure, status: Status.ERROR));
      },
      (response) {
        onLogout();
        emit(state.copyWith(status: Status.SUCCESS));
      },
    );
  }
}
