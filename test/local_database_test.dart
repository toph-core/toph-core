/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 0 — replication layer tests.
///
/// Covers the two things Phase 0 has to get right before anything is built on
/// it: that a raw change-log row survives the round trip into the shape the
/// app's existing models parse, and that replication can never overwrite an
/// unsynced local write.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';

/// A `goods` row shaped exactly as `to_jsonb(NEW)` renders it: numerics as JSON
/// numbers, `deleted_at` present, no API-layer transformation.
Map<String, dynamic> goodsRow({
  String id = 'g-1',
  String name = 'Pizza Margherita',
  String? categoryId = 'c-1',
  num price = 15000.00,
  int? deletedAt,
}) =>
    {
      'id': id,
      'name': name,
      'description': 'Classic',
      'category_id': categoryId,
      'branch_id': 'b-1',
      'picture_url': null,
      'color_code': '#FF5733',
      'price': price,
      'cook_time': 30,
      'cost_price': 10500.00,
      'profit': 4500.00,
      'profit_margin': 42.86,
      'markup_percent': null,
      'created_at': '2026-07-12T13:17:20+00:00',
      'updated_at': '2026-07-12T13:17:20+00:00',
      'deleted_at': deletedAt,
    };

void main() {
  late LocalDatabase db;
  late ChangeApplier applier;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
  });

  tearDown(() => db.dispose());

  group('schema', () {
    test('creates a table for every replicated entity', () {
      final counts = db.tableCounts();
      expect(counts.length, kReplicatedEntities.length);
      for (final spec in kReplicatedEntities) {
        expect(counts[spec.name], 0, reason: '${spec.name} should exist, empty');
      }
    });

    test('the registry is internally consistent', () {
      expect(validateRegistry(), isEmpty);
    });

    test('registry entity names are unique', () {
      final names = kReplicatedEntities.map((e) => e.name).toSet();
      expect(names.length, kReplicatedEntities.length);
    });

    test('replicates every entity the backend logs a trigger for', () {
      // Mirrors the `trg_change_log_*` triggers in the backend's tenant
      // migrations (8_movements.up.sql, 41_modifier_calculation.up.sql). If the
      // backend adds a trigger, this list and the registry both need the entry
      // — an unreplicated entity is silently skipped at runtime, so the gap
      // would otherwise only show up as missing data on a screen.
      const loggedByBackend = {
        'attendances', 'bill_daily_counters', 'branches', 'cafe_tables',
        'calculation', 'categories', 'compound_stock', 'compounds',
        'compounds_details', 'deduction_act_groups',
        'deduction_item_ingredients', 'deduction_items', 'deductions',
        'departments', 'goods', 'goods_details', 'halls', 'ingredient_groups',
        'ingredient_stock', 'ingredient_stock_movements', 'ingredients',
        'inventories', 'inventory_items', 'invoice_detailed', 'invoices',
        'modifier_calculation', 'order_item_modifiers', 'order_items', 'orders',
        'shifts', 'storages', 'suppliers', 'translations', 'user_payments',
        'users',
      };
      expect(kEntitiesByName.keys.toSet(), loggedByBackend);
    });

    test('local table names cannot collide with replicated entities', () {
      for (final spec in kReplicatedEntities) {
        expect(LocalTables.all.contains(spec.name), isFalse);
      }
    });

    test('bill_daily_counters is keyed by day, not id', () {
      expect(kEntitiesByName['bill_daily_counters']!.pk, 'day');
      // Everything else uses `id`, matching log_change()'s trigger argument.
      for (final spec in kReplicatedEntities) {
        if (spec.name == 'bill_daily_counters') continue;
        expect(spec.pk, 'id', reason: spec.name);
      }
    });
  });

  group('normalization', () {
    test('numeric columns become strings the Flutter models can parse', () {
      final spec = kEntitiesByName['goods']!;
      final out = PayloadNormalizer.normalize(spec, goodsRow());

      // GoodsModel declares these as String; a raw JSON number would throw.
      expect(out['price'], isA<String>());
      expect(out['price'], '15000');
      expect(out['cost_price'], '10500');
      expect(out['profit_margin'], '42.86');
      // Nulls stay null rather than becoming "null".
      expect(out['markup_percent'], isNull);
      // Non-numeric fields are untouched.
      expect(out['name'], 'Pizza Margherita');
      expect(out['cook_time'], 30);
    });

    test('integral values render without a fractional part', () {
      expect(PayloadNormalizer.numToCanonicalString(15000.00), '15000');
      expect(PayloadNormalizer.numToCanonicalString(15000), '15000');
      expect(PayloadNormalizer.numToCanonicalString(0.0), '0');
      expect(PayloadNormalizer.numToCanonicalString(42.86), '42.86');
      expect(PayloadNormalizer.numToCanonicalString(-5000.0), '-5000');
    });

    test('credential columns never reach disk', () {
      final spec = kEntitiesByName['users']!;
      final out = PayloadNormalizer.normalize(spec, {
        'id': 'u-1',
        'full_name': 'Aziza',
        'username': 'aziza',
        'role': 'cashier',
        'hash_password': r'$2a$10$secret',
        'pincode': '1234',
        'branch_id': 'b-1',
        'is_active': true,
      });

      expect(out.containsKey('hash_password'), isFalse);
      expect(out.containsKey('pincode'), isFalse);
      expect(out['username'], 'aziza');
    });

    test('a users row stored through the applier carries no credentials', () {
      applier.applyOne(
        entity: 'users',
        action: 'create',
        payload: {
          'id': 'u-1',
          'username': 'aziza',
          'role': 'cashier',
          'hash_password': 'secret',
          'pincode': '1234',
        },
      );
      final stored = db.byId('users', 'u-1')!;
      expect(stored.containsKey('hash_password'), isFalse);
      expect(stored.containsKey('pincode'), isFalse);

      // Not merely absent from the decoded map — absent from the stored text.
      final raw = db.select('SELECT data FROM users WHERE id = ?', ['u-1']);
      expect(raw.first['data'].toString().contains('secret'), isFalse);
      expect(raw.first['data'].toString().contains('1234'), isFalse);
    });
  });

  group('upsert and read', () {
    test('round-trips a row and promotes indexed columns', () {
      applier.applyOne(
        entity: 'goods',
        action: 'create',
        payload: goodsRow(),
      );

      final stored = db.byId('goods', 'g-1');
      expect(stored, isNotNull);
      expect(stored!['name'], 'Pizza Margherita');
      expect(stored['price'], '15000');

      // Promoted columns are queryable as real SQL, not just inside `data`.
      final byCategory = db.selectData(
        'SELECT data FROM goods WHERE category_id = ?',
        ['c-1'],
      );
      expect(byCategory, hasLength(1));
    });

    test('re-applying the same row is idempotent', () {
      for (var i = 0; i < 3; i++) {
        applier.applyOne(
          entity: 'goods',
          action: 'create',
          payload: goodsRow(),
        );
      }
      expect(db.tableCounts()['goods'], 1);
    });

    test('soft-deleted rows are excluded from reads', () {
      applier.applyOne(
        entity: 'goods',
        action: 'update',
        payload: goodsRow(deletedAt: 1752328640),
      );
      expect(db.byId('goods', 'g-1'), isNull);
      expect(db.allOf('goods'), isEmpty);
      // The row is still stored — the server said "deleted", not "gone".
      expect(db.tableCounts()['goods'], 1);
    });

    test('a delete action removes the row outright', () {
      applier.applyOne(entity: 'goods', action: 'create', payload: goodsRow());
      final stats =
          applier.applyOne(entity: 'goods', action: 'delete', entityId: 'g-1');
      expect(stats.deleted, 1);
      expect(db.tableCounts()['goods'], 0);
    });
  });

  group('applyPullResponse', () {
    test('applies creates, updates and deletes, and advances the cursor', () {
      final stats = applier.applyPullResponse({
        'next_sync_cursor': 42,
        'changes': {
          'goods': {
            'created': [goodsRow(id: 'g-1'), goodsRow(id: 'g-2')],
            'updated': [goodsRow(id: 'g-1', name: 'Renamed')],
            'deleted': <String>[],
          },
          'categories': {
            'created': [
              {'id': 'c-1', 'name': 'Pizza', 'department_id': null},
            ],
          },
        },
      });

      expect(stats.applied, 4);
      expect(stats.failed, 0);
      expect(db.syncCursor, 42);
      expect(db.byId('goods', 'g-1')!['name'], 'Renamed');
      expect(db.tableCounts()['goods'], 2);
      expect(db.tableCounts()['categories'], 1);
    });

    test('deletes are applied after upserts within one batch', () {
      // The pull response groups by action, losing change_log ordering. A row
      // created and deleted inside one batch must end up deleted.
      final stats = applier.applyPullResponse({
        'next_sync_cursor': 7,
        'changes': {
          'goods': {
            'created': [goodsRow(id: 'g-1')],
            'deleted': ['g-1'],
          },
        },
      });

      expect(stats.applied, 1);
      expect(stats.deleted, 1);
      expect(db.tableCounts()['goods'], 0);
    });

    test('unknown entities are skipped, not fatal', () {
      final stats = applier.applyPullResponse({
        'next_sync_cursor': 5,
        'changes': {
          'some_future_table': {
            'created': [
              {'id': 'x'},
            ],
            'deleted': ['y'],
          },
          'goods': {
            'created': [goodsRow()],
          },
        },
      });

      expect(stats.skippedUnknown, 2);
      expect(stats.applied, 1);
      expect(db.syncCursor, 5);
    });

    test('the cursor never moves backwards', () {
      applier.applyPullResponse({'next_sync_cursor': 100, 'changes': {}});
      expect(db.syncCursor, 100);

      // A retried or reordered batch must not rewind the cursor, which would
      // make the client re-request the same range forever.
      applier.applyPullResponse({'next_sync_cursor': 50, 'changes': {}});
      expect(db.syncCursor, 100);
    });

    test('malformed rows are counted, not thrown', () {
      final stats = applier.applyPullResponse({
        'next_sync_cursor': 1,
        'changes': {
          'goods': {
            'created': [
              {'name': 'no primary key'},
              'not a map',
            ],
            'deleted': [''],
          },
        },
      });

      expect(stats.failed, 3);
      expect(stats.applied, 0);
    });

    test('an empty response is a no-op', () {
      final stats = applier.applyPullResponse({
        'next_sync_cursor': 0,
        'changes': <String, dynamic>{},
      });
      expect(stats.total, 0);
      expect(db.syncCursor, 0);
    });
  });

  group('local-write guard', () {
    test('replication cannot overwrite an unsynced local write', () {
      applier.applyLocalWrite(
        entity: 'goods',
        id: 'g-1',
        payload: goodsRow(name: 'Local edit'),
      );

      final stats = applier.applyPullResponse({
        'next_sync_cursor': 9,
        'changes': {
          'goods': {
            'updated': [goodsRow(name: 'Server version')],
          },
        },
      });

      expect(stats.skippedPending, 1);
      expect(stats.applied, 0);
      expect(db.byId('goods', 'g-1')!['name'], 'Local edit');
    });

    test('replication cannot delete an unsynced local write', () {
      applier.applyLocalWrite(
        entity: 'goods',
        id: 'g-1',
        payload: goodsRow(),
      );
      final stats = applier.applyPullResponse({
        'next_sync_cursor': 9,
        'changes': {
          'goods': {'deleted': ['g-1']},
        },
      });

      expect(stats.skippedPending, 1);
      expect(db.byId('goods', 'g-1'), isNotNull);
    });

    test('the server wins again once the write is acknowledged', () {
      applier.applyLocalWrite(
        entity: 'goods',
        id: 'g-1',
        payload: goodsRow(name: 'Local edit'),
      );
      db.clearPending('goods', 'g-1');

      applier.applyPullResponse({
        'next_sync_cursor': 9,
        'changes': {
          'goods': {
            'updated': [goodsRow(name: 'Server version')],
          },
        },
      });

      expect(db.byId('goods', 'g-1')!['name'], 'Server version');
    });

    test('applyLocalWrite rejects an unknown entity', () {
      expect(
        () => applier.applyLocalWrite(
          entity: 'not_an_entity',
          id: 'x',
          payload: const {},
        ),
        throwsArgumentError,
      );
    });
  });

  group('reactivity', () {
    test('watch emits current state immediately, then on change', () async {
      final emissions = <int>[];
      final sub = db
          .watch({'goods'}, () => db.allOf('goods').length)
          .listen(emissions.add);

      await pumpEventQueue();
      expect(emissions, [0]);

      applier.applyOne(entity: 'goods', action: 'create', payload: goodsRow());
      await pumpEventQueue();
      expect(emissions, [0, 1]);

      await sub.cancel();
    });

    test('watch ignores changes to unrelated tables', () async {
      final emissions = <int>[];
      final sub = db
          .watch({'goods'}, () => db.allOf('goods').length)
          .listen(emissions.add);
      await pumpEventQueue();

      applier.applyOne(
        entity: 'categories',
        action: 'create',
        payload: {'id': 'c-1', 'name': 'Pizza'},
      );
      await pumpEventQueue();

      expect(emissions, [0], reason: 'categories must not wake a goods watcher');
      await sub.cancel();
    });

    test('a batch notifies once per table, not once per row', () async {
      var wakeups = 0;
      final sub =
          db.watch({'goods'}, () => db.allOf('goods').length).listen((_) {
        wakeups++;
      });
      await pumpEventQueue();
      expect(wakeups, 1); // the immediate emission

      applier.applyPullResponse({
        'next_sync_cursor': 1,
        'changes': {
          'goods': {
            'created': [
              for (var i = 0; i < 25; i++) goodsRow(id: 'g-$i'),
            ],
          },
        },
      });
      await pumpEventQueue();

      expect(wakeups, 2, reason: '25 rows must coalesce into one notification');
      await sub.cancel();
    });

    test('a rolled-back transaction notifies nobody', () async {
      final emissions = <int>[];
      final sub = db
          .watch({'goods'}, () => db.allOf('goods').length)
          .listen(emissions.add);
      await pumpEventQueue();

      expect(
        () => db.transaction(() {
          applier.applyOne(
            entity: 'goods',
            action: 'create',
            payload: goodsRow(),
          );
          throw StateError('boom');
        }),
        throwsStateError,
      );
      await pumpEventQueue();

      expect(emissions, [0]);
      expect(db.tableCounts()['goods'], 0);
      await sub.cancel();
    });
  });

  group('lifecycle', () {
    test('clearAll wipes replicated data, outbox and cursor', () {
      applier.applyPullResponse({
        'next_sync_cursor': 88,
        'changes': {
          'goods': {'created': [goodsRow()]},
        },
      });
      db.markPending('goods', 'g-1');
      db.markBootstrapped();

      db.clearAll();

      expect(db.tableCounts()['goods'], 0);
      expect(db.syncCursor, 0);
      expect(db.isBootstrapped, isFalse);
      expect(db.isPending('goods', 'g-1'), isFalse);
    });

    test('a fresh database needs bootstrap', () {
      expect(db.syncCursor, 0);
      expect(db.isBootstrapped, isFalse);
    });
  });
}
