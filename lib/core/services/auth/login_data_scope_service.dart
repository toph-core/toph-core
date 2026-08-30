import 'dart:async';
import 'dart:convert';

import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/sync/replication_service.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
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
/// What a login turned out to need, decided by [LoginDataScopeService
/// .onSuccessfulLogin] and acted on by its caller.
enum LoginDataScope {
  /// Same brand, same register. The replica already describes this terminal.
  none,

  /// Same brand, different register. Branch-scoped rows are refetched
  /// additively in the background — nothing is cleared, so the app is usable
  /// throughout and there is nothing to wait for.
  branchRefresh,

  /// A terminal with no usable replica: first ever login, an interrupted
  /// setup, or a brand switch that invalidates everything stored. The caller
  /// must run [LoginDataScopeService.runInitialSetup] and keep the operator on
  /// a progress screen until it finishes.
  initialSetup,
}

/// How [LoginDataScopeService.runInitialSetup] ended.
enum InitialSetupOutcome {
  /// The replica is filled and the terminal is marked initialized.
  ready,

  /// The pull could not run or could not finish — no connectivity, a server
  /// error, or a partial feed. The cursor holds whatever was applied, so
  /// retrying resumes rather than restarting.
  incomplete,
}

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

  /// The JWT's `cash_register_id` is the only place the terminal's own
  /// register binding exists today (plan §1). `ShiftBloc` used to decode the
  /// same claim for the same reason; it no longer needs to, since a shift is
  /// the branch's rather than the register's.
  /// Where `ShiftBloc` used to keep this terminal's private active shift,
  /// before the shift became a replicated `branch_shifts` row shared by the
  /// whole branch. Kept only so an upgrading terminal's leftover record is
  /// cleared once rather than lingering in SharedPreferences forever; nothing
  /// reads it.
  ///
  /// Public so the brand-switch test can assert the clear actually happens —
  /// the record lives outside the replica, so it is the one piece of shift
  /// state the replica wipe cannot account for.
  static const String legacyLocalShiftPrefsKey = 'pos_local_active_shift';

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
  ///
  /// Decides; it no longer also acts. The first-time pull used to be started
  /// here with `unawaited(...)`, so login returned immediately and the
  /// operator walked into an app whose halls, tables and menu were still
  /// arriving — or, offline, were not coming at all. The plan always called
  /// for this to be a foreground step ("the single request in the product a
  /// person waits on"); returning the decision instead of firing it is what
  /// lets the caller put a screen in front of it.
  ///
  /// The background case stays background: a branch refresh is additive over
  /// a replica that already works, so there is nothing to wait for.
  Future<LoginDataScope> onSuccessfulLogin() async {
    final brandId = (await _storage.readBrandIdToken())?.brandId ?? '';
    if (brandId.isEmpty) return LoginDataScope.none;
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
      // `resetAndBootstrap`'s first act in [runInitialSetup], so the clear and
      // the refill are one operation and there is no window in which the
      // terminal has an empty database and no bootstrap running.
      //
      // The shift needs no special handling here any more. It used to live in
      // SharedPreferences, outside the replica, so a stale shift from the
      // previous brand would have been presented as this brand's active shift
      // if it survived the switch — hence the explicit removal that used to
      // stand here. It is a `branch_shifts` row now, inside the replica, so
      // `resetAndBootstrap`'s wipe takes it with everything else, and the
      // active-shift query is branch-scoped besides.
      //
      // The legacy key is still cleared, once, so a terminal upgrading from a
      // build that wrote it does not leave the record behind forever.
      await _prefs.remove(legacyLocalShiftPrefsKey);
      await _storage.setPosInitialized(false);
    }

    await _storage.writeLastAuthContext(
      brandId: brandId,
      cashRegisterId: cashRegisterId,
    );

    if (brandChanged || firstTime) {
      // Remembered rather than acted on, because only this method knows the
      // difference: a brand switch must drop the previous tenant's rows,
      // while a first login on a fresh terminal has nothing to drop and an
      // interrupted setup has a cursor worth resuming from.
      _pendingReset = brandChanged;
      return LoginDataScope.initialSetup;
    }
    if (branchChanged) {
      // Same brand, different branch: keep existing local data, refetch the
      // new branch's data additively. No box is cleared and the brand-level
      // catalog is not redownloaded, so this can run behind the app.
      unawaited(_syncEngine.hydrateNow());
      return LoginDataScope.branchRefresh;
    }
    return LoginDataScope.none;
  }

  /// Set by [onSuccessfulLogin] when the pending setup is a brand switch, and
  /// therefore has to drop the replica before refilling it.
  bool _pendingReset = false;

  /// The one-time replica fill, in the foreground.
  ///
  /// Safe to call repeatedly: `bootstrap` resumes from the stored cursor and
  /// only marks completion on a clean catch-up, so a retry after a failure
  /// continues rather than starting over.
  ///
  /// Reports progress so the screen in front of it can show something real
  /// instead of an indefinite spinner — `onProgress` has existed on
  /// [ReplicationService.bootstrap] since it was written and had no caller
  /// until now.
  Future<InitialSetupOutcome> runInitialSetup({
    void Function(ReplicationProgress)? onProgress,
  }) async {
    try {
      final replication = _syncEngine.replication;
      final result = _pendingReset
          ? await replication.resetAndBootstrap(onProgress: onProgress)
          : await replication.bootstrap(onProgress: onProgress);
      // Cleared only once the reset has actually happened, so an interrupted
      // brand switch still drops the old tenant's rows on the retry.
      if (result.ok) _pendingReset = false;

      // The gap-fillers the change feed cannot carry (table timers, menu
      // images). Failing here does not invalidate the pull above.
      await _syncEngine.hydrateNow(includeGoods: true);

      // Marked done only when data actually landed — a fully offline "first
      // time" login must stay un-initialized so the next chance retries. The
      // same two entities as before, asked of the replica: a terminal with
      // halls' tables or a catalog has been provisioned.
      final counts = _replica.tableCounts();
      final filled =
          (counts['cafe_tables'] ?? 0) > 0 || (counts['categories'] ?? 0) > 0;
      if (result.outcome == ReplicationOutcome.caughtUp && filled) {
        await _storage.setPosInitialized(true);
        return InitialSetupOutcome.ready;
      }
      return InitialSetupOutcome.incomplete;
    } catch (_) {
      return InitialSetupOutcome.incomplete;
    }
  }
}
