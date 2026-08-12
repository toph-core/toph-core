/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — replication loop tests.
///
/// The loop's job is narrow but unforgiving: page through the feed until caught
/// up, never lose a cursor position, never spin forever, and never let a
/// network failure corrupt what is already stored. These cover each of those.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/sync/replication_service.dart';
import 'package:mary_ai_pos/core/sync/sync_api_client.dart';

/// A scripted [SyncApi] — each entry is one page, returned in order.
class FakeSyncApi implements SyncApi {
  final List<Object> _script;
  int calls = 0;
  final List<int> requestedCursors = [];

  /// Entries are either a [SyncPullPage] to return or an [Object] to throw.
  FakeSyncApi(this._script);

  @override
  Future<SyncPullPage> pull({required int cursor, int limit = 500}) async {
    requestedCursors.add(cursor);
    final index = calls < _script.length ? calls : _script.length - 1;
    calls++;
    final entry = _script[index];
    if (entry is SyncPullPage) return entry;
    throw entry;
  }
}

/// Builds a page of `goods` rows with sequential ids, as the server would.
SyncPullPage page({
  required int nextCursor,
  int rows = 0,
  int startId = 0,
  bool asDeletes = false,
}) {
  final changes = <String, dynamic>{};
  if (rows > 0) {
    changes['goods'] = asDeletes
        ? {'deleted': [for (var i = 0; i < rows; i++) 'g-${startId + i}']}
        : {
            'created': [
              for (var i = 0; i < rows; i++)
                {
                  'id': 'g-${startId + i}',
                  'name': 'Item ${startId + i}',
                  'price': 1000.00,
                  'category_id': 'c-1',
                },
            ],
          };
  }
  return SyncPullPage(
    nextCursor: nextCursor,
    body: {'next_sync_cursor': nextCursor, 'changes': changes},
    rowCount: rows,
  );
}

void main() {
  late LocalDatabase db;
  late ChangeApplier applier;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
  });

  tearDown(() => db.dispose());

  ReplicationService serviceWith(FakeSyncApi api) =>
      ReplicationService(api: api, db: db, applier: applier);

  group('drain', () {
    test('a short first page means caught up in one request', () async {
      final api = FakeSyncApi([page(nextCursor: 10, rows: 3)]);
      final result = await serviceWith(api).drain();

      expect(result.outcome, ReplicationOutcome.caughtUp);
      expect(result.rowsApplied, 3);
      expect(api.calls, 1);
      expect(db.syncCursor, 10);
      expect(db.tableCounts()['goods'], 3);
    });

    test('pages until a short page arrives, resuming from the stored cursor',
        () async {
      final api = FakeSyncApi([
        page(nextCursor: 500, rows: SyncApiClient.batchSize, startId: 0),
        page(nextCursor: 1000, rows: SyncApiClient.batchSize, startId: 500),
        page(nextCursor: 1200, rows: 7, startId: 1000),
      ]);
      final result = await serviceWith(api).drain();

      expect(result.outcome, ReplicationOutcome.caughtUp);
      expect(result.batches, 3);
      expect(api.calls, 3);
      // Each request must continue from where the previous page ended.
      expect(api.requestedCursors, [0, 500, 1000]);
      expect(db.syncCursor, 1200);
      expect(db.tableCounts()['goods'], SyncApiClient.batchSize * 2 + 7);
    });

    test('an empty feed is a single no-op request', () async {
      final api = FakeSyncApi([page(nextCursor: 0)]);
      final result = await serviceWith(api).drain();

      expect(result.outcome, ReplicationOutcome.caughtUp);
      expect(result.rowsApplied, 0);
      expect(api.calls, 1);
    });

    test('a full page that does not advance the cursor stops the loop',
        () async {
      // Pathological server behaviour: a full page whose cursor does not move.
      // Without the second stop condition this would page forever.
      final api = FakeSyncApi([
        page(nextCursor: 0, rows: SyncApiClient.batchSize),
      ]);
      final result = await serviceWith(api).drain();

      expect(result.outcome, ReplicationOutcome.caughtUp);
      expect(api.calls, 1);
    });

    test('respects the batch ceiling and reports more available', () async {
      final api = FakeSyncApi([
        for (var i = 1; i <= 5; i++)
          page(
            nextCursor: i * 500,
            rows: SyncApiClient.batchSize,
            startId: (i - 1) * 500,
          ),
      ]);
      final result = await serviceWith(api).drain(maxBatches: 3);

      expect(result.outcome, ReplicationOutcome.moreAvailable);
      expect(result.batches, 3);
      expect(db.syncCursor, 1500);
    });

    test('a mid-run failure keeps everything applied so far', () async {
      final api = FakeSyncApi([
        page(nextCursor: 500, rows: SyncApiClient.batchSize, startId: 0),
        StateError('network down'),
      ]);
      final result = await serviceWith(api).drain();

      expect(result.outcome, ReplicationOutcome.failed);
      expect(result.error, isA<StateError>());
      // The first page is durable and the cursor sits exactly after it, so the
      // next attempt neither replays nor skips.
      expect(db.syncCursor, 500);
      expect(db.tableCounts()['goods'], SyncApiClient.batchSize);
    });

    test('a failure on the very first page changes nothing', () async {
      final api = FakeSyncApi([StateError('offline')]);
      final result = await serviceWith(api).drain();

      expect(result.outcome, ReplicationOutcome.failed);
      expect(db.syncCursor, 0);
      expect(db.tableCounts()['goods'], 0);
    });

    test('overlapping runs collapse instead of double-pulling', () async {
      final api = FakeSyncApi([page(nextCursor: 10, rows: 2)]);
      final service = serviceWith(api);

      final first = service.drain();
      final second = service.drain();
      final results = await Future.wait([first, second]);

      final outcomes = results.map((r) => r.outcome).toList();
      expect(outcomes, contains(ReplicationOutcome.caughtUp));
      expect(outcomes, contains(ReplicationOutcome.alreadyRunning));
      expect(api.calls, 1);
    });

    test('the guard clears after a failure so the next run proceeds', () async {
      final api = FakeSyncApi([
        StateError('transient'),
        page(nextCursor: 10, rows: 1),
      ]);
      final service = serviceWith(api);

      expect((await service.drain()).outcome, ReplicationOutcome.failed);
      expect(service.isRunning, isFalse);
      expect((await service.drain()).outcome, ReplicationOutcome.caughtUp);
      expect(db.tableCounts()['goods'], 1);
    });

    test('reports progress once per page', () async {
      final api = FakeSyncApi([
        page(nextCursor: 500, rows: SyncApiClient.batchSize, startId: 0),
        page(nextCursor: 600, rows: 4, startId: 500),
      ]);
      final seen = <ReplicationProgress>[];
      await serviceWith(api).drain(onProgress: seen.add);

      expect(seen, hasLength(2));
      expect(seen.first.batches, 1);
      expect(seen.last.rowsApplied, SyncApiClient.batchSize + 4);
      expect(seen.last.cursor, 600);
    });

    test('deletes in the feed remove replicated rows', () async {
      final api = FakeSyncApi([page(nextCursor: 5, rows: 3)]);
      await serviceWith(api).drain();
      expect(db.tableCounts()['goods'], 3);

      final api2 = FakeSyncApi([
        page(nextCursor: 9, rows: 3, asDeletes: true),
      ]);
      final result = await serviceWith(api2).drain();

      expect(result.rowsApplied, 3);
      expect(db.tableCounts()['goods'], 0);
    });
  });

  group('bootstrap', () {
    test('marks the terminal initialized only on a clean catch-up', () async {
      final api = FakeSyncApi([page(nextCursor: 42, rows: 5)]);
      final service = serviceWith(api);

      expect(service.needsBootstrap, isTrue);
      final result = await service.bootstrap();

      expect(result.outcome, ReplicationOutcome.caughtUp);
      expect(db.isBootstrapped, isTrue);
      expect(service.needsBootstrap, isFalse);
    });

    test('a failed bootstrap stays un-initialized and is resumable', () async {
      final api = FakeSyncApi([
        page(nextCursor: 500, rows: SyncApiClient.batchSize, startId: 0),
        StateError('connection reset'),
      ]);
      final service = serviceWith(api);

      expect((await service.bootstrap()).outcome, ReplicationOutcome.failed);
      expect(db.isBootstrapped, isFalse);
      expect(service.needsBootstrap, isTrue);
      // The partial fill survives, so retrying resumes rather than restarting.
      expect(db.syncCursor, 500);
      expect(db.tableCounts()['goods'], SyncApiClient.batchSize);

      final retry = FakeSyncApi([page(nextCursor: 600, rows: 3, startId: 500)]);
      expect(
        (await serviceWith(retry).bootstrap()).outcome,
        ReplicationOutcome.caughtUp,
      );
      expect(retry.requestedCursors, [500], reason: 'must resume, not restart');
      expect(db.isBootstrapped, isTrue);
    });

    test('hitting the ceiling leaves it un-initialized', () async {
      final api = FakeSyncApi([
        for (var i = 1; i <= 3; i++)
          page(
            nextCursor: i * 500,
            rows: SyncApiClient.batchSize,
            startId: (i - 1) * 500,
          ),
      ]);
      final service = serviceWith(api);
      final result = await service.bootstrap(maxBatches: 2);

      // A partial fill is usable but not a complete replica, so the terminal
      // must keep treating itself as un-bootstrapped until a later pass
      // finishes the feed.
      expect(result.outcome, ReplicationOutcome.moreAvailable);
      expect(db.isBootstrapped, isFalse);
      expect(service.needsBootstrap, isTrue);
      expect(db.tableCounts()['goods'], SyncApiClient.batchSize * 2);
    });

    test('resetAndBootstrap wipes the previous tenant before refilling',
        () async {
      await serviceWith(FakeSyncApi([page(nextCursor: 99, rows: 4)])).drain();
      expect(db.tableCounts()['goods'], 4);
      expect(db.syncCursor, 99);

      final fresh = FakeSyncApi([page(nextCursor: 7, rows: 1)]);
      await serviceWith(fresh).resetAndBootstrap();

      // The new tenant's feed is read from the beginning, not from the old
      // tenant's cursor, and none of its rows remain.
      expect(fresh.requestedCursors, [0]);
      expect(db.tableCounts()['goods'], 1);
      expect(db.syncCursor, 7);
    });
  });

  group('SyncApiClient.countRows', () {
    test('counts every action across every entity', () {
      expect(
        SyncApiClient.countRows({
          'goods': {
            'created': [1, 2, 3],
            'updated': [4],
            'deleted': ['a', 'b'],
          },
          'categories': {
            'created': [5],
          },
        }),
        7,
      );
    });

    test('tolerates missing keys and malformed shapes', () {
      expect(SyncApiClient.countRows(null), 0);
      expect(SyncApiClient.countRows('nonsense'), 0);
      expect(SyncApiClient.countRows({'goods': 'nonsense'}), 0);
      expect(SyncApiClient.countRows({'goods': <String, dynamic>{}}), 0);
    });
  });
}
