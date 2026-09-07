import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/theme/app_theme.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_secure_storage.dart';

/// The on-screen keyboard is the only way to type on these terminals — there
/// is no physical one — so the mechanism behind every text field is worth
/// pinning down: it has to reach the screen from inside a dialog, write what
/// is tapped into the field's controller, and not swallow the next tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // A POS-sized window: the default 800x600 test surface is smaller than
    // the keyboard plus a field, which leaves keys clipped off-screen.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1600, 1000);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    InMemorySecureStoragePlatform.install();
    if (!inject.isRegistered<AppTokenStorage>()) {
      inject.registerSingleton<AppTokenStorage>(
        AppTokenStorage(
          await SharedPreferences.getInstance(),
          const FlutterSecureStorage(),
        ),
      );
    }
  });

  tearDown(FloatingKeyboard.close);

  Widget host(Widget child) => MaterialApp(
    navigatorKey: navigatorKey,
    theme: AppTheme.lightTheme,
    navigatorObservers: [KeyboardRouteObserver()],
    home: Scaffold(body: child),
  );

  Future<void> tapKey(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pump();
  }

  testWidgets(
    'typing on the keyboard writes into the field it was opened for',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextField(
              controller: controller,
              onTap: () => FloatingKeyboard.openText(context, controller),
            ),
          ),
        ),
      );

      expect(find.byType(StyledVirtualKeyboard), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(StyledVirtualKeyboard), findsOneWidget);

      await tapKey(tester, 'a');
      await tapKey(tester, 'b');
      expect(controller.text, 'ab');
    },
  );

  testWidgets('the keyboard reaches the screen from inside a dialog', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(const SizedBox.expand()));

    unawaitedShowDialog(
      navigatorKey.currentContext!,
      (dialogContext) => Dialog(
        child: SizedBox(
          height: 120,
          child: TextField(
            controller: controller,
            onTap: () => FloatingKeyboard.openText(dialogContext, controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Painted above the dialog, not behind it: the keyboard's overlay entry
    // is inserted into the root overlay after the dialog's route.
    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);
    await tapKey(tester, 'z');
    expect(controller.text, 'z');
  });

  testWidgets('an outside tap dismisses the keyboard and still presses '
      'the button underneath', (tester) async {
    final controller = TextEditingController();
    var pressed = 0;
    await tester.pumpWidget(
      host(
        Column(
          children: [
            Builder(
              builder: (context) => TextField(
                controller: controller,
                onTap: () => FloatingKeyboard.openText(context, controller),
              ),
            ),
            ElevatedButton(
              onPressed: () => pressed++,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(pressed, 1, reason: 'the tap must not be eaten by the dismisser');
    expect(find.byType(StyledVirtualKeyboard), findsNothing);
  });

  testWidgets('AppScaffold.open works from a screen that has no AppScaffold',
      (tester) async {
    // The static entry point carries no BuildContext, so it has to find the
    // overlay through the root navigator — and the navigator's own context
    // has no ancestor Overlay to find.
    final controller = TextEditingController();
    await tester.pumpWidget(host(
      TextField(
        controller: controller,
        onTap: () => AppScaffold.open(controller),
      ),
    ));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);
    await tapKey(tester, 'q');
    expect(controller.text, 'q');
  });

  testWidgets('tapping a second field moves the keyboard to it',
      (tester) async {
    // Order matters: the dismisser fires on pointer-up, the field's own
    // onTap when the gesture arena is swept just after — so the keyboard
    // closes and re-opens on the new field rather than staying on the old.
    final first = TextEditingController();
    final second = TextEditingController();
    await tester.pumpWidget(host(
      Column(
        children: [
          Builder(
            builder: (context) => TextField(
              key: const Key('first'),
              controller: first,
              onTap: () => FloatingKeyboard.openText(context, first),
            ),
          ),
          Builder(
            builder: (context) => TextField(
              key: const Key('second'),
              controller: second,
              onTap: () => FloatingKeyboard.openText(context, second),
            ),
          ),
        ],
      ),
    ));

    await tester.tap(find.byKey(const Key('first')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'a');
    expect(first.text, 'a');

    await tester.tap(find.byKey(const Key('second')));
    await tester.pumpAndSettle();
    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);

    await tapKey(tester, 'b');
    expect(second.text, 'b');
    expect(first.text, 'a', reason: 'the old field must not keep receiving');
  });

  testWidgets('dragging behind the keyboard does not dismiss it',
      (tester) async {
    // Scrolling the results while typing a search must not take the keyboard
    // away — only a tap outside does.
    final controller = TextEditingController();
    await tester.pumpWidget(host(
      Column(
        children: [
          Builder(
            builder: (context) => TextField(
              controller: controller,
              onTap: () => FloatingKeyboard.openText(context, controller),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 40, child: Text('row $i')),
              ],
            ),
          ),
        ],
      ),
    ));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);

    await tester.drag(find.text('row 1'), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);
  });

  testWidgets('closeFor leaves a keyboard that has moved to another field',
      (tester) async {
    final gone = TextEditingController();
    final live = TextEditingController();
    await tester.pumpWidget(host(
      Builder(
        builder: (context) => TextField(
          controller: live,
          onTap: () => FloatingKeyboard.openText(context, live),
        ),
      ),
    ));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);

    // What a disposed field's `dispose` does — it must not take down the
    // keyboard that has since moved on.
    FloatingKeyboard.closeFor(gone);
    await tester.pumpAndSettle();
    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);

    FloatingKeyboard.closeFor(live);
    await tester.pumpAndSettle();
    expect(find.byType(StyledVirtualKeyboard), findsNothing);
  });

  testWidgets('a number field gets the digit pad, not the letters', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            onTap: () => FloatingKeyboard.openFor(
              context,
              controller,
              keyboardType: TextInputType.number,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(StyledNumericKeyboard), findsOneWidget);
    expect(find.byType(StyledVirtualKeyboard), findsNothing);

    await tapKey(tester, '7');
    expect(controller.text, '7');
  });

  testWidgets('leaving the screen takes the keyboard with it', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Column(
            children: [
              TextField(
                controller: controller,
                onTap: () => FloatingKeyboard.openText(context, controller),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SizedBox()),
                ),
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(StyledVirtualKeyboard), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.byType(StyledVirtualKeyboard), findsNothing);
  });
}

/// `showDialog` completes only when the dialog is popped; the tests here
/// drive the dialog while it is still up, so the future is deliberately
/// dropped.
void unawaitedShowDialog(BuildContext context, WidgetBuilder builder) {
  showDialog<void>(context: context, builder: builder);
}
