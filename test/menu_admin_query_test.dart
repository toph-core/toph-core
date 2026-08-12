/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the menu-admin screens.
///
/// I had twice reported these as blocked on `modifiers`/`goods_modifiers` and
/// offered to migrate them degraded. Neither screen references modifiers; the
/// plan's note is about the order screen. Everything they read replicates, so
/// there was no tradeoff to make — see DECISIONS.md D8.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/menu_admin_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/menu_admin_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/local_write_result.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_admin_local_repository.dart';

void main() {
  late LocalDatabase db;
  late MenuAdminQuery query;
  late OutboxStore outbox;
  late MenuAdminLocalRepository repo;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  /// A complete row. `GoodsModel` declares six numeric/text fields
  /// non-nullable, and the repository skips rows it cannot decode — so a thin
  /// fixture silently produces an empty list with a correct-looking total,
  /// which is exactly what a real replica row missing a column would do.
  void good(String id, {String name = 'Osh', String category = 'c-1', int? deletedAt}) =>
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
    query = MenuAdminQuery(db);
    outbox = OutboxStore(db);
    repo = MenuAdminLocalRepositoryImpl(
      db,
      LocalWriter(db: db, applier: ChangeApplier(db), outbox: outbox),
    );
  });

  tearDown(() => db.dispose());

  group('the goods listing', () {
    test('pages, and reports the true total for the paginator', () {
      for (var i = 0; i < 25; i++) {
        good('g-$i', name: 'Taom ${i.toString().padLeft(2, '0')}');
      }

      final first = repo.searchGoods(limit: 20, offset: 0);
      expect(first.items, hasLength(20));
      expect(first.total, 25, reason: 'total is the match count, not the page');

      final second = repo.searchGoods(limit: 20, offset: 20);
      expect(second.items, hasLength(5));
      expect(second.total, 25);
    });

    test('search matches across the whole menu, not just the loaded page', () {
      // The bug in the old screen. It fetched one page and filtered *that*
      // client-side, so a match on page 3 did not exist as far as the operator
      // could tell.
      for (var i = 0; i < 40; i++) {
        good('g-$i', name: 'Taom $i');
      }
      good('g-late', name: 'Lagmon');

      final result = repo.searchGoods(limit: 20, offset: 0, search: 'lagmon');

      expect(result.total, 1);
      expect(result.items.single.id, 'g-late');
    });

    test('category and search combine', () {
      good('g-1', name: 'Osh', category: 'c-1');
      good('g-2', name: 'Osh palov', category: 'c-2');
      good('g-3', name: 'Lagmon', category: 'c-1');

      final result =
          repo.searchGoods(limit: 20, offset: 0, categoryId: 'c-1', search: 'osh');

      expect(result.items.single.id, 'g-1');
      expect(result.total, 1);
    });

    test('soft-deleted goods are excluded from page and count alike', () {
      good('g-1');
      good('g-2', deletedAt: 1735689600);

      final result = repo.searchGoods(limit: 20, offset: 0);
      expect(result.items, hasLength(1));
      expect(result.total, 1);
    });

    test('a wildcard in the name searches literally', () {
      // "100% Cacao" must not match everything.
      good('g-1', name: '100% Cacao');
      good('g-2', name: 'Osh');

      expect(repo.searchGoods(limit: 20, offset: 0, search: '%').total, 1);
      expect(
        repo.searchGoods(limit: 20, offset: 0, search: '100%').items.single.id,
        'g-1',
      );
    });

    test('ordering is stable across pages', () {
      // The endpoint returned whatever order the planner gave, so a row could
      // show on two pages or none while other terminals edited the menu.
      good('g-b', name: 'Bbb');
      good('g-a', name: 'aaa');
      good('g-c', name: 'Ccc');

      expect(
        query.goods(limit: 10, offset: 0).map((g) => g['id']),
        ['g-a', 'g-b', 'g-c'],
      );
    });
  });

  group('the good editor', () {
    test('assembles a good with its calculation rows', () {
      good('g-1');
      put('calculation', {
        'id': 'calc-1',
        'good_id': 'g-1',
        'ingredient_id': 'i-1',
        'quantity': 2,
      });
      put('calculation', {'id': 'calc-2', 'good_id': 'g-9', 'quantity': 1});

      final assembled = repo.goodWithCalculations('g-1')!;

      expect(assembled['name'], 'Osh');
      expect(assembled['calculations'], hasLength(1));
      expect((assembled['calculations'] as List).single['id'], 'calc-1');
    });

    test('a missing good is null, not an empty shell', () {
      expect(repo.goodWithCalculations('nope'), isNull);
    });

    test('editing a good shows immediately in the list', () {
      good('g-1', name: 'Osh');

      final result = repo.saveGood(mealId: 'g-1', body: {'name': 'Osh (yangi)'});

      expect(result.getOrElse(() => LocalWriteResult.queued),
          LocalWriteResult.applied);
      expect(repo.searchGoods(limit: 20, offset: 0).items.single.name,
          'Osh (yangi)');
      expect(outbox.pending().single.action, 'update');
    });

    test('the nested calculations list is not written into the good row', () {
      // `calculations` is a separate table the endpoint unpacks. Mirroring that
      // here would mean inventing ids for rows the server owns.
      good('g-1');

      repo.saveGood(mealId: 'g-1', body: {
        'name': 'Osh',
        'calculations': [
          {'ingredient_id': 'i-1', 'quantity': 3},
        ],
      });

      expect(db.byId('goods', 'g-1')!.containsKey('calculations'), isFalse);
      // The server still receives them.
      expect(outbox.pending().single.payload['calculations'], hasLength(1));
    });

    test('creating a good queues without inventing an id', () {
      final result = repo.saveGood(body: {'name': 'Yangi taom'});

      expect(result.getOrElse(() => LocalWriteResult.applied),
          LocalWriteResult.queued);
      expect(repo.searchGoods(limit: 20, offset: 0).items, isEmpty);
      expect(outbox.pending().single.entityId, isNull);
    });

    test('deleting a good removes it and guards it against a pull', () {
      good('g-1');

      expect(repo.deleteGood('g-1').isRight(), isTrue);
      expect(repo.searchGoods(limit: 20, offset: 0).items, isEmpty);
      expect(db.isPending('goods', 'g-1'), isTrue);
    });
  });

  group('reactivity', () {
    test('the list updates on a write with no refetch', () async {
      good('g-1', name: 'Osh');

      final seen = <GoodsPage>[];
      final sub = repo.watchGoods(limit: 20, offset: 0).listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.single.items.single.name, 'Osh');

      repo.saveGood(mealId: 'g-1', body: {'name': 'Lagmon'});
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.items.single.name, 'Lagmon');
      await sub.cancel();
    });

    test('a category change wakes the goods list too', () async {
      // They share a watch set: the list renders category names beside goods.
      good('g-1');
      final seen = <GoodsPage>[];
      final sub = repo.watchGoods(limit: 20, offset: 0).listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      put('categories', {'id': 'c-1', 'name': 'Issiq taomlar'});
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      await sub.cancel();
    });
  });

  group('undecodable rows', () {
    test('one bad row costs that row, not the page', () {
      good('g-1');
      // A row the server logged without `cook_time`, which `GoodsModel`
      // declares non-nullable.
      final broken = {
        'id': 'g-2',
        'name': 'Yarim taom',
        'category_id': 'c-1',
        'branch_id': 'b-1',
        'description': '',
        'price': 1000,
        'cost_price': 500,
        'profit': 500,
        'profit_margin': 50,
      };
      put('goods', broken);

      final result = repo.searchGoods(limit: 20, offset: 0);

      expect(result.items, hasLength(1));
      expect(result.items.single.id, 'g-1');
    });

    test('the total counts rows the page cannot decode', () {
      // Deliberate, and worth stating: the count is a `COUNT(*)`, so it does
      // not decode. Making it agree would mean decoding every matching row on
      // every page — paying the full-table cost the paginator exists to avoid.
      // The visible effect is a page showing fewer items than the total
      // implies, which is honest about there being a row the client cannot
      // read; silently lowering the count would hide that a menu item exists
      // and is unrenderable.
      good('g-1');
      put('goods', {
        'id': 'g-2',
        'name': 'Yarim taom',
        'category_id': 'c-1',
        'branch_id': 'b-1',
        'price': 1000,
      });

      final result = repo.searchGoods(limit: 20, offset: 0);

      expect(result.items, hasLength(1));
      expect(result.total, 2);
    });
  });
}

