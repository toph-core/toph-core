/// Every ordering screen has to fit the terminal it runs on.
///
/// The offline suite renders at 1920×1080 and *suppresses* overflow errors, for
/// a good reason of its own — it is looking for network reach, and a wall of
/// RenderFlex failures would drown that out. The cost was that nothing in this
/// repository ever asserted a screen fits a smaller terminal, and entry-level
/// POS hardware is exactly where it does not: the order grids sized their tiles
/// by flooring a column count against a 180 px "maximum", which on a 1366×768
/// machine produced four cards nearly 200 px wide and a cashier scrolling for
/// items that used to be on screen.
///
/// So this suite pumps the ordering flow at the sizes real hardware ships with
/// and fails on any overflow. It is a ratchet, not a snapshot: it does not care
/// what the layout looks like, only that nothing is clipped off the edge of a
/// machine somebody is standing at.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/design_system/pos_grid_metrics.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';

import 'support/offline_app_harness.dart';

/// The terminals this product actually runs on.
///
/// 1024×768 is the smallest thing called a POS monoblock; 1366×768 is the
/// entry-level 15.6" panel `PosBreakpoints` calls "compact" and the one the
/// tile-size report came from; 1280×1024 is the older 5:4 panel still on plenty
/// of counters.
const _terminals = <String, Size>{
  '1024x768 (small monoblock)': Size(1024, 768),
  '1366x768 (entry-level 15.6")': Size(1366, 768),
  '1280x1024 (5:4 panel)': Size(1280, 1024),
};
CafeTableModel _table({required String id, required int number}) =>
    CafeTableModel(
      id: id,
      hallId: kHallId,
      number: number,
      posX: 40,
      posY: 40,
      width: 90,
      height: 90,
      rotation: 0,
      capacity: 4,
      status: TableStatus.free,
      tableType: 'dine_in',
    );


/// Boots the app at [size], runs [body], and fails on anything clipped.
///
/// Two details here are load-bearing, both learned the hard way.
///
/// The overflow list is cleared once the app has landed, so a test named for
/// one screen reports only that screen. `pumpApp` renders the floor plan on
/// the way past, and its header overflows first at these widths — without the
/// clear, every test in this file reported the same header and none of them
/// was testing what its name said.
///
/// And the failure message must never quote the framework's own wording. The
/// harness installs a `FlutterError.onError` that drops RenderFlex overflows,
/// and a message containing "overflowed by" was caught by that same filter on
/// its way out — swallowing the TestFailure, so `flutter_test` waited forever
/// for a completion that never came. The harness now filters on the error type
/// as well, and this reports pixel counts rather than repeating the sentence.
Future<void> _expectNoOverflow(
  WidgetTester tester,
  Size size,
  String label,
  Future<void> Function(WidgetTester, OfflineAppHarness) body,
) async {
  final overflows = <String>[];
  final app = await OfflineAppHarness.boot(tester);
  try {
    app.seedVenue();
    await app.signIn();
    await app.openShift();
    await app.pumpApp(tester, surfaceSize: size, overflows: overflows);
    overflows.clear();
    await body(tester, app);
    expect(
      overflows.map(_clippedBy).toList(),
      isEmpty,
      reason:
          'Content is cut off the edge of a $label terminal. '
          'Size it from the space available (LayoutBuilder, Expanded, '
          'PosGridMetrics) rather than in fixed pixels.',
    );
  } finally {
    await app.settle(tester, rounds: 25);
    await app.dispose(tester);
  }
}

/// "RenderFlex overflowed by 6.2 pixels on the right." → "6.2 px right".
///
/// Deliberately not the raw sentence — see [_expectNoOverflow].
String _clippedBy(String error) {
  final amount = RegExp(r'by ([\d.]+) pixels on the (\w+)').firstMatch(error);
  return amount == null
      ? 'clipped'
      : '${amount.group(1)} px ${amount.group(2)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the ordering flow fits the terminal', () {
    // One screen per test, one boot per screen: the harness drives the real
    // composition root, and stacking three routes onto one boot left timers
    // from each screen running under the next one's settle loop.
    _terminals.forEach((label, size) {
      testWidgets('the app really is rendering at $label', (tester) async {
        // The guard for the guard. `setSurfaceSize` alone resizes the render
        // surface but not the view, and `PosBreakpoints` reads MediaQuery — so
        // this suite once asked for a 1024 px terminal and got every
        // breakpoint decision made as though the screen were 2400 px wide.
        await _expectNoOverflow(tester, size, label, (tester, app) async {
          final media = tester.view.physicalSize / tester.view.devicePixelRatio;
          expect(media.width, size.width);
          expect(media.height, size.height);
        });
      });

      testWidgets('the floor plan fits $label', (tester) async {
        // The screen the app lands on, and the one whose header sits closest
        // to the edge on a small terminal.
        await _expectNoOverflow(tester, size, label, (tester, app) async {
          await app.settle(tester);
        });
      });

      testWidgets('the category screen fits $label', (tester) async {
        await _expectNoOverflow(tester, size, label, (tester, app) async {
          await app.open(
            tester,
            AppRoutes.departmentSelectionScreen,
            arguments: {
              'table': _table(id: kFreeTableId, number: 1),
              'guest_count': 2,
              'table_status': TableStatus.free,
            },
          );
        });
      });

      testWidgets('the menu screen fits $label', (tester) async {
        await _expectNoOverflow(tester, size, label, (tester, app) async {
          await app.open(
            tester,
            AppRoutes.detailScreen,
            arguments: {
              'table': _table(id: kFreeTableId, number: 1),
              'guest_count': 2,
              'table_status': TableStatus.free,
            },
          );
        });
      });
    });
  });

  group('order-grid metrics', () {
    // The unit-level half: the grids ask PosGridMetrics for their column
    // count, so its promises are worth pinning directly rather than only
    // through a rendered frame.
    test('a card is never wider than the ceiling, at any width', () {
      for (var width = 320.0; width <= 2600; width += 7) {
        final grid = PosGridMetrics.forOrderGrid(width);
        expect(
          grid.cardWidth,
          lessThanOrEqualTo(180.0 + 0.001),
          reason: 'a $width px grid produced ${grid.cardWidth} px cards',
        );
        expect(grid.columns, greaterThanOrEqualTo(2));
        // The cards plus their gaps must fit the space they were given.
        final used =
            grid.cardWidth * grid.columns + grid.spacing * (grid.columns - 1);
        expect(used, lessThanOrEqualTo(width + 0.001));
      }
    });

    test('a POS-sized grid gets about seven columns', () {
      // The width of the product pane on the terminals above, once the cart
      // sidebar has taken its share.
      for (final width in [700.0, 826.0, 900.0, 1046.0]) {
        expect(
          PosGridMetrics.forOrderGrid(width).columns,
          inInclusiveRange(6, 8),
          reason: '$width px should hold about seven columns',
        );
      }
    });

    test('a narrow pane drops columns rather than shrinking to nothing', () {
      final narrow = PosGridMetrics.forOrderGrid(420);
      expect(narrow.columns, lessThan(7));
      expect(narrow.cardWidth, greaterThanOrEqualTo(90));
    });
  });
}
