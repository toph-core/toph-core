/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the customer menu's reads, now on
/// the replica. Pins the contract the menu screen relies on: live rows only,
/// ordered by name, goods filtered by category, decoded into the screen's
/// models, and a row the model cannot parse dropped rather than crashing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/menu_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';

void main() {
  late LocalDatabase db;
  late MenuQuery query;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  // GoodsModel declares six non-nullable fields; a thinner row is unparseable
  // and drops. Mirrors menu_admin_query_test's fixture.
  void good(String id,
          {String name = 'Osh', String category = 'c-1', int? deletedAt}) =>
      put('goods', {
        'id': id,
        'name': name,
        'category_id': category,
        'branch_id': 'b-1',
        'cook_time': 15,
        'description': '',
        'price': 25000,
        'cost_price': 12000,
        'profit': 13000,
        'profit_margin': 52,
        'deleted_at': deletedAt,
      });

  setUp(() {
    db = LocalDatabase.open(':memory:');
    query = MenuQuery(db);
  });

  tearDown(() => db.dispose());

  group('categories & departments', () {
    test('live, decoded, ordered by name, soft-deleted excluded', () {
      put('categories', {'id': 'c2', 'name': 'Salads'});
      put('categories', {'id': 'c1', 'name': 'Drinks'});
      put('categories',
          {'id': 'c3', 'name': 'Hidden', 'deleted_at': 1735689600000});
      expect(query.categories().map((c) => c.name), ['Drinks', 'Salads']);
      expect(query.categories().map((c) => c.id), ['c1', 'c2']);

      put('departments', {'id': 'd1', 'name': 'Kitchen'});
      expect(query.departments().map((d) => d.name), ['Kitchen']);
    });
  });

  group('goods per category', () {
    setUp(() {
      good('g1', name: 'Lagman', category: 'c-1');
      good('g2', name: 'Osh', category: 'c-1');
      good('g3', name: 'Cola', category: 'c-2');
      good('g4', name: 'Gone', category: 'c-1', deletedAt: 1735689600000);
    });

    test('filters by category_id, ordered by name, soft-deleted excluded', () {
      expect(query.goodsForCategory('c-1').map((g) => g.id), ['g1', 'g2']);
      expect(query.goodsForCategory('c-2').map((g) => g.id), ['g3']);
    });

    test("'all' returns every live good, ordered by name", () {
      expect(query.goodsForCategory('all').map((g) => g.id), ['g3', 'g1', 'g2']);
      expect(query.goods().map((g) => g.id), ['g3', 'g1', 'g2']);
    });

    test('a row the model cannot decode is dropped, not thrown', () {
      // Missing the non-nullable numeric fields GoodsModel needs.
      put('goods', {'id': 'bad', 'name': 'Broken', 'category_id': 'c-1'});
      expect(query.goodsForCategory('c-1').map((g) => g.id), ['g1', 'g2']);
    });
  });

  group('goodById — the receipt builders\' lookup', () {
    test('resolves one good by primary key', () {
      good('g1', name: 'Osh', category: 'c-1');
      good('g2', name: 'Lagmon', category: 'c-2');
      expect(query.goodById('g1')?.name, 'Osh');
      expect(query.goodById('g2')?.categoryId, 'c-2');
    });

    test('an unknown id, or an empty one, is null rather than a throw', () {
      good('g1');
      expect(query.goodById('nope'), isNull);
      expect(query.goodById(''), isNull);
    });

    test('a good removed from the menu still resolves, so a reprint of an '
        'older bill keeps its name and category', () {
      good('g1', name: 'Retired dish', deletedAt: 1735689600000);
      expect(query.goodsForCategory('c-1'), isEmpty);
      expect(query.goodById('g1')?.name, 'Retired dish');
    });

    test('a row the model cannot decode is null, not a throw', () {
      put('goods', {'id': 'bad', 'name': 'Broken', 'category_id': 'c-1'});
      expect(query.goodById('bad'), isNull);
    });
  });

  group('ingredient & compound pickers (raw maps)', () {
    test('live, ordered by name, soft-deleted excluded', () {
      put('ingredients', {'id': 'i2', 'name': 'Salt'});
      put('ingredients', {'id': 'i1', 'name': 'Flour'});
      put('ingredients',
          {'id': 'i3', 'name': 'Gone', 'deleted_at': 1735689600000});
      expect(query.ingredients().map((m) => m['name']), ['Flour', 'Salt']);

      put('compounds', {'id': 'k1', 'name': 'Dough', 'branch_id': 'b-1'});
      expect(query.compounds().map((m) => m['name']), ['Dough']);
    });
  });
}
