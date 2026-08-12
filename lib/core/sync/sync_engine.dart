import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_filter_request/archives_filter_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_response/archives_response_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/table_timer_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/dio_client.dart';
import '../database/local_database.dart';
import '../service/minio/minio_service.dart';
import '../services/cache/cache_service.dart';
import '../services/connectivity/connectivity_cubit.dart';
import '../services/lan_hub/lan_hub_service.dart';
import '../outbox/outbox_drainer.dart';
import '../services/offline_queue/offline_queue_service.dart';
import 'replication_service.dart';

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
  final LocalDatabase _localDb;

  /// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — the cursor-driven change-log
  /// replication that is replacing every `_hydrateX` method below. Both run for
  /// now: replication fills the SQLite replica while the screens still read
  /// `CacheService`/`LocalDatabase`. Phase 4 moves the screens across and
  /// deletes the hydration half.
  final ReplicationService _replication;

  /// Phase 2 — replay of locally-queued writes. Dormant until Phase 4
  /// registers executors; the drain call below is a no-op against an empty
  /// registry, so wiring it now costs nothing and means no trigger has to be
  /// added later.
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
    required CacheService cache,
    required ConnectivityCubit connectivity,
    required DioClient client,
    required LanHubService lanHub,
    required SharedPreferences prefs,
    required LocalDatabase localDb,
    required ReplicationService replication,
    required OutboxDrainer outbox,
  })  : _queue = queue,
        _cache = cache,
        _connectivity = connectivity,
        _client = client,
        _lanHub = lanHub,
        _prefs = prefs,
        _localDb = localDb,
        _replication = replication,
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
          // Phase 5 deletes this whole branch's cloud access: a follower's
          // inbound data will arrive from the leader's LAN relay, not from its
          // own uplink. Until then a follower replicates the same way a leader
          // does, matching the behaviour the hydration calls below already had.
          await _outbox.drain();
          await _replication.drain();
          await _cache.prefetchAllGoods(_client);
          await _mirrorGoodsIntoLocalDb();
          await _hydrateReferenceData();
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
      // returning a version `_pending` then has to shield.
      //
      // Both sit above the legacy hydration so that, once the screens move in
      // Phase 4, deleting everything below this line is the whole change.
      // Neither throws — each returns a result — so a sync failure cannot stop
      // the hydration below it.
      await _outbox.drain();
      await _replication.drain();
      await _cache.prefetchAllGoods(_client);
      await _mirrorGoodsIntoLocalDb();
      await _hydrateReferenceData();
      _refreshUserProfile();
      _recordSync();
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] tick error: $e');
    } finally {
      _tickRunning = false;
    }
  }

  /// CLIENT_FACING_OFFLINE_PLAN.md §1 — login-triggered hydration, called by
  /// `LoginDataScopeService` for first-time setup (with [includeGoods], the
  /// full catalog prep fetch) and for a same-brand branch switch (without —
  /// additive branch-data refetch, the catalog isn't redownloaded). Bypasses
  /// the reference-data freshness TTL: a login that changed brand/branch
  /// must not be told "fetched 3 minutes ago, still fresh" about the
  /// previous context's data.
  Future<void> hydrateNow({bool includeGoods = false}) async {
    if (!_connectivity.isOnline) return;
    try {
      if (includeGoods) {
        await _cache.prefetchAllGoods(_client, force: true);
        await _mirrorGoodsIntoLocalDb();
      }
      await _hydrateReferenceData(force: true);
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
        await _localDb.saveCategories(categories);
      }
      if (departments != null) {
        await _cache.saveDepartments(departments.map((d) => d.toJson()).toList());
        await _localDb.saveDepartments(departments);
      }
      if (halls != null) {
        await _cache.saveHalls(halls.map((h) => h.toJson()).toList());
        await _localDb.saveHalls(halls);
      }
      if (tables != null) {
        await _cache.saveTables(tables.map((t) => t.toJson()).toList());
        await _localDb.saveTables(tables);
      }
      if (users != null && users.isNotEmpty) {
        await _cache.saveUsers(users.map((u) => u.toJson()).toList());
        await _localDb.saveUsers(users);
      }
      // Only mark fresh if at least reference-data reads didn't all fail —
      // an all-null pass (e.g. a mid-request disconnect) shouldn't suppress
      // the next tick's retry for the full TTL window.
      if (categories != null || departments != null || halls != null || tables != null) {
        await _cache.markReferenceDataFetched();
      }

      // ── §8 Phase 1: entities that previously had NO hydration path at
      // all (§0's SyncEngine row) — each independently best-effort so one
      // entity's failure doesn't block the others or the five above.
      await _hydrateIngredientsAndCompounds(repo);
      await _hydrateTransactionGroups(repo);
      await _hydrateCashRegisters(repo);
      await _hydrateArchives(repo);
      await _hydratePrinterSettings(repo);
      await _hydrateServiceCharge(repo);
      if (categories != null) await _hydrateGoodsByCategory(repo, categories);
      await _hydrateOpenOrderDetails(repo, tables ?? _localDb.getTables());
      await _hydrateTableTimers(repo, tables ?? _localDb.getTables());
      await _hydrateMenuImages();
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateReferenceData error: $e');
    }
  }

  /// `CacheService.prefetchAllGoods` (unchanged, still the only place that
  /// actually does the paginated network fetch) only ever wrote into
  /// `CacheService`'s flat blob box. Mirrors its result into `LocalDatabase`
  /// too — no extra network call, just decoding what's already in memory —
  /// so `LocalDatabase` becomes a real second source for "goods (all)"
  /// alongside the per-category entries `_hydrateGoodsByCategory` below
  /// writes. Best-effort: a decode failure here must not undo the cache
  /// write that already succeeded.
  Future<void> _mirrorGoodsIntoLocalDb() async {
    try {
      final raw = _cache.getGoods();
      if (raw.isEmpty) return;
      await _localDb.saveGoods(raw.map(GoodsModel.fromJson).toList());
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] mirrorGoodsIntoLocalDb error: $e');
    }
  }

  Future<void> _hydrateIngredientsAndCompounds(MainRepository repo) async {
    try {
      final ingredients = (await repo.getIngredients()).fold((_) => null, (r) => r);
      if (ingredients != null) {
        await _cache.saveIngredients(ingredients);
        await _localDb.saveIngredients(ingredients);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateIngredients error: $e');
    }
    try {
      final compounds = (await repo.getCompounds()).fold((_) => null, (r) => r);
      if (compounds != null) {
        await _cache.saveCompounds(compounds);
        await _localDb.saveCompounds(compounds);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateCompounds error: $e');
    }
  }

  /// §8 Phase 6/V8 — mirrors only the default "first page, unfiltered,
  /// today" archive view `archive_screen.dart` shows on open, matching
  /// exactly what `ArchivesLocalRepositoryImpl` already blob-caches for
  /// offline reads (same default `ArchivesFilterRequestModel()` shape).
  /// Replaces that screen's own `Timer.periodic` silent refresh — the
  /// archive screen becomes a `watchArchives()` stream consumer instead.
  Future<void> _hydrateArchives(MainRepository repo) async {
    try {
      final result = await repo.getArchives(
        const ArchivesFilterRequestModel(
          pagination: PaginationRequestModel(limit: 20),
        ),
      );
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        await _localDb.saveArchives((ok as ArchivesResponseModel).toJson());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateArchives error: $e');
    }
  }

  Future<void> _hydrateTransactionGroups(MainRepository repo) async {
    try {
      final groups = (await repo.getTransactionGroups()).fold((_) => null, (r) => r);
      if (groups != null) {
        await _cache.saveTransactionGroups(groups);
        await _localDb.saveTransactionGroups(groups);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateTransactionGroups error: $e');
    }
  }

  /// §8 Phase 5 (back-office tier) — `transactions_list_section.dart`'s cash
  /// register picker, same "unfiltered default list" scope as transaction
  /// groups above.
  Future<void> _hydrateCashRegisters(MainRepository repo) async {
    try {
      final registers = (await repo.getCashRegisters()).fold((_) => null, (r) => r);
      if (registers != null) await _localDb.saveCashRegisters(registers);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateCashRegisters error: $e');
    }
  }

  Future<void> _hydratePrinterSettings(MainRepository repo) async {
    try {
      final entries = (await repo.getPrinterSettings()).fold((_) => null, (r) => r);
      if (entries != null) await _localDb.savePrinterSettings(entries);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydratePrinterSettings error: $e');
    }
  }

  /// Same DI-ordering reason the class doc above already explains for
  /// `MainRepository`: resolved lazily via `inject`, mirroring the exact
  /// `inject<UserBloc>().state.userMOdel?.branchId` pattern
  /// `LanHubService` already uses for the same terminal's own branch.
  Future<void> _hydrateServiceCharge(MainRepository repo) async {
    try {
      final branchId = inject<UserBloc>().state.userMOdel?.branchId ?? '';
      if (branchId.isEmpty) return;
      final value = (await repo.getServiceCharge(branchId)).fold((_) => null, (r) => r);
      if (value != null) {
        await _cache.saveServiceCharge(branchId, {'default_service_percent': value});
        await _localDb.saveServiceCharge(branchId, value);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncEngine] hydrateServiceCharge error: $e');
    }
  }

  /// `CacheService`'s own doc note on why "all goods" filtered client-side
  /// isn't a real per-category cache applies here too — this is the genuine
  /// per-category fetch that note says was previously missing entirely.
  Future<void> _hydrateGoodsByCategory(
    MainRepository repo,
    List<CategoryModel> categories,
  ) async {
    for (final category in categories) {
      try {
        final goods =
            (await repo.getGoodsByCategoryId(category.id)).fold((_) => null, (r) => r);
        if (goods != null) {
          await _cache.saveGoodsForCategory(
            category.id,
            goods.map((g) => g.toJson()).toList(),
          );
          await _localDb.saveGoodsForCategory(category.id, goods);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SyncEngine] hydrateGoodsByCategory(${category.id}) error: $e');
        }
      }
    }
  }

  /// §1.2: order/bill state becomes a first-class `LocalDatabase` table kept
  /// current by this hydration pass and by Phase 2's local-write path.
  /// Deliberately `getPaymentDetailWithTableId` (the `archiveWithId`-backed
  /// bill/totals shape `ArchiveDetailModel` parses — the same one
  /// `DetailBloc`/`PaymentBloc` already cache under this exact key via
  /// `CacheService.saveOrderDetail`), **not** `getOrderItemsRaw` (a
  /// differently-shaped `order-items` list endpoint used only by
  /// `OfflineQueueService`'s executors internally) — an earlier draft of
  /// this method used the latter, which would have handed `DetailBloc`/
  /// `PaymentBloc` JSON their `ArchiveDetailModel.fromJson` can't parse.
  /// Bounded to currently-busy tables, not every table, since a free table
  /// has no order to fetch.
  Future<void> _hydrateOpenOrderDetails(
    MainRepository repo,
    List<CafeTableModel> tables,
  ) async {
    for (final table in tables.where((t) => t.status == TableStatus.busy)) {
      try {
        final detail = (await repo.getPaymentDetailWithTableId(table.id))
            .fold((_) => null, (r) => r);
        if (detail is ArchiveDetailModel) {
          final json = detail.toJson();
          await _cache.saveOrderDetail(table.id, json);
          await _localDb.saveOrderDetail(table.id, json);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SyncEngine] hydrateOpenOrderDetails(${table.id}) error: $e');
        }
      }
    }
  }

  /// CLIENT_FACING_OFFLINE_PLAN.md §2: table-timer state lives locally now
  /// (`local_db_table_timers`, the sole runtime source for the timer UI) —
  /// this pass reconciles the server's snapshot into that box for busy
  /// time-based tables, replacing the two deleted 60s UI polls as the only
  /// place server timer truth enters the terminal. Orders with queued,
  /// not-yet-replayed local timer ops are skipped so hydration never stomps
  /// unsynced local changes.
  Future<void> _hydrateTableTimers(
    MainRepository repo,
    List<CafeTableModel> tables,
  ) async {
    for (final table in tables.where(
      (t) =>
          t.status == TableStatus.busy &&
          (t.tableType?.toLowerCase() == 'time_based'),
    )) {
      try {
        final orderId =
            _localDb.getOrderDetail(table.id)?['id'] as String? ?? '';
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
        await _localDb.saveTableTimer(
          orderId,
          TableTimerLocalRepositoryImpl.normalizeServerSnapshot(raw),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SyncEngine] hydrateTableTimers(${table.id}) error: $e');
        }
      }
    }
  }

  /// V9 fix (§9): hydrates every distinct menu-image object name referenced
  /// by `LocalDatabase`'s "goods (all)" list, via the same
  /// `MinioService.getImageByObjectName` the now-deleted-in-Phase-6
  /// `FutureBuilder` in `menu_manage_screen.dart` calls directly today.
  /// Skips object names already cached — an unconditional re-fetch every
  /// tick would turn a small reference-data pass into a large one for a
  /// menu with many pictured items.
  Future<void> _hydrateMenuImages() async {
    try {
      final refs = _localDb
          .getGoods()
          .map((g) => g.pictureUrl)
          .whereType<String>()
          .where((r) => r.isNotEmpty)
          .toSet();
      for (final ref in refs) {
        if (_localDb.getImage(ref) != null) continue;
        try {
          final bytes = await MinioService.instance.getImageByObjectName(ref);
          if (bytes != null && bytes.isNotEmpty) {
            await _localDb.saveImage(ref, bytes);
          }
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
