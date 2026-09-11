import 'dart:convert';

import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
// §9.3's offline suite swaps `HttpClientAdapter` — Dio's own transport
// extension point — for one that throws, so the whole app runs with the cable
// genuinely pulled. This file is already the transport layer as far as the
// §9.1 ratchet is concerned; see `DiOverrides` below for why the seam lives
// here rather than in a parallel test-only wiring.
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mary_ai_pos/core/api/app_security_context.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_log_service.dart';
import 'package:mary_ai_pos/core/services/auth/login_data_scope_service.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/service/printer/legacy_usb_printer_names.dart';
import 'package:mary_ai_pos/core/service/receipt/receipt_info_storage.dart';
// The one database (OFFLINE_FIRST_EVERYWHERE_PLAN.md §2). Still imported under
// a prefix: `LocalDatabase` is a common enough name that the alias reads as
// documentation at every use site, and the churn of dropping it across the
// file would obscure the change that actually retired the second store.
import 'package:mary_ai_pos/core/db/apply_change.dart' as replica;
import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/db/local_database_factory.dart' as replica;
import 'package:mary_ai_pos/core/db/order_detail_query.dart' as replica;
import 'package:mary_ai_pos/core/db/table_occupancy_reconciler.dart' as replica;
import 'package:mary_ai_pos/features/view/main/presentation/cubit/printers/printers_controller.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/transactions/transaction_categories_controller.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/transactions/transactions_list_controller.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/table_timer/time_based_table_badge_controller.dart';
import 'package:mary_ai_pos/core/media/local_image_cache.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/orders_outbox.dart';
import 'package:mary_ai_pos/core/db/branch_shift_query.dart';
import 'package:mary_ai_pos/core/outbox/branch_shift_outbox.dart';
import 'package:mary_ai_pos/core/outbox/timer_shift_outbox.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/sync/change_feed_relay.dart';
import 'package:mary_ai_pos/core/sync/local_change_relay.dart';
import 'package:mary_ai_pos/core/db/halls_tables_query.dart';
import 'package:mary_ai_pos/core/sync/replica_repair.dart';
import 'package:mary_ai_pos/core/sync/replication_service.dart';
import 'package:mary_ai_pos/core/sync/snapshot_api_client.dart';
import 'package:mary_ai_pos/core/sync/sync_api_client.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/leader_election_service.dart';
import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/core/services/table_timer/table_timer_sync_service.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/service/minio/minio_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/check_user_auth/check_user_data_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/user/get_user_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/archives_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/halls_tables_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/menu_admin_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/users_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/halls_tables_outbox.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/menu_admin_outbox.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/transactions_outbox.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/users_outbox.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/halls_tables_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_admin_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/users_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/halls_tables/halls_tables_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/menu_admin/menu_goods_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/menu_admin/menu_manage_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/users/users_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/table_timer_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/waiter_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/orders_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/payment_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/tables_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/menu_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/transactions_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/payment_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/archives_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/waiter_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/sync_printer_settings_usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/branches_outbox.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/service_charge_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/service_charge_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archive/archive_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/counter/counter_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/create_order/create_order_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/department_selection/department_selection_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/hour_price/hour_price_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/keyboard/keyboard_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/notification/notification_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/service_charge/service_charge_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:mary_ai_pos/features/view/auth/data/data_sources/auth_datasource.dart';
import 'package:mary_ai_pos/features/view/auth/data/repositories/login_repository_impl.dart';
import 'package:mary_ai_pos/features/view/auth/domain/repository/auth_repository.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/check_user_auth/check_user_auth.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/get_app_language/get_app_langauage_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/login_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/verify_manager_pincode_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login_with_brand/login_with_brand_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout_from_app_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/set_app_language/set_app_language_uscase.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/main_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/table_timer/table_timer_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/waiter/waiter_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/ui_prefs/ui_prefs_cubit.dart';

/// The two places `initDi` reaches for something a test cannot supply, and
/// nothing else.
///
/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §9.3 asks for "the whole app driven with
/// the Dio client replaced by one that throws on any call" — which means the
/// offline suite has to boot the *real* composition root, not a hand-rolled
/// copy of it. §9's opening line is the reason that matters: the previous
/// attempts failed because "fixes landed on one path and not its duplicate."
/// A second, test-only wiring would be exactly that duplicate, and it would
/// go stale the first time someone registered a dependency here and nowhere
/// else — silently, because the suite would still be green.
///
/// So the seam is deliberately the smallest thing that unblocks a headless
/// boot, and it is *only* the two constructions that need a platform the test
/// binding does not provide:
///
/// * [database] — `LocalDatabaseFactory.openDefault()` resolves a real
///   application-support directory through `path_provider`, a plugin with no
///   implementation under `flutter test`. A test passes
///   `LocalDatabase.open(':memory:')` instead.
/// * [httpClientAdapter] — Dio's own extension point, swapped in before
///   anything can use the client. This is what makes the cable-pulled suite
///   mean something: the adapter throws, so no code path anywhere in the app
///   can complete a request, and any screen or action that quietly depends on
///   one fails instead of passing on a cached response.
///
/// Everything else `initDi` touches already has a real, settable seam of its
/// own that a test installs from the outside and this class therefore has no
/// business duplicating: `SharedPreferences.setMockInitialValues`,
/// `FlutterSecureStoragePlatform.instance`, `ConnectivityPlatform.instance`,
/// and `Hive.init` pointed at a temporary directory.
///
/// Passing no overrides — the production call in `main()` — leaves every line
/// below byte-for-byte what it was: the two `??`/`if` guards fall through to
/// the same constructions.
class DiOverrides {
  const DiOverrides({this.database, this.httpClientAdapter});

  /// Replaces the on-disk replica. When null, the real application-support
  /// file is opened.
  final replica.LocalDatabase? database;

  /// Installed on `DioClient.dio` immediately after construction, before the
  /// probe client is attached and long before any request is made. When null,
  /// Dio keeps whatever adapter `DioClient` configured for itself.
  final HttpClientAdapter? httpClientAdapter;
}

final inject = GetIt.instance;
Future<void> initDi({DiOverrides? overrides}) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  const secureStorage = FlutterSecureStorage();

  // One-time upgrade for installs that predate the secure-storage migration
  // (§11 Phase 6) — moves any credential still sitting in plaintext
  // SharedPreferences into secure storage before anything reads it.
  await AppTokenStorage.migrateLegacyPlaintext(prefs, secureStorage);
  await OfflineAuthCache.migrateLegacyPlaintext(prefs, secureStorage);

  final AppTokenStorage tokenStorage = AppTokenStorage(prefs, secureStorage);

  inject.registerSingleton<SharedPreferences>(prefs);
  inject.registerSingleton<FlutterSecureStorage>(secureStorage);
  inject.registerSingleton<AppTokenStorage>(tokenStorage);
  inject.registerSingleton<OfflineAuthCache>(const OfflineAuthCache(secureStorage));
  inject.registerSingleton<ReceiptInfoStorage>(ReceiptInfoStorage(prefs));

  final alice = Alice(
    configuration: AliceConfiguration(
      showNotification: false,
      showInspectorOnShake: false,
    ),
  );
  inject.registerSingleton<Alice>(alice);

  final connectivity = Connectivity();
  final connectivityCubit = ConnectivityCubit(connectivity);
  inject.registerSingleton<ConnectivityCubit>(connectivityCubit);

  // OFFLINE_FIRST_EVERYWHERE_PLAN.md §2 — the replica of the tenant database,
  // and now the only one. `CacheService` and the Hive `LocalDatabase` that
  // used to be constructed above are deleted; every screen reads this.
  final replicaDb =
      overrides?.database ?? await replica.LocalDatabaseFactory.openDefault();
  // Every row this terminal commits is handed to `LocalChangeRelay`, which
  // puts it on the LAN so the rest of the venue sees it without a round trip
  // through the cloud. Resolved lazily for the same reason `onBatchApplied`
  // below is — the relay needs `LanHubService`, which is registered further
  // down — and guarded on registration because a write during DI setup itself
  // would otherwise resolve a service that does not exist yet.
  final changeApplier = replica.ChangeApplier(
    replicaDb,
    onLocalChange: ({
      required String entity,
      required String action,
      required String id,
      Map<String, dynamic>? payload,
    }) {
      if (!inject.isRegistered<LocalChangeRelay>()) return;
      inject<LocalChangeRelay>().broadcast(
        entity: entity,
        action: action,
        id: id,
        payload: payload,
      );
    },
  );
  inject.registerSingleton<replica.LocalDatabase>(replicaDb);
  inject.registerSingleton<replica.ChangeApplier>(changeApplier);
  // The order-detail read, shared by the order detail screen (via
  // OrdersRepository) and the waiter open-order list — one instance over the
  // one replica.
  inject.registerSingleton<replica.OrderDetailQuery>(
    replica.OrderDetailQuery(replicaDb),
  );

  // Occupancy and table timers are local authority, so no pull can correct
  // them — and until this ran, nothing did: a bill settled anywhere but this
  // terminal left its table busy and its hourly timer charging forever, on top
  // of an order screen that showed an empty 0-som bill because the paid order
  // is (correctly) no longer a live one. One pass at startup heals a terminal
  // that was off while the venue closed its checks; `ChangeApplier` keeps it
  // true from here on. Synchronous and tiny — a handful of tables.
  replica.TableOccupancyReconciler(replicaDb).reconcileAll();

  // OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — the outbox, in the same SQLite
  // file as the replica so a local row and its queued send commit together.
  // The executor registry is deliberately empty here: Phase 4 registers a
  // handler as each repository moves across, and an empty registry keeps the
  // drainer dormant rather than quarantining what it cannot yet send.
  final outboxStore = OutboxStore(replicaDb);
  final outboxExecutors = OutboxExecutors();
  inject.registerSingleton<OutboxStore>(outboxStore);
  inject.registerSingleton<OutboxExecutors>(outboxExecutors);
  inject.registerSingleton<LocalWriter>(LocalWriter(
    db: replicaDb,
    applier: changeApplier,
    outbox: outboxStore,
  ));
  final outboxDrainer = OutboxDrainer(
    store: outboxStore,
    executors: outboxExecutors,
    db: replicaDb,
    applier: changeApplier,
  );
  inject.registerSingleton<OutboxDrainer>(outboxDrainer);

  final offlineQueue = await OfflineQueueService.init();
  inject.registerSingleton<OfflineQueueService>(offlineQueue);

  final privilegedActionAuditLog = await PrivilegedActionAuditLogService.init();
  inject.registerSingleton<PrivilegedActionAuditLogService>(privilegedActionAuditLog);

  final securityContext = await buildAppSecurityContext();
  final dioClient = DioClient(
    tokenStorage,
    connectivityCubit,
    securityContext: securityContext,
  );
  // Before `attachProbeClient` below and before `syncEngine.start()`'s first
  // tick, so a test's throwing adapter is in place for every request the app
  // could possibly make — including the ones startup makes on its own.
  final adapterOverride = overrides?.httpClientAdapter;
  if (adapterOverride != null) dioClient.dio.httpClientAdapter = adapterOverride;
  alice.addAdapter(dioClient.aliceDioAdapter);
  inject.registerSingleton<DioClient>(dioClient);
  connectivityCubit.attachProbeClient(dioClient);

  final lanHubService = LanHubService(
    prefs,
    tokenStorage: tokenStorage,
    connectivity: connectivityCubit,
  );
  inject.registerSingleton<LanHubService>(lanHubService);

  // LAN_HUB_AND_LEASING_PLAN.md — active again on all three table-open
  // paths (CreateOrderBloc, waiter create, timed-order create); see
  // LeaseManager's class doc for the rejection/unreachable policy.
  // Occupancy comes from the replica's local-authority overlay (the same
  // source the floor plan reads), not the retiring Hive store — see
  // LeaseManager._arbitrate.
  final leaseManager = LeaseManager(lanHub: lanHubService, localDb: replicaDb);
  inject.registerSingleton<LeaseManager>(leaseManager);

  // offline-first-target-architecture.md §8 Phase 4, on by default since
  // Phase 6 (see LeaderElectionService.enabledByDefault). The comment here
  // used to say the opposite — "disabled by default, no-op unless opted in" —
  // which was true when it was written and has been wrong since the flip.
  final leaderElection = LeaderElectionService(lanHub: lanHubService, prefs: prefs);
  inject.registerSingleton<LeaderElectionService>(leaderElection);
  // Election owns the discovery socket whenever it is enabled, so the settings
  // screen has to ask it — not LanHubService's own idle instance — which UDP
  // port is actually bound. A callback rather than a dependency: these two are
  // constructed together and a real reference back would be a cycle.
  lanHubService.discoveryPortReporter = () => leaderElection.boundDiscoveryPort;

  // Phase 1 — the replication loop. Registered before SyncEngine because
  // SyncEngine drives it from the sync triggers it already owns; nothing else
  // in the app may call it, and nothing may call `SyncApiClient` directly.
  final syncApiClient = SyncApiClient(dioClient);
  inject.registerSingleton<SyncApiClient>(syncApiClient);
  inject.registerSingleton<ChangeFeedRelay>(
    ChangeFeedRelay(db: replicaDb, applier: changeApplier),
  );
  // The peer-to-peer half of replication, beside the cloud half above. This
  // one carries what *this* terminal writes; `ChangeFeedRelay` carries what
  // the leader pulled. Only this one keeps working with the uplink down,
  // which is the gap it was added to close.
  inject.registerSingleton<LocalChangeRelay>(
    LocalChangeRelay(
      applier: changeApplier,
      // Table timers are local-authority state and never pass through the
      // applier, so the relay needs the database directly for those.
      db: replicaDb,
      send: lanHubService.broadcastLocalChange,
      // Lazy: PrintQueueService (which owns the one stable per-terminal id
      // this codebase has) is registered further down.
      terminalId: () => inject<PrintQueueService>().terminalId,
    ),
  );
  final replicationService = ReplicationService(
    api: syncApiClient,
    db: replicaDb,
    applier: changeApplier,
    // Phase 5: whatever this terminal pulls, its followers get. A no-op unless
    // this terminal is the leader and something is connected to it — resolved
    // lazily because LanHubService is registered after this.
    onBatchApplied: (body, fromCursor) => inject<LanHubService>()
        .broadcastChangeFeed(body: jsonEncode(body), fromCursor: fromCursor),
  );
  inject.registerSingleton<ReplicationService>(replicationService);

  // The other half of the inbound path: the feed patches this replica forward,
  // this reconciles it against the server's current rows when the feed cannot.
  // Driven only by SyncEngine, like ReplicationService above.
  final replicaRepair = ReplicaRepair(
    api: SnapshotApiClient(dioClient),
    db: replicaDb,
    applier: changeApplier,
  );
  inject.registerSingleton<ReplicaRepair>(replicaRepair);

  final syncEngine = SyncEngine(
    feed: inject<ChangeFeedRelay>(),
    connectivity: connectivityCubit,
    lanHub: lanHubService,
    prefs: prefs,
    replication: replicationService,
    outbox: outboxDrainer,
    repair: replicaRepair,
  );
  // NOTE: start() is deliberately deferred until after _cubit() below —
  // its immediate startup tick resolves MainRepository/UserBloc lazily, and
  // `await PrintQueueService.init` further down would otherwise give its
  // microtask a chance to run before those registrations exist.
  inject.registerSingleton<SyncEngine>(syncEngine);

  // CLIENT_FACING_OFFLINE_PLAN.md §1 — the brand/branch retention rule
  // applied on each successful PIN login.
  inject.registerLazySingleton<LoginDataScopeService>(
    () => LoginDataScopeService(
      storage: tokenStorage,
      replica: replicaDb,
      syncEngine: syncEngine,
      prefs: prefs,
    ),
  );

  final MinioService minioService = MinioService.instance;
  minioService.configure(securityContext: securityContext);
  inject.registerLazySingleton(() => minioService);

  final printerConfigStorage = PrinterConfigStorage(prefs);
  await printerConfigStorage.adoptLegacyUsbPrinterNames(
    await LegacyUsbPrinterNames.read(),
  );
  inject.registerSingleton<PrinterConfigStorage>(printerConfigStorage);
  final printerService = PrinterService(printerConfigStorage);
  inject.registerSingleton<PrinterService>(printerService);

  // Print-job relay (Phase 5): needs `printerService` (transport) and
  // `lanHubService` (broadcast) to already exist, which is why this is
  // registered here rather than alongside them above. `PrintQueueService`
  // itself never imports `lan_hub_*` — see its own doc comment for why —
  // so the LAN side is wired here as plain closures over `lanHubService`'s
  // new `broadcastPrintJob*`/`canRelayPrintJobs` members.
  final printQueueService = await PrintQueueService.init(
    printerService,
    printerConfigStorage,
    prefs,
    isLanRelayPossible: () => lanHubService.canRelayPrintJobs,
    broadcastAnnounce: ({
      required jobId,
      required jobType,
      required entryId,
      required payloadBase64,
    }) =>
        lanHubService.broadcastPrintJobAnnounce(
          jobId: jobId,
          jobType: jobType,
          entryId: entryId,
          payloadBase64: payloadBase64,
        ),
    broadcastClaim: lanHubService.broadcastPrintJobClaim,
    broadcastGrant: lanHubService.broadcastPrintJobGrant,
    broadcastResult: lanHubService.broadcastPrintJobResult,
    // A job that fails after its caller was released on the 500ms budget has
    // nobody left to return an error to, so it is surfaced here instead.
    onLateFailure: (job) => printerService.notifyLateFailure(
      jobType: job.jobType,
      ip: job.ip,
      port: job.port,
      error: job.lastError,
    ),
  );
  inject.registerSingleton<PrintQueueService>(printQueueService);
  printerService.attachPrintQueue(printQueueService.submitJob);

  // A receipt waiting on the terminal that owns its printer should come out the
  // moment that terminal is back, not up to `deferredRetryInterval` later — the
  // usual shape of this is a till rebooting mid-service while the close check
  // for an order someone else closed sits queued against it.
  //
  // Both roles, because either can be the one holding the queued job: the
  // leader watches its follower count, a follower watches its own link to the
  // leader. Wired here rather than inside `PrintQueueService`, which does not
  // import `lan_hub_*` — same reason its broadcast callbacks are closures here.
  lanHubService.clientCountListenable.addListener(
    printQueueService.retryPendingRelays,
  );
  lanHubService.onClientConnectionChanged.listen((connected) {
    if (connected) printQueueService.retryPendingRelays();
  });

  // The same three moments, for the routing knowledge itself: a terminal that
  // has just joined (or just been joined) has to say which printers hang off
  // it, or its peers go on dialling printers they cannot reach. The third
  // moment — a printer added or edited here — is announced by the settings
  // screen itself, which is the only place that knows a change happened.
  inject.registerSingleton<PrinterSettingsAnnouncer>(
    lanHubService.announcePrinterSettings,
  );
  lanHubService.clientCountListenable.addListener(
    lanHubService.announcePrinterSettings,
  );
  lanHubService.onClientConnectionChanged.listen((connected) {
    if (connected) lanHubService.announcePrinterSettings();
  });

  _dataSources();
  _repositories();
  _useCase();
  _cubit();

  // OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the outbox stops being dormant
  // here. Registered after `_repositories()` because a handler resolves the
  // remote repository it sends through; one call per migrated screen, so the
  // registry stays a readable list of what is actually on the queue.
  registerUsersOutboxHandlers(outboxExecutors, inject<MainRepository>());
  registerHallsTablesOutboxHandlers(outboxExecutors, inject<MainRepository>());
  registerMenuAdminOutboxHandlers(outboxExecutors, inject<MainRepository>());
  registerTransactionsOutboxHandlers(outboxExecutors, inject<MainRepository>());
  registerBranchesOutboxHandlers(outboxExecutors, inject<MainRepository>());
  // The order aggregate speaks HTTP directly (the 409 merge / 404-tolerant
  // cancel have no home in a CRUD repository), so it takes the DioClient, not
  // MainRepository. Handlers only — the order writes move onto this outbox in
  // §B2; until then these register and stay idle.
  registerOrdersOutboxHandlers(outboxExecutors, inject<DioClient>());
  registerTimerShiftOutboxHandlers(
    outboxExecutors,
    inject<DioClient>(),
    inject<MainRepository>(),
  );
  // Branch shifts speak HTTP directly for the same reason the order aggregate
  // does — the endpoints exist for this queue and fit no CRUD repository. The
  // per-register shift handlers above stay registered: they still drain shifts
  // queued by an older build of the app that has not been updated yet.
  registerBranchShiftOutboxHandlers(outboxExecutors, inject<DioClient>());

  // BACKEND_SYNC_PLAN.md §5: every registration the startup tick's
  // hydration pass resolves lazily (MainRepository, UserBloc, ...) exists
  // by this point — see the note at the SyncEngine registration above.
  syncEngine.start();

  // Deferred until here: `client` mode's initial connect attempt reads the
  // current user via `inject<UserBloc>()` for its branch id, and `UserBloc`
  // isn't registered until `_cubit()` above runs.
  await lanHubService.init();
  // Same DI-ordering reason as lanHubService.init() above.
  //
  // Note what this call cannot do from here: `UserBloc` has no branch id yet.
  // Its cached profile is read on `UserEvent.started()`, dispatched from the
  // widget tree in `main.dart` — which runs after `initDi()` returns. So the
  // election always finds an empty branch here and arms its own short retry
  // rather than giving up; see LeaderElectionService.start(). Sequencing this
  // call after login instead would fix the cold start and miss the
  // logout→login case, which is why the wait lives in the service.
  await leaderElection.start();
}

void _dataSources() {
  inject.registerLazySingleton<AuthDatasource>(
    () => AuthDatasourceImpl(inject(), inject(), inject()),
  );
  inject.registerLazySingleton<MainDataSources>(
    () => MainDataSourcesImpl(inject()),
  );
}

void _repositories() {
  inject.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(inject(), inject()),
  );
  inject.registerLazySingleton<MainRepository>(
    () => MainRepositoryImpl(inject(), inject<replica.LocalDatabase>()),
  );
  inject.registerLazySingleton<ArchivesLocalRepository>(
    () => ArchivesLocalRepositoryImpl(
      inject<replica.LocalDatabase>(),
      branchId: _currentBranchId,
    ),
  );
  // OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the staff screen reads the
  // replica and writes through the outbox. Takes LocalDatabase + LocalWriter
  // and nothing else: no datasource, no DioClient, no ConnectivityCubit fork.
  inject.registerLazySingleton<UsersLocalRepository>(
    () => UsersLocalRepositoryImpl(
      inject<replica.LocalDatabase>(),
      inject(),
      branchId: _currentBranchId,
    ),
  );
  // Same shape for halls & tables. Note this deliberately does *not* replace
  // `TablesRepository`, which still serves the floor plan and waiter screens
  // from the Hive store — those move in their own commits, per screen.
  // One image cache for the whole app: the widget that displays images and the
  // repository that serves them must share a dedupe set, or the same bytes get
  // fetched twice.
  inject.registerLazySingleton<LocalImageCache>(
    () => LocalImageCache(
      watch: inject<replica.LocalDatabase>().watchImage,
      read: inject<replica.LocalDatabase>().getImage,
      write: (name, bytes) async =>
          inject<replica.LocalDatabase>().saveImage(name, bytes),
      fetch: MinioService.instance.getImageByObjectName,
    ),
  );
  inject.registerLazySingleton<ServiceChargeRepository>(
    () => ServiceChargeRepositoryImpl(
      inject<replica.LocalDatabase>(),
      inject(),
    ),
  );
  inject.registerLazySingleton<MenuAdminLocalRepository>(
    () => MenuAdminLocalRepositoryImpl(
      inject<replica.LocalDatabase>(),
      inject(),
    ),
  );
  inject.registerLazySingleton<HallsTablesLocalRepository>(
    () => HallsTablesLocalRepositoryImpl(
      inject<replica.LocalDatabase>(),
      inject(),
      branchId: _currentBranchId,
    ),
  );
  // CLIENT_FACING_OFFLINE_PLAN.md §2 — local-first now: LocalDatabase +
  // outbox + OrdersRepository (for the timed-order create), no DioClient.
  // The timed-order create is lease-gated (LAN_HUB_AND_LEASING_PLAN.md §8).
  inject.registerLazySingleton<TableTimerLocalRepository>(
    () => TableTimerLocalRepositoryImpl(
      inject<replica.LocalDatabase>(),
      inject(),
      inject(),
      inject(),
      // So a pause on one till stops the clock on every till.
      relay: inject<LocalChangeRelay>(),
    ),
  );
  // CLIENT_FACING_OFFLINE_PLAN.md §5 — rebuilt local-first on LocalDatabase
  // + the already-correct Orders/Payment repositories; no DioClient. The
  // create path is lease-gated (LAN_HUB_AND_LEASING_PLAN.md §8).
  inject.registerLazySingleton<WaiterLocalRepository>(
    () => WaiterLocalRepositoryImpl(
      inject<replica.LocalDatabase>(),
      inject(),
      inject<replica.OrderDetailQuery>(),
      inject(),
      inject(),
      inject(),
      inject(),
      inject(),
    ),
  );

  // offline-first-target-architecture.md §8 Phase 2 — the LocalRepository
  // layer §1/§9 describe: reactive reads over LocalDatabase, writes that
  // commit locally (outbox enqueue) and return without awaiting the network.
  inject.registerLazySingleton<OrdersRepository>(
    () => OrdersRepositoryImpl(
      db: inject<replica.LocalDatabase>(),
      applier: inject<replica.ChangeApplier>(),
      writer: inject<LocalWriter>(),
      detail: inject<replica.OrderDetailQuery>(),
      lanHub: inject(),
      tables: inject(),
    ),
  );
  inject.registerLazySingleton<PaymentRepository>(
    () => PaymentRepositoryImpl(writer: inject()),
  );
  // Phase 4: halls/tables reads and occupancy move to the replica. The Hive
  // store still backs menus, bills and timers until their own screens follow.
  inject.registerLazySingleton<TablesRepository>(
    () => TablesRepositoryImpl(
      localDb: inject<replica.LocalDatabase>(),
      branchId: _currentBranchId,
    ),
  );
  inject.registerLazySingleton<MenuRepository>(
    () => MenuRepositoryImpl(
      replicaDb: inject<replica.LocalDatabase>(),
      images: inject(),
      branchId: _currentBranchId,
    ),
  );
  // Presentation-layer seam so PrintersSection reads categories from the replica
  // and syncs printers best-effort without resolving repositories itself (§9.2).
  inject.registerLazySingleton<PrintersController>(
    () => PrintersController(menu: inject(), remote: inject()),
  );
  inject.registerLazySingleton<TransactionCategoriesController>(
    () => TransactionCategoriesController(local: inject()),
  );
  inject.registerLazySingleton<TransactionsListController>(
    () => TransactionsListController(local: inject()),
  );
  inject.registerLazySingleton<TimeBasedTableBadgeController>(
    () => TimeBasedTableBadgeController(inject()),
  );
  // §8 Phase 5 (back-office tier) — read-only, see TransactionsRepository's
  // own class doc for what's deliberately not covered.
  inject.registerLazySingleton<TransactionsRepository>(
    () => TransactionsRepositoryImpl(
      replicaDb: inject<replica.LocalDatabase>(),
      writer: inject<LocalWriter>(),
      branchId: _currentBranchId,
    ),
  );
}

void _useCase() {
  inject.registerLazySingleton(() => LogoutFromAppUseCase(inject()));
  inject.registerLazySingleton(() => CheckUserAuthUseCase(inject()));
  inject.registerLazySingleton(() => LoginUsecase(inject()));
  inject.registerLazySingleton(() => VerifyManagerPincodeUsecase(inject()));
  inject.registerLazySingleton(() => GetAppLangauageUsecase(inject()));
  inject.registerLazySingleton(() => SetAppLanguageUscase(inject()));
  inject.registerLazySingleton(() => LoginWithBrandUsecase(inject()));
  inject.registerLazySingleton(() => LogoutUsecase(inject()));
  inject.registerLazySingleton(() => CheckUserDataUsecase(inject()));
  inject.registerLazySingleton(() => GetUserUsecase(inject()));
  inject.registerLazySingleton(
    () => SyncPrinterSettingsUsecase(inject(), inject()),
  );
}

void _cubit() {
  //? lazy singleton
  inject.registerLazySingleton(
    () => AuthCubit(
      inject(),
      inject(),
      inject(),
      inject(),
      inject(),
      inject(),
      inject(),
    ),
  );
  inject.registerLazySingleton(() => SettingsCubit(inject(), inject()));
  inject.registerLazySingleton(() => UiPrefsCubit(inject()));
  inject.registerLazySingleton(() => ServiceChargeCubit(inject()));
  inject.registerLazySingleton(
    () => MainCubit(inject(), inject(), inject()),
  );
  inject.registerLazySingleton(() => KeyboardCubit());
  // A factory, not a singleton: UsersCubit holds a replica subscription and the
  // staff screen's filter state, and closes both on dispose. A singleton would
  // be handed out closed the second time the screen opened.
  inject.registerFactory(() => UsersCubit(inject()));
  inject.registerFactory(() => HallsTablesCubit(inject()));
  inject.registerFactory(() => MenuGoodsCubit(inject()));
  inject.registerFactory(() => MenuManageCubit(inject()));
  inject.registerLazySingleton(
    () => ShiftBloc(
      printerService: inject(),
      // Reads the branch's shift straight off the replica, and writes it back
      // through the same LocalWriter every other write in the app uses — which
      // is what puts the shift on every terminal in the venue instead of in one
      // terminal's SharedPreferences.
      shifts: BranchShiftQuery(inject<replica.LocalDatabase>()),
      writer: inject<LocalWriter>(),
    ),
  );

  //? factory
  inject.registerLazySingleton(
    () => UserBloc(
      getUserUsecase: inject(),
      syncPrinterSettingsUsecase: inject(),
    ),
  );
  // Branch-scoped reads re-run when the session's branch changes.
  //
  // One listener rather than a hook in each auth path: the branch can arrive
  // from a PIN login, a full login, a cached-profile restore on a cold offline
  // start, or a server profile refresh, and every one of them ends here. The
  // screens that care hold streams over `HallsTablesQuery.watchedTables`, and
  // `MainCubit` is a singleton whose subscriptions outlive a login — so without
  // this the floor plan kept whatever scope it was built with.
  var lastBranchId = '';
  inject<UserBloc>().stream.listen((state) {
    final branchId = state.userMOdel?.branchId ?? '';
    if (branchId == lastBranchId) return;
    lastBranchId = branchId;
    inject<replica.LocalDatabase>().touchChannel(
      HallsTablesQuery.branchScopeChannel,
    );
  });
  inject.registerFactory(
    () => LoginPinCubit(
      inject(),
      inject(),
      inject(),
      inject(),
      inject(),
      inject(),
    ),
  );
  inject.registerFactory(
    () => DetailBloc(
      inject(),
      inject(),
      inject(),
    ),
  );
  inject.registerFactory(
    () => DepartmentSelectionCubit(inject()),
  );
  inject.registerFactory(
    () => CreateOrderBloc(
      ordersRepository: inject(),
      leaseManager: inject(),
      lanHub: inject(),
      printerService: inject(),
      shiftBloc: inject(),
    ),
  );
  inject.registerFactory(() => CounterCubit());
  inject.registerFactory(
    () => ArchivesBloc(archivesRepository: inject(), tableTimers: inject()),
  );
  inject.registerFactory(() => ArchiveBloc(archivesRepository: inject()));
  inject.registerFactory(
    () => PaymentBloc(
      ordersRepository: inject(),
      paymentRepository: inject(),
      printerService: inject(),
      serviceChargeRepository: inject(),
    ),
  );
  inject.registerFactory(() => NotificationBloc());
  inject.registerLazySingleton(() => SavedOrdersBloc());
  inject.registerFactory(() => HourPriceBloc(timerRepository: inject()));
  inject.registerFactory(
    () => WaiterCubit(inject(), inject(), inject()),
  );
  inject.registerLazySingleton(() => TableTimerSyncService());
  inject.registerFactory(() => TableTimerCubit(inject(), inject()));
}

/// This terminal's branch, for the reads that must not show another branch's
/// data.
///
/// A function rather than a value because it is empty until the operator logs
/// in, and the repositories that consult it are built long before that. It
/// reads the same source every screen already uses — the cached `UserModel`,
/// which `UserBloc` restores from the offline auth cache, so it answers with
/// the cable pulled exactly as it does online.
///
/// Empty when nothing is logged in yet, which the queries read as "no filter"
/// rather than "no rows".
String _currentBranchId() {
  try {
    return inject<UserBloc>().state.userMOdel?.branchId ?? '';
  } catch (_) {
    // Resolved before UserBloc is registered, or in a test wiring without it.
    return '';
  }
}
