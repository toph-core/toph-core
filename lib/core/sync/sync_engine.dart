import 'dart:async';

import 'package:flutter/foundation.dart';

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

  Timer? _ticker;
  bool _tickRunning = false;

  static const tickInterval = Duration(seconds: 60);

  SyncEngine({
    required OfflineQueueService queue,
    required CacheService cache,
    required ConnectivityCubit connectivity,
    required DioClient client,
    required LanHubService lanHub,
  })  : _queue = queue,
        _cache = cache,
        _connectivity = connectivity,
        _client = client,
        _lanHub = lanHub;

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
  Future<void> tick() async {
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
        }
        return;
      }
      if (!_connectivity.isOnline) return;
      if (_queue.hasItems) {
        await _queue.syncAll(_client);
      }
      await _cache.prefetchAllGoods(_client);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] tick error: $e');
    } finally {
      _tickRunning = false;
    }
  }

  void dispose() => stop();
}
