import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/widgets/app_sidebar.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/core/widgets/lan_solo_banner.dart';
import 'package:mary_ai_pos/core/widgets/offline_banner.dart';

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
  final ValueNotifier<bool> _showVirtualKeyboard = ValueNotifier<bool>(false);
  final ValueNotifier<TextEditingController?> _keyboardController = ValueNotifier<TextEditingController?>(null);
  ValueChanged<String>? _keyboardOnChanged;

  static _AppScaffoldState? _instance;

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

  // BACKEND_SYNC_PLAN.md §5 (structural note): this widget no longer owns
  // any sync trigger. The app-startup tick and the reconnect-edge tick both
  // live in SyncEngine.start() now, and the old one-shot first-mount
  // prefetch gate (with its logout reset) is superseded by
  // LoginDataScopeService's login-triggered hydrateNow().
  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
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
