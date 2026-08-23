import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/services/auth/login_data_scope_service.dart';
import 'package:mary_ai_pos/core/sync/replication_service.dart';
import 'package:mary_ai_pos/core/widgets/brand_logo.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// The one screen in this application that waits on the network, and the only
/// place a request is allowed to block a person.
///
/// It exists because the alternative was worse and silent. `onSuccessfulLogin`
/// used to start the first-time pull with `unawaited(...)` and return, so a
/// freshly provisioned terminal went straight to the floor plan while its
/// halls, tables and menu were still arriving — and if the terminal happened
/// to be offline, they were not arriving at all. The operator saw an empty
/// app and no explanation. `LoginDataScopeService`'s own comment had called
/// for this screen ("Phase 4 promotes it to a foreground step with a progress
/// screen — the single request in the product a person waits on"); this is it.
///
/// Two rules shape the rest:
///
/// * **It reports real progress.** `ReplicationService.bootstrap` has taken an
///   `onProgress` callback since it was written and never had a caller, so the
///   row count below is the actual feed position, not a spinner standing in
///   for one.
/// * **It never traps anyone.** A terminal that cannot reach the server still
///   has to be usable — that is the whole premise of the product — so a failed
///   or partial pull offers Retry *and* Continue. Continuing leaves
///   `isPosInitialized` false, which is what makes the next login try again
///   instead of treating a half-filled replica as provisioned.
class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  bool _running = true;
  bool _failed = false;
  int _rows = 0;

  @override
  void initState() {
    super.initState();
    // Post-frame rather than straight from initState: the run navigates on
    // completion, and a pull served entirely from a warm cursor can finish
    // inside the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _failed = false;
    });

    final outcome = await inject<LoginDataScopeService>().runInitialSetup(
      onProgress: (ReplicationProgress p) {
        if (!mounted) return;
        setState(() => _rows = p.rowsApplied);
      },
    );

    if (!mounted) return;
    if (outcome == InitialSetupOutcome.ready) {
      _continue();
      return;
    }
    setState(() {
      _running = false;
      _failed = true;
    });
  }

  /// Onward to the ordinary startup path, which decides where this terminal
  /// belongs. Replaces the whole stack: nothing here is worth coming back to.
  void _continue() => Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.splashScreen,
        (route) => false,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.bgDefault,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(height: 96),
                const SizedBox(height: 40),
                if (_failed) ..._failure(text) else ..._progress(text),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _progress(TextTheme text) => [
        Text(
          S.current.strSetupTitle,
          style: text.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          S.current.strSetupSubtitle,
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        // Only once something has actually arrived — "0 records" while the
        // first batch is in flight reads as a stall rather than a start.
        if (_rows > 0)
          Text(S.current.strSetupProgress(_rows), style: text.bodySmall),
      ];

  List<Widget> _failure(TextTheme text) => [
        Text(
          S.current.strSetupFailedTitle,
          style: text.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          S.current.strSetupFailedBody,
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _running ? null : _run,
            child: Text(S.current.strRetry),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          // The escape hatch, and deliberately not the primary action: the
          // data really is worth waiting for when waiting is possible.
          child: TextButton(
            onPressed: _continue,
            child: Text(S.current.strSetupContinueAnyway),
          ),
        ),
      ];
}
