import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mary_ai_pos/core/api/app_security_context.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/service/receipt/receipt_info_storage.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/service/minio/minio_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/check_user_auth/check_user_data_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/user/get_user_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/check_shift_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/close_shift_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_payment_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_take_away_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_archive_with_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_archives_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_categories_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_departments_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_goods_by_category_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_goods_with_name_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_hour_price_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/sync_printer_settings_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_payment_detail_with_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_payment_detail_with_table_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/open_shift_usecase.dart';
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
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login_with_brand/login_with_brand_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout_from_app_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/set_app_language/set_app_language_uscase.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/main_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_halls_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_staff_waiters_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_tables_by_hall_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/table_timer/table_timer_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/waiter/waiter_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/ui_prefs/ui_prefs_cubit.dart';

final inject = GetIt.instance;
Future<void> initDi() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final AppTokenStorage tokenStorage = AppTokenStorage(prefs);

  inject.registerSingleton<SharedPreferences>(prefs);
  inject.registerSingleton<AppTokenStorage>(tokenStorage);
  inject.registerSingleton<OfflineAuthCache>(OfflineAuthCache(prefs));
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

  final offlineQueue = await OfflineQueueService.init();
  inject.registerSingleton<OfflineQueueService>(offlineQueue);

  final securityContext = await buildAppSecurityContext();
  final dioClient = DioClient(
    tokenStorage,
    connectivityCubit,
    securityContext: securityContext,
  );
  alice.addAdapter(dioClient.aliceDioAdapter);
  inject.registerSingleton<DioClient>(dioClient);

  final lanHubService = LanHubService(prefs);
  await lanHubService.init();
  inject.registerSingleton<LanHubService>(lanHubService);

  final MinioService minioService = MinioService.instance;
  minioService.configure(securityContext: securityContext);
  inject.registerLazySingleton(() => minioService);

  inject.registerLazySingleton(() => PrinterConfigStorage(inject()));
  inject.registerLazySingleton(() => PrinterService(inject<PrinterConfigStorage>()));

  _dataSources();
  _repositories();
  _useCase();
  _cubit();
}

void _dataSources() {
  inject.registerLazySingleton<AuthDatasource>(
    () => AuthDatasourceImpl(inject(), inject()),
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
    () => MainRepositoryImpl(inject()),
  );
}

void _useCase() {
  inject.registerLazySingleton(() => LogoutFromAppUseCase(inject()));
  inject.registerLazySingleton(() => CheckUserAuthUseCase(inject()));
  inject.registerLazySingleton(() => LoginUsecase(inject()));
  inject.registerLazySingleton(() => GetAppLangauageUsecase(inject()));
  inject.registerLazySingleton(() => SetAppLanguageUscase(inject()));
  inject.registerLazySingleton(() => LoginWithBrandUsecase(inject()));
  inject.registerLazySingleton(() => GetTablesByHallIdUsecase(inject()));
  inject.registerLazySingleton(() => GetHallsUsecase(inject()));
  inject.registerLazySingleton(() => GetCategoriesUsecase(inject()));
  inject.registerLazySingleton(() => GetDepartmentsUsecase(inject()));
  inject.registerLazySingleton(() => GetGoodsByCategoryIdUseCase(inject()));
  inject.registerLazySingleton(() => GetGoodsWithNameUseCase(inject()));
  inject.registerLazySingleton(() => GetArchivesUsecase(inject()));
  inject.registerLazySingleton(() => GetArchiveWithIdUsecase(inject()));
  inject.registerLazySingleton(() => LogoutUsecase(inject()));
  inject.registerLazySingleton(() => CheckUserDataUsecase(inject()));
  inject.registerLazySingleton(() => CreateOrderUsecase(inject()));
  inject.registerLazySingleton(() => CreatePaymentUsecase(inject()));
  inject.registerLazySingleton(
    () => GetPaymentDetailWithTableIdUsecase(inject()),
  );
  inject.registerLazySingleton(() => CreateTakeAwayOrderUsecase(inject()));
  inject.registerFactory(
    () => GetPaymentDetailWithIdUsecase(repository: inject()),
  );
  inject.registerLazySingleton(() => GetUserUsecase(inject()));
  inject.registerLazySingleton(
    () => SyncPrinterSettingsUsecase(inject(), inject()),
  );
  inject.registerLazySingleton(() => GetStaffWaitersUsecase(inject()));
  inject.registerLazySingleton(() => CheckShiftUsecase(inject()));
  inject.registerFactory(() => OpenShiftUsecase(inject()));
  inject.registerFactory(() => CloseShiftUsecase(inject()));
  inject.registerFactory(() => GetHourPriceUsecase(repository: inject()));
}

void _cubit() {
  //? lazy singleton
  inject.registerLazySingleton(
    () => AuthCubit(inject(), inject(), inject(), inject(), inject(), inject(), inject()),
  );
  inject.registerLazySingleton(() => SettingsCubit(inject(), inject()));
  inject.registerLazySingleton(() => UiPrefsCubit(inject()));
  inject.registerLazySingleton(() => ServiceChargeCubit(inject()));
  inject.registerLazySingleton(
    () => MainCubit(inject(), inject(), inject(), inject(), inject()),
  );
  inject.registerLazySingleton(() => KeyboardCubit());
  inject.registerLazySingleton(
    () => ShiftBloc(
      checkShiftUsecase: inject(),
      openShiftUsecase: inject(),
      closeShiftUsecase: inject(),
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
  inject.registerFactory(() => LoginPinCubit(inject(), inject(), inject(), inject(), inject()));
  inject.registerFactory(() => DetailBloc(inject(), inject(), inject(), inject(), inject(), inject()));
  inject.registerFactory(() => DepartmentSelectionCubit(inject(), inject()));
  inject.registerFactory(
    () => CreateOrderBloc(
      createOrderUsecase: inject(),
      createTakeAwayOrderUsecase: inject(),
      connectivity: inject(),
      queue: inject(),
      lanHub: inject(),
      client: inject(),
      printerService: inject(),
    ),
  );
  inject.registerFactory(() => CounterCubit());
  inject.registerFactory(
    () => ArchivesBloc(
      getArchivesUsecase: inject(),
      getArchiveWithIdUsecase: inject(),
    ),
  );
  inject.registerFactory(() => ArchiveBloc(getArchiveWithIdUsecase: inject()));
  inject.registerFactory(
    () => PaymentBloc(
      getPaymentDetailWithTableIdUsecase: inject(),
      createPaymentUsecase: inject(),
      getPaymentDetailWithId: inject(),
      printerService: inject(),
    ),
  );
  inject.registerFactory(() => NotificationBloc());
  inject.registerLazySingleton(() => SavedOrdersBloc());
  inject.registerFactory(() => HourPriceBloc(getHourPriceUsecase: inject()));
  inject.registerFactory(() => WaiterCubit(inject(), inject(), inject()));
  inject.registerFactory(() => TableTimerCubit(inject()));
}
