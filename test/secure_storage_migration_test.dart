import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

/// Covers §11 Phase 6's secure-storage migration: credential-bearing keys
/// (tokens, brand password, pincode, the offline auth cache) now live in
/// `flutter_secure_storage` instead of plaintext `SharedPreferences`, and
/// installs upgrading from the old plaintext era get migrated once at
/// startup rather than losing their session. Non-sensitive config
/// (language prefs, the initialized flag) deliberately stays in
/// `SharedPreferences` — asserted here too, since that's a real behavior
/// difference, not an oversight.
void main() {
  Future<(SharedPreferences, FlutterSecureStorage)> freshBackends() async {
    SharedPreferences.setMockInitialValues({});
    InMemorySecureStoragePlatform.install();
    return (await SharedPreferences.getInstance(), const FlutterSecureStorage());
  }

  group('AppTokenStorage: secure vs plain routing', () {
    test('brand id/password and auth tokens are not readable from plain SharedPreferences', () async {
      final (prefs, secure) = await freshBackends();
      final storage = AppTokenStorage(prefs, secure);

      await storage.writeBrandIdToken(
        const BrandIdTokenPair(brandId: 'brand-1', password: 'super-secret'),
      );
      await storage.writeAuthToken(
        const AuthTokenPair(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      await storage.writeLastPincode('1234');

      // The whole point of the migration: none of this shows up in a
      // plaintext dump of SharedPreferences.
      final dump = prefs.getKeys().map((k) => prefs.get(k)).join(' ');
      expect(dump, isNot(contains('super-secret')));
      expect(dump, isNot(contains('access-1')));
      expect(dump, isNot(contains('1234')));

      // But it's still readable back through the storage's own API.
      final brandPair = await storage.readBrandIdToken();
      expect(brandPair?.password, 'super-secret');
      final tokenPair = await storage.readAuthToken();
      expect(tokenPair?.accessToken, 'access-1');
      expect(await storage.readLastPincode(), '1234');
    });

    test('non-sensitive config (language, initialized flag) still lives in plain SharedPreferences', () async {
      final (prefs, secure) = await freshBackends();
      final storage = AppTokenStorage(prefs, secure);

      await storage.writeString(TokensStorageKeys.appLanguage, 'uz');
      await storage.setPosInitialized(true);

      expect(prefs.getString(TokensStorageKeys.appLanguage.keyName), 'uz');
      expect(prefs.getBool(TokensStorageKeys.posIsInitialized.keyName), isTrue);
      // isPosInitialized has to stay synchronous — that's the reason this
      // key wasn't moved to secure storage.
      expect(storage.isPosInitialized, isTrue);
    });

    test('deleteAll wipes both backends', () async {
      final (prefs, secure) = await freshBackends();
      final storage = AppTokenStorage(prefs, secure);

      await storage.writeBrandIdToken(
        const BrandIdTokenPair(brandId: 'brand-1', password: 'secret'),
      );
      await storage.writeString(TokensStorageKeys.appLanguage, 'ru');

      await storage.deleteAll();

      expect(await storage.readBrandIdToken(), isNull);
      expect(prefs.getString(TokensStorageKeys.appLanguage.keyName), isNull);
    });
  });

  group('AppTokenStorage.migrateLegacyPlaintext', () {
    test('moves a plaintext credential into secure storage and deletes the plaintext copy', () async {
      final (prefs, secure) = await freshBackends();
      // Simulate a pre-migration install: the brand token was written
      // straight into SharedPreferences by the old code.
      await prefs.setString(
        TokensStorageKeys.brandId.keyName,
        '{"brandId":"legacy-brand","password":"legacy-pw"}',
      );

      await AppTokenStorage.migrateLegacyPlaintext(prefs, secure);

      expect(
        prefs.getString(TokensStorageKeys.brandId.keyName),
        isNull,
        reason: 'the plaintext copy must be deleted once migrated',
      );
      final migrated = AppTokenStorage(prefs, secure);
      final brandPair = await migrated.readBrandIdToken();
      expect(brandPair?.brandId, 'legacy-brand');
      expect(brandPair?.password, 'legacy-pw');
    });

    test('is a safe no-op when there is nothing plaintext to migrate', () async {
      final (prefs, secure) = await freshBackends();
      await AppTokenStorage.migrateLegacyPlaintext(prefs, secure);
      final storage = AppTokenStorage(prefs, secure);
      expect(await storage.readBrandIdToken(), isNull);
      expect(await storage.readAuthToken(), isNull);
    });

    test('running migration twice is harmless (idempotent)', () async {
      final (prefs, secure) = await freshBackends();
      await prefs.setString(TokensStorageKeys.lastPincode.keyName, '9999');

      await AppTokenStorage.migrateLegacyPlaintext(prefs, secure);
      await AppTokenStorage.migrateLegacyPlaintext(prefs, secure);

      final storage = AppTokenStorage(prefs, secure);
      expect(await storage.readLastPincode(), '9999');
    });
  });

  group('OfflineAuthCache.migrateLegacyPlaintext', () {
    test('moves both cache blobs into secure storage and deletes the plaintext copies', () async {
      final (prefs, secure) = await freshBackends();
      final legacyUser = OfflineCachedUser(
        brandId: 'brand-1',
        password: 'pw',
        accessToken: 'a1',
        refreshToken: 'r1',
        userModelJson: const UserModel(id: 'u1').toJson(),
      );
      await prefs.setString(
        'offline_users_v1',
        jsonEncode({'brand-1': legacyUser.toJson()}),
      );

      await OfflineAuthCache.migrateLegacyPlaintext(prefs, secure);

      expect(prefs.getString('offline_users_v1'), isNull);
      final cache = OfflineAuthCache(secure);
      final cached = await cache.getCachedUser('brand-1');
      expect(cached?.accessToken, 'a1');
    });
  });
}
