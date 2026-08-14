/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the transactions list's reads.
///
/// The list's pagination, search and type/cash-register filters were REST query
/// parameters; here they are SQL over the local replica. These assertions pin
/// the behaviour to the server's `GetAllTransactions`: newest first, live rows
/// only, description-or-amount search, exact type/register filters.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/db/transactions_query.dart';

void main() {
  late LocalDatabase db;
  late TransactionsQuery query;

  void tx(
    String id, {
    required String type,
    required String register,
    required String date,
    required num amount,
    String description = '',
    int deletedAt = 0,
  }) {
    final spec = kEntitiesByName['transactions']!;
    db.upsert(
      spec,
      id,
      PayloadNormalizer.normalize(spec, {
        'id': id,
        'type': type,
        'cash_register_id': register,
        'date': date,
        'amount': amount,
        'description': description,
        'branch_id': 'b-1',
        'deleted_at': deletedAt,
      }),
    );
  }

  setUp(() {
    db = LocalDatabase.open(':memory:');
    query = TransactionsQuery(db);
  });

  tearDown(() => db.dispose());

  List<String> ids(List<Map<String, dynamic>> rows) =>
      rows.map((e) => e['id'] as String).toList();

  group('the transactions list', () {
    setUp(() {
      tx('t1', type: 'income', register: 'r1', date: '2026-08-10T09:00:00Z', amount: 15000, description: 'Sale');
      tx('t2', type: 'expense', register: 'r1', date: '2026-08-11T10:00:00Z', amount: 5000, description: 'Supplies');
      tx('t3', type: 'income', register: 'r2', date: '2026-08-12T11:00:00Z', amount: 22000, description: 'Catering order');
      // soft-deleted: arrives with a real epoch, must never be listed
      tx('t4', type: 'income', register: 'r1', date: '2026-08-13T12:00:00Z', amount: 8000, description: 'Void', deletedAt: 1750000000);
    });

    test('lists live rows newest first, excluding soft-deleted', () {
      expect(ids(query.transactions(limit: 10, offset: 0)), ['t3', 't2', 't1']);
    });

    test('total is the match count, not the page size', () {
      expect(query.transactionsCount(), 3);
      // and a short page does not change it
      expect(query.transactions(limit: 1, offset: 0), hasLength(1));
      expect(query.transactionsCount(), 3);
    });

    test('filters by type', () {
      expect(ids(query.transactions(limit: 10, offset: 0, type: 'income')), ['t3', 't1']);
      expect(query.transactionsCount(type: 'income'), 2);
    });

    test('filters by cash register', () {
      expect(ids(query.transactions(limit: 10, offset: 0, cashRegisterId: 'r1')), ['t2', 't1']);
    });

    test('type and register combine', () {
      expect(ids(query.transactions(limit: 10, offset: 0, type: 'income', cashRegisterId: 'r1')), ['t1']);
    });

    test('search matches description', () {
      expect(ids(query.transactions(limit: 10, offset: 0, search: 'Cater')), ['t3']);
    });

    test('search matches the amount a cashier types', () {
      expect(ids(query.transactions(limit: 10, offset: 0, search: '22000')), ['t3']);
    });

    test('search treats % and _ literally, not as wildcards', () {
      tx('t5', type: 'income', register: 'r1', date: '2026-08-14T09:00:00Z', amount: 100, description: '50% deposit');
      expect(ids(query.transactions(limit: 10, offset: 0, search: '50%')), ['t5']);
    });

    test('paginates with offset', () {
      expect(ids(query.transactions(limit: 2, offset: 0)), ['t3', 't2']);
      expect(ids(query.transactions(limit: 2, offset: 2)), ['t1']);
    });
  });
}
