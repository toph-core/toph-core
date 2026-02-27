import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/login_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login_pin/login_pin_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/splash/splash_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/archive/archive_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/close_shift_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/main_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/notification/notification_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/payment_screen.dart';

class RouteGenerate {
  Route generate(RouteSettings settings) {
    final args = settings.arguments;
    switch (settings.name) {
      case AppRoutes.splashScreen:
        return simpleRoute(const SplashScreen());

      case AppRoutes.loginScreen:
        return simpleRoute(const LoginScreen());

      case AppRoutes.loginPinScreen:
        return simpleRoute(const LoginPinScreen());

      case AppRoutes.mainScreen:
        return simpleRoute(const MainScreen());

      case AppRoutes.detailScreen:
        return simpleRoute(const DetailScreen(), args: args);

      case AppRoutes.paymentScreen:
        return simpleRoute(const PaymentScreen(), args: args);

      case AppRoutes.archiveScreen:
        return simpleRoute(const ArchiveScreen());

      case AppRoutes.closeShiftScreen:
        return simpleRoute(const CloseShiftScreen());

      case AppRoutes.notificationsScreen:
        return simpleRoute(const NotificationScreen());
    }
    return throw UnimplementedError();
  }

  Route<dynamic> simpleRoute(Widget route, {Object? args}) => PageRouteBuilder(
    settings: RouteSettings(arguments: args),
    pageBuilder: (context, animation, secondaryAnimation) => route,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}
