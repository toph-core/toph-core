import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/dio_client.dart';
import '../services/cache/cache_service.dart';
import '../services/connectivity/connectivity_cubit.dart';
import '../services/lan_hub/lan_hub_service.dart';
import '../services/offline_queue/offline_queue_service.dart';

/// Thin coordination shell around the existing offline services — wraps
/// `OfflineQueueService`/`CacheService` rather than replacing them, so later
/// phases (see offline-first-architecture-plan.md, §11) can swap what's
/// inside without every call site needing to change.
///
/// The one capability this adds that didn't exist before: a periodic tick,
/// so the outbox drains even without a connectivity false→true edge (e.g.
/// the app launched already offline, or the OS link never flagged a backend
/// outage as a disconnect — see `ConnectivityCubit`'s reachability probe).
class SyncEngine {
  final OfflineQueueService _queue;
  final CacheService _cache;
  final ConnectivityCubit _connectivity;
  final DioClient _client;
  final LanHubService _lanHub;
  final SharedPreferences _prefs;

  Timer? _ticker;
  bool _tickRunning = false;

  static const tickInterval = Duration(seconds: 60);
  static const _lastSyncKey = 'sync_engine_last_success_at';

  /// When the last sync pass completed without throwing *and* actually had
  /// connectivity to do something (a LAN-relay pass, or a direct cloud
  /// pass) — not merely "tick() was called," which also fires while fully
  /// offline and does nothing. Seeded from `SharedPreferences` so a status
  /// screen doesn't show "never synced" on every cold start.
  late final ValueNotifier<DateTime?> lastSyncAt =
      ValueNotifier(_readPersistedLastSync());

  DateTime? _readPersistedLastSync() {
    final raw = _prefs.getString(_lastSyncKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  void _recordSync() {
    final now = DateTime.now();
    lastSyncAt.value = now;
    unawaited(_prefs.setString(_lastSyncKey, now.toIso8601String()));
  }

  SyncEngine({
    required OfflineQueueService queue,
    required CacheService cache,
    required ConnectivityCubit connectivity,
    required DioClient client,
    required LanHubService lanHub,
    required SharedPreferences prefs,
  })  : _queue = queue,
        _cache = cache,
        _connectivity = connectivity,
        _client = client,
        _lanHub = lanHub,
        _prefs = prefs;

  void start() {
    _ticker ??= Timer.periodic(tickInterval, (_) => tick());
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Runs one sync pass: drain the outbox, then opportunistically refresh
  /// reference-data caches that have gone stale. Safe to call more often than
  /// [tickInterval] (e.g. from a reconnect-edge listener) — concurrent calls
  /// collapse into one no-op via [_tickRunning], and `OfflineQueueService`
  /// applies its own backoff so a failed pass doesn't retry immediately.
  ///
  /// In LAN `client` mode (Phase 4 sole-uplink), the outbox drains through
  /// the leader instead of this terminal's own cloud connectivity — a
  /// follower with no internet of its own but a live LAN link to the leader
  /// must still be able to sync, so this branch deliberately does not gate
  /// on [_connectivity]. Cache refresh is unaffected: relaying arbitrary
  /// reads through the leader is a separate, bigger feature this phase
  /// doesn't attempt (see offline-first-architecture-plan.md §11 Phase 4),
  /// so it still depends on this terminal's own connectivity either way.
  /// [force] bypasses `OfflineQueueService`'s own backoff — for a
  /// user-triggered "sync now" button (sync-status screen, §11 Phase 6),
  /// where waiting out an exponential backoff from a previous failure would
  /// defeat the point of a manual retry. The periodic timer and
  /// reconnect-edge callers never pass this, so their behavior is unchanged.
  Future<void> tick({bool force = false}) async {
    if (_tickRunning) return;
    _tickRunning = true;
    try {
      if (_lanHub.mode == LanMode.client) {
        if (_queue.hasItems) {
          await _queue.relayViaLan(
            isLeaderConnected: () => _lanHub.isClientConnected,
            relayOne: (op) => _lanHub.relayOperation(op),
          );
        }
        if (_connectivity.isOnline) {
          await _cache.prefetchAllGoods(_client);
          await _hydrateReferenceData();
        }
        _recordSync();
        return;
      }
      if (!_connectivity.isOnline) return;
      if (_queue.hasItems) {
        await _queue.syncAll(_client, force: force);
      }
      await _cache.prefetchAllGoods(_client);
      await _hydrateReferenceData();
      _recordSync();
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] tick error: $e');
    } finally {
      _tickRunning = false;
    }
  }

  /// Bulk-hydrates categories, departments, halls, tables, and staff into
  /// `CacheService` — the entities that previously had no login-time/
  /// periodic prefetch at all (only `goods` did) and were left to whatever a
  /// screen happened to fetch lazily on open. Uses `MainRepository`
  /// (resolved lazily via `inject`, not a constructor dependency — `di.dart`
  /// constructs `SyncEngine` before `_repositories()` registers
  /// `MainRepository`, mirroring the same lazy-resolution pattern
  /// `LanHubService` already uses for `UserBloc` for the same DI-ordering
  /// reason) so it reuses the exact same network calls those screens already
  /// make, rather than a second, parallel fetch path.
  Future<void> _hydrateReferenceData({bool force = false}) async {
    if (!force && _cache.isReferenceDataFresh()) return;
    final repo = inject<MainRepository>();
    try {
      // Kicked off together (each call starts running immediately, before
      // the first `await` below) rather than via `Future.wait` — the five
      // results have different generic types (`Either<Failure,
      // List<CategoryModel>>` vs. `List<DepartmentModel>>` etc.), so a
      // single heterogeneous `Future.wait` list would lose static typing.
      final categoriesF = repo.getCategories();
      final departmentsF = repo.getDepartments();
      final hallsF = repo.getHalls();
      final tablesF = repo.getAllTables();
      final usersF = repo.getUsers();
      final categories = (await categoriesF).fold((_) => null, (r) => r);
      final departments = (await departmentsF).fold((_) => null, (r) => r);
      final halls = (await hallsF).fold((_) => null, (r) => r);
      final tables = (await tablesF).fold((_) => null, (r) => r);
      final users = (await usersF).fold((_) => null, (r) => r);
      if (categories != null) {
        await _cache.saveCategories(categories.map((c) => c.toJson()).toList());
      }
      if (departments != null) {
        await _cache.saveDepartments(departments.map((d) => d.toJson()).toList());
      }
      if (halls != null) {
        await _cache.saveHalls(halls.map((h) => h.toJson()).toList());
      }
      if (tables != null) {
        await _cache.saveTables(tables.map((t) => t.toJson()).toList());
      }
      if (users != null && users.isNotEmpty) {
        await _cache.saveUsers(users.map((u) => u.toJson()).toList());
      }
      // Only mark fresh if at least reference-data reads didn't all fail —
      // an all-null pass (e.g. a mid-request disconnect) shouldn't suppress
      // the next tick's retry for the full TTL window.
      if (categories != null || departments != null || halls != null || tables != null) {
        await _cache.markReferenceDataFetched();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateReferenceData error: $e');
    }
  }

  void dispose() => stop();
}
