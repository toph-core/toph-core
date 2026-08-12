/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 5 — the leader's change feed, from
/// the follower's side.
///
/// The plan's version of this is three lines: broadcast the batch, apply it
/// with the same function the cloud path uses, delete the follower's uplink.
/// Two of those hold. The third does not survive a follower that misses a
/// broadcast, and the gap group below is why.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';
import 'package:mary_ai_pos/core/sync/change_feed_relay.dart';

void main() {
  late LocalDatabase db;
  late ChangeFeedRelay relay;

  String feed({
    required int nextCursor,
    String entity = 'halls',
    List<Map<String, dynamic>> rows = const [],
  }) =>
      jsonEncode({
        'next_sync_cursor': nextCursor,
        'changes': {
          entity: {'created': rows, 'updated': <Map>[], 'deleted': <String>[]},
        },
      });

  Map<String, dynamic> hall(String id, {String name = 'Zal'}) => {
        'id': id,
        'branch_id': 'b-1',
        'name': name,
        'width': 1000,
        'height': 800,
      };

  setUp(() {
    db = LocalDatabase.open(':memory:');
    relay = ChangeFeedRelay(db: db, applier: ChangeApplier(db));
  });

  tearDown(() => db.dispose());

  group('the happy path — a follower with no uplink stays current', () {
    test('rows in a broadcast land in the replica', () {
      relay.apply(
        body: feed(nextCursor: 10, rows: [hall('h-1', name: 'Asosiy')]),
        fromCursor: 0,
      );

      expect(db.byId('halls', 'h-1')?['name'], 'Asosiy');
      expect(db.syncCursor, 10);
      expect(relay.needsBackfill, isFalse);
    });

    test('consecutive batches advance the cursor with the leader', () {
      relay.apply(body: feed(nextCursor: 10, rows: [hall('h-1')]), fromCursor: 0);
      relay.apply(body: feed(nextCursor: 20, rows: [hall('h-2')]), fromCursor: 10);

      expect(db.syncCursor, 20);
      expect(relay.needsBackfill, isFalse);
    });

    test('a redelivered batch is harmless', () {
      relay.apply(body: feed(nextCursor: 20, rows: [hall('h-1')]), fromCursor: 0);
      expect(db.syncCursor, 20);

      // The leader resends an earlier batch. Re-applying is an upsert, and the
      // cursor never moves backwards.
      relay.apply(body: feed(nextCursor: 15, rows: [hall('h-1')]), fromCursor: 10);

      expect(db.syncCursor, 20);
      expect(relay.needsBackfill, isFalse);
    });

    test('a malformed payload is dropped, not applied', () {
      expect(relay.apply(body: 'not json', fromCursor: 0), isNull);
      expect(relay.apply(body: '[1,2,3]', fromCursor: 0), isNull);
      expect(db.syncCursor, 0);
    });
  });

  group('the gap the plan does not cover', () {
    test('a missed batch does not carry the cursor past the hole', () {
      // The follower is at 10. The leader's batch starts at 50, so rows 10–50
      // went out while this terminal was not listening. Applying normally would
      // set the cursor to 60 and those rows would never be requested again —
      // the follower would look caught up while missing them.
      relay.apply(body: feed(nextCursor: 60, rows: [hall('h-9')]), fromCursor: 50);

      expect(db.syncCursor, 0, reason: 'cursor stays where it can be vouched for');
      expect(relay.needsBackfill, isTrue);
    });

    test('the rows in hand still apply — they are upserts', () {
      relay.apply(body: feed(nextCursor: 60, rows: [hall('h-9')]), fromCursor: 50);

      expect(db.byId('halls', 'h-9'), isNotNull);
    });

    test('the flag persists until a pull actually closes the hole', () {
      relay.apply(body: feed(nextCursor: 60, rows: [hall('h-9')]), fromCursor: 50);
      expect(relay.needsBackfill, isTrue);

      // Later broadcasts keep arriving and keep being gapped.
      relay.apply(body: feed(nextCursor: 70, rows: [hall('h-10')]), fromCursor: 60);
      expect(relay.needsBackfill, isTrue);
      expect(db.syncCursor, 0);

      relay.backfillDone();
      expect(relay.needsBackfill, isFalse);
    });

    test('once backfilled, broadcasts resume advancing the cursor', () {
      relay.apply(body: feed(nextCursor: 60, rows: [hall('h-9')]), fromCursor: 50);
      // A cloud pull catches the replica up to the leader.
      db.syncCursor = 70;
      relay.backfillDone();

      relay.apply(body: feed(nextCursor: 80, rows: [hall('h-11')]), fromCursor: 70);

      expect(db.syncCursor, 80);
      expect(relay.needsBackfill, isFalse);
    });
  });

  group('the wire format', () {
    test('a change feed message survives a round trip', () {
      final body = feed(nextCursor: 42, rows: [hall('h-1')]);
      final encoded =
          LanHubMessage.changeFeed(body: body, fromCursor: 7).toJson();

      final parsed = LanHubMessage.tryParse(encoded)!;

      expect(parsed.type, LanHubMessageType.changeFeed);
      expect(parsed.feedFromCursor, 7);
      expect(parsed.feedBody, body);
    });

    test('the body is the cloud response verbatim, not a second format', () {
      // What the follower applies must be exactly what the leader received, so
      // that both sides run one parser. If this ever needs a translation step,
      // that is the moment the two paths can drift.
      final body = feed(nextCursor: 42, rows: [hall('h-1')]);
      final parsed =
          LanHubMessage.tryParse(LanHubMessage.changeFeed(body: body, fromCursor: 0).toJson())!;

      relay.apply(body: parsed.feedBody!, fromCursor: parsed.feedFromCursor!);

      expect(db.byId('halls', 'h-1'), isNotNull);
      expect(db.syncCursor, 42);
    });
  });
}
