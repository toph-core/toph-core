import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/services/auth/login_data_scope_service.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_app_harness.dart';

/// What a login decides, which is now separate from what it does.
///
/// `onSuccessfulLogin` used to start the first-time pull itself, with
/// `unawaited(...)`, and return — so login navigation was never blocked and a
/// terminal with nothing in its replica walked straight onto the floor plan.
/// It returns the decision now and `LoginPinCubit` acts on it by routing to
/// `InitialSetupScreen`, so these three answers are the hinge the whole
/// first-run experience turns on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineAppHarness app;
  late AppTokenStorage storage;
  late LoginDataScopeService scope;

  Future<void> bootHarness(WidgetTester tester) async {
    app = await OfflineAppHarness.boot(tester);
    app.seedVenue();
    await app.signIn();
    storage = inject<AppTokenStorage>();
    scope = inject<LoginDataScopeService>();
  }

  testWidgets('a terminal that has never been set up asks for setup', (
    tester,
  ) async {
    await bootHarness(tester);
    try {
      // No stored auth context at all — the shape of a terminal being
      // provisioned for the first time.
      await tester.runAsync(() async {
        expect(await scope.onSuccessfulLogin(), LoginDataScope.initialSetup);
      });
    } finally {
      await app.settle(tester, rounds: 25);
      await app.dispose(tester);
    }
  });

  testWidgets('a terminal that finished setup logs straight in', (
    tester,
  ) async {
    await bootHarness(tester);
    try {
      await tester.runAsync(() async {
        await storage.writeLastAuthContext(
          brandId: 'brand-1',
          cashRegisterId: '',
        );
        await storage.setPosInitialized(true);

        // The ordinary case, and the one that must not put a progress screen
        // in front of a cashier starting their shift.
        expect(await scope.onSuccessfulLogin(), LoginDataScope.none);
      });
    } finally {
      await app.settle(tester, rounds: 25);
      await app.dispose(tester);
    }
  });

  testWidgets('a brand switch asks for setup and drops the old shift', (
    tester,
  ) async {
    await bootHarness(tester);
    try {
      await tester.runAsync(() async {
        await storage.writeLastAuthContext(
          brandId: 'a-different-brand',
          cashRegisterId: '',
        );
        await storage.setPosInitialized(true);
        // The shift is a replicated `branch_shifts` row now, so the replica
        // wipe carries it. What is still checked here is the *legacy* key: a
        // terminal upgrading from a build that kept the shift in
        // SharedPreferences must not have that record survive a brand switch,
        // where it would otherwise sit outside the replica forever.
        await inject<SharedPreferences>()
            .setString(LoginDataScopeService.legacyLocalShiftPrefsKey, '{"id":"old-shift"}');

        expect(await scope.onSuccessfulLogin(), LoginDataScope.initialSetup);
        expect(
          inject<SharedPreferences>().getString(LoginDataScopeService.legacyLocalShiftPrefsKey),
          isNull,
          reason: "the previous brand's shift survived the switch",
        );
        expect(
          storage.isPosInitialized,
          isFalse,
          reason: 'a brand switch must not count as already provisioned',
        );
      });
    } finally {
      await app.settle(tester, rounds: 25);
      await app.dispose(tester);
    }
  });
}
