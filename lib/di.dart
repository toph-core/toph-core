import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/service/minio/minio_service.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/check_user_auth/check_user_data_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_categories_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_goods_by_category_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/counter/counter_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/create_order/create_order_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_cubit.dart';
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
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_tables_by_hall_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';

final inject = GetIt.instance;
Future<void> initDi() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final AppTokenStorage tokenStorage = AppTokenStorage(prefs);

  inject.registerSingleton<AppTokenStorage>(tokenStorage);
  final MinioService minioService = MinioService.instance;
  inject.registerSingleton<DioClient>(DioClient(tokenStorage));
  inject.registerLazySingleton(() => minioService);

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
  inject.registerLazySingleton(() => GetGoodsByCategoryIdUseCase(inject()));
  inject.registerLazySingleton(() => LogoutUsecase(inject()));
  inject.registerLazySingleton(() => CheckUserDataUsecase(inject()));
  inject.registerLazySingleton(() => CreateOrderUsecase(inject()));
}

void _cubit() {
  //? lazy singleton
  inject.registerLazySingleton(
    () => AuthCubit(inject(), inject(), inject(), inject(), inject()),
  );
  inject.registerLazySingleton(() => SettingsCubit(inject(), inject()));
  inject.registerLazySingleton(() => MainCubit(inject(), inject()));

  //? factory
  inject.registerFactory(() => LoginPinCubit(inject(), inject(), inject()));
  inject.registerFactory(() => DetailCubit(inject(), inject()));
  inject.registerFactory(() => CreateOrderBloc(createOrderUsecase: inject()));
  inject.registerFactory(() => CounterCubit());

}
