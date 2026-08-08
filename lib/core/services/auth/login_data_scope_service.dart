import 'dart:async';
import 'dart:convert';

import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';

/// CLIENT_FACING_OFFLINE_PLAN.md §1 — the brand/branch-aware retention rule
/// applied on every successful PIN login, before any cached data is touched:
///
/// | New login is...                    | Action                            |
/// |------------------------------------|-----------------------------------|
/// | Same brand, same cash register     | Nothing — normal offline login    |
/// | Same brand, different register     | Additive refetch of branch data   |
/// | Different brand                    | Wipe brand-scoped data, run       |
/// |                                    | first-time setup fresh            |
///
/// First-time setup (no stored context yet, or `isPosInitialized` false —
/// the read site that flag never had) is the one carve-out where hitting the
/// network is allowed: it's prep phase, not runtime. The hydration itself is
/// `SyncEngine`'s existing pass, kicked once here rather than a second,
/// parallel fetch path.
class LoginDataScopeService {
  final AppTokenStorage _storage;
  final LocalDatabase _localDb;
  final CacheService _cache;
  final SyncEngine _syncEngine;

  LoginDataScopeService({
    required AppTokenStorage storage,
    required LocalDatabase localDb,
    required CacheService cache,
    required SyncEngine syncEngine,
  })  : _storage = storage,
        _localDb = localDb,
        _cache = cache,
        _syncEngine = syncEngine;

  /// Same claim-decode `ShiftBloc` uses — the JWT's `cash_register_id` is
  /// the only place the terminal's branch binding exists today (plan §1).
  static String? _jwtClaim(String jwt, String key) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final obj = jsonDecode(decoded);
      if (obj is! Map) return null;
      final v = obj[key];
      if (v == null) return null;
      return v.toString();
    } catch (_) {
      return null;
    }
  }

  /// Called from `LoginPinCubit` after every successful login (online or
  /// offline-cached alike) — compares the new login's brand + cash register
  /// against the stored last pair and applies the retention rule above.
  /// The data actions (wipe / store) are awaited; the hydration fetch is
  /// deliberately not, so login navigation isn't blocked on the network.
  Future<void> onSuccessfulLogin() async {
    final brandId = (await _storage.readBrandIdToken())?.brandId ?? '';
    if (brandId.isEmpty) return;
    final token = await _storage.readAccessToken() ?? '';
    final cashRegisterId =
        token.isEmpty ? '' : (_jwtClaim(token, 'cash_register_id') ?? '');

    final last = await _storage.readLastAuthContext();
    final firstTime = last == null || !_storage.isPosInitialized;
    final brandChanged = last != null && last.brandId != brandId;
    final branchChanged = last != null &&
        !brandChanged &&
        cashRegisterId.isNotEmpty &&
        last.cashRegisterId.isNotEmpty &&
        last.cashRegisterId != cashRegisterId;

    if (brandChanged) {
      // Different brand entirely: clear brand-scoped local data first, then
      // run first-time setup fresh. CacheService has no per-tenant scoping
      // at all (see its clearAll doc), so it goes too. printerSettings is
      // device-scoped and survives inside clearBrandScopedData.
      await _localDb.clearBrandScopedData();
      await _cache.clearAll();
      await _storage.setPosInitialized(false);
      // Without this, the first-mount hydration gate stays latched from the
      // previous brand's session — same reason AuthCubit.logoutFromApp
      // already resets it.
      AppScaffold.resetPrefetchGate();
    }

    await _storage.writeLastAuthContext(
      brandId: brandId,
      cashRegisterId: cashRegisterId,
    );

    if (brandChanged || firstTime) {
      unawaited(_runFirstTimeSetup());
    } else if (branchChanged) {
      // Same brand, different branch: keep existing local data, refetch the
      // new branch's data additively (halls/tables/open orders/archives) —
      // no box is cleared, the brand-level catalog is not redownloaded.
      unawaited(_syncEngine.hydrateNow());
    }
  }

  Future<void> _runFirstTimeSetup() async {
    await _syncEngine.hydrateNow(includeGoods: true);
    // Only mark setup done when the fetch actually landed data — a fully
    // offline "first-time" login must stay un-initialized so the next
    // online chance retries the prep fetch.
    if (_localDb.getTables().isNotEmpty || _localDb.getCategories().isNotEmpty) {
      await _storage.setPosInitialized(true);
    }
  }
}
