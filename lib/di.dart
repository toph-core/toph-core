import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mary_ai_pos/core/api/app_security_context.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_log_service.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/service/receipt/receipt_info_storage.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
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
import 'package:mary_ai_pos/features/view/main/domain/usecase/check_shift_usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/archives_local_repository_impl.dart';
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
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_goods_with_name_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_hour_price_usecase.dart';
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

  // offline-first-target-architecture.md §8 Phase 3 — additive, not yet
  // wired into CreateOrderBloc's table-open path (see EXECUTION_CONCERNS.md
  // and the class doc on LeaseManager for why).
  final leaseManager = LeaseManager(lanHub: lanHubService, localDb: localDatabase);
  inject.registerSingleton<LeaseManager>(leaseManager);

  // offline-first-target-architecture.md §8 Phase 4 — additive, disabled by
  // default (see LeaderElectionService's class doc / EXECUTION_CONCERNS.md).
  // start() itself no-ops unless a branch has explicitly opted in via
  // setEnabled(true), so this call is safe to make unconditionally here.
  final leaderElection = LeaderElectionService(lanHub: lanHubService, prefs: prefs);
  inject.registerSingleton<LeaderElectionService>(leaderElection);

  final syncEngine = SyncEngine(
    queue: offlineQueue,
    cache: cacheService,
    connectivity: connectivityCubit,
    client: dioClient,
    lanHub: lanHubService,
    prefs: prefs,
    localDb: localDatabase,
  );
  syncEngine.start();
  inject.registerSingleton<SyncEngine>(syncEngine);

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
    () => ArchivesLocalRepositoryImpl(inject(), inject(), inject(), inject()),
  );
  inject.registerLazySingleton<MenuLocalRepository>(
    () => MenuLocalRepositoryImpl(inject(), inject(), inject()),
  );
  inject.registerLazySingleton<TableTimerLocalRepository>(
    () => TableTimerLocalRepositoryImpl(inject()),
  );
  inject.registerLazySingleton<WaiterLocalRepository>(
    () => WaiterLocalRepositoryImpl(inject(), inject(), inject(), inject()),
  );

  // offline-first-target-architecture.md §8 Phase 2 — the LocalRepository
  // layer §1/§9 describe: reactive reads over LocalDatabase, writes that
  // commit locally (outbox enqueue) and return without awaiting the network.
  inject.registerLazySingleton<OrdersRepository>(
    () => OrdersRepositoryImpl(localDb: inject(), queue: inject(), lanHub: inject()),
  );
  inject.registerLazySingleton<PaymentRepository>(
    () => PaymentRepositoryImpl(queue: inject()),
  );
  inject.registerLazySingleton<TablesRepository>(
    () => TablesRepositoryImpl(localDb: inject()),
  );
  inject.registerLazySingleton<MenuRepository>(
    () => MenuRepositoryImpl(localDb: inject()),
  );
  // §8 Phase 5 (back-office tier) — read-only, see TransactionsRepository's
  // own class doc for what's deliberately not covered.
  inject.registerLazySingleton<TransactionsRepository>(
    () => TransactionsRepositoryImpl(localDb: inject()),
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
  inject.registerLazySingleton(() => GetGoodsWithNameUseCase(inject()));
  inject.registerLazySingleton(() => LogoutUsecase(inject()));
  inject.registerLazySingleton(() => CheckUserDataUsecase(inject()));
  inject.registerLazySingleton(() => GetUserUsecase(inject()));
  inject.registerLazySingleton(
    () => SyncPrinterSettingsUsecase(inject(), inject()),
  );
  inject.registerLazySingleton(() => CheckShiftUsecase(inject()));
  inject.registerFactory(() => GetHourPriceUsecase(repository: inject()));
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
    () => MainCubit(inject(), inject()),
  );
  inject.registerLazySingleton(() => KeyboardCubit());
  inject.registerLazySingleton(
    () => ShiftBloc(
      checkShiftUsecase: inject(),
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
    () => LoginPinCubit(inject(), inject(), inject(), inject(), inject()),
  );
  inject.registerFactory(
    () => DetailBloc(
      inject(),
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
      mainRepository: inject(),
    ),
  );
  inject.registerFactory(() => NotificationBloc());
  inject.registerLazySingleton(() => SavedOrdersBloc());
  inject.registerFactory(() => HourPriceBloc(getHourPriceUsecase: inject()));
  inject.registerFactory(
    () => WaiterCubit(inject(), inject(), inject()),
  );
  inject.registerLazySingleton(() => TableTimerSyncService());
  inject.registerFactory(() => TableTimerCubit(inject(), inject()));
}
