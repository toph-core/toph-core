/// A write the server refuses has to be visible to somebody.
///
/// The outbox quarantines a definite 4xx — correctly, since replaying a verdict
/// only reproduces it. What was missing is the other half: the operator was
/// never told. Five writes were lost on the terminals in this repository (a
/// payment, two table edits, two shift opens) and not one of them left a trace
/// a cashier could see.
///
/// There *was* a "Karantin" card on the sync-status screen the whole time. It
/// read `OfflineQueueService` — the Hive queue that has had no producer since
/// the writes moved to `OutboxStore` — so it sat at "no rejected operations"
/// while the real queue held them. An empty box is the most reassuring possible
/// way to be wrong, which is why this test asserts against the store the
/// drainer actually writes to.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/failure_outcome.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';

void main() {
  late LocalDatabase db;
  late OutboxStore store;
  late LocalWriter writer;
  late ChangeApplier applier;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
    store = OutboxStore(db);
    writer = LocalWriter(db: db, applier: applier, outbox: store);
  });

  tearDown(() => db.dispose());

  OutboxDrainer drainerRejecting(String entity, Failure failure) {
    final executors = OutboxExecutors()
      ..register(
        entity,
        'update',
        OutboxHandler(
          send: (op) async => switch (outcomeForFailure(failure)) {
            OutboxOutcome.permanent => OutboxExecutionResult.permanent(
              failure.toString(),
            ),
            OutboxOutcome.retry => OutboxExecutionResult.retry(
              failure.toString(),
            ),
            OutboxOutcome.succeeded => const OutboxExecutionResult.succeeded(),
          },
        ),
      );
    return OutboxDrainer(
      db: db,
      store: store,
      applier: applier,
      executors: executors,
    );
  }

  test('a rejected write reaches the quarantine list with the reason', () async {
    // The shape of the real incident: a table edit refused with the server's
    // own explanation of what was wrong with the body.
    writer.write(
      entity: 'cafe_tables',
      id: 't-1',
      row: {'id': 't-1', 'hall_id': 'h-1', 'number': 11, 'deleted_at': 0},
      request: {'number': 11, 'price_per_hour': '0'},
    );

    await drainerRejecting(
      'cafe_tables',
      const MessageFailure('price_per_hour: cannot unmarshal string'),
    ).drain();

    final quarantined = store.quarantined();
    expect(quarantined, hasLength(1));
    expect(store.quarantineDepth, 1);

    final op = quarantined.single;
    expect(op.entity, 'cafe_tables');
    expect(op.action, 'update');
    expect(
      op.lastError,
      contains('price_per_hour'),
      reason: "the server's words survive to the screen — this used to read "
          "'MessageFailure()' and nothing else",
    );
    expect(
      op.payload,
      containsPair('price_per_hour', '0'),
      reason: 'the operator can see what was sent',
    );
  });

  test('the list is reactive, so the card updates without a reload', () async {
    // The card watches the outbox table. If a quarantine did not publish a
    // change, the screen would keep showing "no rejected operations" until
    // something unrelated happened to redraw it.
    final seen = <int>[];
    final sub = db
        .watch({'_outbox'}, () => store.quarantineDepth)
        .listen(seen.add);
    await Future<void>.delayed(Duration.zero);

    writer.write(
      entity: 'cafe_tables',
      id: 't-1',
      row: {'id': 't-1', 'hall_id': 'h-1', 'number': 11, 'deleted_at': 0},
      request: {'number': 11},
    );
    await drainerRejecting(
      'cafe_tables',
      const MessageFailure('rejected'),
    ).drain();
    await Future<void>.delayed(Duration.zero);

    expect(seen.first, 0);
    expect(seen.last, 1);
    await sub.cancel();
  });

  test('retrying puts it back in line with a clean attempt budget', () async {
    writer.write(
      entity: 'cafe_tables',
      id: 't-1',
      row: {'id': 't-1', 'hall_id': 'h-1', 'number': 11, 'deleted_at': 0},
      request: {'number': 11},
    );
    await drainerRejecting(
      'cafe_tables',
      const MessageFailure('rejected'),
    ).drain();
    expect(store.quarantineDepth, 1);

    store.retryQuarantined(store.quarantined().single.id);

    expect(store.quarantineDepth, 0);
    expect(store.pending(), hasLength(1));
    expect(store.pending().single.attempts, 0);
  });

  test('discarding removes it for good', () async {
    writer.write(
      entity: 'cafe_tables',
      id: 't-1',
      row: {'id': 't-1', 'hall_id': 'h-1', 'number': 11, 'deleted_at': 0},
      request: {'number': 11},
    );
    await drainerRejecting(
      'cafe_tables',
      const MessageFailure('rejected'),
    ).drain();

    store.dismissQuarantined(store.quarantined().single.id);

    expect(store.quarantineDepth, 0);
    expect(store.pending(), isEmpty);
  });
}
