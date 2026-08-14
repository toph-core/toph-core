import 'dart:convert';

import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mary_ai_pos/core/api/app_security_context.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_log_service.dart';
import 'package:mary_ai_pos/core/services/auth/login_data_scope_service.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/service/receipt/receipt_info_storage.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — the SQLite replica that replaces
// both `CacheService` and the Hive `LocalDatabase` above. Imported under a
// prefix only because the two `LocalDatabase` classes coexist during the
// migration; the Hive one and this prefix both go away in Phase 4.
import 'package:mary_ai_pos/core/db/apply_change.dart' as replica;
import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/db/local_database_factory.dart' as replica;
import 'package:mary_ai_pos/core/media/local_image_cache.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/sync/change_feed_relay.dart';
import 'package:mary_ai_pos/core/sync/replication_service.dart';
import 'package:mary_ai_pos/core/sync/sync_api_client.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
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
import 'package:mary_ai_pos/features/view/main/data/outbox/users_outbox.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/halls_tables_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_admin_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/users_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/halls_tables/halls_tables_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/menu_admin/menu_goods_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/menu_admin/menu_manage_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/users/users_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/menu_local_repository_impl.dart';
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
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/waiter_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_departments_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/sync_printer_settings_usecase.dart';
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

final inject = GetIt.instance;
Future<void> initDi() async {
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

  final cacheService = await CacheService.init();
  inject.registerSingleton<CacheService>(cacheService);

  // offline-first-target-architecture.md §8 Phase 0 — additive alongside
  // CacheService, nothing reads from it yet except SyncEngine's hydration
  // writes (§8 Phase 1).
  final localDatabase = await LocalDatabase.init();
  inject.registerSingleton<LocalDatabase>(localDatabase);

  // OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — the replica of the tenant
  // database. Additive for now: replication fills it in the background while
  // screens still read the two stores above. Phase 4 moves the screens across
  // and deletes both.
  final replicaDb = await replica.LocalDatabaseFactory.openDefault();
  final changeApplier = replica.ChangeApplier(replicaDb);
  inject.registerSingleton<replica.LocalDatabase>(replicaDb);
  inject.registerSingleton<replica.ChangeApplier>(changeApplier);

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
  final leaseManager = LeaseManager(lanHub: lanHubService, localDb: localDatabase);
  inject.registerSingleton<LeaseManager>(leaseManager);

  // offline-first-target-architecture.md §8 Phase 4 — additive, disabled by
  // default (see LeaderElectionService's class doc / EXECUTION_CONCERNS.md).
  // start() itself no-ops unless a branch has explicitly opted in via
  // setEnabled(true), so this call is safe to make unconditionally here.
  final leaderElection = LeaderElectionService(lanHub: lanHubService, prefs: prefs);
  inject.registerSingleton<LeaderElectionService>(leaderElection);

  // Phase 1 — the replication loop. Registered before SyncEngine because
  // SyncEngine drives it from the sync triggers it already owns; nothing else
  // in the app may call it, and nothing may call `SyncApiClient` directly.
  final syncApiClient = SyncApiClient(dioClient);
  inject.registerSingleton<SyncApiClient>(syncApiClient);
  inject.registerSingleton<ChangeFeedRelay>(
    ChangeFeedRelay(db: replicaDb, applier: changeApplier),
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

  final syncEngine = SyncEngine(
    feed: inject<ChangeFeedRelay>(),
    queue: offlineQueue,
    cache: cacheService,
    connectivity: connectivityCubit,
    client: dioClient,
    lanHub: lanHubService,
    prefs: prefs,
    localDb: localDatabase,
    replication: replicationService,
    outbox: outboxDrainer,
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
      localDb: localDatabase,
      cache: cacheService,
      syncEngine: syncEngine,
      prefs: prefs,
    ),
  );

  final MinioService minioService = MinioService.instance;
  minioService.configure(securityContext: securityContext);
  inject.registerLazySingleton(() => minioService);

  final printerConfigStorage = PrinterConfigStorage(prefs);
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
    cacheService,
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
    broadcastResult: lanHubService.broadcastPrintJobResult,
  );
  inject.registerSingleton<PrintQueueService>(printQueueService);
  printerService.attachPrintQueue(printQueueService.submitJob);

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

  // BACKEND_SYNC_PLAN.md §5: every registration the startup tick's
  // hydration pass resolves lazily (MainRepository, UserBloc, ...) exists
  // by this point — see the note at the SyncEngine registration above.
  syncEngine.start();

  // Deferred until here: `client` mode's initial connect attempt reads the
  // current user via `inject<UserBloc>()` for its branch id, and `UserBloc`
  // isn't registered until `_cubit()` above runs.
  await lanHubService.init();
  // Same DI-ordering reason as lanHubService.init() above — start() itself
  // is a no-op unless a branch opted in via setEnabled(true).
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
    () => MainRepositoryImpl(inject(), inject(), inject()),
  );
  inject.registerLazySingleton<ArchivesLocalRepository>(
    () => ArchivesLocalRepositoryImpl(inject(), inject(), inject()),
  );
  // OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the staff screen reads the
  // replica and writes through the outbox. Takes LocalDatabase + LocalWriter
  // and nothing else: no datasource, no DioClient, no ConnectivityCubit fork.
  inject.registerLazySingleton<UsersLocalRepository>(
    () => UsersLocalRepositoryImpl(inject<replica.LocalDatabase>(), inject()),
  );
  // Same shape for halls & tables. Note this deliberately does *not* replace
  // `TablesRepository`, which still serves the floor plan and waiter screens
  // from the Hive store — those move in their own commits, per screen.
  // One image cache for the whole app: the widget that displays images and the
  // repository that serves them must share a dedupe set, or the same bytes get
  // fetched twice.
  inject.registerLazySingleton<LocalImageCache>(
    () => LocalImageCache(
      watch: inject<LocalDatabase>().watchImage,
      read: inject<LocalDatabase>().getImage,
      write: inject<LocalDatabase>().saveImage,
      fetch: MinioService.instance.getImageByObjectName,
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
    ),
  );
  inject.registerLazySingleton<MenuLocalRepository>(
    () => MenuLocalRepositoryImpl(inject(), inject(), inject(), inject()),
  );
  // CLIENT_FACING_OFFLINE_PLAN.md §2 — local-first now: LocalDatabase +
  // outbox + OrdersRepository (for the timed-order create), no DioClient.
  // The timed-order create is lease-gated (LAN_HUB_AND_LEASING_PLAN.md §8).
  inject.registerLazySingleton<TableTimerLocalRepository>(
    () => TableTimerLocalRepositoryImpl(inject(), inject(), inject(), inject()),
  );
  // CLIENT_FACING_OFFLINE_PLAN.md §5 — rebuilt local-first on LocalDatabase
  // + the already-correct Orders/Payment repositories; no DioClient. The
  // create path is lease-gated (LAN_HUB_AND_LEASING_PLAN.md §8).
  inject.registerLazySingleton<WaiterLocalRepository>(
    () => WaiterLocalRepositoryImpl(
      inject(),
      inject(),
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
      localDb: inject(),
      queue: inject(),
      lanHub: inject(),
      cache: inject(),
      tables: inject(),
    ),
  );
  inject.registerLazySingleton<PaymentRepository>(
    () => PaymentRepositoryImpl(queue: inject()),
  );
  // Phase 4: halls/tables reads and occupancy move to the replica. The Hive
  // store still backs menus, bills and timers until their own screens follow.
  inject.registerLazySingleton<TablesRepository>(
    () => TablesRepositoryImpl(localDb: inject<replica.LocalDatabase>()),
  );
  inject.registerLazySingleton<MenuRepository>(
    () => MenuRepositoryImpl(localDb: inject(), images: inject()),
  );
  // §8 Phase 5 (back-office tier) — read-only, see TransactionsRepository's
  // own class doc for what's deliberately not covered.
  inject.registerLazySingleton<TransactionsRepository>(
    () => TransactionsRepositoryImpl(
      localDb: inject<LocalDatabase>(),
      replicaDb: inject<replica.LocalDatabase>(),
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
  inject.registerLazySingleton(() => GetDepartmentsUsecase(inject()));
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
  inject.registerLazySingleton(() => ServiceChargeCubit(inject(), inject()));
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
      prefs: inject(),
      tokenStorage: inject(),
      printerService: inject(),
    ),
  );

  //? factory
  inject.registerLazySingleton(
    () => UserBloc(
      getUserUsecase: inject(),
      syncPrinterSettingsUsecase: inject(),
    ),
  );
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
      inject(),
      inject(),
    ),
  );
  inject.registerFactory(
    () => DepartmentSelectionCubit(inject(), inject()),
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
    () => ArchivesBloc(archivesRepository: inject()),
  );
  inject.registerFactory(() => ArchiveBloc(archivesRepository: inject()));
  inject.registerFactory(
    () => PaymentBloc(
      ordersRepository: inject(),
      paymentRepository: inject(),
      printerService: inject(),
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
