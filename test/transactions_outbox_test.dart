/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — replaying a queued cash-ledger
/// write.
///
/// Two halves, deliberately. The first drives the handlers directly: given an
/// operation, which endpoint is called and with what body. The second drives
/// the whole path — repository, queue, drainer — because the handlers being
/// individually right says nothing about a movement being sent exactly once,
/// which on a cash ledger is the property that actually matters.
///
/// The `transactions/create` handler is the one with a decision to make: the
/// ledger's create is two endpoints on the server, an income/expense movement
/// and a register-to-register transfer, and the queued body is what tells them
/// apart. Getting that dispatch wrong would post a transfer as an expense.
library;

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/transactions_outbox.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/transactions_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

/// Only the six methods the handlers call are real; every other member of this
/// wide interface is a `noSuchMethod` forwarder that throws if a handler ever
/// reaches for it — which is itself part of what is asserted.
class _FakeMainRepository implements MainRepository {
  Either<Failure, bool> result = const Right(true);

  /// What a create endpoint hands back on success. The three creates return
  /// the row the server wrote so the drainer can swap the provisional one for
  /// it; [result]'s failures still apply to them, so a test that sets a `Left`
  /// gets that failure from every endpoint alike.
  Map<String, dynamic> createdRow = const {'id': 'server-id'};

  Either<Failure, Map<String, dynamic>> get _created =>
      result.fold(Left.new, (_) => Right(createdRow));

  /// One entry per request that actually left, in order, so "sent once" is a
  /// countable claim rather than a hopeful one.
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<Either<Failure, Map<String, dynamic>>> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  ) async {
    calls.add('income-expense');
    bodies.add(body);
    return _created;
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> createTransferTransaction(
    Map<String, dynamic> body,
  ) async {
    calls.add('transfer');
    bodies.add(body);
    return _created;
  }

  @override
  Future<Either<Failure, bool>> updateTransaction(
    String id,
    Map<String, dynamic> body,
  ) async {
    calls.add('update:$id');
    bodies.add(body);
    return result;
  }

  @override
  Future<Either<Failure, bool>> deleteTransaction(String id) async {
    calls.add('delete:$id');
    return result;
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> createTransactionGroup(
    String name,
  ) async {
    calls.add('group-create:$name');
    return _created;
  }

  @override
  Future<Either<Failure, bool>> updateTransactionGroup(
    String id,
    String name,
  ) async {
    calls.add('group-update:$id:$name');
    return result;
  }

  @override
  Future<Either<Failure, bool>> deleteTransactionGroup(String id) async {
    calls.add('group-delete:$id');
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OutboxOperation _op({
  String entity = 'transactions',
  String action = 'create',
  String? entityId = 't-1',
  Map<String, dynamic> payload = const {},
}) =>
    OutboxOperation(
      id: 'op-1',
      entity: entity,
      action: action,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.utc(2026, 8, 20),
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  group('which endpoint a queued create reaches', () {
    late _FakeMainRepository remote;
    late OutboxExecutors executors;

    setUp(() {
      remote = _FakeMainRepository();
      executors = OutboxExecutors();
      registerTransactionsOutboxHandlers(executors, remote);
    });

    Future<OutboxExecutionResult> send(OutboxOperation op) =>
        executors.resolve(op)!.send(op);

    test('an income/expense body goes to the income-expense endpoint', () async {
      const body = {
        'type': 'expense',
        'cash_register_id': 'reg-1',
        'amount': '5000',
      };
      final result = await send(_op(payload: body));

      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['income-expense']);
      expect(remote.bodies.single, body);
    });

    test('a from/to body goes to the transfer endpoint', () async {
      const body = {
        'from_cash_register_id': 'reg-1',
        'to_cash_register_id': 'reg-2',
        'amount': '50000',
      };
      final result = await send(_op(payload: body));

      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['transfer']);
      expect(remote.bodies.single, body);
    });

    test('a body that is neither shape is permanent, not retried', () async {
      // No amount of retrying turns an unaddressable request into a valid one,
      // and retrying it would block everything queued behind it.
      final result = await send(_op(payload: const {'amount': '100'}));
      expect(result.outcome, OutboxOutcome.permanent);
      expect(remote.calls, isEmpty);
    });

    test('a create carries the row the server wrote', () async {
      // The endpoint assigns the id, so the local row is provisional until
      // this comes back. Carrying the response is what lets the drainer swap
      // the provisional row for the server's in place — and repoint anything
      // still queued that quoted the provisional id — instead of deleting the
      // movement the operator just entered and waiting for the next pull.
      final result = await send(_op(payload: const {'type': 'income'}));
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(result.serverRow, {'id': 'server-id'});
    });

    test('a transfer create carries its row too', () async {
      final result = await send(_op(payload: const {
        'from_cash_register_id': 'reg-1',
        'to_cash_register_id': 'reg-2',
        'amount': '100',
      }));
      expect(remote.calls, ['transfer']);
      expect(result.serverRow, {'id': 'server-id'});
    });
  });

  group('update and delete', () {
    late _FakeMainRepository remote;
    late OutboxExecutors executors;

    setUp(() {
      remote = _FakeMainRepository();
      executors = OutboxExecutors();
      registerTransactionsOutboxHandlers(executors, remote);
    });

    Future<OutboxExecutionResult> send(OutboxOperation op) =>
        executors.resolve(op)!.send(op);

    test('an update addresses its row and sends its patch', () async {
      final result = await send(
        _op(action: 'update', payload: const {'amount': '2500'}),
      );
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['update:t-1']);
      expect(remote.bodies.single, {'amount': '2500'});
    });

    test('an update with no id is permanent by construction', () async {
      final result = await send(_op(action: 'update', entityId: null));
      expect(result.outcome, OutboxOutcome.permanent);
      expect(remote.calls, isEmpty);
    });

    test('a delete whose target is already gone counts as done', () async {
      // Scoped to delete: for an update a 404 means the write was lost, which
      // is the opposite of done.
      remote.result = const Left(NotFoundFailure());
      final result = await send(_op(action: 'delete'));
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['delete:t-1']);
    });

    test('a delete refused on the merits is not swallowed', () async {
      remote.result = const Left(ValidationFailure());
      final result = await send(_op(action: 'delete'));
      expect(result.outcome, OutboxOutcome.permanent);
    });
  });

  group('transaction groups', () {
    late _FakeMainRepository remote;
    late OutboxExecutors executors;

    setUp(() {
      remote = _FakeMainRepository();
      executors = OutboxExecutors();
      registerTransactionsOutboxHandlers(executors, remote);
    });

    Future<OutboxExecutionResult> send(OutboxOperation op) =>
        executors.resolve(op)!.send(op);

    OutboxOperation groupOp({
      String action = 'create',
      String? entityId = 'g-1',
      Map<String, dynamic> payload = const {'name': 'Kommunal'},
    }) =>
        _op(
          entity: 'group_transactions',
          action: action,
          entityId: entityId,
          payload: payload,
        );

    test('a create sends the bare name the endpoint takes', () async {
      final result = await send(groupOp());
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['group-create:Kommunal']);
    });

    test('a create with no name is permanent', () async {
      final result = await send(groupOp(payload: const {}));
      expect(result.outcome, OutboxOutcome.permanent);
      expect(remote.calls, isEmpty);
    });

    test('a rename sends both id and name', () async {
      final result = await send(
        groupOp(action: 'update', payload: const {'name': 'Yangi'}),
      );
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['group-update:g-1:Yangi']);
    });

    test('a delete addresses its row and tolerates a 404', () async {
      remote.result = const Left(NotFoundFailure());
      final result = await send(groupOp(action: 'delete'));
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['group-delete:g-1']);
    });
  });

  group('transient versus final', () {
    late _FakeMainRepository remote;
    late OutboxExecutors executors;

    setUp(() {
      remote = _FakeMainRepository();
      executors = OutboxExecutors();
      registerTransactionsOutboxHandlers(executors, remote);
    });

    test('no connection keeps the movement in the queue', () async {
      remote.result = const Left(ConnectionFailure());
      final op = _op(payload: const {'type': 'income'});
      final result = await executors.resolve(op)!.send(op);
      expect(result.outcome, OutboxOutcome.retry);
    });

    test('a rejection on the merits stops', () async {
      remote.result = const Left(ValidationFailure());
      final op = _op(payload: const {'type': 'income'});
      final result = await executors.resolve(op)!.send(op);
      expect(result.outcome, OutboxOutcome.permanent);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The whole path: repository → queue → drainer → endpoint
  // ───────────────────────────────────────────────────────────────────────
  group('a movement is sent once', () {
    late LocalDatabase db;
    late OutboxStore store;
    late TransactionsRepository repo;
    late _FakeMainRepository remote;
    late OutboxDrainer drainer;
    late DateTime now;

    setUp(() {
      db = LocalDatabase.open(':memory:');
      now = DateTime.utc(2026, 8, 20, 12);
      store = OutboxStore(db, now: () => now);
      final applier = ChangeApplier(db);
      repo = TransactionsRepositoryImpl(
        replicaDb: db,
        writer: LocalWriter(db: db, applier: applier, outbox: store),
      );
      remote = _FakeMainRepository();
      final executors = OutboxExecutors();
      registerTransactionsOutboxHandlers(executors, remote);
      drainer = OutboxDrainer(
        store: store,
        executors: executors,
        db: db,
        applier: applier,
      );
    });

    tearDown(() => db.dispose());

    Map<String, dynamic> body() => const {
          'type': 'income',
          'cash_register_id': 'reg-1',
          'amount': '15000',
          'description': 'Kunlik tushum',
        };

    test('one create, one request, and no second one on the next drain', () async {
      repo.createIncomeExpenseTransaction(body());

      final first = await drainer.drain();
      expect(first.sent, 1);
      expect(remote.calls, ['income-expense']);
      expect(store.depth, 0);

      // The drainer runs on a 60s tick; a succeeded operation is gone, so the
      // next pass has nothing to resend. This is the assertion that stops a
      // cash movement being posted twice by the queue itself.
      final second = await drainer.drain();
      expect(second.total, 0);
      expect(remote.calls, ['income-expense']);
    });

    test('a retried create sends the same body and still posts once', () async {
      repo.createIncomeExpenseTransaction(body());
      final queuedId = store.pending().single.id;

      remote.result = const Left(ConnectionFailure());
      final failed = await drainer.drain();
      expect(failed.retrying, 1);
      // Still queued, under the same operation id — the retry is the same
      // operation, not a second one.
      expect(store.pending().single.id, queuedId);

      now = now.add(const Duration(minutes: 5)); // past the backoff
      remote.result = const Right(true);
      final sent = await drainer.drain();

      expect(sent.sent, 1);
      expect(store.depth, 0);
      // Two attempts, one movement: the body is the one captured at write
      // time, never re-derived from a row that may have changed since.
      expect(remote.calls, ['income-expense', 'income-expense']);
      expect(remote.bodies.first, remote.bodies.last);
      expect(remote.bodies.last, body());
    });

    test('the provisional row is released once the create lands', () async {
      // The documented no-id branch: the endpoint's reply does not reach us
      // through MainRepository, so the drainer will not keep a row under an id
      // it cannot justify. The server's version arrives by replication.
      repo.createIncomeExpenseTransaction(body());
      final localId =
          db.selectData('SELECT data FROM transactions').single['id'] as String;
      expect(db.isProvisional('transactions', localId), isTrue);

      await drainer.drain();

      expect(db.byId('transactions', localId), isNull);
      expect(db.isProvisional('transactions', localId), isFalse);
    });

    test('a transfer drains to the transfer endpoint, once', () async {
      repo.createTransferTransaction(const {
        'from_cash_register_id': 'reg-1',
        'to_cash_register_id': 'reg-2',
        'amount': '50000',
      });

      await drainer.drain();

      expect(remote.calls, ['transfer']);
      expect(remote.bodies.single, {
        'from_cash_register_id': 'reg-1',
        'to_cash_register_id': 'reg-2',
        'amount': '50000',
      });
      expect(store.depth, 0);
    });

    test('an edit and a delete drain in the order they were made', () async {
      repo.updateTransaction('t-9', {'amount': '2500'});
      repo.deleteTransaction('t-9');

      await drainer.drain();

      expect(remote.calls, ['update:t-9', 'delete:t-9']);
    });
  });
}
