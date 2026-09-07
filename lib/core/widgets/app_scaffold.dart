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
  ///
  /// Kept as the entry point the screens already call, but the keyboard
  /// itself now lives in the root [Overlay] ([FloatingKeyboard]) rather than
  /// in this scaffold's own `Stack`. Screens outside an [AppScaffold]
  /// (login, payment, waiter, order detail) used to get nothing at all from
  /// this call, and dialogs got a keyboard painted *underneath* them.
  static void open(
    TextEditingController controller, {
    ValueChanged<String>? onChanged,
  }) {
    FloatingKeyboard.openText(null, controller, onChanged: onChanged);
  }

  /// Closes the virtual keyboard.
  static void close() => FloatingKeyboard.close();

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  // BACKEND_SYNC_PLAN.md §5 (structural note): this widget no longer owns
  // any sync trigger. The app-startup tick and the reconnect-edge tick both
  // live in SyncEngine.start() now, and the old one-shot first-mount
  // prefetch gate (with its logout reset) is superseded by
  // LoginDataScopeService's login-triggered hydrateNow().
  @override
  void dispose() {
    FloatingKeyboard.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor:
          widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      // The keyboard is an entry in the root Overlay now, so it needs no
      // slot in this tree — and dismissing it on an outside tap is handled
      // by the overlay's own pointer catcher.
      body: Column(
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
    );
  }
}
