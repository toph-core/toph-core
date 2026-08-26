/// The payment screen's side of the same defect: what a cashier actually sees
/// when the bill cannot be resolved.
///
/// `payment_bill_resolution_test.dart` pins the bloc; this pins the frame.
/// The screen's only render gate is `state.detail != null`, so before the fix
/// an unresolvable bill was an endless spinner with no message and no way
/// back. Booted through `OfflineAppHarness` so the real composition root is
/// what renders — nothing here is stubbed below the widget layer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/payment_screen.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

import 'support/offline_app_harness.dart';

/// Boot, seed, sign in, open a shift, run — the same cold-start shape
/// `offline_screen_suite_test.dart` uses, and for the same reason: teardown
/// has to run inside the test's own zone.
void paymentTest(
  String description,
  Future<void> Function(WidgetTester tester, OfflineAppHarness app) body,
) {
  testWidgets(description, (tester) async {
    final app = await OfflineAppHarness.boot(tester);
    try {
      app.seedVenue();
      await app.signIn();
      await app.openShift();
      await app.pumpApp(tester);
      await body(tester, app);
    } finally {
      await app.settle(tester, rounds: 25);
      await app.dispose(tester);
    }
  });
}

void main() {
  paymentTest('an open bill renders from the table key alone', (
    tester,
    app,
  ) async {
    await app.open(
      tester,
      AppRoutes.paymentScreen,
      arguments: {'table_id': kBusyTableId},
    );

    expect(find.byType(PaymentScreen), findsWidgets);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'the screen never left its detail spinner',
    );
  });

  paymentTest('a bill that has left the open-bill read renders by order id', (
    tester,
    app,
  ) async {
    // `kPaidOrderId` sits on `kFreeTableId` with `bill_status = 'closed'`, so
    // the table key resolves to null — the shape a check settled a moment ago
    // has. Watching both keys is what keeps the bill on screen.
    await app.open(
      tester,
      AppRoutes.paymentScreen,
      arguments: {'table_id': kFreeTableId, 'order_id': kPaidOrderId},
    );

    expect(find.byType(PaymentScreen), findsWidgets);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason:
          'a settled bill left the table key resolving to null and the screen '
          'spun forever — the order key has to be tried too',
    );
    expect(find.text(S.current.strPaymentInfoNotFound), findsNothing);
  });

  paymentTest('a bill under neither key is a dead end no longer', (
    tester,
    app,
  ) async {
    await app.open(
      tester,
      AppRoutes.paymentScreen,
      arguments: {'table_id': 'tb-no-such-table'},
    );

    // The honest answer, not a spinner: the replica read is synchronous and
    // authoritative, so there is nothing in flight to keep waiting on.
    expect(find.text(S.current.strPaymentInfoNotFound), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // ... and it comes with a way back out of the screen.
    expect(find.text(S.current.strBackToScreen), findsOneWidget);
  });

  paymentTest('no keys at all resolves rather than spinning', (
    tester,
    app,
  ) async {
    // Typed literal on purpose: the screen reads its route arguments with
    // `as Map<String, dynamic>`, so a bare `const {}` — a
    // `Map<dynamic, dynamic>` — fails that cast in `build` and this would be
    // testing the cast rather than the empty-key path. Every real call site
    // passes a `Map<String, dynamic>`.
    await app.open(
      tester,
      AppRoutes.paymentScreen,
      arguments: const <String, dynamic>{},
    );

    expect(find.text(S.current.strPaymentInfoNotFound), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
