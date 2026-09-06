/// What the operator is told when a printer does not reach the backend.
///
/// The save dialog used to fire the push with `unawaited(...)` and pop with a
/// success result whatever happened. On an offline terminal — the ordinary case
/// in this product — the printer existed on exactly one machine, nothing said
/// so, and the next logout deleted it. This drives the real screen: the dialog
/// stays open with the warning when the push fails, and closes having adopted
/// the backend's id when it succeeds.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/theme/app_theme.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/printers/printers_controller.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/sections/printers_section.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connectivity_platform.dart';
import 'support/in_memory_secure_storage.dart';

/// Everything these two fakes are not asked for throws rather than returning a
/// plausible-looking null — a test that starts leaning on an unstubbed method
/// should fail loudly, not quietly pass for the wrong reason.
class _Unimplemented {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

class _FakeMenuRepository extends _Unimplemented implements MenuRepository {
  @override
  List<CategoryModel> getCategories() => const [];
}

class _FakeMainRepository extends _Unimplemented implements MainRepository {
  _FakeMainRepository(this._reply);

  final Either<Failure, PrinterSettingEntry?> Function(String? existingId)
      _reply;
  final List<String?> pushedIds = [];

  @override
  Future<Either<Failure, PrinterSettingEntry?>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  }) async {
    pushedIds.add(existingId);
    return _reply(existingId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PrinterConfigStorage storage;
  late _FakeMainRepository remote;

  Future<void> setUpTerminal(
    WidgetTester tester,
    Either<Failure, PrinterSettingEntry?> Function(String?) reply,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = PrinterConfigStorage(prefs);
    remote = _FakeMainRepository(reply);

    await inject.reset();
    inject.registerSingleton<PrinterConfigStorage>(storage);
    inject.registerSingleton<PrinterService>(PrinterService(storage));
    inject.registerSingleton<PrintersController>(
      PrintersController(menu: _FakeMenuRepository(), remote: remote),
    );
    // The screen tells the other terminals what changed after a save. A real
    // service in its default `disabled` mode is the honest stand-in: it has no
    // hub to broadcast over, so the call is a no-op rather than a mock.
    InMemorySecureStoragePlatform.install();
    FakeConnectivityPlatform.install();
    // Built inside `runAsync` on purpose. Its 20s reachability probe is a
    // periodic timer, and a timer created in the widget-test zone is a *fake*
    // one the binding counts — the tree would be torn down with it still
    // pending and the test would fail on `!timersPending` before any
    // `addTearDown` ran. Created in a real zone it is a real timer, invisible
    // to that check, and still cancelled by `close()` below.
    final connectivity = (await tester.runAsync(() async {
      final cubit = ConnectivityCubit(Connectivity());
      // Let `_init` reach its `Timer.periodic` while still in the real zone.
      await Future<void>.delayed(Duration.zero);
      return cubit;
    }))!;
    addTearDown(connectivity.close);
    final lanHub = LanHubService(
      prefs,
      tokenStorage: AppTokenStorage(prefs, const FlutterSecureStorage()),
      connectivity: connectivity,
    );
    inject.registerSingleton<LanHubService>(lanHub);
    // `printers_section` announces the change after a save — the same callback
    // `di.dart` registers in production. In `disabled` mode there is no hub to
    // broadcast over, so the call is a no-op; it still has to be registered, or
    // the screen throws on the lookup the moment a save succeeds.
    inject.registerSingleton<PrinterSettingsAnnouncer>(
      lanHub.announcePrinterSettings,
    );
  }

  tearDown(() => inject.reset());

  /// The dialog's footer row overflows its 520px by 38px under the test
  /// binding's fallback font — with the labels this change did not touch, and
  /// on the real device's Inter it fits. Same reason and same shape as
  /// `offline_app_harness.dart`'s `_ignoreLayoutOverflow`: a layout complaint
  /// from the test font would drown out what this file is actually asserting.
  void ignoreLayoutOverflow() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('overflowed by')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ignoreLayoutOverflow();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalWidgetsLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          S.delegate,
        ],
        locale: const Locale('uz'),
        supportedLocales: const [Locale('en'), Locale('uz'), Locale('ru')],
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: PrintersSection()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens "Add printer" and fills in a plain network close-check printer —
  /// the shortest valid form (a category printer would also need a category,
  /// and this replica has none).
  Future<void> fillNewPrinter(WidgetTester tester) async {
    await tester.tap(find.text(S.current.strAddPrinter));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Chek');
    await tester.enterText(find.byType(TextFormField).at(1), '192.168.1.100');
    await tester.tap(find.text(S.current.strCheckPrinter));
    await tester.pumpAndSettle();
  }

  testWidgets('a failed push keeps the dialog open and says so', (tester) async {
    await setUpTerminal(tester, (_) => const Left(ConnectionFailure()));
    await pumpSection(tester);
    await fillNewPrinter(tester);

    await tester.tap(find.text(S.current.strAdd));
    await tester.pumpAndSettle();

    // Still open, and explicit about what happened.
    expect(find.textContaining('faqat shu terminalda saqlandi'), findsOneWidget);
    expect(find.text('Yopish'), findsOneWidget);
    // The local save stands — offline still works.
    expect(storage.listEntries().length, 1);
    expect(PrinterConfigStorage.isLocalId(storage.listEntries().single.id), isTrue);
  });

  testWidgets('retrying does not add a second local entry', (tester) async {
    await setUpTerminal(tester, (_) => const Left(ConnectionFailure()));
    await pumpSection(tester);
    await fillNewPrinter(tester);

    await tester.tap(find.text(S.current.strAdd));
    await tester.pumpAndSettle();
    // The same button retries — its label does not change.
    await tester.tap(find.text(S.current.strAdd));
    await tester.pumpAndSettle();

    expect(storage.listEntries().length, 1);
    // Both attempts are creates: the id the first attempt saved locally is a
    // `local-` one, which cannot be PUT.
    expect(remote.pushedIds, [null, null]);
  });

  testWidgets('a successful push adopts the backend id and closes', (tester) async {
    const backendId = '33333333-3333-4333-8333-333333333333';
    await setUpTerminal(
      tester,
      (_) => const Right(
        PrinterSettingEntry(
          id: backendId,
          ip: '192.168.1.100',
          port: 9100,
          type: 'close_check',
          connectedEntityIds: [],
          name: 'Chek',
          connectionType: 'cable',
          branchId: 'branch-9',
        ),
      ),
    );
    await pumpSection(tester);
    await fillNewPrinter(tester);

    await tester.tap(find.text(S.current.strAdd));
    await tester.pumpAndSettle();

    // The dialog is gone: no warning, no footer.
    expect(find.textContaining('faqat shu terminalda saqlandi'), findsNothing);
    expect(find.text(S.current.strAdd), findsNothing);
    final saved = storage.listEntries().single;
    expect(saved.id, backendId);
    expect(saved.branchId, 'branch-9');
    // The per-device paper size was written under the local id and moved with
    // the entry; if it had not, the ticket would silently change width.
    expect(storage.getPaperSizeCode(backendId), isNotNull);
  });
}
