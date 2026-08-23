/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the transactions screen's two
/// picker lists, now read from the local replica instead of the Hive store.
///
/// These pin the contract the screen relies on: live rows only (soft-deleted
/// excluded), ordered by name, each list isolated from the other, and returned
/// as the raw server map the pickers decode (`id`, `name`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/db/transaction_pickers_query.dart';

void main() {
  late LocalDatabase db;
  late TransactionPickersQuery pickers;

  // Mirrors how the change applier lands a row: a real epoch in deleted_at is
  // soft-deleted, 0 is live (the applier maps 0 -> NULL on the way in).
  void put(String entity, String id, String name, {int deletedAt = 0}) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(
      spec,
      id,
      PayloadNormalizer.normalize(spec, {
        'id': id,
        'name': name,
        'branch_id': 'b-1',
        'deleted_at': deletedAt,
      }),
    );
  }

  setUp(() {
    db = LocalDatabase.open(':memory:');
    pickers = TransactionPickersQuery(db);
  });

  tearDown(() => db.dispose());

  List<String> names(List<Map<String, dynamic>> rows) =>
      rows.map((e) => e['name'] as String).toList();

  group('transaction group picker', () {
    test('lists live groups ordered by name, soft-deleted excluded', () {
      put('group_transactions', 'g2', 'Utilities');
      put('group_transactions', 'g1', 'Advances');
      put('group_transactions', 'g3', 'Supplies', deletedAt: 1735689600000);
      expect(names(pickers.transactionGroups()), ['Advances', 'Utilities']);
    });

    test('watch emits the current live groups', () async {
      put('group_transactions', 'g1', 'Advances');
      expect(names(await pickers.watchTransactionGroups().first), ['Advances']);
    });

    test('search filters by name, case-insensitively', () {
      put('group_transactions', 'g1', 'Advances');
      put('group_transactions', 'g2', 'Utilities');
      expect(names(pickers.searchTransactionGroups('adv')), ['Advances']);
      expect(names(pickers.searchTransactionGroups('ITIES')), ['Utilities']);
    });

    test('a blank query is the full list, as the endpoint behaved', () {
      put('group_transactions', 'g1', 'Advances');
      put('group_transactions', 'g2', 'Utilities');
      expect(names(pickers.searchTransactionGroups('   ')),
          ['Advances', 'Utilities']);
    });

    test('search excludes soft-deleted groups', () {
      put('group_transactions', 'g1', 'Advances', deletedAt: 1735689600000);
      expect(pickers.searchTransactionGroups('adv'), isEmpty);
    });

    test('% and _ are matched literally, not as wildcards', () {
      put('group_transactions', 'g1', 'Advances');
      put('group_transactions', 'g2', 'VAT 20%');
      expect(names(pickers.searchTransactionGroups('%')), ['VAT 20%']);
      expect(pickers.searchTransactionGroups('_'), isEmpty);
    });
  });

  group('cash register picker', () {
    test('lists live registers ordered by name, soft-deleted excluded', () {
      put('cash_registers', 'r2', 'Bar');
      put('cash_registers', 'r1', 'Aylanma');
      put('cash_registers', 'r3', 'Zal', deletedAt: 1735689600000);
      expect(names(pickers.cashRegisters()), ['Aylanma', 'Bar']);
    });
  });

  test('the two pickers do not bleed into each other', () {
    put('group_transactions', 'g1', 'Advances');
    put('cash_registers', 'r1', 'Bar');
    expect(names(pickers.transactionGroups()), ['Advances']);
    expect(names(pickers.cashRegisters()), ['Bar']);
    // Each row keeps the raw server shape the picker decodes.
    final g = pickers.transactionGroups().single;
    expect(g['id'], 'g1');
    expect(g['name'], 'Advances');
  });
}
