import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';

import 'support/in_memory_secure_storage.dart';

/// Covers the two genuinely low-dependency, high-value units behind the
/// offline-auth revocation design (§11 Phase 6): the failure classification
/// that decides "trust the server's answer" vs "fall back to the cache",
/// and the cache's new removal methods that make a rejection actually stick
/// offline. The cubits that wire these together (`LoginPinCubit`,
/// `AuthCubit`, `UserBloc`) aren't covered here — they'd need a real
/// `LoginUsecase`/`AuthRepository`/`DioClient` chain to exercise end to end,
/// which is disproportionate to what's actually new in them (a few lines of
/// branching over already-tested primitives) — that wiring is verified by
/// code review instead, same tradeoff made for `PrinterService
/// .printKitchenReceiptFor`'s DI-entangled call sites in Phase 5.
void main() {
  group('Failure.isDefiniteAuthRejection', () {
    test('a real server answer about the credential is a definite rejection', () {
      expect(const ValidationFailure().isDefiniteAuthRejection, isTrue);
      expect(const UnauthorizedFailure().isDefiniteAuthRejection, isTrue);
      expect(const NotFoundFailure().isDefiniteAuthRejection, isTrue);
      expect(const MessageFailure('inactive').isDefiniteAuthRejection, isTrue);
    });

    test('failing to get a real answer at all is not a definite rejection', () {
      expect(const ConnectionFailure().isDefiniteAuthRejection, isFalse);
      expect(const TimeoutFailure().isDefiniteAuthRejection, isFalse);
      expect(const ServerFailure().isDefiniteAuthRejection, isFalse);
      expect(const UnknownFailure().isDefiniteAuthRejection, isFalse);
      expect(const ParsingFailure().isDefiniteAuthRejection, isFalse);
      expect(const OtherFailure().isDefiniteAuthRejection, isFalse);
      expect(const CacheFailure().isDefiniteAuthRejection, isFalse);
      expect(const EmptyFailure().isDefiniteAuthRejection, isFalse);
    });

    // 403 is deliberately excluded from the definite-rejection set — the
    // backend uses it for role/permission gating on unrelated endpoints, not
    // "this credential is invalid" (confirmed: wrong pincode returns 401).
    // Treating it as definite would risk purging a valid offline-cached user
    // over a permission check unrelated to their credential's validity.
    test('a 403 (forbidden) is not treated as a definite credential rejection', () {
      expect(const UnauthenticatedFailure().isDefiniteAuthRejection, isFalse);
    });
  });

  group('Failure.isConnectivityIssue', () {
    test('connection and timeout failures are queue-worthy', () {
      expect(const ConnectionFailure().isConnectivityIssue, isTrue);
      expect(const TimeoutFailure().isConnectivityIssue, isTrue);
    });

    test('a real server answer is not a connectivity issue', () {
      expect(const ValidationFailure().isConnectivityIssue, isFalse);
      expect(const UnauthorizedFailure().isConnectivityIssue, isFalse);
      expect(const ServerFailure().isConnectivityIssue, isFalse);
      expect(const MessageFailure('x').isConnectivityIssue, isFalse);
    });
  });

  group('OfflineAuthCache removal', () {
    OfflineAuthCache freshCache() {
      InMemorySecureStoragePlatform.install();
      return const OfflineAuthCache(FlutterSecureStorage());
    }

    test('removeUser purges a cached brand-level login and only that one', () async {
      final cache = freshCache();
      await cache.saveUser(
        brandId: 'brand-1',
        password: 'secret',
        user: const UserModel(id: 'u1'),
        accessToken: 'a1',
        refreshToken: 'r1',
      );
      await cache.saveUser(
        brandId: 'brand-2',
        password: 'other',
        user: const UserModel(id: 'u2'),
        accessToken: 'a2',
        refreshToken: 'r2',
      );

      expect(await cache.getCachedUser('brand-1'), isNotNull);

      await cache.removeUser('brand-1');

      expect(await cache.getCachedUser('brand-1'), isNull);
      expect(
        await cache.getCachedUser('brand-2'),
        isNotNull,
        reason: 'removing one brand must not touch an unrelated one',
      );
    });

    test('removeUser on a brand that was never cached is a safe no-op', () async {
      final cache = freshCache();
      await cache.removeUser('never-cached');
      expect(await cache.getCachedUser('never-cached'), isNull);
    });

    test('removeForPin purges a cached PIN login and only that one, leaving other pincodes for the same brand intact', () async {
      final cache = freshCache();
      await cache.saveForPin(
        brandId: 'brand-1',
        pincode: '1111',
        user: const UserModel(id: 'waiter-1'),
        accessToken: 'a1',
        refreshToken: 'r1',
      );
      await cache.saveForPin(
        brandId: 'brand-1',
        pincode: '2222',
        user: const UserModel(id: 'waiter-2'),
        accessToken: 'a2',
        refreshToken: 'r2',
      );

      expect(await cache.getForPin('brand-1', '1111'), isNotNull);

      await cache.removeForPin('brand-1', '1111');

      expect(
        await cache.getForPin('brand-1', '1111'),
        isNull,
        reason: 'the revoked pincode must no longer authenticate offline',
      );
      expect(
        await cache.getForPin('brand-1', '2222'),
        isNotNull,
        reason: 'a different waiter\'s cached pincode on the same brand must survive',
      );
    });

    test('a subsequent save can still re-populate a previously removed entry (re-hire / re-validated case)', () async {
      final cache = freshCache();
      await cache.saveForPin(
        brandId: 'brand-1',
        pincode: '1111',
        user: const UserModel(id: 'w1'),
        accessToken: 'a1',
        refreshToken: 'r1',
      );
      await cache.removeForPin('brand-1', '1111');
      expect(await cache.getForPin('brand-1', '1111'), isNull);

      await cache.saveForPin(
        brandId: 'brand-1',
        pincode: '1111',
        user: const UserModel(id: 'w1'),
        accessToken: 'a3',
        refreshToken: 'r3',
      );
      final revived = await cache.getForPin('brand-1', '1111');
      expect(revived, isNotNull);
      expect(revived!.accessToken, 'a3');
    });
  });
}
