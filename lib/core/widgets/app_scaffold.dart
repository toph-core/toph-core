import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/widgets/app_sidebar.dart';

class AppScaffold extends StatelessWidget {
  final String activeRoute;
  final Widget body;
  final Color? backgroundColor;

  const AppScaffold({
    super.key,
    required this.activeRoute,
    required this.body,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          AppSidebar(activeRoute: activeRoute),
          Expanded(child: body),
        ],
      ),
    );
  }
}
