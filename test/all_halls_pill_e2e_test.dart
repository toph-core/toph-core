/// Reproduces the report: the "All" pill beside the hall row on the main
/// floor plan should widen the grid back to every hall's tables.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

import 'support/offline_app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the All pill shows every hall\'s tables', (tester) async {
    final app = await OfflineAppHarness.boot(tester);
    try {
      app.seedVenue();
      // A second hall with one table — the venue fixture only has one hall,
      // and a single-hall venue cannot show this bug.
      app.put('halls', {
        'id': 'h-2',
        'name': 'Terrasa',
        'branch_id': kBranchId,
        'width': 1200,
        'height': 800,
        'deleted_at': 0,
      });
      // seedVenue's own h-1 tables omit `capacity`/`rotation`, which
      // `decodeRows` drops, so seed a complete one for hall 1 too.
      app.put('cafe_tables', {
        'id': 'tb-main',
        'hall_id': kHallId,
        'number': 11,
        'pos_x': 40,
        'pos_y': 40,
        'width': 90,
        'height': 90,
        'rotation': 0,
        'capacity': 4,
        'status': 'free',
        'shape': 'square',
        'table_type': 'dine_in',
        'price_per_hour': '0',
        'deleted_at': 0,
      });
      app.put('cafe_tables', {
        'id': 'tb-terrasa',
        'hall_id': 'h-2',
        'number': 77,
        'pos_x': 40,
        'pos_y': 40,
        'width': 90,
        'height': 90,
        'rotation': 0,
        'capacity': 4,
        'status': 'free',
        'shape': 'square',
        'table_type': 'dine_in',
        'price_per_hour': '0',
        'deleted_at': 0,
      });
      await app.signIn();
      await app.openShift();
      await app.pumpApp(tester);

      // Default state: no hall selected, so every hall's section is on screen.
      expect(find.text('Asosiy zal'), findsWidgets);
      expect(find.text('Terrasa'), findsWidgets);
      expect(find.text('Stol 77'), findsWidgets, reason: 'hall 2 table visible');
      expect(find.text('Stol 11'), findsWidgets, reason: 'hall 1 table visible');

      // Narrow to one hall.
      await tester.tap(find.text('Terrasa').first);
      await app.settle(tester);
      expect(find.text('Stol 77'), findsWidgets);
      expect(find.text('Stol 11'), findsNothing, reason: 'hall 1 filtered out');

      // Widen again with the All pill.
      await tester.tap(find.text(S.current.strAllHalls).first);
      await app.settle(tester);
      expect(
        find.text('Stol 77'),
        findsWidgets,
        reason: 'All must still show hall 2',
      );
      expect(
        find.text('Stol 11'),
        findsWidgets,
        reason: 'All must bring hall 1 tables back',
      );
    } finally {
      await app.settle(tester, rounds: 25);
      await app.dispose(tester);
    }
  });
}
