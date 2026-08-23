import 'dart:async';
import 'dart:convert';

import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart'
    show ShiftBloc;
import 'package:shared_preferences/shared_preferences.dart';

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
  final LocalDatabase _replica;
  final SyncEngine _syncEngine;
  final SharedPreferences _prefs;

  LoginDataScopeService({
    required AppTokenStorage storage,
    required LocalDatabase replica,
    required SyncEngine syncEngine,
    required SharedPreferences prefs,
  })  : _storage = storage,
        _replica = replica,
        _syncEngine = syncEngine,
        _prefs = prefs;

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
      // Different brand entirely. The replica wipe is not done here — it is
      // `resetAndBootstrap`'s first act below, so the clear and the refill
      // are one operation and there is no window in which the terminal has
      // an empty database and no bootstrap running.
      //
      // The active-shift record lives in SharedPreferences, outside the
      // replica — and `ShiftBloc._checkShift` is local-only, so a stale shift
      // from the previous brand would be presented as this brand's active
      // shift if it survived the switch.
      await _prefs.remove(ShiftBloc.localShiftPrefsKey);
      await _storage.setPosInitialized(false);
    }

    await _storage.writeLastAuthContext(
      brandId: brandId,
      cashRegisterId: cashRegisterId,
    );

    if (brandChanged) {
      // OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — the replica mirrors exactly
      // one tenant, so a login to a different brand must drop it entirely
      // rather than merge two tenants' rows under one cursor.
      unawaited(_syncEngine.replication.resetAndBootstrap());
    }

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
    // OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — the one-time replica fill.
    // Deliberately still in the background here, alongside the legacy prep
    // fetch: until Phase 4 moves the screens onto the replica, nothing reads
    // what this produces, so blocking login on it would add a wait for data
    // no one is looking at. Phase 4 promotes it to a foreground step with a
    // progress screen — the single request in the product a person waits on.
    //
    // Safe to call on every first-time login: `bootstrap` resumes from the
    // stored cursor and only marks completion on a clean catch-up.
    if (_syncEngine.replication.needsBootstrap) {
      unawaited(_syncEngine.replication.bootstrap());
    }

    await _syncEngine.hydrateNow(includeGoods: true);
    // Only mark setup done when data actually landed — a fully offline
    // "first-time" login must stay un-initialized so the next online chance
    // retries. The same two entities as before, asked of the replica: a
    // terminal with halls' tables or a catalog has been provisioned.
    final counts = _replica.tableCounts();
    if ((counts['cafe_tables'] ?? 0) > 0 || (counts['categories'] ?? 0) > 0) {
      await _storage.setPosInitialized(true);
    }
  }
}
