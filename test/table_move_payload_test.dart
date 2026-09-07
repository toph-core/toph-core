/// Regression guard for the settings-screen table move.
///
/// A drag in Settings > Halls & Tables used to PUT the whole row it had on
/// screen, including `status`. That field is the *local* occupancy overlay, and
/// it can hold `away` — which the update endpoint rejects, because
/// `table_status` is a two-value Postgres enum (`free`, `busy`). A 400 is a
/// verdict, so `outcomeForFailure` quarantines the operation permanently: the
/// move showed as saved on that terminal and never reached the server.
///
/// See `tableMovePayload`'s own doc for why each field is or isn't there.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/sections/halls_tables_section.dart';

void main() {
  group('tableMovePayload', () {
    final payload = tableMovePayload(hallId: 'hall-1', posX: 120, posY: 240);

    test('carries the new position', () {
      expect(payload['pos_x'], 120);
      expect(payload['pos_y'], 240);
    });

    test('carries hall_id, which the outbox uses as the causal chain key', () {
      // `_hallChain` reads this to keep a move behind its hall's own create.
      expect(payload['hall_id'], 'hall-1');
    });

    test('never sends status — occupancy is local authority, and "away" 400s',
        () {
      expect(payload.containsKey('status'), isFalse);
    });

    test('never sends table_type — a stale null would reclassify the billing',
        () {
      expect(payload.containsKey('table_type'), isFalse);
    });

    test('sends geometry only, so no unrelated field can be clobbered', () {
      expect(payload.keys.toSet(), {'hall_id', 'pos_x', 'pos_y'});
    });
  });
}
