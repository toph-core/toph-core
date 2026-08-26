/// Peer-to-peer propagation of local writes — the half of replication that
/// keeps working with the venue's uplink down.
///
/// `ChangeFeedRelay` (and `change_feed_relay_test.dart` beside this) covers the
/// leader redistributing what it pulled from the cloud. That path is empty when
/// there is no cloud to pull from, which is exactly when a restaurant most
/// needs its terminals to agree. These tests cover the path that fills it.
///
/// Every test wires real `LocalChangeRelay`/`ChangeApplier`/`LocalWriter`
/// instances over real in-memory databases, and moves messages between them
/// **through `toJson`/`tryParse`** rather than by handing objects across. The
/// wire format is part of what is being asserted: a field that serializes but
/// does not parse back would otherwise pass every one of these.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/core/sync/local_change_relay.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/table_timer_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:get_it/get_it.dart';

Map<String, dynamic> goodsRow(String id, {String name = 'Item'}) => {
      'id': id,
      'name': name,
      'category_id': 'c-1',
      'price': 1000.00,
    };

/// One POS terminal: its own database, its own writer, its own relay.
///
/// Nothing is shared between two of these but the [wire] they are attached to,
/// which is the point — two terminals in a venue share a network and nothing
/// else, and a test that let them share a `LocalDatabase` would prove nothing.
class Terminal {
  final String name;
  late final LocalDatabase db;
  late final ChangeApplier applier;
  late final OutboxStore outbox;
  late final LocalWriter writer;
  late final LocalChangeRelay relay;

  /// Frames this terminal put on the network, in order, as JSON strings.
  final List<String> outbound = [];

  Terminal(this.name) {
    db = LocalDatabase.open(':memory:');
    outbox = OutboxStore(db);
    applier = ChangeApplier(
      db,
      onLocalChange: ({
        required String entity,
        required String action,
        required String id,
        Map<String, dynamic>? payload,
      }) =>
          relay.broadcast(
        entity: entity,
        action: action,
        id: id,
        payload: payload,
      ),
    );
    relay = LocalChangeRelay(
      applier: applier,
      db: db,
      send: (msg) => outbound.add(msg.toJson()),
      terminalId: () => name,
    );
    writer = LocalWriter(db: db, applier: applier, outbox: outbox);
  }

  /// Delivers everything this terminal has said to [others], the way the hub
  /// does: through the wire format, and never back to the sender.
  void flushTo(List<Terminal> others) {
    for (final frame in outbound) {
      final msg = LanHubMessage.tryParse(frame);
      expect(msg, isNotNull, reason: '$name emitted an unparseable frame');
      for (final peer in others) {
        // Mirrors `LanHubService._handleRemoteMessage`'s dispatch: routing
        // every frame to `apply` would silently drop timer frames, which is
        // how the first version of this helper hid a real failure.
        switch (msg!.type) {
          case LanHubMessageType.localChange:
            peer.relay.apply(msg);
          case LanHubMessageType.timerAction:
            peer.relay.applyTimer(msg);
          default:
            fail('$name emitted an unexpected frame type: ${msg.type}');
        }
      }
    }
    outbound.clear();
  }

  int get outboxDepth => outbox.pending().length;

  /// Built lazily: most tests here have nothing to do with timers, and the
  /// repository needs a table row and a `PrintQueueService` in GetIt.
  TableTimerLocalRepositoryImpl timers() {
    final spec = kEntitiesByName['cafe_tables']!;
    db.upsert(spec, 't1', {
      'id': 't1',
      'name': 'Bilyard 1',
      'table_type': 'time_based',
      'price_per_hour': '60000',
    });
    return TableTimerLocalRepositoryImpl(
      db,
      writer,
      _FakeOrders(),
      LeaseManager(lanHub: _FakeLanHub(), localDb: db),
      relay: relay,
    );
  }

  Map<String, dynamic>? timerRecord(String orderId) => db.getTableTimer(orderId);

  void dispose() => db.dispose();
}

class _FakeOrders implements OrdersRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakeLanHub implements LanHubService {
  @override
  LanMode get mode => LanMode.disabled;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakePrintQueue implements PrintQueueService {
  @override
  String get terminalId => 'terminal-under-test';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  late Terminal a;
  late Terminal b;

  setUp(() {
    a = Terminal('till-a');
    b = Terminal('till-b');
  });

  tearDown(() {
    a.dispose();
    b.dispose();
  });

  group('a local write reaches the other terminals', () {
    test('an order rung in on one till appears on the other, with no cloud',
        () {
      a.writer.write(
        entity: 'orders',
        id: 'o-1',
        action: 'create',
        row: {'id': 'o-1', 'table_id': 't-9', 'bill_status': 'open'},
      );

      // Nothing has crossed the network yet.
      expect(b.db.byId('orders', 'o-1'), isNull);

      a.flushTo([b]);

      final row = b.db.byId('orders', 'o-1');
      expect(row, isNotNull, reason: 'the order never crossed the LAN');
      expect(row!['table_id'], 't-9');
    });

    test('a create, an update and a delete all cross', () {
      a.writer.create(entity: 'goods', row: goodsRow('g-1'), id: 'g-1');
      a.flushTo([b]);
      expect(b.db.byId('goods', 'g-1'), isNotNull);

      a.writer.write(
        entity: 'goods',
        id: 'g-1',
        row: goodsRow('g-1', name: 'Renamed'),
      );
      a.flushTo([b]);
      expect(b.db.byId('goods', 'g-1')!['name'], 'Renamed');

      a.writer.delete(entity: 'goods', id: 'g-1');
      a.flushTo([b]);
      expect(b.db.byId('goods', 'g-1'), isNull,
          reason: 'the delete did not cross — LocalWriter.delete must go '
              'through ChangeApplier so it reaches the one emission point');
    });

    test('an order and its line items arrive as separate, ordered frames', () {
      // The shape `OrdersRepositoryImpl._writeOrderWithItems` produces: the
      // aggregate root through the writer, its children through the applier.
      a.writer.write(
        entity: 'orders',
        id: 'o-2',
        action: 'create',
        row: {'id': 'o-2', 'table_id': 't-1', 'bill_status': 'open'},
      );
      a.applier.applyOne(
        entity: 'order_items',
        action: 'create',
        payload: {'id': 'i-1', 'order_id': 'o-2', 'good_id': 'g-1'},
      );

      expect(a.outbound.length, 2, reason: 'both rows should be announced');
      a.flushTo([b]);

      expect(b.db.byId('orders', 'o-2'), isNotNull);
      expect(b.db.byId('order_items', 'i-1'), isNotNull);
    });
  });

  group('the receiving terminal does not take ownership', () {
    test("a peer's row is not queued for the server", () {
      a.writer.write(
        entity: 'orders',
        id: 'o-1',
        action: 'create',
        row: {'id': 'o-1', 'bill_status': 'open'},
      );
      a.flushTo([b]);

      expect(a.outboxDepth, 1, reason: 'the originator owes the server a write');
      expect(
        b.outboxDepth,
        0,
        reason: 'a peer that queued this too would make the server see one '
            'order N times — the duplicate-create this design exists to avoid',
      );
    });

    test("a peer's row is not pending-guarded, so the cloud can correct it", () {
      a.writer.write(
        entity: 'orders',
        id: 'o-1',
        action: 'create',
        row: {'id': 'o-1', 'bill_status': 'open'},
      );
      a.flushTo([b]);

      expect(a.db.isPending('orders', 'o-1'), isTrue);
      expect(b.db.isPending('orders', 'o-1'), isFalse);

      // The canonical version lands on B from the server and wins, because B
      // never claimed authority over it.
      ChangeApplier(b.db).applyPullResponse({
        'next_sync_cursor': 5,
        'changes': {
          'orders': {
            'updated': [
              {'id': 'o-1', 'bill_status': 'closed'},
            ],
          },
        },
      });
      expect(b.db.byId('orders', 'o-1')!['bill_status'], 'closed');
    });

    test('an unsynced local edit beats an incoming peer row', () {
      // Both tills touch the same order while the venue is offline. B's own
      // unsent work must not be silently reverted by A's broadcast.
      b.writer.write(
        entity: 'orders',
        id: 'o-1',
        row: {'id': 'o-1', 'bill_status': 'closed'},
      );
      b.outbound.clear();

      a.writer.write(
        entity: 'orders',
        id: 'o-1',
        row: {'id': 'o-1', 'bill_status': 'open'},
      );
      a.flushTo([b]);

      expect(b.db.byId('orders', 'o-1')!['bill_status'], 'closed');
    });
  });

  group('provisional ids do not leave duplicates on peers', () {
    test('the id swap deletes the provisional row on peers as well as here',
        () {
      // `LocalWriter.create` invents an id for entities whose server assigns
      // its own (halls, users, tables…). Peers see that provisional row. When
      // the create acks under a different id, the drainer swaps it — and if
      // that swap is invisible to peers, they keep both rows and the manager
      // sees the same hall twice.
      final provisionalId =
          a.writer.create(entity: 'halls', row: {'name': 'Terrace'});
      a.flushTo([b]);
      expect(b.db.byId('halls', provisionalId), isNotNull);

      // What OutboxDrainer._reconcile does once the server answers.
      a.db.clearPending('halls', provisionalId);
      a.applier.applyOne(
        entity: 'halls',
        action: 'delete',
        entityId: provisionalId,
      );
      a.applier.applyOne(
        entity: 'halls',
        action: 'update',
        entityId: 'server-hall-1',
        payload: {'id': 'server-hall-1', 'name': 'Terrace'},
      );
      a.flushTo([b]);

      expect(b.db.byId('halls', provisionalId), isNull,
          reason: 'the provisional row outlived its replacement on the peer');
      expect(b.db.byId('halls', 'server-hall-1'), isNotNull);
    });

    test('the drainer routes that delete through the applier, not the db', () {
      // Pins the call site itself: `_db.deleteRow` there would commit locally
      // and say nothing on the wire, which is invisible in any single-terminal
      // test.
      final source =
          File('lib/core/outbox/outbox_drainer.dart').readAsStringSync();
      // Matched on the name alone: the return type has changed once already
      // (it now reports how many queued payloads were repointed) and pinning
      // the signature made this fail for a reason that had nothing to do with
      // what it is guarding.
      final start = source.indexOf('_reconcile(\n');
      expect(start, isNot(-1), reason: '_reconcile has been renamed');
      final reconcile = source.substring(start);
      expect(
        reconcile.contains('_db.deleteRow('),
        isFalse,
        reason: 'a provisional row removed straight from the database never '
            'reaches LAN peers — use _applier.applyOne(action: "delete")',
      );
    });
  });

  group('the feed does not echo', () {
    test('applying a peer message emits nothing of its own', () {
      a.writer.write(
        entity: 'orders',
        id: 'o-1',
        action: 'create',
        row: {'id': 'o-1', 'bill_status': 'open'},
      );
      a.flushTo([b]);

      expect(
        b.outbound,
        isEmpty,
        reason: 'the hub already fanned this out; re-emitting would put the '
            'leader and its followers in a permanent echo',
      );
    });

    test('a three-terminal venue settles after one hop', () {
      final c = Terminal('till-c');
      addTearDown(c.dispose);

      a.writer.write(
        entity: 'orders',
        id: 'o-1',
        action: 'create',
        row: {'id': 'o-1', 'bill_status': 'open'},
      );
      a.flushTo([b, c]);

      expect(b.db.byId('orders', 'o-1'), isNotNull);
      expect(c.db.byId('orders', 'o-1'), isNotNull);
      expect(b.outbound, isEmpty);
      expect(c.outbound, isEmpty);
    });

    test('a cloud pull is never rebroadcast as a local change', () {
      // The two feeds must not feed each other: `ChangeFeedRelay` already
      // distributes pull batches, so emitting them here as well would double
      // every row the leader receives.
      a.applier.applyPullResponse({
        'next_sync_cursor': 7,
        'changes': {
          'goods': {
            'created': [goodsRow('g-9')],
          },
        },
      });

      expect(a.db.byId('goods', 'g-9'), isNotNull);
      expect(a.outbound, isEmpty);
    });
  });

  group('emission is tied to the commit, not the call', () {
    test('a rolled-back transaction announces nothing', () {
      expect(
        () => a.db.transaction(() {
          a.writer.write(
            entity: 'goods',
            id: 'g-1',
            row: goodsRow('g-1'),
          );
          throw StateError('payment validation failed');
        }),
        throwsStateError,
      );

      expect(a.db.byId('goods', 'g-1'), isNull);
      expect(
        a.outbound,
        isEmpty,
        reason: 'a peer told about a row that then rolled back here would hold '
            'it until some later pull happened to correct it',
      );
    });

    test('a committed outer transaction announces every row inside it once',
        () {
      a.db.transaction(() {
        a.writer.write(
          entity: 'goods',
          id: 'g-1',
          action: 'create',
          row: goodsRow('g-1'),
        );
        a.writer.write(
          entity: 'goods',
          id: 'g-2',
          action: 'create',
          row: goodsRow('g-2'),
        );
      });

      expect(a.outbound.length, 2);
      a.flushTo([b]);
      expect(b.db.byId('goods', 'g-1'), isNotNull);
      expect(b.db.byId('goods', 'g-2'), isNotNull);
    });
  });

  group('a malformed frame is dropped, not thrown', () {
    test('an unparseable payload is ignored', () {
      const msg = LanHubMessage(
        type: LanHubMessageType.localChange,
        changeEntity: 'goods',
        changeAction: 'update',
        changeEntityId: 'g-1',
        changePayload: '{not json',
      );
      expect(b.relay.apply(msg), isNull);
      expect(b.db.byId('goods', 'g-1'), isNull);
    });

    test('a create with no payload is ignored, a delete without one is not',
        () {
      expect(
        b.relay.apply(LanHubMessage.localChange(
          entity: 'goods',
          action: 'create',
          entityId: 'g-1',
        )),
        isNull,
      );

      b.applier.applyOne(
        entity: 'goods',
        action: 'create',
        payload: goodsRow('g-2'),
      );
      final stats = b.relay.apply(LanHubMessage.localChange(
        entity: 'goods',
        action: 'delete',
        entityId: 'g-2',
      ));
      expect(stats?.deleted, 1);
      expect(b.db.byId('goods', 'g-2'), isNull);
    });

    test('an entity this build does not replicate is skipped, not fatal', () {
      final stats = b.relay.apply(LanHubMessage.localChange(
        entity: 'some_future_table',
        action: 'update',
        entityId: 'x-1',
        payloadJson: '{"id":"x-1"}',
      ));
      expect(stats?.skippedUnknown, 1);
    });
  });

  group('table timers move with the orders they belong to', () {
    // The gap that stayed open after row propagation landed: a table timer is
    // local-authority state, so `ChangeApplier` never sees it and the row feed
    // cannot carry it. A waiter pausing a table on one till left every other
    // till counting — visibly wrong, and wrong about money.
    setUp(() {
      GetIt.I.registerSingleton<PrintQueueService>(_FakePrintQueue());
    });
    tearDown(() => GetIt.I.reset());

    test('a pause on one till stops the clock on the other', () async {
      final aTimers = a.timers();
      await aTimers.startTimer('o-1', tableId: 't1');
      a.flushTo([b]);

      expect(b.timerRecord('o-1')?['state'], 'running',
          reason: 'the start never crossed');

      await aTimers.pauseTimer('o-1');
      a.flushTo([b]);

      expect(b.timerRecord('o-1')?['state'], 'paused',
          reason: 'the pause never crossed — the peer is still counting');
    });

    test('resume crosses too, and both sides agree on the accumulator',
        () async {
      final aTimers = a.timers();
      await aTimers.startTimer('o-1', tableId: 't1');
      await aTimers.pauseTimer('o-1');
      await aTimers.resumeTimer('o-1');
      a.flushTo([b]);

      expect(b.timerRecord('o-1')?['state'], 'running');
      expect(
        b.timerRecord('o-1')?['accumulated_active_sec'],
        a.timerRecord('o-1')?['accumulated_active_sec'],
        reason: 'the two tills would bill this table differently',
      );
    });

    test('closing the order drops the record everywhere, not just here',
        () async {
      final aTimers = a.timers();
      await aTimers.startTimer('o-1', tableId: 't1');
      a.flushTo([b]);
      expect(b.timerRecord('o-1'), isNotNull);

      await aTimers.evictTimer('o-1');
      a.flushTo([b]);

      expect(a.timerRecord('o-1'), isNull);
      expect(
        b.timerRecord('o-1'),
        isNull,
        reason: 'a paid-off table keeping its timer on every other screen is '
            'exactly the confusion this exists to prevent, and the next order '
            'on that table would inherit it',
      );
    });

    test('the peer does not queue the timer action for the server', () async {
      final aTimers = a.timers();
      await aTimers.startTimer('o-1', tableId: 't1');
      await aTimers.pauseTimer('o-1');
      a.flushTo([b]);

      expect(a.outboxDepth, greaterThan(0),
          reason: 'the till the waiter touched owes the server these');
      expect(
        b.outboxDepth,
        0,
        reason: 'two terminals replaying the same pause would bill the table '
            'twice for one tap',
      );
    });

    test('applying a peer timer does not echo', () async {
      final aTimers = a.timers();
      await aTimers.startTimer('o-1', tableId: 't1');
      a.flushTo([b]);

      expect(b.outbound, isEmpty);
    });

    test('a timer transition that rolls back announces nothing', () async {
      final aTimers = a.timers();
      await aTimers.startTimer('o-1', tableId: 't1');
      a.outbound.clear();

      expect(
        () => a.db.transaction(() {
          aTimers.pauseTimer('o-1');
          throw StateError('something else in the same commit failed');
        }),
        throwsStateError,
      );

      expect(a.outbound, isEmpty);
    });

    test('a malformed timer frame is dropped, not thrown', () {
      expect(
        b.relay.applyTimer(LanHubMessage.timerAction(
          orderId: 'o-1',
          action: 'pause',
          recordJson: '{not json',
        )),
        isFalse,
      );
      expect(
        b.relay.applyTimer(const LanHubMessage(
          type: LanHubMessageType.timerAction,
          timerActionName: 'pause',
        )),
        isFalse,
        reason: 'no order id — nothing to apply it to',
      );
      expect(
        b.relay.applyTimer(LanHubMessage.timerAction(
          orderId: 'o-1',
          action: 'pause',
        )),
        isFalse,
        reason: 'a pause with no record cannot be reconstructed',
      );
    });

    test('an evict needs no record and is still applied', () {
      b.db.saveTableTimer('o-1', {'order_id': 'o-1', 'state': 'running'});
      expect(
        b.relay.applyTimer(
          LanHubMessage.timerAction(orderId: 'o-1', action: kTimerEvict),
        ),
        isTrue,
      );
      expect(b.timerRecord('o-1'), isNull);
    });
  });

  group('no local-authority table silently misses propagation', () {
    /// Local-authority tables that other terminals must be told about, and the
    /// message that tells them.
    ///
    /// This map exists because of how the table-timer gap happened: timers are
    /// not a replicated entity, so the row feed could not carry them, and
    /// nothing anywhere said so. A table paused on one till kept running on
    /// every other one, and the code was silent about the omission — there was
    /// no list to be missing from.
    const propagated = {
      LocalTables.tableStatus: 'LanHubMessageType.tableStatus',
      LocalTables.tableTimers: 'LanHubMessageType.timerAction',
    };

    /// Local-authority tables that are deliberately private to one terminal,
    /// and why. Sharing any of these would be a bug, not a feature.
    const perTerminal = {
      LocalTables.meta:
          'The sync cursor. Each terminal is at its own position in the change '
              'feed; copying one to another would skip or replay rows.',
      LocalTables.outbox:
          "The queue of writes this terminal owes the server. Sharing it is the "
              'duplicate-send this whole design avoids — the originator owns '
              'its own trip to the cloud.',
      LocalTables.pending:
          'Which rows this terminal has edited and not yet sent. It is the '
              'guard that makes a local edit beat an incoming one, so it is '
              'meaningless — and harmful — on any other terminal.',
      LocalTables.provisional:
          'Client-invented ids awaiting the server\'s. Peers receive the row '
              'itself and, later, its replacement; they never own the swap.',
      LocalTables.images:
          'Menu image blobs, derived from replicated goods. Each terminal '
              'fetches its own from object storage; there is no shared state '
              'to agree on.',
    };

    test('every local-authority table is classified', () {
      final classified = {...propagated.keys, ...perTerminal.keys};
      final unclassified = LocalTables.all.difference(classified).toList()
        ..sort();

      expect(
        unclassified,
        isEmpty,
        reason: 'A new local-authority table was added without deciding '
            'whether the rest of the venue needs to know about it. That '
            'decision being implicit is how table timers ended up visible on '
            'exactly one terminal. Add it to `propagated` with its message '
            'type, or to `perTerminal` with the reason it stays private:\n'
            '${unclassified.map((t) => '  - $t').join('\n')}',
      );
    });

    test('the classification names only tables that exist', () {
      final classified = {...propagated.keys, ...perTerminal.keys};
      final gone = classified.difference(LocalTables.all).toList()..sort();
      expect(gone, isEmpty,
          reason: 'these tables are no longer in LocalTables.all: $gone');
    });

    test('each propagated table really has its message type', () {
      final names = LanHubMessageType.values.map((t) => 'LanHubMessageType.${t.name}');
      for (final entry in propagated.entries) {
        expect(
          names,
          contains(entry.value),
          reason: '${entry.key} claims to propagate via ${entry.value}, '
              'which is not a real message type',
        );
      }
    });
  });

  group('the wire format survives a round trip', () {
    test('every localChange field parses back', () {
      final original = LanHubMessage.localChange(
        entity: 'orders',
        action: 'update',
        entityId: 'o-1',
        payloadJson: '{"id":"o-1"}',
        origin: 'till-a',
      );
      final parsed = LanHubMessage.tryParse(original.toJson())!;

      expect(parsed.type, LanHubMessageType.localChange);
      expect(parsed.changeEntity, 'orders');
      expect(parsed.changeAction, 'update');
      expect(parsed.changeEntityId, 'o-1');
      expect(parsed.changePayload, '{"id":"o-1"}');
      expect(parsed.changeOrigin, 'till-a');
    });

    test('every timerAction field parses back', () {
      final parsed = LanHubMessage.tryParse(
        LanHubMessage.timerAction(
          orderId: 'o-1',
          action: 'pause',
          recordJson: '{"state":"paused"}',
          origin: 'till-a',
        ).toJson(),
      )!;

      expect(parsed.type, LanHubMessageType.timerAction);
      expect(parsed.timerOrderId, 'o-1');
      expect(parsed.timerActionName, 'pause');
      expect(parsed.timerRecord, '{"state":"paused"}');
      expect(parsed.changeOrigin, 'till-a');
    });
  });

  group('counters', () {
    test('sent and received are observable for the sync-status screen', () {
      a.writer.write(
        entity: 'goods',
        id: 'g-1',
        action: 'create',
        row: goodsRow('g-1'),
      );
      a.flushTo([b]);

      expect(a.relay.counters.sent, 1);
      expect(a.relay.counters.received, 0);
      expect(b.relay.counters.sent, 0);
      expect(b.relay.counters.received, 1);
    });
  });

  group('a terminal with no hub wiring is unaffected', () {
    test('writes still commit locally when there is nowhere to broadcast', () {
      final db = LocalDatabase.open(':memory:');
      addTearDown(db.dispose);
      final applier = ChangeApplier(db);
      final writer =
          LocalWriter(db: db, applier: applier, outbox: OutboxStore(db));

      writer.write(
        entity: 'goods',
        id: 'g-1',
        action: 'create',
        row: goodsRow('g-1'),
      );
      expect(db.byId('goods', 'g-1'), isNotNull);
    });
  });
}
