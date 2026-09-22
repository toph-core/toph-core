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

/// A sync stamp above anything [LocalDatabase.nextSyncStamp] can issue, so
/// "written before this" means every row in the replica. Stamps are epoch
/// milliseconds, so a small sentinel like `1 << 40` sits in 2004 and matches
/// nothing.
const _afterEverything = 1 << 62;

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
      //
      // Queued through LocalWriter rather than marked by hand: a guard is only
      // honoured while an unsent operation stands behind it, so a bare
      // `markPending` here would be asserting something the app cannot
      // produce — and would pass whatever the sweep did with orphaned guards.
      LocalWriter(db: db, applier: applier, outbox: OutboxStore(db)).write(
        entity: 'cafe_tables',
        id: 't2',
        row: table('t2', number: 2),
        request: table('t2', number: 2),
      );

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

  group('a guard must not outlive the write it was protecting', () {
    // The ghost cafe tables. A guard says "this terminal owes the server a
    // write for this row, so replication must not touch it" — and it was
    // honoured unconditionally, including after the write it referred to was
    // given up on. `ChangeApplier` then refused the server's delete (the feed
    // never repeats one) and `unsweptRowIds` skipped the row in every repair
    // sweep, so a table the venue removed stayed on that one terminal for
    // good. The operator's only visible symptom was a floor plan that did not
    // match anyone else's.

    /// A drainer whose only handler always fails in a retryable way — an
    /// endpoint that is down, or a payload the server keeps refusing with a
    /// 5xx.
    ({OutboxStore store, LocalWriter writer, OutboxDrainer drainer}) alwaysRetries(
      String entity,
      String action,
    ) {
      final store = OutboxStore(db);
      final writer = LocalWriter(db: db, applier: applier, outbox: store);
      final executors = OutboxExecutors()
        ..register(
          entity,
          action,
          OutboxHandler(
            send: (op) async => const OutboxExecutionResult.retry('503'),
          ),
        );
      return (
        store: store,
        writer: writer,
        drainer: OutboxDrainer(
          db: db,
          store: store,
          applier: applier,
          executors: executors,
        ),
      );
    }

    test('an exhausted retry budget releases the row it guarded', () async {
      final ctx = alwaysRetries('cafe_tables', 'update');
      seedTables(['t1']);
      ctx.writer.write(
        entity: 'cafe_tables',
        id: 't1',
        row: table('t1', number: 9),
        request: table('t1', number: 9),
      );
      expect(db.isPending('cafe_tables', 't1'), isTrue);

      // Every attempt the store allows. Backoff is cleared between passes so
      // the whole budget is spent here rather than over the next hour.
      for (var attempt = 0; attempt < OutboxStore.maxAttempts; attempt++) {
        ctx.store.clearBackoff();
        await ctx.drainer.drain();
      }

      expect(
        ctx.store.quarantined().length,
        1,
        reason: 'the operation itself was given up on',
      );
      expect(
        db.isPending('cafe_tables', 't1'),
        isFalse,
        reason: 'and the row it was holding has to be let go with it',
      );
    });

    test('the released row then accepts the delete it was refusing', () async {
      final ctx = alwaysRetries('cafe_tables', 'update');
      seedTables(['t1', 't2']);
      ctx.writer.write(
        entity: 'cafe_tables',
        id: 't1',
        row: table('t1', number: 9),
        request: table('t1', number: 9),
      );

      applier.applyPullResponse({
        'next_sync_cursor': 101,
        'changes': {
          'cafe_tables': {
            'deleted': ['t1'],
          },
        },
      });
      expect(
        tableIds(),
        containsAll(['t1', 't2']),
        reason: 'guarded, so the delete is refused — and never repeated',
      );

      for (var attempt = 0; attempt < OutboxStore.maxAttempts; attempt++) {
        ctx.store.clearBackoff();
        await ctx.drainer.drain();
      }

      // The delete is gone from the feed for good, so only a repair can
      // finish the job — which is the point: the guard no longer blocks it.
      final api = FakeSnapshotApi({
        'cafe_tables': [table('t2', number: 2)],
      });
      final repair = repairOver(api)..requireFull();
      final result = await repair.run();

      expect(result.outcome, RepairOutcome.repaired);
      expect(tableIds(), ['t2']);
    });

    test('a guard with no operation at all is dropped at open', () {
      seedTables(['t1']);
      // The state an older build left on disk: the row guarded, the operation
      // that justified it long gone. Written straight to the guard table
      // because no supported path can produce it any more.
      db.markPending('cafe_tables', 't1');
      expect(db.isPending('cafe_tables', 't1'), isTrue);

      db.releaseOrphanedGuards();

      expect(db.isPending('cafe_tables', 't1'), isFalse);
      expect(
        db.unsweptRowIds('cafe_tables', _afterEverything),
        ['t1'],
        reason: 'and the sweep can finally see it',
      );
    });

    test('a guard with a live operation survives — unsynced work is kept', () {
      final store = OutboxStore(db);
      final writer = LocalWriter(db: db, applier: applier, outbox: store);
      seedTables(['t1']);
      writer.write(
        entity: 'cafe_tables',
        id: 't1',
        row: table('t1', number: 9),
        request: table('t1', number: 9),
      );

      db.releaseOrphanedGuards();

      expect(
        db.isPending('cafe_tables', 't1'),
        isTrue,
        reason: 'the write is still queued; the guard is doing its job',
      );
      expect(db.unsweptRowIds('cafe_tables', _afterEverything), isEmpty);
    });
  });

  group('a partial payload cannot undelete a row', () {
    // The other way a ghost is made. An upsert takes the whole row, so an
    // absent key reads as null — and for `deleted_at` that turns any partial
    // payload into a restore. The row then picks up a guard (pending from a
    // local write, peer-origin from a LAN broadcast), which is exactly what
    // keeps a repair sweep off it.

    test('a peer broadcast of a stale row leaves it deleted', () {
      seedTables(['t1']);
      // The venue deleted it; this terminal heard, as a soft delete carried by
      // an ordinary update.
      applier.applyPullResponse({
        'next_sync_cursor': 101,
        'changes': {
          'cafe_tables': {
            'updated': [table('t1', number: 1)..['deleted_at'] = 1735000000],
          },
        },
      });
      expect(tableIds(), isEmpty);

      // The till next door has not heard yet, and the hub fans its copy out.
      final stale = table('t1', number: 1)..remove('deleted_at');
      applier.applyFromPeer(
        entity: 'cafe_tables',
        action: 'update',
        payload: stale,
      );

      expect(
        tableIds(),
        isEmpty,
        reason: "a payload that says nothing about deleted_at cannot clear it",
      );
    });

    test('an explicit deleted_at of 0 still restores — the backend has one', () {
      seedTables(['t1']);
      applier.applyPullResponse({
        'next_sync_cursor': 101,
        'changes': {
          'cafe_tables': {
            'updated': [table('t1', number: 1)..['deleted_at'] = 1735000000],
          },
        },
      });
      expect(tableIds(), isEmpty);

      // RestoreCafeTable sets deleted_at back to 0, and that arrives on the
      // feed as an ordinary update carrying the 0 — which must be honoured.
      applier.applyPullResponse({
        'next_sync_cursor': 102,
        'changes': {
          'cafe_tables': {
            'updated': [table('t1', number: 1)],
          },
        },
      });

      expect(tableIds(), ['t1']);
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
