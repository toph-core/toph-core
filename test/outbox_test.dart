/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — outbox tests.
///
/// The outbox is the highest-stakes code in the application: a bug here either
/// loses a cashier's write or sends it twice. These cover the ordering,
/// retry and quarantine rules that keep both from happening.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';

/// Drives [OutboxStore]'s clock so backoff windows are exact, not slept through.
class FakeClock {
  DateTime now = DateTime.utc(2026, 1, 1, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// Records what was sent and replies from a script.
class ScriptedExecutor {
  final List<OutboxOperation> sent = [];
  final Map<String, List<OutboxExecutionResult>> _replies;
  final OutboxExecutionResult _fallback;

  ScriptedExecutor({
    Map<String, List<OutboxExecutionResult>>? replies,
    OutboxExecutionResult fallback = const OutboxExecutionResult.succeeded(),
  })  : _replies = replies ?? {},
        _fallback = fallback;

  Future<OutboxExecutionResult> call(OutboxOperation op) async {
    sent.add(op);
    final queue = _replies[op.entityId ?? op.id];
    if (queue != null && queue.isNotEmpty) return queue.removeAt(0);
    return _fallback;
  }
}

Map<String, dynamic> goodsRow(String id, {String name = 'Item'}) => {
      'id': id,
      'name': name,
      'category_id': 'c-1',
      'price': 1000.00,
    };

void main() {
  late LocalDatabase db;
  late ChangeApplier applier;
  late FakeClock clock;
  late OutboxStore store;
  late OutboxExecutors executors;
  late LocalWriter writer;
  late OutboxDrainer drainer;

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
    clock = FakeClock();
    store = OutboxStore(db, now: clock.call);
    executors = OutboxExecutors();
    writer = LocalWriter(db: db, applier: applier, outbox: store);
    drainer = OutboxDrainer(
      store: store,
      executors: executors,
      db: db,
      applier: applier,
    );
  });

  tearDown(() => db.dispose());

  void registerGoods(ScriptedExecutor exec, {String action = 'update'}) {
    executors.register('goods', action, OutboxHandler(send: exec.call));
  }

  group('LocalWriter', () {
    test('a write lands in the replica and the queue atomically', () {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));

      expect(db.byId('goods', 'g-1'), isNotNull);
      expect(store.depth, 1);
      // Guarded, so a pull mid-flight cannot revert it.
      expect(db.isPending('goods', 'g-1'), isTrue);
    });

    test('the queued payload defaults to the row and can differ from it', () {
      writer.write(
        entity: 'goods',
        id: 'g-1',
        row: goodsRow('g-1', name: 'Local'),
        action: 'archive',
        request: {'reason': 'discontinued'},
      );

      final op = store.pending().single;
      expect(op.action, 'archive');
      expect(op.payload, {'reason': 'discontinued'});
      expect(db.byId('goods', 'g-1')!['name'], 'Local');
    });

    test('delete removes the row and queues the delete', () {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      writer.delete(entity: 'goods', id: 'g-1');

      expect(db.byId('goods', 'g-1'), isNull);
      // Still guarded — an in-flight pull must not resurrect it.
      expect(db.isPending('goods', 'g-1'), isTrue);
      expect(store.pending().last.action, 'delete');
    });

    test('a failed write leaves neither a row nor a queue entry', () {
      expect(
        () => writer.write(entity: 'not_an_entity', id: 'x', row: const {}),
        throwsArgumentError,
      );
      expect(store.depth, 0);
    });
  });

  group('ordering', () {
    test('drains in creation order, not grouped by type', () async {
      // The Hive queue this replaces grouped by operation type, which reorders
      // a pause→resume→pause sequence into something that never happened.
      for (final id in ['a', 'b', 'c']) {
        writer.write(entity: 'goods', id: 'g-$id', row: goodsRow('g-$id'));
        clock.advance(const Duration(seconds: 1));
      }
      final exec = ScriptedExecutor();
      registerGoods(exec);

      await drainer.drain();

      expect(exec.sent.map((o) => o.entityId), ['g-a', 'g-b', 'g-c']);
      expect(store.depth, 0);
    });

    test('a failure blocks its own chain but not unrelated ones', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      clock.advance(const Duration(seconds: 1));
      writer.write(
        entity: 'goods',
        id: 'g-1',
        row: goodsRow('g-1', name: 'second edit'),
        operationId: 'op-2',
      );
      clock.advance(const Duration(seconds: 1));
      writer.write(entity: 'goods', id: 'g-9', row: goodsRow('g-9'));

      final exec = ScriptedExecutor(replies: {
        'g-1': [const OutboxExecutionResult.retry('boom')],
      });
      registerGoods(exec);

      final result = await drainer.drain();

      // g-1's first op failed; its second is held back to preserve order.
      // g-9 is a different chain and goes through regardless.
      expect(result.retrying, 1);
      expect(result.blocked, 1);
      expect(result.sent, 1);
      expect(exec.sent.map((o) => o.entityId), ['g-1', 'g-9']);
    });

    test('a custom chain key groups children under their aggregate', () async {
      // order_items must not overtake the order they belong to.
      executors.register(
        'orders',
        'create',
        OutboxHandler(
          send: (op) async => const OutboxExecutionResult.retry('offline'),
        ),
      );
      final itemsExec = ScriptedExecutor();
      executors.register(
        'order_items',
        'create',
        OutboxHandler(
          send: itemsExec.call,
          chainKey: (op) => op.payload['order_id'] as String,
        ),
      );

      writer.write(
        entity: 'orders',
        id: 'o-1',
        row: {'id': 'o-1', 'table_id': 't-1'},
        action: 'create',
      );
      clock.advance(const Duration(seconds: 1));
      writer.write(
        entity: 'order_items',
        id: 'i-1',
        row: {'id': 'i-1', 'order_id': 'o-1', 'good_id': 'g-1', 'quantity': 1},
        action: 'create',
      );

      final result = await drainer.drain();

      // The chain key resolves the item onto the order's chain, so the item
      // never reaches a server that has not heard of the order.
      expect(result.retrying, 1);
      expect(result.blocked, 1);
      expect(itemsExec.sent, isEmpty);
    });
  });

  group('retry and backoff', () {
    test('a retry is not eligible again until its backoff elapses', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      final exec = ScriptedExecutor(replies: {
        'g-1': [const OutboxExecutionResult.retry('offline')],
      });
      registerGoods(exec);

      await drainer.drain();
      expect(store.depth, 1);
      expect(store.ready(), isEmpty, reason: 'backing off');

      clock.advance(const Duration(minutes: 5));
      expect(store.ready(), hasLength(1));

      await drainer.drain();
      expect(store.depth, 0, reason: 'second attempt succeeds');
      expect(exec.sent, hasLength(2));
    });

    test('backoff stays within the configured envelope', () {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      final id = store.pending().single.id;

      for (var i = 1; i < OutboxStore.maxAttempts; i++) {
        store.markFailed(id, 'attempt $i');
        final op = store.pending().single;
        final wait = op.nextAttemptAt.difference(clock.now);
        expect(wait, greaterThanOrEqualTo(Duration.zero));
        expect(wait, lessThanOrEqualTo(OutboxStore.maxBackoff));
      }
    });

    test('quarantines after the attempt budget is spent', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      final exec = ScriptedExecutor(
        fallback: const OutboxExecutionResult.retry('still offline'),
      );
      registerGoods(exec);

      for (var i = 0; i < OutboxStore.maxAttempts; i++) {
        await drainer.drain();
        clock.advance(const Duration(minutes: 5));
      }

      expect(store.depth, 0);
      expect(store.quarantineDepth, 1);
      expect(store.quarantined().single.lastError, 'still offline');
    });

    test('an executor that throws is treated as retryable', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      executors.register(
        'goods',
        'update',
        OutboxHandler(send: (_) async => throw StateError('socket closed')),
      );

      final result = await drainer.drain();

      expect(result.retrying, 1);
      expect(store.quarantineDepth, 0);
      expect(store.pending().single.lastError, contains('socket closed'));
    });

    test('clearBackoff makes everything eligible again', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      registerGoods(ScriptedExecutor(
        fallback: const OutboxExecutionResult.retry('offline'),
      ));
      await drainer.drain();
      expect(store.ready(), isEmpty);

      store.clearBackoff();
      expect(store.ready(), hasLength(1));
    });
  });

  group('quarantine', () {
    test('a permanent rejection quarantines immediately', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      registerGoods(ScriptedExecutor(
        fallback: const OutboxExecutionResult.permanent('422 invalid price'),
      ));

      final result = await drainer.drain();

      expect(result.quarantined, 1);
      expect(store.quarantineDepth, 1);
      expect(store.depth, 0);
    });

    test('quarantining releases the local row to replication', () async {
      // Otherwise a write the server never accepted would be shielded from
      // every future pull, leaving this terminal with a private truth.
      writer.write(
        entity: 'goods',
        id: 'g-1',
        row: goodsRow('g-1', name: 'Rejected edit'),
      );
      expect(db.isPending('goods', 'g-1'), isTrue);

      registerGoods(ScriptedExecutor(
        fallback: const OutboxExecutionResult.permanent('rejected'),
      ));
      await drainer.drain();

      expect(db.isPending('goods', 'g-1'), isFalse);

      // Replication can now correct it.
      applier.applyPullResponse({
        'next_sync_cursor': 5,
        'changes': {
          'goods': {
            'updated': [goodsRow('g-1', name: 'Server version')],
          },
        },
      });
      expect(db.byId('goods', 'g-1')!['name'], 'Server version');
    });

    test('an operation with no handler is quarantined, not retried', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      executors.register('categories', 'update',
          OutboxHandler(send: (_) async => const OutboxExecutionResult.succeeded()));

      final result = await drainer.drain();

      expect(result.quarantined, 1);
      expect(store.quarantined().single.lastError, contains('no executor'));
    });

    test('retryQuarantined puts it back with a fresh budget', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      registerGoods(ScriptedExecutor(
        fallback: const OutboxExecutionResult.permanent('rejected'),
      ));
      await drainer.drain();
      final id = store.quarantined().single.id;

      store.retryQuarantined(id);

      expect(store.quarantineDepth, 0);
      expect(store.depth, 1);
      expect(store.ready().single.attempts, 0);
    });

    test('dismissQuarantined discards it', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      registerGoods(ScriptedExecutor(
        fallback: const OutboxExecutionResult.permanent('rejected'),
      ));
      await drainer.drain();

      store.dismissQuarantined(store.quarantined().single.id);

      expect(store.quarantineDepth, 0);
      expect(store.depth, 0);
    });
  });

  group('success handling', () {
    test('success clears the queue entry and the pending guard', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      registerGoods(ScriptedExecutor());

      await drainer.drain();

      expect(store.depth, 0);
      expect(db.isPending('goods', 'g-1'), isFalse);
    });

    test('a returned server row is applied over the local one', () async {
      // Server-assigned fields — a bill number, a computed total — converge
      // immediately instead of waiting for the next pull.
      writer.write(
        entity: 'goods',
        id: 'g-1',
        row: goodsRow('g-1', name: 'Local'),
      );
      executors.register(
        'goods',
        'update',
        OutboxHandler(
          send: (_) async => OutboxExecutionResult.succeeded(
            serverRow: goodsRow('g-1', name: 'Canonical'),
          ),
        ),
      );

      await drainer.drain();

      expect(db.byId('goods', 'g-1')!['name'], 'Canonical');
    });

    test('a replay the server already applied counts as success', () async {
      // CreateOrder returns the existing order for a known client id; PayOrder
      // returns the order unchanged when already paid. Both mean the desired
      // state holds, so the operation must leave the queue.
      writer.write(
        entity: 'goods',
        id: 'g-1',
        row: goodsRow('g-1'),
        action: 'create',
      );
      executors.register(
        'goods',
        'create',
        OutboxHandler(
          send: (_) async => const OutboxExecutionResult.succeeded(),
        ),
      );

      await drainer.drain();
      await drainer.drain();

      expect(store.depth, 0);
    });
  });

  group('drain guards', () {
    test('an empty registry leaves the queue untouched', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));

      final result = await drainer.drain();

      // Phase 2 ships with no handlers; the queue must wait for Phase 4, not
      // be quarantined for want of one.
      expect(result.total, 0);
      expect(store.depth, 1);
      expect(store.quarantineDepth, 0);
    });

    test('overlapping drains collapse', () async {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      final exec = ScriptedExecutor();
      registerGoods(exec);

      final results = await Future.wait([drainer.drain(), drainer.drain()]);

      expect(exec.sent, hasLength(1));
      expect(results.map((r) => r.total), containsAll([1, 0]));
    });

    test('depth and hasWork reflect the queue', () {
      expect(store.hasWork, isFalse);
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      writer.write(entity: 'goods', id: 'g-2', row: goodsRow('g-2'));
      expect(store.depth, 2);
      expect(store.hasWork, isTrue);
    });
  });

  group('durability', () {
    test('a queued operation survives with its payload intact', () {
      writer.write(
        entity: 'goods',
        id: 'g-1',
        row: goodsRow('g-1'),
        action: 'create',
        request: {'id': 'g-1', 'name': 'Pizza', 'price': '15000'},
      );

      final op = store.pending().single;
      expect(op.entity, 'goods');
      expect(op.action, 'create');
      expect(op.entityId, 'g-1');
      expect(op.payload['name'], 'Pizza');
      expect(op.status, OutboxStatus.pending);
      expect(op.attempts, 0);
    });

    test('clearAll empties the queue with the replica', () {
      writer.write(entity: 'goods', id: 'g-1', row: goodsRow('g-1'));
      expect(store.depth, 1);

      db.clearAll();

      expect(store.depth, 0);
      expect(store.quarantineDepth, 0);
    });
  });
}
