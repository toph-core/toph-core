/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the live order-detail read,
/// assembled from the replica. Pins the stored-side assembly: the open bill of
/// a table, its live items joined to goods for names, and the table/hall header.
/// The offline-queue overlay is deliberately not covered here — it stays in
/// detail_bloc.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';

void main() {
  late LocalDatabase db;
  late OrderDetailQuery query;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  setUp(() {
    db = LocalDatabase.open(':memory:');
    query = OrderDetailQuery(db);

    put('halls', {'id': 'h1', 'name': 'Main', 'branch_id': 'b1', 'deleted_at': 0});
    put('cafe_tables', {'id': 'tb1', 'hall_id': 'h1', 'number': 5, 'deleted_at': 0});
    put('cafe_tables', {'id': 'tb2', 'hall_id': 'h1', 'number': 6, 'deleted_at': 0});
    put('goods', {'id': 'g1', 'name': 'Osh', 'branch_id': 'b1', 'price': 25000, 'deleted_at': 0});
    put('goods', {'id': 'g2', 'name': 'Lagmon', 'branch_id': 'b1', 'price': 30000, 'deleted_at': 0});
  });

  tearDown(() => db.dispose());

  void order(String id, String table, String status, String createdAt, {int deletedAt = 0}) =>
      put('orders', {
        'id': id, 'table_id': table, 'bill_status': status,
        'branch_id': 'b1', 'created_at': createdAt, 'deleted_at': deletedAt,
      });

  void item(String id, String order, String good, String createdAt, {int deletedAt = 0}) =>
      put('order_items', {
        'id': id, 'order_id': order, 'good_id': good, 'quantity': 1,
        'price': 25000, 'created_at': createdAt, 'deleted_at': deletedAt,
      });

  group('the live order-detail read', () {
    test('returns the open bill of a table with its header and items', () {
      order('o1', 'tb1', 'open', '2026-08-12T10:00:00Z');
      item('i1', 'o1', 'g1', '2026-08-12T10:01:00Z');
      item('i2', 'o1', 'g2', '2026-08-12T10:02:00Z');

      final o = query.liveOrderForTable('tb1')!;
      expect(o['id'], 'o1');
      expect(o['table_number'], 5);
      expect(o['hall_name'], 'Main');
      final items = (o['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((e) => e['id']), ['i1', 'i2']);
      expect(items.map((e) => e['good_name']), ['Osh', 'Lagmon']);
    });

    test('items are ordered by created_at, not by id or insertion order', () {
      order('o1', 'tb1', 'open', '2026-08-12T10:00:00Z');
      // `created_at` is not a promoted column on order_items; it is read from
      // the stored `data` blob with json_extract. This case makes the id order
      // the OPPOSITE of the chronological order — 'aa' sorts first by id but was
      // rung in last — so ordering by the (non-existent) `oi.created_at` column,
      // or falling back to id/rowid order, both give the wrong answer here.
      item('aa', 'o1', 'g1', '2026-08-12T10:05:00Z');
      item('zz', 'o1', 'g2', '2026-08-12T10:01:00Z');

      final items = (query.liveOrderForTable('tb1')!['items'] as List)
          .cast<Map<String, dynamic>>();
      expect(items.map((e) => e['id']), ['zz', 'aa']);
    });

    test('a cancelled (soft-deleted) item is excluded', () {
      order('o1', 'tb1', 'open', '2026-08-12T10:00:00Z');
      item('i1', 'o1', 'g1', '2026-08-12T10:01:00Z');
      item('i2', 'o1', 'g1', '2026-08-12T10:02:00Z', deletedAt: 1750000000);

      final items = (query.liveOrderForTable('tb1')!['items'] as List);
      expect(items.map((e) => e['id']), ['i1']);
    });

    test('a closed bill on the same table is ignored', () {
      order('o0', 'tb1', 'closed', '2026-08-11T09:00:00Z');
      order('o1', 'tb1', 'open', '2026-08-12T10:00:00Z');

      expect(query.liveOrderForTable('tb1')!['id'], 'o1');
    });

    test('a free table returns null', () {
      expect(query.liveOrderForTable('tb2'), isNull);
    });
  });

  group('by id — the payment and archive screens\' read', () {
    test('a paid bill still assembles, header, items and all', () {
      // The list read filters closed bills out; this one must not, or the
      // payment screen would go blank the instant the bill was settled and the
      // archive detail would have nothing to show at all.
      order('o1', 'tb1', 'closed', '2026-08-12T10:00:00Z');
      item('i1', 'o1', 'g1', '2026-08-12T10:01:00Z');
      item('i2', 'o1', 'g2', '2026-08-12T10:02:00Z');

      final o = query.liveOrderById('o1')!;
      expect(o['id'], 'o1');
      expect(o['table_number'], 5);
      expect(o['hall_name'], 'Main');
      expect(
        (o['items'] as List).map((e) => e['good_name']),
        ['Osh', 'Lagmon'],
      );
    });

    test('a takeaway bill with no table assembles on the LEFT JOINs', () {
      put('orders', {
        'id': 'o-tw', 'bill_status': 'closed', 'branch_id': 'b1',
        'order_type': 'takeaway', 'created_at': '2026-08-12T10:00:00Z',
        'deleted_at': 0,
      });
      item('i1', 'o-tw', 'g1', '2026-08-12T10:01:00Z');

      final o = query.liveOrderById('o-tw')!;
      expect(o['table_number'], isNull);
      expect(o['hall_name'], isNull);
      expect((o['items'] as List).single['good_name'], 'Osh');
    });

    test('an unknown id is null — what the archive detail reports as not found',
        () {
      expect(query.liveOrderById('nope'), isNull);
    });

    test('a soft-deleted bill is null', () {
      order('o1', 'tb1', 'closed', '2026-08-12T10:00:00Z',
          deletedAt: 1750000000);
      expect(query.liveOrderById('o1'), isNull);
    });
  });
}
