import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/table_timer_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/dio_client.dart';
import '../db/halls_tables_query.dart';
import '../db/order_detail_query.dart';
import '../service/minio/minio_service.dart';
import '../services/connectivity/connectivity_cubit.dart';
import '../services/lan_hub/lan_hub_service.dart';
import '../outbox/outbox_drainer.dart';
import '../services/offline_queue/offline_queue_service.dart';
import 'change_feed_relay.dart';
import 'replication_service.dart';

/// The only component that touches the network (OFFLINE_FIRST_EVERYWHERE_PLAN
/// .md §3).
///
/// A pass is: send, then receive, then fill the two gaps the change feed
/// cannot. The ~300 lines of per-entity `_hydrateX` fetching that used to sit
/// below the receive step are gone — that was Phase 4's whole promise, and it
/// held: one `POST /sync/pull` loop replaced every one of them, because every
/// screen now reads the replica the loop fills.
///
/// What survives is exactly what the feed does not carry:
///
/// * **Table timers.** `table_time_sessions` has no change-log trigger
///   (§5 item 1, the highest-value backend ask), so a server timer snapshot
///   can only arrive by asking for it.
/// * **Menu images.** Minio is a blob store, not a logged table.
/// * **The user profile re-check**, which is session revalidation rather
///   than data.
///
/// The periodic tick also drains the outbox without waiting on a connectivity
/// false→true edge — the app may have launched already offline, or the OS link
/// may never have flagged a backend outage as a disconnect.
class SyncEngine {
  final OfflineQueueService _queue;
  final ConnectivityCubit _connectivity;
  final DioClient _client;
  final LanHubService _lanHub;
  final SharedPreferences _prefs;

  /// The cursor-driven change-log replication — the single inbound data path
  /// now that Phase 4 has deleted the per-entity hydration it replaced.
  final ReplicationService _replication;

  /// Phase 5 — tracks whether this terminal, as a follower, knows it is behind
  /// the leader's feed. The only thing that still justifies a follower's own
  /// cloud pull.
  final ChangeFeedRelay _feed;

  /// Phase 2 — replay of locally-queued writes.
  final OutboxDrainer _outbox;

  Timer? _ticker;
  bool _tickRunning = false;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<bool>? _lanClientSub;

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
    required ConnectivityCubit connectivity,
    required DioClient client,
    required LanHubService lanHub,
    required SharedPreferences prefs,
    required ReplicationService replication,
    required ChangeFeedRelay feed,
    required OutboxDrainer outbox,
  })  : _queue = queue,
        _connectivity = connectivity,
        _client = client,
        _lanHub = lanHub,
        _prefs = prefs,
        _replication = replication,
        _feed = feed,
        _outbox = outbox;

  /// The replication loop, for the login flow's one-time bootstrap and the
  /// sync-status screen. Exposed here rather than injected directly anywhere
  /// else so `SyncEngine` stays the single entry point to networking.
  ReplicationService get replication => _replication;

  /// BACKEND_SYNC_PLAN.md §5: every sync trigger now lives here, in one
  /// place, instead of being scattered across widget lifecycles:
  ///  - periodic (60s ticker, unchanged);
  ///  - app-startup (the immediate tick below — previously AppScaffold's
  ///    one-shot first-mount prefetch gate);
  ///  - internet reconnect-edge (the connectivity subscription — previously
  ///    AppScaffold's own listener);
  ///  - LAN reconnect-edge (§5 gap 2 — a follower whose link to the leader
  ///    comes back relays its outbox immediately instead of waiting for the
  ///    next periodic tick; `tick()` already routes through `relayViaLan`
  ///    in client mode);
  ///  - local-write (§5 gap 1 — `OfflineQueueService.enqueue` nudges
  ///    `tick()` on every enqueue, see its doc);
  ///  - manual retry (`tick(force: true)` from the sync-status screen,
  ///    unchanged).
  void start() {
    _ticker ??= Timer.periodic(tickInterval, (_) => tick());
    _connectivitySub ??= _connectivity.stream.listen((isOnline) {
      if (isOnline) tick();
    });
    _lanClientSub ??= _lanHub.onClientConnectionChanged.listen((connected) {
      if (connected) tick();
    });
    // The app-startup tick. Callers must invoke start() only after every
    // DI registration the hydration pass resolves lazily (MainRepository,
    // UserBloc) exists — di.dart calls this after _cubit() for exactly
    // that reason.
    if (_connectivity.isOnline) unawaited(tick());
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _lanClientSub?.cancel();
    _lanClientSub = null;
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
          // Phase 5: a follower no longer pulls the change feed on a timer.
          // Its inbound rows arrive from the leader's broadcast, which is the
          // point — N terminals polling the cloud for the same rows was the
          // cost this phase removes, and a follower with no uplink of its own
          // now stays current as long as the LAN link is up.
          //
          // The one exception is a hole. If this terminal missed broadcasts
          // while disconnected, `ChangeFeedRelay` has held its cursor back
          // rather than skipping the rows, and only a cloud pull from that
          // cursor can fill them — the leader cannot replay its change log,
          // it keeps current rows, not history. So the uplink survives as
          // recovery, not as a poll.
          await _outbox.drain();
          if (_feed.needsBackfill) {
            final result = await _replication.drain();
            if (result.outcome == ReplicationOutcome.caughtUp) {
              _feed.backfillDone();
            }
          }
          await _fillFeedGaps();
          _refreshUserProfile();
        }
        _recordSync();
        return;
      }
      if (!_connectivity.isOnline) return;
      if (_queue.hasItems) {
        await _queue.syncAll(_client, force: force);
      }
      // Send before receiving: draining the outbox first means the pull in the
      // same pass already reflects what this terminal just wrote, rather than
      // returning a version `_pending` then has to shield. Neither throws —
      // each returns a result — so one failing cannot stop what follows.
      await _outbox.drain();
      await _replication.drain();
      await _fillFeedGaps();
      _refreshUserProfile();
      _recordSync();
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] tick error: $e');
    } finally {
      _tickRunning = false;
    }
  }

  /// The login path's "make sure this terminal is current" call, from
  /// `LoginDataScopeService` — a branch switch, or the tail of first-time
  /// setup.
  ///
  /// It used to be a forced re-run of the reference-data fetch, bypassing that
  /// pass's freshness TTL so a login that changed brand or branch was not told
  /// "fetched 3 minutes ago, still fresh". There is no such pass and no such
  /// TTL any more: the replica is filled by the cursor, which has no notion of
  /// staleness, so this is simply one immediate pull plus the two gap-fillers.
  Future<void> hydrateNow({bool includeGoods = false}) async {
    if (!_connectivity.isOnline) return;
    try {
      await _replication.drain();
      await _fillFeedGaps();
      _recordSync();
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateNow error: $e');
    }
  }

  DateTime? _lastProfileRefreshAt;
  static const _profileRefreshInterval = Duration(minutes: 5);

  /// CLIENT_FACING_OFFLINE_PLAN.md §1 — the server profile re-check
  /// (`UserBloc`'s `getUser`, which also revalidates the session and purges
  /// the offline-auth cache on a definite rejection) is initiated from here,
  /// the background sync side, instead of from splash/`AppScaffold`'s
  /// reconnect listener. Throttled so the periodic 60s tick doesn't turn a
  /// once-per-reconnect call into a once-per-minute one.
  void _refreshUserProfile() {
    final now = DateTime.now();
    if (_lastProfileRefreshAt != null &&
        now.difference(_lastProfileRefreshAt!) < _profileRefreshInterval) {
      return;
    }
    _lastProfileRefreshAt = now;
    try {
      inject<UserBloc>().add(const UserEvent.getUser());
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] refreshUserProfile error: $e');
    }
  }

  /// The two things the change feed cannot deliver, fetched after every pull.
  ///
  /// Deliberately a short, closed list rather than the open-ended hydration
  /// this replaced: an entity belongs here only if the backend logs no
  /// change-log trigger for it. Everything else arrives on the feed, and
  /// adding a fetch here for something that replicates would reintroduce
  /// exactly the second data path Phase 4 removed.
  Future<void> _fillFeedGaps() async {
    await _hydrateTableTimers();
    await _hydrateMenuImages();
  }

  /// Reconciles the server's timer snapshot into the replica's timer store for
  /// every busy time-based table.
  ///
  /// This is the one *entity* fetch left in the engine, and it is here because
  /// `table_time_sessions` carries no change-log trigger — plan §5 item 1, the
  /// highest-value backend ask. Until it does, asking per open order is the
  /// only way server timer truth reaches the terminal at all, and a time-based
  /// table's charge is usually the largest line on its bill.
  ///
  /// Both inputs now come from the replica rather than the retiring Hive
  /// store: the busy time-based tables from `HallsTablesQuery` (whose rows
  /// already carry the venue's live occupancy, not the server's stale
  /// `status`), and each one's open order from `OrderDetailQuery`. Orders with
  /// queued, not-yet-replayed local timer ops are skipped so a fetch never
  /// stomps an unsynced start/pause the cashier just made.
  Future<void> _hydrateTableTimers() async {
    final db = _replication.db;
    final tables = HallsTablesQuery(db).tables().where((t) {
      final status = t['status']?.toString().toLowerCase();
      final type = t['table_type']?.toString().toLowerCase();
      return status == 'busy' && type == 'time_based';
    }).toList();
    if (tables.isEmpty) return;

    final orders = OrderDetailQuery(db);
    final repo = inject<MainRepository>();
    for (final table in tables) {
      final tableId = table['id']?.toString() ?? '';
      if (tableId.isEmpty) continue;
      try {
        final orderId =
            orders.liveOrderForTable(tableId)?['id']?.toString() ?? '';
        if (orderId.isEmpty) continue;
        if (TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(
          _queue,
          orderId,
        )) {
          continue;
        }
        final raw = (await repo.getOrderTableTimer(orderId))
            .fold((_) => null, (r) => r);
        if (raw == null) continue;
        db.saveTableTimer(
          orderId,
          TableTimerLocalRepositoryImpl.normalizeServerSnapshot(raw),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SyncEngine] hydrateTableTimers($tableId) error: $e');
        }
      }
    }
  }

  /// OFFLINE_FIRST_EVERYWHERE_PLAN.md §1 — the ahead-of-time half of menu
  /// image caching, now keyed off the **replicated** `goods.picture_url`
  /// values rather than the Hive catalog blob.
  ///
  /// Minio is a blob store with no change-log trigger, so images can never
  /// arrive on the feed; this pass and `MenuRepository.imageStream`'s
  /// fetch-on-miss are the only two ways bytes reach the terminal. Both write
  /// to the replica's image table and skip what is already there, so whichever
  /// gets to an object first wins and the other is a no-op.
  Future<void> _hydrateMenuImages() async {
    try {
      final db = _replication.db;
      final have = db.cachedImageNames();
      final refs = <String>{};
      for (final row in db.allOf('goods')) {
        final ref = row['picture_url'];
        if (ref is String && ref.isNotEmpty && !have.contains(ref)) {
          refs.add(ref);
        }
      }
      for (final ref in refs) {
        try {
          final bytes = await MinioService.instance.getImageByObjectName(ref);
          if (bytes != null && bytes.isNotEmpty) db.saveImage(ref, bytes);
        } catch (e) {
          if (kDebugMode) debugPrint('[SyncEngine] hydrateMenuImages($ref) error: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateMenuImages error: $e');
    }
  }

  void dispose() => stop();
}
