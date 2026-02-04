import 'package:flutter/cupertino.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/login_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login_pin/login_pin_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/splash/splash_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/main_screen.dart';

class RouteGenerate {
  Route generate(RouteSettings settings) {
    // final args = settings.arguments;

    switch (settings.name) {
      case AppRoutes.splashScreen:
        return simpleRoute(const SplashScreen());

      case AppRoutes.loginScreen:
        return simpleRoute(const LoginScreen());

      case AppRoutes.loginPinScreen:
        return simpleRoute(const LoginPinScreen());

      case AppRoutes.mainScreen:
        return simpleRoute(const MainScreen());
    }
    return throw UnimplementedError();
  }

  Route<CupertinoPageRoute> simpleRoute(Widget route, {Object? args}) =>
      CupertinoPageRoute(
        builder: (context) => route,
        settings: RouteSettings(arguments: args),
      );
}
