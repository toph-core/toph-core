import 'dart:convert';
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
  lastPincode('pos_last_pincode');

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

  Future<String?> _read(TokensStorageKeys key) => _secureKeys.contains(key)
      ? _secure.read(key: key.keyName)
      : Future.value(_prefs.getString(key.keyName));

  Future<void> _write(TokensStorageKeys key, String value) =>
      _secureKeys.contains(key)
          ? _secure.write(key: key.keyName, value: value)
          : _prefs.setString(key.keyName, value);

  Future<void> _delete(TokensStorageKeys key) => _secureKeys.contains(key)
      ? _secure.delete(key: key.keyName)
      : _prefs.remove(key.keyName);

  /// Read auth token pair from storage
  Future<BrandIdTokenPair?> readBrandIdToken() async {
    try {
      final tokenJson = await _read(TokensStorageKeys.brandId);
      if (tokenJson == null) return null;
      return BrandIdTokenPair.fromJson(
        jsonDecode(tokenJson) as Map<String, dynamic>,
      );
    } catch (e) {
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
