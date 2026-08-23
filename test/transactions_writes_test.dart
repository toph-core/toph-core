/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2/4 — the transactions screen's
/// seven writes, on the outbox.
///
/// Every one of them used to be a bare `POST`/`PUT`/`DELETE` with no local row
/// and nothing queued, so a cashier who logged a cash movement while the
/// terminal was offline simply lost it. What each must do now is the same shape
/// the staff and halls screens already prove: the row the operator sees and the
/// operation that will carry it to the server commit together, and the call
/// returns without touching the network.
///
/// The money assertions are the ones worth reading twice. `amount` is a
/// Postgres `numeric`, which arrives from the change feed as a JSON number and
/// from REST as a string; a row this repository authors has to land in the same
/// shape as a replicated one or the two would decode differently through the
/// same model.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/transactions_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

void main() {
  late LocalDatabase db;
  late OutboxStore store;
  late TransactionsRepository repo;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    store = OutboxStore(db);
    repo = TransactionsRepositoryImpl(
      replicaDb: db,
      writer: LocalWriter(
        db: db,
        applier: ChangeApplier(db),
        outbox: store,
      ),
    );
  });

  tearDown(() => db.dispose());

  /// The one queued operation, insisting there is exactly one — a write that
  /// enqueues twice is as wrong as one that enqueues not at all.
  OutboxOperation onlyOp() {
    final ops = store.pending();
    expect(ops, hasLength(1), reason: 'expected exactly one queued operation');
    return ops.single;
  }

  Map<String, dynamic> onlyRow(String entity) {
    final rows = db.selectData('SELECT data FROM $entity');
    expect(rows, hasLength(1), reason: 'expected exactly one $entity row');
    return rows.single;
  }

  Map<String, dynamic> incomeBody({String amount = '15000'}) => {
        'type': 'income',
        'cash_register_id': 'reg-1',
        'group_transaction_id': 'grp-1',
        'amount': amount,
        'description': 'Kunlik tushum',
        'pay_type': 'cash',
        'date': '2026-08-20T09:00:00.000Z',
      };

  group('an income or expense movement', () {
    test('lands a local row and queues the create, in one call', () {
      final result = repo.createIncomeExpenseTransaction(incomeBody());
      expect(result.isRight(), isTrue);

      final row = onlyRow('transactions');
      expect(row['type'], 'income');
      expect(row['cash_register_id'], 'reg-1');
      expect(row['description'], 'Kunlik tushum');

      final op = onlyOp();
      expect(op.entity, 'transactions');
      expect(op.action, 'create');
      expect(op.entityId, row['id']);
    });

    test('the row is provisional, because the endpoint assigns the id', () {
      repo.createIncomeExpenseTransaction(incomeBody());
      final id = onlyRow('transactions')['id'] as String;
      expect(db.isProvisional('transactions', id), isTrue);
    });

    test('the queued body is the request, not the local row', () {
      // The invented id must not travel: the server assigns its own, and
      // sending ours would be noise at best and a rejection at worst.
      repo.createIncomeExpenseTransaction(incomeBody());
      final op = onlyOp();
      expect(op.payload.containsKey('id'), isFalse);
      expect(op.payload, incomeBody());
    });

    test('it shows up in the ledger read the screen consumes', () {
      repo.createIncomeExpenseTransaction(incomeBody());
      final page = repo.getTransactions(limit: 20, offset: 0);
      expect(page.total, 1);
      expect(page.items.single['type'], 'income');
    });

    test('the write reaches an already-open watcher', () async {
      final seen = <int>[];
      final sub = repo
          .watchTransactions(limit: 20, offset: 0)
          .listen((page) => seen.add(page.total));
      await Future<void>.delayed(Duration.zero);

      repo.createIncomeExpenseTransaction(incomeBody());
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });

  group('money keeps the shape a replicated row has', () {
    /// What the change feed would put on disk for the same movement: a raw
    /// Postgres row, whose `numeric` is a JSON number.
    String replicatedAmount(num value) => PayloadNormalizer.normalize(
          kEntitiesByName['transactions']!,
          {'id': 't-1', 'amount': value},
        )['amount'] as String;

    test('a trailing-zero string is canonicalised, not stored verbatim', () {
      repo.createIncomeExpenseTransaction(incomeBody(amount: '15000.00'));
      expect(onlyRow('transactions')['amount'], '15000');
      expect(onlyRow('transactions')['amount'], replicatedAmount(15000.00));
    });

    test('a fractional amount keeps its value', () {
      repo.createIncomeExpenseTransaction(incomeBody(amount: '4200.50'));
      expect(onlyRow('transactions')['amount'], '4200.5');
      expect(onlyRow('transactions')['amount'], replicatedAmount(4200.50));
    });

    test('a numeric amount is rendered the same way a string one is', () {
      repo.createIncomeExpenseTransaction({
        ...incomeBody(),
        'amount': 15000,
      });
      expect(onlyRow('transactions')['amount'], '15000');
    });

    test('the amount is always a String, so one model parses both sources', () {
      repo.createIncomeExpenseTransaction({...incomeBody(), 'amount': 900});
      expect(onlyRow('transactions')['amount'], isA<String>());
    });

    test('an unparseable amount is left as typed for the server to reject', () {
      // Silently coercing it to 0 would post a movement the operator never
      // asked for.
      repo.createIncomeExpenseTransaction({...incomeBody(), 'amount': 'abc'});
      expect(onlyRow('transactions')['amount'], 'abc');
    });

    test('the request keeps whatever the screen composed', () {
      repo.createIncomeExpenseTransaction(incomeBody(amount: '15000.00'));
      expect(onlyOp().payload['amount'], '15000.00');
    });
  });

  group('a transfer between cash registers', () {
    Map<String, dynamic> transferBody() => {
          'from_cash_register_id': 'reg-1',
          'to_cash_register_id': 'reg-2',
          'amount': '50000',
          'description': 'Smena topshirig\'i',
          'pay_type': 'cash',
          'date': '2026-08-20T18:00:00.000Z',
        };

    test('writes the sending leg, shaped the way the server shapes it', () {
      repo.createTransferTransaction(transferBody());

      final row = onlyRow('transactions');
      expect(row['type'], 'transfer_expense');
      expect(row['cash_register_id'], 'reg-1');
      expect(row['to_cash_register_id'], 'reg-2');
      // The request's own key is not a column on the expense row; the server's
      // CreateTransfer puts the sender in `cash_register_id`.
      expect(row.containsKey('from_cash_register_id'), isFalse);
    });

    test('only one row: the receiving leg is the server\'s to create', () {
      // Mirroring it would mean inventing an id for a row the server owns —
      // the same call MenuAdminLocalRepository makes about a good's
      // calculations. It arrives on the next pull.
      repo.createTransferTransaction(transferBody());
      expect(db.selectData('SELECT data FROM transactions'), hasLength(1));
    });

    test('queues one create carrying the transfer request verbatim', () {
      repo.createTransferTransaction(transferBody());
      final op = onlyOp();
      expect(op.entity, 'transactions');
      expect(op.action, 'create');
      expect(op.payload, transferBody());
    });
  });

  group('editing an existing movement', () {
    setUp(() {
      final spec = kEntitiesByName['transactions']!;
      db.upsert(
        spec,
        't-1',
        PayloadNormalizer.normalize(spec, {
          'id': 't-1',
          'type': 'expense',
          'cash_register_id': 'reg-1',
          'group_transaction_id': 'grp-1',
          'amount': 1000,
          'description': 'Original',
          'date': '2026-08-19T09:00:00Z',
          'branch_id': 'b-1',
        }),
      );
    });

    test('merges over the stored row rather than replacing it', () {
      repo.updateTransaction('t-1', {
        'amount': '2500',
        'description': 'Tuzatildi',
      });

      final row = db.byId('transactions', 't-1')!;
      expect(row['amount'], '2500');
      expect(row['description'], 'Tuzatildi');
      // The dialog sends four fields; the replica must still hold an entity.
      expect(row['type'], 'expense');
      expect(row['cash_register_id'], 'reg-1');
      expect(row['branch_id'], 'b-1');
    });

    test('queues the PUT with only the fields the form owns', () {
      repo.updateTransaction('t-1', {'amount': '2500'});
      final op = onlyOp();
      expect(op.action, 'update');
      expect(op.entityId, 't-1');
      expect(op.payload, {'amount': '2500'});
    });

    test('a deleted row goes immediately and the DELETE is queued', () {
      repo.deleteTransaction('t-1');
      expect(db.byId('transactions', 't-1'), isNull);
      // Guarded, so a pull already in flight cannot resurrect it.
      expect(db.isPending('transactions', 't-1'), isTrue);

      final op = onlyOp();
      expect(op.action, 'delete');
      expect(op.entityId, 't-1');
    });
  });

  group('transaction groups', () {
    test('a create lands a provisional row and queues the name', () {
      expect(repo.createTransactionGroup('Kommunal').isRight(), isTrue);

      final row = onlyRow('group_transactions');
      expect(row['name'], 'Kommunal');
      expect(db.isProvisional('group_transactions', row['id'] as String),
          isTrue);

      final op = onlyOp();
      expect(op.entity, 'group_transactions');
      expect(op.action, 'create');
      expect(op.payload, {'name': 'Kommunal'});
    });

    test('a create is visible to the picker immediately', () {
      repo.createTransactionGroup('Kommunal');
      expect(repo.getTransactionGroups().single['name'], 'Kommunal');
    });

    test('a rename keeps the rest of the row', () {
      final spec = kEntitiesByName['group_transactions']!;
      db.upsert(spec, 'g-1', {
        'id': 'g-1',
        'name': 'Eski',
        'branch_id': 'b-1',
      });

      repo.updateTransactionGroup('g-1', 'Yangi');

      final row = db.byId('group_transactions', 'g-1')!;
      expect(row['name'], 'Yangi');
      expect(row['branch_id'], 'b-1');
      expect(onlyOp().payload, {'name': 'Yangi'});
    });

    test('a delete removes the row and queues the DELETE', () {
      final spec = kEntitiesByName['group_transactions']!;
      db.upsert(spec, 'g-1', {'id': 'g-1', 'name': 'Eski'});

      repo.deleteTransactionGroup('g-1');

      expect(db.byId('group_transactions', 'g-1'), isNull);
      final op = onlyOp();
      expect(op.entity, 'group_transactions');
      expect(op.action, 'delete');
      expect(op.entityId, 'g-1');
    });
  });

  group('nothing on this path can wait on the network', () {
    test('every mutation returns a value, not a future', () {
      // The signature is the guarantee: there is no future to await because
      // there is nothing to wait for. A regression here would not be a slow
      // screen, it would be a lost cash movement.
      expect(repo.createIncomeExpenseTransaction(incomeBody()), isNot(isA<Future>()));
      expect(repo.updateTransaction('t-1', const {}), isNot(isA<Future>()));
      expect(repo.deleteTransaction('t-1'), isNot(isA<Future>()));
      expect(repo.createTransactionGroup('x'), isNot(isA<Future>()));
      expect(repo.updateTransactionGroup('g-1', 'y'), isNot(isA<Future>()));
      expect(repo.deleteTransactionGroup('g-1'), isNot(isA<Future>()));
    });
  });
}
