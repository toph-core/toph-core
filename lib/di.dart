import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/service/minio/minio_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:mary_ai_pos/features/view/auth/data/data_sources/auth_datasource.dart';
import 'package:mary_ai_pos/features/view/auth/data/repositories/login_repository_impl.dart';
import 'package:mary_ai_pos/features/view/auth/domain/repository/auth_repository.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/check_user_auth/check_user_auth.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/get_app_language/get_app_langauage_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/login_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login_with_brand/login_with_brand_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/logout/logout.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/set_app_language/set_app_language_uscase.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/main_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_tables_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';

final inject = GetIt.instance;
Future<void> initDi() async {
  const FlutterSecureStorage secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(useBackwardCompatibility: true),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  const AppTokenStorage tokenStorage = AppTokenStorage(secureStorage);

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
  inject.registerLazySingleton(() => LogoutUseCase(inject()));
  inject.registerLazySingleton(() => CheckUserAuthUseCase(inject()));
  inject.registerLazySingleton(() => LoginUsecase(inject()));
  inject.registerLazySingleton(() => GetAppLangauageUsecase(inject()));
  inject.registerLazySingleton(() => SetAppLanguageUscase(inject()));
  inject.registerLazySingleton(() => LoginWithBrandUsecase(inject()));
  inject.registerLazySingleton(() => GetTablesUsecase(inject()));
}

void _cubit() {
  //? lazy singleton
  inject.registerLazySingleton(() => AuthCubit(inject(), inject(), inject()));
  inject.registerLazySingleton(() => SettingsCubit(inject(), inject()));
  inject.registerLazySingleton(() => MainCubit(inject()));

  //? factory
  inject.registerFactory(() => LoginPinCubit(inject(), inject(), inject()));
}
