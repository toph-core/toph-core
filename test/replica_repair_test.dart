/// The repair path — what brings a replica back into agreement with the server
/// when the change feed cannot.
///
/// The bug these cover: a hall the backend has 9 tables in, showing 16 on a
/// terminal. `change_log` never repeats a row, so a delete refused once (the
/// local copy had an unsynced edit) or missed entirely (retention compacted it
/// away) is gone forever, and every pull afterwards reports the terminal as
/// fully caught up while it displays tables the venue removed.
///
/// The offline-first half matters just as much and has its own tests below: a
/// repair must never take work the outbox is still carrying.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/sync/replica_repair.dart';
import 'package:mary_ai_pos/core/sync/snapshot_api_client.dart';

/// A snapshot server holding a fixed set of rows, paged the way the real one
/// pages: one entity at a time, keyset by id, `next` until `done`.
class FakeSnapshotApi implements SnapshotApi {
  /// entity → rows the server currently holds.
  final Map<String, List<Map<String, dynamic>>> server;
  final int cursor;

  /// Every fetch this api served, for asserting the walk echoes coordinates.
  final List<String> calls = [];

  /// When set, the walk fails on the nth call (1-based) — an uplink dying
  /// mid-repair.
  int? failOnCall;

  FakeSnapshotApi(this.server, {this.cursor = 900, this.failOnCall});

  List<String> get _entities => server.keys.toList()..sort();

  @override
  Future<SnapshotPage> fetch({
    int? cursor,
    String? entity,
    String? afterId,
    int limit = 500,
  }) async {
    calls.add('${entity ?? '-'}/${afterId ?? '-'}');
    if (failOnCall != null && calls.length == failOnCall) {
      throw StateError('uplink died');
    }

    final entities = _entities;
    var index = entity == null || entity.isEmpty ? 0 : entities.indexOf(entity);
    if (index < 0) index = entities.length;

    // One entity per page, in full — enough to exercise the walk without
    // reimplementing the server's row budget.
    if (index >= entities.length) {
      return SnapshotPage(
        snapshotCursor: cursor ?? this.cursor,
        entities: const [],
        rows: const {},
        count: 0,
        next: null,
        done: true,
      );
    }

    final name = entities[index];
    final rows = server[name]!;
    final last = index == entities.length - 1;

    return SnapshotPage(
      snapshotCursor: cursor ?? this.cursor,
      entities: entity == null || entity.isEmpty ? entities : const [],
      rows: {name: rows},
      count: rows.length,
      next: last
          ? null
          : SnapshotCoordinate(entity: entities[index + 1], afterId: ''),
      done: last,
    );
  }
}

Map<String, dynamic> table(String id, {int number = 1, String hall = 'h1'}) => {
  'id': id,
  'hall_id': hall,
  'number': number,
  'status': 'free',
  'table_type': 'standard',
  'deleted_at': 0,
};

void main() {
  late LocalDatabase db;
  late ChangeApplier applier;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
  });

  tearDown(() => db.dispose());

  List<String> tableIds() => [
    for (final row in db.allOf('cafe_tables')) row['id'] as String,
  ];

  /// Puts [ids] in the replica the way a pull would.
  void seedTables(List<String> ids) {
    applier.applyPullResponse({
      'next_sync_cursor': 100,
      'changes': {
        'cafe_tables': {
          'created': [
            for (var i = 0; i < ids.length; i++) table(ids[i], number: i + 1),
          ],
        },
      },
    });
  }

  ReplicaRepair repairOver(FakeSnapshotApi api) =>
      ReplicaRepair(api: api, db: db, applier: applier);

  group('the divergence the feed cannot close', () {
    test('a row the server no longer has is swept', () async {
      seedTables(['t1', 't2', 't3']);
      // The server kept two of them — the third was deleted while this
      // terminal was refusing or missing changes.
      final api = FakeSnapshotApi({
        'cafe_tables': [table('t1'), table('t2', number: 2)],
      });
      final repair = repairOver(api);
      repair.noteRefused({'cafe_tables'});

      final result = await repair.run();

      expect(result.outcome, RepairOutcome.repaired);
      expect(result.rowsSwept, 1);
      expect(tableIds(), unorderedEquals(['t1', 't2']));
    });

    test('a refused delete no longer survives forever', () async {
      // The exact sequence from the report: the row is locally edited (so
      // pending), the server deletes it, the pull refuses the delete, and the
      // cursor moves on. Nothing will ever redeliver it.
      seedTables(['t1', 't2']);
      db.markPending('cafe_tables', 't2');

      final stats = applier.applyPullResponse({
        'next_sync_cursor': 101,
        'changes': {
          'cafe_tables': {
            'deleted': ['t2'],
          },
        },
      });
      expect(stats.skippedPending, 1, reason: 'the delete was refused');
      expect(stats.refusedEntities, contains('cafe_tables'));
      expect(tableIds(), contains('t2'), reason: 'still on the floor plan');

      // The outbox drains, the guard clears, and the repair pass runs.
      db.clearPending('cafe_tables', 't2');
      final repair = repairOver(
        FakeSnapshotApi({
          'cafe_tables': [table('t1')],
        }),
      );
      repair.noteRefused(stats.refusedEntities);
      await repair.run();

      expect(tableIds(), ['t1']);
    });

    test(
      'the snapshot cursor is adopted so the next pull resumes from it',
      () async {
        seedTables(['t1']);
        db.syncCursor = 100;
        final repair = repairOver(
          FakeSnapshotApi({
            'cafe_tables': [table('t1')],
          }, cursor: 777),
        );
        repair.requireFull();

        await repair.run();

        expect(db.syncCursor, 777);
        expect(repair.isNeeded, isFalse);
      },
    );

    test('rows the snapshot delivers are applied, not just swept', () async {
      final repair = repairOver(
        FakeSnapshotApi({
          'cafe_tables': [table('t1'), table('t2', number: 2)],
        }),
      );
      repair.requireFull();

      final result = await repair.run();

      expect(result.rowsApplied, 2);
      expect(tableIds(), unorderedEquals(['t1', 't2']));
    });
  });

  group('offline-first: a repair never takes unsynced work', () {
    test('a pending row is not swept', () async {
      seedTables(['t1', 't2']);
      // t2 carries a local edit the outbox has not sent. The server cannot
      // have it, and its absence from the snapshot proves nothing.
      db.markPending('cafe_tables', 't2');

      final repair = repairOver(
        FakeSnapshotApi({
          'cafe_tables': [table('t1')],
        }),
      );
      repair.requireFull();
      final result = await repair.run();

      expect(result.rowsSwept, 0);
      expect(tableIds(), unorderedEquals(['t1', 't2']));
    });

    test('a provisional row created offline is not swept', () async {
      final store = OutboxStore(db);
      final writer = LocalWriter(db: db, applier: applier, outbox: store);
      seedTables(['t1']);
      // A table added on this terminal with the uplink down: local id, queued
      // create, nothing the server has ever heard of.
      final localId = writer.create(
        entity: 'cafe_tables',
        row: table('ignored', number: 9),
        request: table('ignored', number: 9),
      );
      expect(db.isProvisional('cafe_tables', localId), isTrue);

      final repair = repairOver(
        FakeSnapshotApi({
          'cafe_tables': [table('t1')],
        }),
      );
      repair.requireFull();
      final result = await repair.run();

      expect(result.rowsSwept, 0);
      expect(tableIds(), contains(localId));
      expect(store.pending().length, 1, reason: 'the outbox is untouched');
    });

    test('a bill rung on another terminal is not swept', () async {
      // The one the audit caught. `applyFromPeer` deliberately does not mark a
      // peer's row pending — the terminal that wrote it owns its trip to the
      // server — so on this terminal it looked like an ordinary replica row
      // with nothing protecting it. The server has never heard of it, because
      // the peer's outbox has not drained, so a sweep deleted a live check and
      // broadcast the delete back to the till that owned it.
      seedTables(['t1']);
      applier.applyFromPeer(
        entity: 'cafe_tables',
        action: 'create',
        payload: table('t-peer', number: 42),
      );
      expect(tableIds(), contains('t-peer'));

      final repair = repairOver(
        FakeSnapshotApi({
          'cafe_tables': [table('t1')],
        }),
      );
      repair.requireFull();
      final result = await repair.run();

      expect(result.rowsSwept, 0);
      expect(tableIds(), contains('t-peer'));
    });

    test('a peer row the server later confirms becomes sweepable', () async {
      // The other half: once the server sends the row itself, it is the
      // authority on whether it still exists, and the protection has to lift —
      // otherwise a peer-relayed row could never be reconciled again.
      applier.applyFromPeer(
        entity: 'cafe_tables',
        action: 'create',
        payload: table('t-peer', number: 42),
      );
      applier.applyPullResponse({
        'next_sync_cursor': 105,
        'changes': {
          'cafe_tables': {
            'created': [table('t-peer', number: 42)],
          },
        },
      });

      // Now the server no longer has it — deleted on another terminal.
      final repair = repairOver(FakeSnapshotApi({'cafe_tables': []}));
      repair.requireFull();
      final result = await repair.run();

      expect(result.rowsSwept, 1);
      expect(tableIds(), isEmpty);
    });

    test('a row the applier refuses is kept, not swept', () async {
      // `branch_shifts.closed_at` is monotonic: a shift closed here must not be
      // reopened by an older server copy. The applier refuses that row — and
      // the refusal left it unstamped, which the sweep read as "the server does
      // not have this" and deleted the shift outright, which is worse than
      // either outcome the guard was choosing between.
      const shiftId = 'sh-1';
      applier.applyPullResponse({
        'next_sync_cursor': 100,
        'changes': {
          'branch_shifts': {
            'created': [
              {
                'id': shiftId,
                'branch_id': 'b1',
                'opened_at': '2026-09-10T08:00:00Z',
                'closed_at': '2026-09-10T23:00:00Z',
                'deleted_at': 0,
              },
            ],
          },
        },
      });

      // The server still has it open — the close has not drained yet.
      final repair = repairOver(
        FakeSnapshotApi({
          'branch_shifts': [
            {
              'id': shiftId,
              'branch_id': 'b1',
              'opened_at': '2026-09-10T08:00:00Z',
              'closed_at': null,
              'deleted_at': 0,
            },
          ],
        }),
      );
      repair.requireFull();
      final result = await repair.run();

      expect(result.rowsSwept, 0);
      final stored = db.byId('branch_shifts', shiftId);
      expect(stored, isNotNull, reason: 'the shift must survive the repair');
      expect(stored!['closed_at'], isNotNull, reason: 'and stay closed');
    });

    test('an interrupted walk sweeps nothing and resumes next pass', () async {
      seedTables(['t1', 't2']);
      final api = FakeSnapshotApi({
        'cafe_tables': [table('t1')],
        'halls': [
          {'id': 'h1', 'name': 'Zal', 'branch_id': 'b1', 'deleted_at': 0},
        ],
      }, failOnCall: 2);
      final repair = repairOver(api);
      repair.requireFull();

      final failed = await repair.run();

      expect(failed.outcome, RepairOutcome.failed);
      expect(
        tableIds(),
        unorderedEquals(['t1', 't2']),
        reason: 'a half-finished walk must not delete anything',
      );
      expect(repair.isNeeded, isTrue, reason: 'still owed a repair');

      // The uplink comes back.
      api.failOnCall = null;
      final done = await repair.run();

      expect(done.outcome, RepairOutcome.repaired);
      expect(tableIds(), ['t1']);
    });
  });

  group('scope', () {
    test('only the entities that refused a row are swept', () async {
      seedTables(['t1', 't2']);
      applier.applyPullResponse({
        'next_sync_cursor': 100,
        'changes': {
          'halls': {
            'created': [
              {'id': 'h1', 'name': 'Zal', 'branch_id': 'b1', 'deleted_at': 0},
              {'id': 'h2', 'name': 'VIP', 'branch_id': 'b1', 'deleted_at': 0},
            ],
          },
        },
      });

      // The server has one of each; only cafe_tables refused anything.
      final repair = repairOver(
        FakeSnapshotApi({
          'cafe_tables': [table('t1')],
          'halls': [
            {'id': 'h1', 'name': 'Zal', 'branch_id': 'b1', 'deleted_at': 0},
          ],
        }),
      );
      repair.noteRefused({'cafe_tables'});
      await repair.run();

      expect(tableIds(), ['t1'], reason: 'swept');
      expect(
        db.allOf('halls').length,
        2,
        reason: 'halls refused nothing, so nothing there is deleted',
      );
    });

    test('a full repair sweeps every entity', () async {
      seedTables(['t1', 't2']);
      applier.applyPullResponse({
        'next_sync_cursor': 100,
        'changes': {
          'halls': {
            'created': [
              {'id': 'h1', 'name': 'Zal', 'branch_id': 'b1', 'deleted_at': 0},
              {'id': 'h2', 'name': 'VIP', 'branch_id': 'b1', 'deleted_at': 0},
            ],
          },
        },
      });

      final repair = repairOver(
        FakeSnapshotApi({
          'cafe_tables': [table('t1')],
          'halls': [
            {'id': 'h1', 'name': 'Zal', 'branch_id': 'b1', 'deleted_at': 0},
          ],
        }),
      );
      repair.requireFull();
      await repair.run();

      expect(tableIds(), ['t1']);
      expect(db.allOf('halls').map((h) => h['id']), ['h1']);
    });

    test('nothing runs when nothing is owed', () async {
      final api = FakeSnapshotApi({
        'cafe_tables': [table('t1')],
      });
      final result = await repairOver(api).run();

      expect(result.outcome, RepairOutcome.notNeeded);
      expect(api.calls, isEmpty, reason: 'no request without a reason');
    });
  });

  group('a permanently rejected create leaves nothing behind', () {
    test('the phantom row and its provisional marker are removed', () async {
      final store = OutboxStore(db);
      final writer = LocalWriter(db: db, applier: applier, outbox: store);
      final executors = OutboxExecutors()
        ..register(
          'cafe_tables',
          'create',
          OutboxHandler(
            send: (op) async =>
                const OutboxExecutionResult.permanent('400 bad request'),
          ),
        );
      final drainer = OutboxDrainer(
        db: db,
        store: store,
        applier: applier,
        executors: executors,
      );

      final localId = writer.create(
        entity: 'cafe_tables',
        row: table('ignored', number: 4),
        request: table('ignored', number: 4),
      );
      expect(tableIds(), [localId]);

      final result = await drainer.drain();

      expect(result.quarantined, 1);
      expect(
        tableIds(),
        isEmpty,
        reason: 'the server refused it for good; no other terminal has it',
      );
      expect(db.isProvisional('cafe_tables', localId), isFalse);
      expect(db.isPending('cafe_tables', localId), isFalse);
      // The payload is still recoverable from the quarantine list.
      expect(store.quarantined().length, 1);
    });

    test('a rejected bill is kept — operator work is never dropped', () async {
      // The counterweight. Every create is marked provisional, bills included,
      // so "drop the provisional row" applied without a second thought would
      // erase a check somebody rang up because the server disliked one field.
      final store = OutboxStore(db);
      final writer = LocalWriter(db: db, applier: applier, outbox: store);
      final executors = OutboxExecutors()
        ..register(
          'orders',
          'create',
          OutboxHandler(
            send: (op) async =>
                const OutboxExecutionResult.permanent('400 bad request'),
          ),
        );
      final drainer = OutboxDrainer(
        db: db,
        store: store,
        applier: applier,
        executors: executors,
      );

      final orderId = writer.create(
        entity: 'orders',
        row: {
          'id': 'ord-1',
          'table_id': 't1',
          'bill_status': 'open',
          'deleted_at': 0,
        },
        request: {'id': 'ord-1', 'table_id': 't1'},
        id: 'ord-1',
      );

      final result = await drainer.drain();

      expect(result.quarantined, 1);
      expect(db.byId('orders', orderId), isNotNull,
          reason: 'the check stays on screen; the failure goes to quarantine');
    });
  });
}
