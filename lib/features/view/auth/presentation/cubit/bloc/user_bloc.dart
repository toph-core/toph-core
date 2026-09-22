import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/user/get_user_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/sync_printer_settings_usecase.dart';
part 'user_event.dart';
part 'user_state.dart';
part 'user_bloc.freezed.dart';

class UserBloc extends Bloc<UserEvent, UserState> {
  late final GetUserUsecase _getUserUsecase;
  late final SyncPrinterSettingsUsecase _syncPrinterSettingsUsecase;

  UserBloc({
    required GetUserUsecase getUserUsecase,
    required SyncPrinterSettingsUsecase syncPrinterSettingsUsecase,
  }) : _getUserUsecase = getUserUsecase,
       _syncPrinterSettingsUsecase = syncPrinterSettingsUsecase,
       super(const UserState()) {
    on<_Started>(_started);
    on<_GetUser>(_getUser);
  }

  /// CLIENT_FACING_OFFLINE_PLAN.md §1: the server profile fetch is no longer
  /// initiated from the UI layer (splash / AppScaffold's reconnect listener
  /// used to fire this) — `SyncEngine.tick()` dispatches it from the
  /// background sync side instead. The UI reads the cached profile via
  /// [_started]. The handler's own logic is unchanged: refresh the offline
  /// cache on success, purge it and return to login on a definite rejection.
  /// The routes that *are* the logged-out state, where a 401 is the normal
  /// condition rather than a session ending.
  static const _authRoutes = {
    AppRoutes.loginScreen,
    AppRoutes.loginPinScreen,
    AppRoutes.splashScreen,
    AppRoutes.initialSetupScreen,
  };

  /// Whether the operator is currently somewhere in the sign-in flow.
  ///
  /// Read from the navigator rather than tracked in state, because the thing
  /// being asked about is literally "what is on screen right now". Unknown
  /// context, or a route with no name, counts as *not* an auth route: the
  /// eject is the safer default for a session that really has ended, and this
  /// guard only exists to stop it firing at the one moment it does harm.
  bool _isOnAuthRoute() {
    final context = navigatorKey.currentContext;
    if (context == null) return false;
    return _authRoutes.contains(ModalRoute.of(context)?.settings.name);
  }

  void _getUser(_GetUser event, emit) async {
    // No LOADING emit when a profile is already on screen — this now runs
    // periodically in the background, and a status flicker on every tick
    // would show through any screen watching this bloc.
    if (state.userMOdel == null) {
      emit(state.copyWith(status: Status.LOADING));
    }

    // Internet yo'q — API ga murojaat qilmasdan darhol cachega o'tamiz
    if (!inject<ConnectivityCubit>().isOnline) {
      await _tryOfflineUser(emit);
      return;
    }

    final response = await _getUserUsecase.call(NoParams());
    // Awaited. `fold` returns whatever its branches return, and both of these
    // are `async` — so nothing used to wait for them, this handler completed
    // first, and the `emit` inside each branch fired against a closed emitter:
    // "emit was called after an event handler completed normally", thrown as an
    // unhandled exception on every 401.
    await response.fold(
      (l) async {
        if (!l.isDefiniteAuthRejection) {
          // Ulanish/timeout/server xatosi — aniq javob yo'q, cache'ga
          // tushamiz (avval faqat ConnectionFailure uchun edi).
          await _tryOfflineUser(emit);
          return;
        }
        // Server aniq javob berdi: token/foydalanuvchi endi yaroqsiz. Bu
        // ayni terminalda keyingi offline PIN/brand loginlar ham shu
        // foydalanuvchi uchun ishlamasligi kerak — shuning uchun tegishli
        // cache yozuvlarini ham o'chiramiz, shunchaki login ekraniga
        // qaytarib qo'yish emas. Bu mexanizm reconnect paytida ham ishlaydi
        // (`AppScaffold`ning har safar aloqa tiklanganda `UserEvent.getUser()`
        // yuborishi orqali) — hozirgi sessiya davomida foydalanuvchi
        // faolsizlantirilgan bo'lsa, keyingi muvaffaqiyatli aloqada aniqlanadi.
        // ...unless the operator is already signing in. This refresh runs on a
        // timer from `SyncEngine`, and on a terminal whose stored token has
        // expired it answers 401 every few minutes — including while somebody
        // is standing at the login flow trying to replace that very token.
        //
        // Ejecting them then is not a no-op, it is the bug: the brand screen
        // does not authenticate (it stores brand id and password and moves on),
        // so the real login happens at the pincode step — and
        // `pushNamedAndRemoveUntil` tears that screen down mid-entry and drops
        // them back at the start. Every attempt was interrupted by the next
        // tick, and the purge below took their offline credentials with it, so
        // the terminal could not fall back to a cached login either. From the
        // floor it looks like the PIN simply does not work.
        //
        // There is nothing to eject them *from* here in any case: these routes
        // are the logged-out state, and the session this would invalidate is
        // the one they are busy replacing.
        if (_isOnAuthRoute()) {
          if (!emit.isDone) emit(state.copyWith(status: Status.ERROR, failure: l));
          return;
        }

        await _purgeOfflineCacheForCurrentUser();
        Navigator.pushNamedAndRemoveUntil(
          navigatorKey.currentContext!,
          AppRoutes.loginScreen,
          (route) => false,
        );
        // Guarded: this branch is `async`, so between the await above and here
        // the handler can have finished even though the fold is now awaited —
        // a `close()` during logout is the ordinary way.
        if (!emit.isDone) emit(state.copyWith(status: Status.ERROR, failure: l));
      },
      (r) async {
        // Navigation already happened in splash screen — just emit user data
        if (emit.isDone) return;
        emit(state.copyWith(status: Status.SUCCESS, userMOdel: r));
        // Offline cache'ni yangilash — keyingi offline loginlar uchun
        unawaited(_updateOfflineCache(r));
        unawaited(
          _syncPrinterSettingsUsecase.call(NoParams()).then((sync) {
            sync.fold(
              (f) {
                if (kDebugMode) {
                  debugPrint('[UserBloc] Printer settings sync: $f');
                }
              },
              (_) {},
            );
          }),
        );
      },
    );
  }

  Future<void> _updateOfflineCache(UserModel user) async {
    try {
      final storage = inject<AppTokenStorage>();
      final brandPair = await storage.readBrandIdToken();
      final tokenPair = await storage.readAuthToken();
      if (brandPair == null || tokenPair == null) return;
      final cache = inject<OfflineAuthCache>();

      // Brand-darajali cache (mavjud)
      await cache.saveUser(
        brandId: brandPair.brandId,
        password: brandPair.password,
        user: user,
        accessToken: tokenPair.accessToken,
        refreshToken: tokenPair.refreshToken,
      );

      // Pincode-darajali cache — har bir ofitsiant uchun alohida
      final pincode = await storage.readLastPincode();
      if (pincode != null && pincode.isNotEmpty) {
        await cache.saveForPin(
          brandId: brandPair.brandId,
          pincode: pincode,
          user: user,
          accessToken: tokenPair.accessToken,
          refreshToken: tokenPair.refreshToken,
        );
      }
    } catch (_) {}
  }

  /// [_updateOfflineCache]ning teskarisi — server bu foydalanuvchi/token endi
  /// yaroqsiz deb aniq javob berganda chaqiriladi. Brand-darajali va (agar
  /// mavjud bo'lsa) pincode-darajali cache yozuvlarini o'chiradi, shunda shu
  /// terminaldagi keyingi offline login urinishlari ham rad etiladi — vaqt
  /// asosidagi muddat emas, aynan shu mexanizm orqali.
  Future<void> _purgeOfflineCacheForCurrentUser() async {
    try {
      final storage = inject<AppTokenStorage>();
      final brandPair = await storage.readBrandIdToken();
      if (brandPair == null) return;
      final cache = inject<OfflineAuthCache>();
      await cache.removeUser(brandPair.brandId);
      final pincode = await storage.readLastPincode();
      if (pincode != null && pincode.isNotEmpty) {
        await cache.removeForPin(brandPair.brandId, pincode);
      }
    } catch (_) {}
  }

  Future<void> _tryOfflineUser(Emitter<UserState> emit) async {
    try {
      final storage = inject<AppTokenStorage>();
      final brandPair = await storage.readBrandIdToken();
      if (brandPair == null) {
        _goToLogin();
        return;
      }

      final offlineCache = inject<OfflineAuthCache>();

      // 1. Brand-darajali cache
      final cached = await offlineCache.getCachedUser(brandPair.brandId);
      if (cached != null) {
        emit(state.copyWith(
          status: Status.SUCCESS,
          userMOdel: UserModel.fromJson(cached.userModelJson),
        ));
        return;
      }

      // 2. Per-pin cache — so'nggi pincode bilan
      final pincode = await storage.readLastPincode();
      if (pincode != null && pincode.isNotEmpty) {
        final pinCached = await offlineCache.getForPin(brandPair.brandId, pincode);
        if (pinCached != null) {
          emit(state.copyWith(
            status: Status.SUCCESS,
            userMOdel: UserModel.fromJson(pinCached.userModelJson),
          ));
          return;
        }
      }

      _goToLogin();
    } catch (_) {
      _goToLogin();
    }
  }

  void _goToLogin() {
    Navigator.pushNamedAndRemoveUntil(
      navigatorKey.currentContext!,
      AppRoutes.loginScreen,
      (route) => false,
    );
  }

  /// CLIENT_FACING_OFFLINE_PLAN.md §1: the UI-initiated path — a pure local
  /// read of the cached profile, no network. Dispatched at app start
  /// (main.dart) and after each login (splash). Prefers the per-pincode
  /// entry (the waiter who actually logged in — offline logins update
  /// `lastPincode` too now) over the brand-level one; silently a no-op when
  /// nothing is cached yet, since this also fires before first login.
  void _started(_Started event, emit) async {
    try {
      final storage = inject<AppTokenStorage>();
      final brandPair = await storage.readBrandIdToken();
      if (brandPair == null) return;
      final cache = inject<OfflineAuthCache>();

      OfflineCachedUser? cached;
      final pincode = await storage.readLastPincode();
      if (pincode != null && pincode.isNotEmpty) {
        cached = await cache.getForPin(brandPair.brandId, pincode);
      }
      cached ??= await cache.getCachedUser(brandPair.brandId);
      if (cached != null) {
        emit(state.copyWith(
          status: Status.SUCCESS,
          userMOdel: UserModel.fromJson(cached.userModelJson),
        ));
      }
    } catch (_) {}
  }
}
