import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';

/// Keys for storage. See [AppTokenStorage._secureKeys] for which of these
/// live in OS-backed secure storage vs plain `SharedPreferences`.
enum TokensStorageKeys {
  /// Key for storing authentication tokens
  authToken('app_auth_token'),

  /// Key for app language preference
  appLanguage('app_language'),

  /// Key for the virtual keyboard's typing-language preference
  keyboardLanguage('keyboard_language'),

  /// Key for brand ID tokens (brand_id + pos_password)
  brandId('app_brand_id_token'),

  /// Key for POS is initialized flag
  posIsInitialized('pos_is_initialized'),

  /// Key for cached user data
  posUser('pos_user'),

  /// Last successfully used pincode (for offline PIN login)
  lastPincode('pos_last_pincode'),

  /// Last authenticated brand id + cash_register_id pair — the comparison
  /// point for CLIENT_FACING_OFFLINE_PLAN.md §1's brand/branch retention
  /// rule on each new login
  lastAuthContext('pos_last_auth_context');

  /// Key name
  final String keyName;

  const TokensStorageKeys(this.keyName);
}

/// Token/credential storage. Credential-bearing keys (auth tokens, the
/// brand_id+password pair, cached user, last pincode) live in OS-backed
/// secure storage (Keychain / EncryptedSharedPreferences / DPAPI / libsecret
/// via `flutter_secure_storage`) — see offline-first-architecture-plan.md
/// §11 Phase 6. Non-sensitive config (language prefs, the initialized flag)
/// stays in plain `SharedPreferences`: `isPosInitialized` in particular has
/// to stay synchronous, which secure storage can't offer.
class AppTokenStorage {
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  /// Creates a new TokenStorageImpl with the given prefs/secure storage backends
  const AppTokenStorage(this._prefs, this._secure);

  static const _secureKeys = {
    TokensStorageKeys.authToken,
    TokensStorageKeys.brandId,
    TokensStorageKeys.posUser,
    TokensStorageKeys.lastPincode,
  };

  /// Linux desktop, debug builds only: mirror secure values into
  /// `SharedPreferences` so a broken libsecret cannot lock a developer out.
  ///
  /// On this platform `flutter_secure_storage` writes a libsecret item that it
  /// then cannot read back — verified on both 9.2.4 and 10.3.1, with the item
  /// present, unlocked, and findable by attribute over the Secret Service API.
  /// The consequence is not a degraded experience, it is a terminal that cannot
  /// sign in at all: the brand credential and the session token both read null,
  /// so the pincode step can never build its request and every authenticated
  /// call goes out bare and comes back 401.
  ///
  /// **This writes credentials in plaintext, so it is fenced twice.** Debug
  /// builds only, and Linux only. A release binary — and every Windows,
  /// Android and iOS build, debug or not — never touches this path and keeps
  /// using the OS keystore alone.
  /// Off unless the developer asks for it explicitly:
  ///
  /// ```
  /// flutter run -d linux --dart-define=POS_DEV_INSECURE_TOKEN_MIRROR=true
  /// ```
  ///
  /// It was briefly `kDebugMode && Platform.isLinux`, which was wrong.
  /// `secure_storage_migration_test` asserts that a credential is never
  /// readable from plain `SharedPreferences` — the invariant `migrateLegacy
  /// Plaintext` and DECISIONS.md D14 exist to protect — and that test failed
  /// the moment this defaulted on, which is exactly what it is for. A
  /// workaround for one broken platform backend must not quietly relax a
  /// security property everywhere else, so it is opt-in, and still fenced to
  /// debug builds on Linux on top of that.
  static const _mirrorRequested =
      bool.fromEnvironment('POS_DEV_INSECURE_TOKEN_MIRROR');

  static bool get _mirrorToPrefs =>
      _mirrorRequested && kDebugMode && Platform.isLinux;

  String _mirrorKey(TokensStorageKeys key) => 'dev_mirror_${key.keyName}';

  Future<String?> _read(TokensStorageKeys key) async {
    if (!_secureKeys.contains(key)) return _prefs.getString(key.keyName);
    try {
      final secure = await _secure.read(key: key.keyName);
      if (secure != null) return secure;
      if (_mirrorToPrefs) {
        final mirrored = _prefs.getString(_mirrorKey(key));
        if (mirrored != null && kDebugMode) {
          debugPrint('[AppTokenStorage] ${key.keyName}: secure store returned '
              'null, using the Linux debug mirror');
        }
        return mirrored;
      }
      return null;
    } catch (e, st) {
      // Every caller wraps its read in `catch (_) => null`, which makes a
      // backend that is refusing to answer indistinguishable from a key that
      // was never written — and on Linux, where the backend is libsecret and a
      // locked or missing keyring is a real runtime condition, those are very
      // different problems with the same symptom: an operator told to sign in
      // again with a credential that is sitting in the keyring already.
      if (kDebugMode) {
        debugPrint('[AppTokenStorage] secure read FAILED for '
            '\'${key.keyName}\': $e\n$st');
      }
      rethrow;
    }
  }

  Future<void> _write(TokensStorageKeys key, String value) async {
    if (!_secureKeys.contains(key)) {
      await _prefs.setString(key.keyName, value);
      return;
    }
    await _secure.write(key: key.keyName, value: value);
    if (_mirrorToPrefs) await _prefs.setString(_mirrorKey(key), value);
  }

  Future<void> _delete(TokensStorageKeys key) async {
    if (!_secureKeys.contains(key)) {
      await _prefs.remove(key.keyName);
      return;
    }
    await _secure.delete(key: key.keyName);
    // The mirror has to go with it, or a logout would leave a credential
    // behind that the next read happily picks back up.
    if (_mirrorToPrefs) await _prefs.remove(_mirrorKey(key));
  }

  /// Read auth token pair from storage
  Future<BrandIdTokenPair?> readBrandIdToken() async {
    try {
      final tokenJson = await _read(TokensStorageKeys.brandId);
      if (tokenJson == null) {
        // Worth a line even though it is an ordinary "not signed in yet" on a
        // fresh terminal. On Linux it is also the signature of a
        // `flutter_secure_storage` backend that accepted the write and cannot
        // find it again — the credential is in the keyring, this returns null,
        // and the pincode screen tells the operator to sign in with a brand id
        // they just entered. Silent, that costs hours.
        if (kDebugMode) {
          debugPrint('[AppTokenStorage] readBrandIdToken -> null');
        }
        return null;
      }
      return BrandIdTokenPair.fromJson(
        jsonDecode(tokenJson) as Map<String, dynamic>,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AppTokenStorage] readBrandIdToken FAILED: $e\n$st');
      }
      return null;
    }
  }

  /// Write auth token pair to storage
  Future<void> writeBrandIdToken(BrandIdTokenPair token) async {
    await _write(
      TokensStorageKeys.brandId,
      jsonEncode(token.toJson()),
    );
  }

  /// Read auth token pair from storage
  Future<AuthTokenPair?> readAuthToken() async {
    try {
      final tokenJson = await _read(TokensStorageKeys.authToken);
      if (tokenJson == null) return null;
      return AuthTokenPair.fromJson(
        jsonDecode(tokenJson) as Map<String, dynamic>,
      );
    } catch (e) {
      return null;
    }
  }

  /// Write auth token pair to storage
  Future<void> writeAuthToken(AuthTokenPair token) async {
    await _write(
      TokensStorageKeys.authToken,
      jsonEncode(token.toJson()),
    );
  }

  /// Read access token from storage
  Future<String?> readAccessToken() async {
    try {
      final tokenPair = await readAuthToken();
      return tokenPair?.accessToken;
    } catch (e) {
      return null;
    }
  }

  /// Read refresh token from storage
  Future<String?> readRefreshToken() async {
    try {
      final tokenPair = await readAuthToken();
      return tokenPair?.refreshToken;
    } catch (e) {
      return null;
    }
  }

  /// Write access token to storage
  Future<void> writeAccessToken(String accessToken) async {
    try {
      final existingPair = await readAuthToken();
      final newPair = AuthTokenPair(
        accessToken: accessToken,
        refreshToken: existingPair?.refreshToken ?? '',
      );
      await writeAuthToken(newPair);
    } catch (e) {
      // Fallback: just write the access token
      await writeAuthToken(
        AuthTokenPair(accessToken: accessToken, refreshToken: ''),
      );
    }
  }

  /// Write refresh token to storage
  Future<void> writeRefreshToken(String refreshToken) async {
    try {
      final existingPair = await readAuthToken();
      final newPair = AuthTokenPair(
        accessToken: existingPair?.accessToken ?? '',
        refreshToken: refreshToken,
      );
      await writeAuthToken(newPair);
    } catch (e) {
      // Fallback: just write the refresh token
      await writeAuthToken(
        AuthTokenPair(accessToken: '', refreshToken: refreshToken),
      );
    }
  }

  /// Delete auth tokens from storage
  Future<void> deleteAuthToken() async {
    await _delete(TokensStorageKeys.authToken);
  }

  /// Delete only user session (keep POS setup: brand_id, pos_password, pos_is_initialized)
  Future<void> deleteUserSession() async {
    await _delete(TokensStorageKeys.authToken);
    await _delete(TokensStorageKeys.posUser);
  }

  /// Mark POS as initialized
  Future<void> setPosInitialized(bool value) async {
    await _prefs.setBool(TokensStorageKeys.posIsInitialized.keyName, value);
  }

  /// Check if POS is initialized
  bool get isPosInitialized =>
      _prefs.getBool(TokensStorageKeys.posIsInitialized.keyName) ?? false;

  /// Read string value from storage
  Future<String?> readString(TokensStorageKeys key) async {
    try {
      return await _read(key);
    } catch (e) {
      return null;
    }
  }

  /// Write string value to storage
  Future<void> writeString(TokensStorageKeys key, String value) async {
    await _write(key, value);
  }

  /// Delete value from storage
  Future<void> delete(TokensStorageKeys key) async {
    await _delete(key);
  }

  Future<void> writeLastPincode(String pincode) async =>
      _write(TokensStorageKeys.lastPincode, pincode);

  /// The stored "last authenticated brand id + cash_register_id" pair
  /// (CLIENT_FACING_OFFLINE_PLAN.md §1). Written after every successful
  /// login; compared against the new login's context before any cached data
  /// is touched. Not a credential, so it lives in plain `SharedPreferences`.
  Future<({String brandId, String cashRegisterId})?> readLastAuthContext() async {
    try {
      final raw = await _read(TokensStorageKeys.lastAuthContext);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        brandId: json['brand_id'] as String? ?? '',
        cashRegisterId: json['cash_register_id'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLastAuthContext({
    required String brandId,
    required String cashRegisterId,
  }) =>
      _write(
        TokensStorageKeys.lastAuthContext,
        jsonEncode({
          'brand_id': brandId,
          'cash_register_id': cashRegisterId,
        }),
      );

  Future<String?> readLastPincode() async => _read(TokensStorageKeys.lastPincode);

  /// Clear all stored data — plain prefs and secure storage alike.
  Future<void> deleteAll() async {
    await _prefs.clear();
    await _secure.deleteAll();
  }

  static const List<TokensStorageKeys> _legacyPlaintextKeys = [
    TokensStorageKeys.authToken,
    TokensStorageKeys.brandId,
    TokensStorageKeys.lastPincode,
  ];

  /// One-time upgrade path for installs that predate the secure-storage
  /// migration: moves any credential still sitting in plaintext
  /// `SharedPreferences` into secure storage, then deletes the plaintext
  /// copy. Idempotent (a no-op once the plaintext keys are gone), so it's
  /// safe to call unconditionally on every startup rather than needing its
  /// own "have I migrated" flag.
  static Future<void> migrateLegacyPlaintext(
    SharedPreferences prefs,
    FlutterSecureStorage secure,
  ) async {
    for (final key in _legacyPlaintextKeys) {
      final plain = prefs.getString(key.keyName);
      if (plain == null) continue;
      await secure.write(key: key.keyName, value: plain);
      await prefs.remove(key.keyName);
    }
  }
}
