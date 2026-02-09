import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';

/// Keys for secure storage
enum TokensStorageKeys {
  /// Key for storing authentication tokens
  authToken('app_auth_token'),

  /// Key for app language preference
  appLanguage('app_language'),

  /// Key for brand ID tokens
  brandId('app_brand_id_token');

  /// Key name
  final String keyName;

  const TokensStorageKeys(this.keyName);
}

/// Implementation of token storage for securely storing authentication tokens
class AppTokenStorage {
  final SharedPreferences _prefs;

  /// Creates a new TokenStorageImpl with the given secure storage
  const AppTokenStorage(this._prefs);

  /// Read auth token pair from secure storage
  Future<BrandIdTokenPair?> readBrandIdToken() async {
    try {
      final tokenJson = _prefs.getString(TokensStorageKeys.brandId.keyName);
      if (tokenJson == null) return null;
      return BrandIdTokenPair.fromJson(
        jsonDecode(tokenJson) as Map<String, dynamic>,
      );
    } catch (e) {
      return null;
    }
  }

  /// Write auth token pair to secure storage
  Future<void> writeBrandIdToken(BrandIdTokenPair token) async {
    await _prefs.setString(
      TokensStorageKeys.brandId.keyName,
      jsonEncode(token.toJson()),
    );
  }

  /// Read auth token pair from secure storage
  Future<AuthTokenPair?> readAuthToken() async {
    try {
      final tokenJson = _prefs.getString(TokensStorageKeys.authToken.keyName);
      if (tokenJson == null) return null;
      return AuthTokenPair.fromJson(
        jsonDecode(tokenJson) as Map<String, dynamic>,
      );
    } catch (e) {
      return null;
    }
  }

  /// Write auth token pair to secure storage
  Future<void> writeAuthToken(AuthTokenPair token) async {
    await _prefs.setString(
      TokensStorageKeys.authToken.keyName,
      jsonEncode(token.toJson()),
    );
  }

  /// Read access token from secure storage
  Future<String?> readAccessToken() async {
    try {
      final tokenPair = await readAuthToken();
      return tokenPair?.accessToken;
    } catch (e) {
      return null;
    }
  }

  /// Read refresh token from secure storage
  Future<String?> readRefreshToken() async {
    try {
      final tokenPair = await readAuthToken();
      return tokenPair?.refreshToken;
    } catch (e) {
      return null;
    }
  }

  /// Write access token to secure storage
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

  /// Write refresh token to secure storage
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

  /// Delete all tokens from secure storage
  Future<void> deleteAuthToken() async {
    await _prefs.remove(TokensStorageKeys.authToken.keyName);
  }

  /// Read string value from secure storage
  Future<String?> readString(TokensStorageKeys key) async {
    try {
      return _prefs.getString(key.keyName);
    } catch (e) {
      return null;
    }
  }

  /// Write string value to secure storage
  Future<void> writeString(TokensStorageKeys key, String value) async {
    await _prefs.setString(key.keyName, value);
  }

  /// Delete value from secure storage
  Future<void> delete(TokensStorageKeys key) async {
    await _prefs.remove(key.keyName);
  }

  /// Clear all stored data
  Future<void> deleteAll() async {
    await _prefs.clear();
  }
}
