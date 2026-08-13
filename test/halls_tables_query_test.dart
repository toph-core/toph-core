/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — halls & tables on the replica.
///
/// The screen was already reactive, but over the Hive store, with writes going
/// straight to the network. Both sides move here, and they had to move
/// together: a write landing in the replica would be invisible to a screen
/// still reading Hive. That coupling is what the last group pins.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/halls_tables_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/halls_tables_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/halls_tables_local_repository.dart';

void main() {
  late LocalDatabase db;
  late HallsTablesQuery query;
  late OutboxStore outbox;
  late HallsTablesLocalRepository repo;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  Map<String, dynamic> hall({
    required String id,
    String name = 'Asosiy zal',
    int? deletedAt,
  }) =>
      {
        'id': id,
        'branch_id': 'b-1',
        'name': name,
        'width': 1000,
        'height': 800,
        'deleted_at': deletedAt,
      };

  Map<String, dynamic> table({
    required String id,
    String hallId = 'h-1',
    int number = 1,
    int posX = 10,
    int posY = 20,
    int? deletedAt,
  }) =>
      {
        'id': id,
        'hall_id': hallId,
        'number': number,
        'pos_x': posX,
        'pos_y': posY,
        'width': 80,
        'height': 80,
        'rotation': 0,
        'capacity': 4,
        'status': 'free',
        'shape': 'square',
        'table_type': 'simple',
        'price_per_hour': '0',
        'deleted_at': deletedAt,
      };

  setUp(() {
    db = LocalDatabase.open(':memory:');
    query = HallsTablesQuery(db);
    outbox = OutboxStore(db);
    repo = HallsTablesLocalRepositoryImpl(
      db,
      LocalWriter(db: db, applier: ChangeApplier(db), outbox: outbox),
    );
  });

  tearDown(() => db.dispose());

  group('HallsTablesQuery', () {
    test('excludes soft-deleted halls and tables', () {
      put('halls', hall(id: 'h-1'));
      put('halls', hall(id: 'h-2', name: 'Terrasa', deletedAt: 1735689600));
      put('cafe_tables', table(id: 't-1'));
      put('cafe_tables', table(id: 't-2', number: 2, deletedAt: 1735689600));

      expect(query.halls(), hasLength(1));
      expect(query.tables(), hasLength(1));
    });

    test('halls sort by name, not insertion order', () {
      // The Hive path returned box order, which moved whenever a hydration
      // pass rewrote it — so the list reshuffled under the operator.
      put('halls', hall(id: 'h-2', name: 'Terrasa'));
      put('halls', hall(id: 'h-1', name: 'Asosiy zal'));
      put('halls', hall(id: 'h-3', name: 'balkon'));

      expect(
        query.halls().map((h) => h['name']),
        ['Asosiy zal', 'balkon', 'Terrasa'],
      );
    });

    test('tablesForHall scopes to one hall, ordered by number', () {
      put('cafe_tables', table(id: 't-3', number: 3));
      put('cafe_tables', table(id: 't-1', number: 1));
      put('cafe_tables', table(id: 't-x', hallId: 'h-2', number: 1));

      final tables = query.tablesForHall('h-1');
      expect(tables.map((t) => t['id']), ['t-1', 't-3']);
    });
  });

  group('HallsTablesLocalRepository — decoding', () {
    test('a malformed row costs that row, not the floor plan', () {
      put('cafe_tables', table(id: 't-1', number: 1));
      // `width` is non-nullable on the model; without a per-row guard this one
      // row would throw and blank the entire plan.
      final broken = table(id: 't-2', number: 2)..remove('width');
      put('cafe_tables', broken);

      final tables = repo.getTablesForHall('h-1');
      expect(tables, hasLength(1));
      expect(tables.single.id, 't-1');
    });
  });

  group('HallsTablesLocalRepository — writes', () {
    test('moving a table writes locally and queues the PUT', () {
      put('cafe_tables', table(id: 't-1', posX: 10, posY: 20));

      final result = repo.updateTable('t-1', {'pos_x': 300, 'pos_y': 400});

      expect(result.isRight(), isTrue);
      final moved = repo.getTablesForHall('h-1').single;
      expect(moved.posX, 300);
      expect(moved.posY, 400);
      expect(outbox.pending().single.action, 'update');
    });

    test('a hall rename does not erase the rest of the row', () {
      put('halls', hall(id: 'h-1', name: 'Asosiy zal'));

      repo.updateHall('h-1', {'name': 'Yangi zal'});

      final row = db.byId('halls', 'h-1')!;
      expect(row['name'], 'Yangi zal');
      expect(row['width'], 1000);
      expect(row['branch_id'], 'b-1');
    });

    test('deleting a hall removes it and guards it against a pull', () {
      put('halls', hall(id: 'h-1'));

      expect(repo.deleteHall('h-1').isRight(), isTrue);
      expect(db.byId('halls', 'h-1'), isNull);
      expect(db.isPending('halls', 'h-1'), isTrue);
      expect(outbox.pending().single.action, 'delete');
    });

    test('a created table appears at once, under a provisional id', () {
      // Was: queued with no local row, because the endpoint assigns the id.
      // Now the row goes in under a stand-in that the drainer swaps for the
      // server's — see DECISIONS.md D1.
      final result = repo.createTable({
        'hall_id': 'h-1',
        'number': 7,
        'capacity': 4,
        'pos_x': 0,
        'pos_y': 0,
        'width': 80,
        'height': 80,
        'rotation': 0,
      });

      expect(result.isRight(), isTrue);
      expect(repo.getTablesForHall('h-1').single.number, 7);

      final op = outbox.pending().single;
      expect(op.action, 'create');
      expect(db.isProvisional('cafe_tables', op.entityId!), isTrue);
      expect(op.payload.containsKey('id'), isFalse,
          reason: 'the server assigns it; ours would be noise');
    });
  });

  group('read and write are one unit', () {
    test('a move is visible on the stream without any refetch', () async {
      put('cafe_tables', table(id: 't-1', posX: 10, posY: 20));

      final seen = <List<CafeTableModel>>[];
      final sub = repo.watchTablesForHall('h-1').listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.single.posX, 10);

      repo.updateTable('t-1', {'pos_x': 300});
      await Future<void>.delayed(Duration.zero);

      // This is the coupling: the write landed in the replica the read watches,
      // so it arrives with no re-fetch and no sync pass in between.
      expect(seen, hasLength(2));
      expect(seen.last.single.posX, 300);

      await sub.cancel();
    });

    test('a hall change also wakes the table stream', () async {
      // Both tables are in the watch set, because a hall delete removes the
      // floor plan the tables were drawn on.
      put('halls', hall(id: 'h-1'));
      put('cafe_tables', table(id: 't-1'));

      final seen = <List<CafeTableModel>>[];
      final sub = repo.watchTablesForHall('h-1').listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));

      repo.updateHall('h-1', {'name': 'Yangi'});
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      await sub.cancel();
    });
  });

  group('live occupancy overlays the replicated status', () {
    test('a local status wins over the row the server logged', () {
      put('cafe_tables', table(id: 't-1'));
      expect(query.tables().single['status'], 'free');

      db.setTableStatus('t-1', 'busy');

      expect(query.tables().single['status'], 'busy');
      expect(query.tablesForHall('h-1').single['status'], 'busy');
    });

    test('tables with no local status keep the replicated one', () {
      put('cafe_tables', table(id: 't-1', number: 1));
      put('cafe_tables', table(id: 't-2', number: 2));
      db.setTableStatus('t-2', 'busy');

      expect(
        {for (final t in query.tables()) t['id']: t['status']},
        {'t-1': 'free', 't-2': 'busy'},
      );
    });

    test('a replication pass no longer wipes the venue’s occupancy', () {
      // The bug this separation fixes. Occupancy used to be a field inside the
      // cached table row, and the periodic reference-data hydration replaced
      // that row wholesale with the server's — so every refresh reset a busy
      // table to whatever the server last knew, which offline is nothing.
      put('cafe_tables', table(id: 't-1'));
      db.setTableStatus('t-1', 'busy');

      // The server re-sends the table, still believing it free.
      put('cafe_tables', table(id: 't-1', posX: 999));

      final row = query.tables().single;
      expect(row['status'], 'busy', reason: 'local occupancy survives the pull');
      expect(row['pos_x'], 999, reason: 'server geometry still lands');
    });

    test('occupancy changes wake table subscribers', () async {
      put('cafe_tables', table(id: 't-1'));

      final seen = <List<CafeTableModel>>[];
      final sub = repo.watchTablesForHall('h-1').listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      db.setTableStatus('t-1', 'busy');
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      expect(seen.last.single.status, TableStatus.busy);
      await sub.cancel();
    });

    test('pruning drops occupancy for tables that no longer exist', () {
      put('cafe_tables', table(id: 't-1'));
      db.setTableStatus('t-1', 'busy');
      db.setTableStatus('t-gone', 'busy');
      expect(db.tableStatuses(), hasLength(2));

      db.pruneTableStatuses();

      expect(db.tableStatuses().keys, ['t-1']);
    });
  });
}

