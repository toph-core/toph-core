import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mary_ai_pos/core/routes/app_pages.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/service/app_version/app_update_service.dart';
import 'package:mary_ai_pos/core/theme/app_theme.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/utils/scroll_physics_modified.dart';
import 'package:mary_ai_pos/core/utils/size_config.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

Future<void> main() async {
  // await flutter_acrylic.Window.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await AppUpdateService.getCloudVersion();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // await flutter_acrylic.Window.hideWindowControls();
  // await WindowManager.instance.ensureInitialized();
  // windowManager.waitUntilReadyToShow().then((_) async {
  //   await windowManager.setTitleBarStyle(
  //     TitleBarStyle.hidden,
  //     windowButtonVisibility: false,
  //   );
  //   await windowManager.setMinimumSize(const Size(1000, 600));
  //   await windowManager.show();
  //   await windowManager.setPreventClose(true);
  //   await windowManager.setSkipTaskbar(false);
  //   await windowManager.setFullScreen(true);
  // });

  await initDi();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => inject<AuthCubit>()),
        BlocProvider(create: (_) => inject<SettingsCubit>()..loadAppLang()),
        BlocProvider(create: (_) => inject<MainCubit>()),
        BlocProvider(create: (_) => inject<SavedOrdersBloc>()),
        BlocProvider(create: (_) => inject<UserBloc>()..add(const UserEvent.started())),
        BlocProvider(create: (_) => inject<ShiftBloc>()..add(const ShiftEvent.started()))
      ],
      child: BlocSelector<SettingsCubit, SettingsState, String>(
        selector: (state) => state.language,
        builder: (context, language) {
          return MaterialApp(
            title: 'Mary AI POS',
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            onGenerateRoute: RouteGenerate().generate,
            localizationsDelegates: const [
              GlobalWidgetsLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              S.delegate,
            ],
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('uz'), Locale('ru')],
            themeMode: ThemeMode.light,
            theme: AppTheme.lightTheme,
            builder: (context, child) {
              return ScrollConfiguration(
                behavior: const ScrollBehaviorModified(),
                child: child!,
              );
            },
            initialRoute: AppRoutes.splashScreen,
            onGenerateInitialRoutes: (initialRoute) => [
              RouteGenerate().generate(
                RouteSettings(
                  name: initialRoute,
                  arguments: {
                    "table_id": "048aa68f-4c4d-490a-8fa6-83025519c3b5",
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ScrollBehaviorModified extends ScrollBehavior {
  const ScrollBehaviorModified();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();

  @override
  Widget buildScrollbar(_, Widget child, _) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysicsModified();
  }
}
