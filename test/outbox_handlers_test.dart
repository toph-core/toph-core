/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2/4 — the retry-or-quarantine
/// decision, and the handlers that use it.
///
/// This is the rule with the widest blast radius in the outbox: get "transient"
/// wrong and a recoverable write is thrown away; get "permanent" wrong and a
/// doomed write blocks its causal chain through eight retries. Every handler
/// added from here inherits it, so it is worth pinning precisely.
library;

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/failure_outcome.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/halls_tables_outbox.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/users_outbox.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

/// Only the three methods the handlers call are real; every other member of
/// this large interface is a `noSuchMethod` forwarder that would throw if the
/// handlers ever reached for it — which is itself part of what is asserted.
class _FakeMainRepository implements MainRepository {
  Either<Failure, bool> createResult = const Right(true);
  Either<Failure, bool> updateResult = const Right(true);
  Either<Failure, bool> deleteResult = const Right(true);

  final calls = <String>[];

  @override
  Future<Either<Failure, bool>> createUser(Map<String, dynamic> body) async {
    calls.add('create');
    return createResult;
  }

  @override
  Future<Either<Failure, bool>> updateUser(
    String id,
    Map<String, dynamic> body,
  ) async {
    calls.add('update:$id');
    return updateResult;
  }

  @override
  Future<Either<Failure, bool>> deleteUser(String id) async {
    calls.add('delete:$id');
    return deleteResult;
  }

  @override
  Future<Either<Failure, bool>> createHall(Map<String, dynamic> body) async {
    calls.add('createHall');
    return createResult;
  }

  @override
  Future<Either<Failure, bool>> updateHall(
    String id,
    Map<String, dynamic> body,
  ) async {
    calls.add('updateHall:$id');
    return updateResult;
  }

  @override
  Future<Either<Failure, bool>> deleteHall(String id) async {
    calls.add('deleteHall:$id');
    return deleteResult;
  }

  @override
  Future<Either<Failure, bool>> createTable(Map<String, dynamic> body) async {
    calls.add('createTable');
    return createResult;
  }

  @override
  Future<Either<Failure, bool>> updateTable(
    String id,
    Map<String, dynamic> body,
  ) async {
    calls.add('updateTable:$id');
    return updateResult;
  }

  @override
  Future<Either<Failure, bool>> deleteTable(String id) async {
    calls.add('deleteTable:$id');
    return deleteResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OutboxOperation _op({
  String action = 'update',
  String? entityId = 'u-1',
  Map<String, dynamic> payload = const {'is_active': false},
}) =>
    OutboxOperation(
      id: 'op-1',
      entity: 'users',
      action: action,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.utc(2026, 8, 12),
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  group('outcomeForFailure — the server did not answer on the merits', () {
    test('no connection, timeout and 5xx are transient', () {
      expect(outcomeForFailure(const ConnectionFailure()), OutboxOutcome.retry);
      expect(outcomeForFailure(const TimeoutFailure()), OutboxOutcome.retry);
      expect(outcomeForFailure(const ServerFailure()), OutboxOutcome.retry);
    });

    test('401 is transient — a lapsed token is the ordinary case', () {
      // Quarantining here would dump the whole queue the first time an access
      // token expired mid-shift, which is both common and recoverable.
      expect(
        outcomeForFailure(const UnauthorizedFailure()),
        OutboxOutcome.retry,
      );
    });

    test('an unclassified failure is treated as transient', () {
      expect(outcomeForFailure(const UnknownFailure()), OutboxOutcome.retry);
      expect(outcomeForFailure(const OtherFailure()), OutboxOutcome.retry);
    });
  });

  group('outcomeForFailure — the server refused', () {
    test('validation, not-found and 403 are permanent', () {
      expect(
        outcomeForFailure(const ValidationFailure()),
        OutboxOutcome.permanent,
      );
      expect(
        outcomeForFailure(const NotFoundFailure()),
        OutboxOutcome.permanent,
      );
      expect(
        outcomeForFailure(const UnauthenticatedFailure()),
        OutboxOutcome.permanent,
      );
    });

    test("a 4xx body carrying the server's own message is permanent", () {
      expect(
        outcomeForFailure(const MessageFailure('username already taken')),
        OutboxOutcome.permanent,
      );
    });

    test('409 goes to a human rather than being guessed at', () {
      // Either "your earlier attempt landed" or "someone else owns this now",
      // and the status alone does not say which.
      expect(
        outcomeForFailure(const ConflictFailure()),
        OutboxOutcome.permanent,
      );
    });
  });

  group('users handlers', () {
    late OutboxExecutors executors;
    late _FakeMainRepository remote;

    setUp(() {
      executors = OutboxExecutors();
      remote = _FakeMainRepository();
      registerUsersOutboxHandlers(executors, remote);
    });

    test('registers exactly the three staff mutations', () {
      expect(executors.resolve(_op(action: 'create')), isNotNull);
      expect(executors.resolve(_op(action: 'update')), isNotNull);
      expect(executors.resolve(_op(action: 'delete')), isNotNull);
      // Nothing else on `users` is claimed — an unregistered action leaves the
      // drainer dormant rather than being sent down the wrong endpoint.
      expect(executors.resolve(_op(action: 'pay')), isNull);
    });

    test('a successful update reports success and sends no server row', () async {
      final result =
          await executors.resolve(_op())!.send(_op());

      expect(result.outcome, OutboxOutcome.succeeded);
      // These endpoints return nothing worth applying; the row arrives through
      // replication like every other change.
      expect(result.serverRow, isNull);
      expect(remote.calls, ['update:u-1']);
    });

    test('a rejected update quarantines rather than retrying forever', () async {
      remote.updateResult = const Left(ValidationFailure());

      final result = await executors.resolve(_op())!.send(_op());

      expect(result.outcome, OutboxOutcome.permanent);
    });

    test('an update that lost its connection keeps its place', () async {
      remote.updateResult = const Left(ConnectionFailure());

      final result = await executors.resolve(_op())!.send(_op());

      expect(result.outcome, OutboxOutcome.retry);
    });

    test('deleting an already-deleted user is a success', () async {
      // Scoped to delete on purpose: a 404 means "done" here and "the write was
      // lost" for an update, which is why the shared mapping does not decide it.
      remote.deleteResult = const Left(NotFoundFailure());
      final op = _op(action: 'delete');

      final result = await executors.resolve(op)!.send(op);

      expect(result.outcome, OutboxOutcome.succeeded);
    });

    test('an update with no id is permanent without calling the server', () async {
      final op = _op(entityId: null);

      final result = await executors.resolve(op)!.send(op);

      expect(result.outcome, OutboxOutcome.permanent);
      // Retrying could never supply the id, so no attempt is spent finding out.
      expect(remote.calls, isEmpty);
    });

    test('create sends the queued body untouched', () async {
      final op = _op(
        action: 'create',
        entityId: null,
        payload: const {'username': 'yangi', 'role': 'waiter'},
      );

      final result = await executors.resolve(op)!.send(op);

      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['create']);
    });
  });

  group('halls & tables handlers', () {
    late OutboxExecutors executors;
    late _FakeMainRepository remote;

    OutboxOperation op({
      String entity = 'cafe_tables',
      String action = 'update',
      String? entityId = 't-1',
      Map<String, dynamic> payload = const {'pos_x': 300},
    }) =>
        OutboxOperation(
          id: 'op-1',
          entity: entity,
          action: action,
          entityId: entityId,
          payload: payload,
          createdAt: DateTime.utc(2026, 8, 12),
          nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
        );

    setUp(() {
      executors = OutboxExecutors();
      remote = _FakeMainRepository();
      registerHallsTablesOutboxHandlers(executors, remote);
    });

    test('registers create/update/delete for both entities', () {
      for (final entity in ['halls', 'cafe_tables']) {
        for (final action in ['create', 'update', 'delete']) {
          expect(
            executors.resolve(op(entity: entity, action: action)),
            isNotNull,
            reason: '$entity/$action',
          );
        }
      }
    });

    test('each handler reaches the endpoint that matches its entity', () async {
      final table = op();
      await executors.resolve(table)!.send(table);
      final hall = op(entity: 'halls', entityId: 'h-1', payload: const {});
      await executors.resolve(hall)!.send(hall);

      expect(remote.calls, ['updateTable:t-1', 'updateHall:h-1']);
    });

    test('a table operation chains to its hall, not to itself', () {
      // So that if the hall's own create is still failing, its tables wait
      // rather than racing ahead to a server that has never heard of the hall.
      final table = op(payload: const {'hall_id': 'h-9', 'pos_x': 1});

      expect(executors.resolve(table)!.chainKey!(table), 'h-9');
    });

    test('a table with no hall in its payload chains to itself', () {
      final table = op(payload: const {'pos_x': 1});

      expect(executors.resolve(table)!.chainKey!(table), 't-1');
    });

    test('a hall operation takes the default chain', () {
      final hall = op(entity: 'halls', entityId: 'h-1', payload: const {});

      expect(executors.resolve(hall)!.chainKey, isNull);
    });

    test('deleting an already-deleted table is a success', () async {
      remote.deleteResult = const Left(NotFoundFailure());
      final table = op(action: 'delete');

      final result = await executors.resolve(table)!.send(table);

      expect(result.outcome, OutboxOutcome.succeeded);
    });

    test('an update with no id never reaches the server', () async {
      final table = op(entityId: null);

      final result = await executors.resolve(table)!.send(table);

      expect(result.outcome, OutboxOutcome.permanent);
      expect(remote.calls, isEmpty);
    });
  });
}
