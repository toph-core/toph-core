import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/widgets/global_virtual_keyboard.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';

/// SettingsCubit'ning yengil fake'i — usecase'larsiz, faqat `language` state.
class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  _FakeSettingsCubit(String language)
      : super(SettingsState(language: language));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _wrap({required String language, required TextEditingController ctrl}) {
  return BlocProvider<SettingsCubit>.value(
    value: _FakeSettingsCubit(language),
    child: MaterialApp(
      home: Scaffold(
        body: GlobalVirtualKeyboard(
          child: Center(child: TextField(controller: ctrl)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('toggle switches Latin ⇄ Russian layout', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(language: 'uz', ctrl: ctrl));

    // Klaviaturani ochamiz (uz → Lotin bilan ochiladi).
    GlobalVirtualKeyboard.open(ctrl);
    await tester.pumpAndSettle();

    // Lotin: 'q' bor, kirill 'й' yo'q.
    expect(find.text('q'), findsOneWidget);
    expect(find.text('й'), findsNothing);

    // Pastki qatordagi globus tugmasini bosamiz.
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();

    // Endi kirill 'й' bor, Lotin 'q' yo'q.
    expect(find.text('й'), findsOneWidget);
    expect(find.text('q'), findsNothing);

    // Yana bosilsa — Lotinga qaytadi.
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    expect(find.text('q'), findsOneWidget);
    expect(find.text('й'), findsNothing);
  });

  testWidgets('tapping the key AROUND the globe icon also switches',
      (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(language: 'uz', ctrl: ctrl));

    GlobalVirtualKeyboard.open(ctrl);
    await tester.pumpAndSettle();
    expect(find.text('q'), findsOneWidget); // Lotin

    // Globus ikonkasidan chetroqda (lekin o'sha tugma katakchasi ichida)
    // bosamiz — paketning ikonka-faqat GestureDetector'i emas, tashqi InkWell
    // ishga tushishi va til baribir almashishi kerak.
    final iconCenter = tester.getCenter(find.byIcon(Icons.language));
    await tester.tapAt(iconCenter - const Offset(28, 0));
    await tester.pumpAndSettle();

    expect(find.text('й'), findsOneWidget); // kirillga o'tdi
    expect(find.text('q'), findsNothing);
  });

  testWidgets('opens in Russian when app language is ru', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(language: 'ru', ctrl: ctrl));

    GlobalVirtualKeyboard.open(ctrl);
    await tester.pumpAndSettle();

    // ru → kirill layout bilan ochiladi.
    expect(find.text('й'), findsOneWidget);
    expect(find.text('q'), findsNothing);
  });
}
