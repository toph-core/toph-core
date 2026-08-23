/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §9.3 — the offline integration suite, and
/// the two definition-of-done boxes §7 leaves open:
///
/// * "Every screen renders with the cable pulled, cold-started"
/// * "Every user action completes without awaiting a network call"
///
/// Every test here boots the real composition root through
/// `OfflineAppHarness`, with `DioClient`'s transport replaced by one that
/// refuses every request (see `DeadNetworkAdapter`). Nothing is stubbed at the
/// bloc, repository or query layer: a screen either finds what it needs in the
/// SQLite replica or it fails.
///
/// The screen list is **driven off the filesystem**, not typed out here — the
/// first group walks `lib/**/*_screen.dart` and asserts every screen it finds
/// is either covered below or explicitly excluded with a reason. A new screen
/// that reaches for the network therefore fails this suite on the first run,
/// which is precisely what §9 guardrail 3 asks for.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/outbox/timer_shift_outbox.dart' show kShiftEntity;
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/login_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/initial_setup/initial_setup_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login_pin/login_pin_screen.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/splash/splash_screen.dart';
import 'package:mary_ai_pos/features/view/cashier/presentation/pages/cashier_screen.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/archive/archive_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/close_shift_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/department_selection/department_selection_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/admin_floor_plan_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/main_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/waiter_floor_plan_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/menu/menu_manage_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/menu/menu_meals_list_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/notification/notification_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/payment_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/settings_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/transactions/transactions_screen.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/waiter/waiter_screen.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/offline_app_harness.dart';

/// Screens deliberately not driven here, and why.
///
/// Empty, and that is a claim rather than an omission: all eighteen screens in
/// `lib/` are rendered below, including the three (`CashierScreen`,
/// `AdminFloorPlanScreen`, `WaiterScreen`) that `RouteGenerate` no longer
/// references. A map rather than a list so a future exclusion carries its
/// reason with it and a reader never has to guess whether a gap was a decision.
const Map<String, String> kExcludedScreens = {};

/// Endpoints a screen is still allowed to reach for, and why.
///
/// The target is an empty map: after Phase 4 a screen reads the replica and
/// writes the outbox, so it has no reason to open a socket at all. Every entry
/// here is therefore a debt with a name on it, and the ratchet in
/// `expectUsableFrame` fails if one is added *or* if one is paid off and left
/// behind.
const Map<Type, Set<String>> kScreenNetworkReach = {};

/// A note on why [InitialSetupScreen] is not in the map above, since it is the
/// one screen that genuinely does try to reach the server.
///
/// It records no reach here, and not because it declines to ask: `sync/pull`
/// is a POST, and `DioClient`'s offline interceptor rejects non-GET requests
/// while the terminal is offline — before the transport, so [DeadNetworkAdapter]
/// never sees one. Under this harness the attempt is short-circuited a layer
/// above the thing that counts.
///
/// That makes an entry here impossible to keep honest in both directions: the
/// ratchet would fail on an empty `reached`. So the screen's contract is
/// pinned by what it *does* instead — it reaches its failure state and offers
/// a way forward, which is the behaviour that matters to an operator whose
/// first login happens in a venue with no working uplink.

/// Screens this suite renders. The filesystem guard below cross-checks it.
const Set<String> kCoveredScreens = {
  'SplashScreen',
  'LoginScreen',
  'LoginPinScreen',
  'InitialSetupScreen',
  'MainScreen',
  'WaiterFloorPlanScreen',
  'AdminFloorPlanScreen',
  'WaiterScreen',
  'CashierScreen',
  'DepartmentSelectionScreen',
  'DetailScreen',
  'PaymentScreen',
  'ArchiveScreen',
  'CloseShiftScreen',
  'NotificationScreen',
  'MenuMealsListScreen',
  'MenuManageScreen',
  'SettingsScreen',
  'TransactionsScreen',
};

/// The shared "it rendered" assertion. Deliberately four separate claims,
/// because any one of them alone passes easily while the screen is in fact
/// broken:
///
/// 1. nothing escaped into the framework (layout overflow aside — see
///    `_ignoreLayoutOverflow` in the harness for why that one is filtered);
/// 2. an `ErrorWidget` — the red box a throwing `build` leaves behind — is
///    nowhere in the tree, which a caught-and-swallowed build failure would
///    otherwise hide;
/// 3. the screen is actually mounted, so a navigation that silently failed
///    cannot pass as a render;
/// 4. the screen reached for nothing on the network beyond what
///    [kScreenNetworkReach] still admits.
void expectUsableFrame(
  WidgetTester tester,
  OfflineAppHarness app, {
  required Type screen,
}) {
  final thrown = tester.takeException();
  expect(
    thrown,
    isNull,
    reason: '$screen threw while rendering offline: $thrown',
  );
  expect(
    find.byType(ErrorWidget),
    findsNothing,
    reason: '$screen rendered an ErrorWidget — its build failed offline.',
  );
  expect(
    find.byType(screen),
    findsWidgets,
    reason: '$screen is not on screen — navigation to it failed offline.',
  );

  // The §9.3 half that makes this more than a smoke test: what did the screen
  // *try* to fetch? A ratchet, in the shape `architecture_guard_test`
  // established — it fails in both directions, so a new fetch is caught and a
  // fetch that has since been retired must be struck off the list.
  final reached = app.network.paths.toSet();
  final allowed = kScreenNetworkReach[screen] ?? const <String>{};
  expect(
    reached.difference(allowed).toList()..sort(),
    isEmpty,
    reason:
        '$screen reached for the network. Reads belong in a query over the '
        'replica; writes belong in the outbox. If this really is transport, '
        'add it to kScreenNetworkReach with a note saying why.',
  );
  expect(
    allowed.difference(reached).toList()..sort(),
    isEmpty,
    reason:
        '$screen no longer reaches these endpoints — remove them from '
        'kScreenNetworkReach so the ratchet keeps its teeth.',
  );
}

/// Endpoints a *user action* is still allowed to reach for, and why.
///
/// The sibling of [kScreenNetworkReach], and it was the hole through which two
/// live violations survived this suite. `expectUsableFrame` pins what a screen
/// touches while rendering, so "every screen renders offline" was genuinely
/// proved — but the action tests below asserted only their local effects and
/// their outbox rows, and never once looked at what went over the wire. A
/// request made *in response to a tap* was therefore invisible here.
///
/// Two were hiding in exactly that gap, both on the cashier's hot path, both
/// fire-and-forget enough that offline they merely failed silently:
///
/// * `DetailBloc._onFetchBillOrders` awaited `getPaymentDetailWithTableId`
///   after every order create — a round-trip to re-read a row it had just
///   written locally.
/// * `PrinterService._fetchGoodIdsByName` awaited `/order-items/order/{id}`
///   before printing a close check, so the receipt waited out Dio's timeout
///   and then grouped by department wrongly anyway.
///
/// Both are gone, so this map is empty and the ratchet below keeps it that
/// way in both directions.
const Map<String, Set<String>> kActionNetworkReach = {};

/// The action-level counterpart of [expectUsableFrame]: this action put
/// nothing on the wire beyond what [kActionNetworkReach] names.
///
/// Call it at the end of a user-action test, after the local assertions. The
/// offline harness makes every request fail, so a violation is silent by
/// construction — nothing here would notice it without this check.
void expectNoNetworkReach(OfflineAppHarness app, String action) {
  final reached = app.network.paths.toSet();
  final allowed = kActionNetworkReach[action] ?? const <String>{};
  expect(
    reached.difference(allowed).toList()..sort(),
    isEmpty,
    reason:
        "'$action' reached for the network. A user action writes the replica "
        'and queues the outbox; it never awaits a request. If this really is '
        'transport, add it to kActionNetworkReach with a note saying why.',
  );
  expect(
    allowed.difference(reached).toList()..sort(),
    isEmpty,
    reason:
        "'$action' no longer reaches these endpoints — remove them from "
        'kActionNetworkReach so the ratchet keeps its teeth.',
  );
}

/// Declares one offline test: cold boot, seed, run, tear down — in that order,
/// inside one live widget-test zone.
///
/// Boot and teardown are deliberately *inside* the test body rather than in
/// `setUp`/`tearDown`, and that is not a style preference. Both are real
/// asynchronous work that has to run through [WidgetTester.runAsync], and
/// `runAsync` needs the test's zone to still exist. A teardown that runs after
/// the body has finished cannot flush Hive's write queue — the lock is held by
/// a continuation scheduled into a `FakeAsync` zone that no longer runs
/// anything — and `Hive.close()` then blocks forever, taking the whole test
/// process with it. Running it here, in the `finally`, keeps that zone alive
/// long enough for the queue to drain.
///
/// Cold per test, never per group: §7's box says "cold-started", and a shared
/// boot would let one screen's state stand in as another screen's evidence.
void offlineTest(
  String description,
  Future<void> Function(WidgetTester tester, OfflineAppHarness app) body, {
  bool signedIn = true,
  bool shiftOpen = true,
}) {
  testWidgets(description, (tester) async {
    final app = await OfflineAppHarness.boot(tester);
    try {
      app.seedVenue();
      if (signedIn) await app.signIn();
      if (shiftOpen) await app.openShift();
      await body(tester, app);
    } finally {
      // One last quiesce before teardown. Anything a user action set going in
      // the background — a receipt print retrying against an unreachable
      // printer, the queue row it saves when it gives up — has to reach an end
      // state while this zone is still alive, or its half-finished Hive write
      // holds a lock that `Hive.close()` then waits on forever.
      await app.settle(tester, rounds: 25);
      await app.dispose(tester);
    }
  });
}

CafeTableModel _table({
  required String id,
  required int number,
  TableStatus status = TableStatus.free,
  String? tableType = 'dine_in',
  String? pricePerHour,
}) => CafeTableModel(
  id: id,
  hallId: kHallId,
  number: number,
  posX: 40,
  posY: 40,
  width: 90,
  height: 90,
  rotation: 0,
  capacity: 4,
  status: status,
  tableType: tableType,
  pricePerHour: pricePerHour,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§9.3 — the screen inventory is complete', () {
    test('every *_screen.dart in lib is covered or explicitly excluded', () {
      final found = <String>{};
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('_screen.dart'))) {
        // `*Screen` only: these files also hold private layout helpers
        // (`_ArchiveRow`, `_CategoriesPanel`, ...) which are parts of a screen,
        // not screens, and are covered by rendering the screen that owns them.
        for (final m in RegExp(
          r'class (\w+Screen) extends (?:Stateful|Stateless)Widget',
        ).allMatches(file.readAsStringSync())) {
          found.add(m.group(1)!);
        }
      }

      final accounted = {...kCoveredScreens, ...kExcludedScreens.keys};
      final uncovered = found.difference(accounted).toList()..sort();
      final stale = accounted.difference(found).toList()..sort();

      expect(
        uncovered,
        isEmpty,
        reason:
            'These screens exist but this suite neither renders nor '
            'excludes them:\n${uncovered.map((s) => '  - $s').join('\n')}\n\n'
            'Add a render test below, or an entry in kExcludedScreens saying '
            'why it cannot be pumped headlessly. A screen that quietly skips '
            'this suite is a screen that can reach for the network unnoticed.',
      );
      expect(
        stale,
        isEmpty,
        reason:
            'These are named as covered or excluded but no longer exist '
            'in lib/:\n${stale.map((s) => '  - $s').join('\n')}',
      );
    });
  });

  group('§7 — every screen renders with the cable pulled', () {
    offlineTest('splash renders and reaches the app without a network call', (
      tester,
      app,
    ) async {
      // The splash screen itself, on the terminal's very first frame.
      await app.pumpFirstFrame(tester);
      expectUsableFrame(tester, app, screen: SplashScreen);

      await app.settle(tester);

      // Splash's whole job is to decide where an already-provisioned terminal
      // goes. Offline that decision must still be "into the app" — a spinner
      // waiting on a profile fetch would be the classic failure this plan
      // exists to remove.
      expectUsableFrame(tester, app, screen: MainScreen);
      expect(app.network.paths, isEmpty);
    });

    offlineTest(
      'the login screen renders on a fresh terminal',
      (tester, app) async {
        await app.pumpApp(tester);
        // No credentials anywhere, so splash routes to login.
        expectUsableFrame(tester, app, screen: LoginScreen);
      },
      signedIn: false,
      shiftOpen: false,
    );

    offlineTest('the PIN screen renders for a provisioned terminal', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.loginPinScreen);
      expectUsableFrame(tester, app, screen: LoginPinScreen);
    });

    offlineTest('the setup screen offers a way out when the pull cannot run', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.initialSetupScreen);
      // The pull is attempted and fails — the cable is pulled — so the screen
      // must settle on its failure state. A terminal that cannot reach the
      // server still has to be usable, so the one thing this must never do is
      // sit on a spinner with no way forward.
      await app.settle(tester, rounds: 30);
      expectUsableFrame(tester, app, screen: InitialSetupScreen);
      expect(
        find.text(S.current.strSetupContinueAnyway),
        findsOneWidget,
        reason: 'an offline terminal is trapped on the setup screen',
      );
      expect(find.text(S.current.strRetry), findsOneWidget);
    });

    offlineTest('the floor plan renders the seeded hall and tables', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);

      expectUsableFrame(tester, app, screen: WaiterFloorPlanScreen);
      expect(find.text('Asosiy zal'), findsWidgets);
      expect(app.network.paths, isEmpty);
    });

    offlineTest('the category screen renders for a free table', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(
        tester,
        AppRoutes.departmentSelectionScreen,
        arguments: {
          'table': _table(id: kFreeTableId, number: 1),
          'guest_count': 2,
          'table_status': TableStatus.free,
        },
      );
      expectUsableFrame(tester, app, screen: DepartmentSelectionScreen);
    });

    offlineTest('the menu screen renders the seeded catalog', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(
        tester,
        AppRoutes.detailScreen,
        arguments: {
          'table': _table(id: kFreeTableId, number: 1),
          'guest_count': 2,
          'table_status': TableStatus.free,
        },
      );
      expectUsableFrame(tester, app, screen: DetailScreen);
      expect(find.text('Osh'), findsWidgets);
    });

    offlineTest('the payment screen renders an open bill', (tester, app) async {
      await app.pumpApp(tester);
      await app.open(
        tester,
        AppRoutes.paymentScreen,
        arguments: {'table_id': kBusyTableId, 'order_id': kOpenOrderId},
      );
      expectUsableFrame(tester, app, screen: PaymentScreen);
    });

    offlineTest('the archive screen renders closed bills', (tester, app) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.archiveScreen);
      expectUsableFrame(tester, app, screen: ArchiveScreen);
    });

    offlineTest(
      'the shift screen renders',
      (tester, app) async {
        await app.pumpApp(tester);
        await app.open(tester, AppRoutes.closeShiftScreen);
        expectUsableFrame(tester, app, screen: CloseShiftScreen);
      },
      // No shift open: this screen's whole reason to exist is the two ends of
      // a shift, and the open-shift half is what a terminal shows first.
      shiftOpen: false,
    );

    offlineTest('the notifications screen renders', (tester, app) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.notificationsScreen);
      expectUsableFrame(tester, app, screen: NotificationScreen);
    });

    offlineTest('the meals list renders the seeded catalog', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.menuMealsScreen);
      expectUsableFrame(tester, app, screen: MenuMealsListScreen);
    });

    offlineTest('the meal editor renders for a seeded good', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(
        tester,
        AppRoutes.menuManageScreen,
        arguments: {'meal_id': kGoodId},
      );
      expectUsableFrame(tester, app, screen: MenuManageScreen);
    });

    offlineTest('the settings screen renders', (tester, app) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.settingsScreen);
      expectUsableFrame(tester, app, screen: SettingsScreen);
    });

    offlineTest('the transactions ledger renders seeded rows', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.transactionsScreen);
      expectUsableFrame(tester, app, screen: TransactionsScreen);
    });

    offlineTest('the unrouted screens still render under the app', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);

      for (final screen in <Widget>[
        const CashierScreen(),
        const AdminFloorPlanScreen(),
        const WaiterScreen(),
      ]) {
        await app.openWidget(tester, screen);
        expectUsableFrame(tester, app, screen: screen.runtimeType);
        await app.back(tester);
      }
    });
  });

  group('§7 — every user action completes without awaiting a network call', () {
    offlineTest('a cashier rings in an order on a free table', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(
        tester,
        AppRoutes.detailScreen,
        arguments: {
          'table': _table(id: kFreeTableId, number: 1),
          'guest_count': 2,
          'table_status': TableStatus.free,
        },
      );

      await tester.tap(find.text('Osh').first);
      await app.settle(tester);
      await tester.tap(find.text(S.current.strSave).first);
      await app.settle(tester);

      // The bill exists locally, immediately, with its line on it.
      final detail = app.orders.getOrderDetail(kFreeTableId);
      expect(detail, isNotNull, reason: 'the order never reached the replica');
      expect(detail!.goods.map((g) => g.name), contains('Osh'));
      // ... and it is queued for the server rather than having gone there.
      expect(app.outboxEntities(), contains('orders'));
      expectNoNetworkReach(app, 'rings in an order');
    });

    offlineTest('a waiter adds a line to a bill already open', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(
        tester,
        AppRoutes.detailScreen,
        arguments: {
          'table': _table(
            id: kBusyTableId,
            number: 2,
            status: TableStatus.busy,
          ),
          'guest_count': 2,
          'table_status': TableStatus.busy,
        },
      );

      final before = app.orders.getOrderDetail(kBusyTableId)!.goods.length;
      await tester.tap(find.text('Lagmon').first);
      await app.settle(tester);
      await tester.tap(find.text(S.current.strAddItems).first);
      await app.settle(tester);

      final after = app.orders.getOrderDetail(kBusyTableId)!;
      expect(after.goods, hasLength(before + 1));
      expect(after.goods.map((g) => g.name), contains('Lagmon'));
      expect(app.outboxEntities(), contains('order_items'));
      expectNoNetworkReach(app, 'adds a line');
    });

    offlineTest('a cashier takes a payment on an open bill', (
      tester,
      app,
    ) async {
      await app.pumpApp(tester);
      await app.open(
        tester,
        AppRoutes.paymentScreen,
        arguments: {'table_id': kBusyTableId, 'order_id': kOpenOrderId},
      );

      // Card rather than cash purely to keep the test about the payment: the
      // cash path additionally requires a tendered amount typed on the keypad,
      // which is arithmetic UI, not offline behaviour.
      await tester.tap(find.text(S.current.strCard).first);
      await app.settle(tester);
      await tester.tap(find.text(S.current.strConfirm).first);
      // A longer budget than the default: the receipt printer is unreachable,
      // and `PrinterService._connectAndPrint` retries twice with a one-second
      // pause between attempts. Those pauses are fake-clock timers, so the
      // settle loop has to advance past them for the print to finish and
      // release its queue row — otherwise the write is still in flight when the
      // test ends.
      await app.settle(tester, rounds: 30);

      // The payment committed on this terminal: the table reads free again on
      // the floor plan, and the charge is queued for the server rather than
      // having been sent to it.
      expect(
        app.db.tableStatuses()[kBusyTableId],
        'free',
        reason: 'the table is still occupied — the payment did not commit',
      );
      expect(app.outboxEntities(), contains('orders'));

      // The bill is closed in the replica, which is the whole point: the paid
      // row is written in the same commit that queues the send, so every
      // replica read agrees the table is settled without waiting for a round
      // trip. Asserted from both sides, because only the pair is meaningful —
      // the table no longer has a live bill, and the bill itself is still
      // there, marked paid, so the receipt and the archive can still find it.
      //
      // This assertion used to read `isNotNull`, pinning the opposite: the bill
      // stayed open on a table the cashier had just paid, and offline nothing
      // ever corrected it. `payment_close_bill_test.dart` pins the row shape.
      expect(
        app.orders.getOrderDetail(kBusyTableId),
        isNull,
        reason: 'the table still reports a live bill after being paid',
      );
      final settled = OrderDetailQuery(app.db).liveOrderById(kOpenOrderId);
      expect(settled, isNotNull, reason: 'the paid bill vanished entirely');
      expect(settled!['bill_status'], 'paid');
      expectNoNetworkReach(app, 'takes a payment');
    });

    offlineTest('a manager adds a table to a hall', (tester, app) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.settingsScreen);

      // The back-office half of the definition of done: a settings edit is a
      // local write plus an outbox row, exactly like an order. Driven through
      // the real navigation — settings → halls → the hall → new table — and the
      // table editor prefills every field, so no typing is needed to reach a
      // valid save.
      await tester.tap(find.text(S.current.strHalls).first);
      await app.settle(tester);
      await tester.tap(find.text('Asosiy zal').first);
      await app.settle(tester);
      await tester.tap(find.text(S.current.strNewTable).first);
      await app.settle(tester);
      await tester.tap(find.text(S.current.strAdd).last);
      await app.settle(tester);

      expect(
        app.db.selectData('SELECT data FROM cafe_tables WHERE hall_id = ?', [
          kHallId,
        ]),
        hasLength(4),
        reason: 'the new table never reached the replica',
      );
      expect(app.outboxEntities(), contains('cafe_tables'));
      expectNoNetworkReach(app, 'adds a table');
    });

    offlineTest('a manager opens a shift', (tester, app) async {
      await app.pumpApp(tester);
      await app.open(tester, AppRoutes.closeShiftScreen);

      // `widgetWithText`, not `find.text`: the screen shows the same phrase
      // twice — once as the heading, once on the button — and tapping the
      // heading is a no-op that would make this test pass for the wrong reason.
      await tester.tap(
        find.widgetWithText(ElevatedButton, S.current.strOpenShift),
      );
      await app.settle(tester, rounds: 30);

      expect(
        inject<SharedPreferences>().getString(ShiftBloc.localShiftPrefsKey),
        isNotNull,
        reason: 'the shift was not recorded locally',
      );
      expect(app.outboxEntities(), contains(kShiftEntity));
      expectNoNetworkReach(app, 'opens a shift');
    }, shiftOpen: false);
  });
}
