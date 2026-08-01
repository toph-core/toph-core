import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/core/widgets/app_sidebar.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/core/widgets/lan_solo_banner.dart';
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

  /// Opens the virtual keyboard for the given controller.
  ///
  /// [onChanged], if provided, is invoked whenever a key press mutates the
  /// controller's text — the virtual keyboard writes to the controller
  /// directly, which does not trigger a [TextField]'s own `onChanged`.
  static void open(TextEditingController controller, {ValueChanged<String>? onChanged}) {
    _AppScaffoldState._openKeyboard(controller, onChanged);
  }

  /// Closes the virtual keyboard.
  static void close() {
    _AppScaffoldState._closeKeyboard();
  }

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  StreamSubscription<bool>? _connectivitySub;
  final ValueNotifier<bool> _showVirtualKeyboard = ValueNotifier<bool>(false);
  final ValueNotifier<TextEditingController?> _keyboardController = ValueNotifier<TextEditingController?>(null);
  ValueChanged<String>? _keyboardOnChanged;

  static _AppScaffoldState? _instance;

  // Ilova ichida prefetch faqat bir marta triggerlanadi (CacheService'da ham
  // o'z throttle bor, lekin bu erda ham qo'shimcha darvoza qo'yamiz —
  // har yangi scaffold yaratilganda qayta urinishi to'xtatiladi).
  static bool _prefetchAttempted = false;

  static void _openKeyboard(
    TextEditingController controller,
    ValueChanged<String>? onChanged,
  ) {
    _instance?._keyboardOnChanged = onChanged;
    _instance?._keyboardController.value = controller;
    _instance?._showVirtualKeyboard.value = true;
  }

  static void _closeKeyboard() {
    _instance?._showVirtualKeyboard.value = false;
  }

  @override
  void initState() {
    super.initState();
    _instance = this;
    _connectivitySub = inject<ConnectivityCubit>().stream.listen((isOnline) {
      if (isOnline) _syncOnReconnect();
    });
    // Birinchi ochilishda bir marta (keyingi scaffoldlar triggerlamaydi)
    if (!_prefetchAttempted && inject<ConnectivityCubit>().isOnline) {
      _prefetchAttempted = true;
      inject<SyncEngine>().tick();
    }
  }

  Future<void> _syncOnReconnect() async {
    await inject<SyncEngine>().tick();
    if (mounted) context.read<MainCubit>().refreshTables();
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    _connectivitySub?.cancel();
    _showVirtualKeyboard.dispose();
    _keyboardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor:
          widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_showVirtualKeyboard.value) {
                _showVirtualKeyboard.value = false;
              }
            },
            child: Column(
              children: [
                const OfflineBanner(),
                const LanSoloBanner(),
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
          // Virtual keyboard overlay
          ValueListenableBuilder(
            valueListenable: _showVirtualKeyboard,
            builder: (context, show, _) {
              if (!show) return const SizedBox.shrink();
              return ValueListenableBuilder(
                valueListenable: _keyboardController,
                builder: (context, controller, _) {
                  if (controller == null) return const SizedBox.shrink();
                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      top: false,
                      child: StyledVirtualKeyboard(
                        controller: controller,
                        height: MediaQuery.of(context).size.height * .48,
                        onClose: () => _showVirtualKeyboard.value = false,
                        onChanged: _keyboardOnChanged,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
