import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/widgets/app_sidebar.dart';
import 'package:mary_ai_pos/core/widgets/global_virtual_keyboard.dart';
import 'package:mary_ai_pos/core/widgets/offline_banner.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';

class AppScaffold extends StatefulWidget {
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
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  StreamSubscription<bool>? _connectivitySub;
  Timer? _bgRefreshTimer;

  static const _bgRefreshInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _connectivitySub = inject<ConnectivityCubit>().stream.listen((isOnline) {
      if (isOnline) {
        _syncOfflineQueue();
        _prefetchGoods();
      }
    });
    // Orqa fonda stollar statusini yangilab turadi
    _bgRefreshTimer = Timer.periodic(_bgRefreshInterval, (_) {
      if (inject<ConnectivityCubit>().isOnline && mounted) {
        context.read<MainCubit>().refreshTables();
      }
    });
    // Birinchi ochilishda ham goods prefetch
    if (inject<ConnectivityCubit>().isOnline) _prefetchGoods();
  }

  void _prefetchGoods() {
    inject<CacheService>().prefetchAllGoods(inject<DioClient>());
  }

  Future<void> _syncOfflineQueue() async {
    final queue = inject<OfflineQueueService>();
    if (!queue.hasItems) return;
    await queue.syncAll(inject<DioClient>());
    if (mounted) context.read<MainCubit>().refreshTables();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _bgRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor:
          widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      body: GlobalVirtualKeyboard(
        child: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: Row(
                children: [
                  AppSidebar(activeRoute: widget.activeRoute),
                  Expanded(child: widget.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
