import 'package:flutter/cupertino.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/login_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login_pin/login_pin_screen.dart';

class RouteGenerate {
  Route generate(RouteSettings settings) {
    // final args = settings.arguments;

    switch (settings.name) {
      /// PROJECT ///

      // case AppRoutes.noInternetScreen:
      //   return simpleRoute(const NoInternetScreen());

      // case AppRoutes.mainScreen:
      //   return simpleRoute(const MainScreen());

      case AppRoutes.loginScreen:
        return simpleRoute(const LoginScreen());

      case AppRoutes.loginPinScreen:
        return simpleRoute(const LoginPinScreen());
    }
    return throw UnimplementedError();
  }

  Route<CupertinoPageRoute> simpleRoute(Widget route, {Object? args}) =>
      CustomDurationCupertinoPageRoute(
        builder: (context) => route,
        settings: RouteSettings(arguments: args),
      );
}

class CustomDurationCupertinoPageRoute<T> extends CupertinoPageRoute<T> {
  CustomDurationCupertinoPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 600);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 600);
}
