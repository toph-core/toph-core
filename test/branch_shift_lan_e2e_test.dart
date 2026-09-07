/// Does opening the shift on one till actually open it on the till beside it?
///
/// `branch_shift_test.dart` answers that against a simulated wire — two
/// `Terminal`s handing frames to each other through `toJson`/`tryParse`. That
/// proves the applier and the query agree, and proves nothing about whether the
/// app is *wired* to carry them: a broadcast that is never sent, or an inbound
/// frame that is never dispatched, would pass every one of those tests and
/// still leave a venue with two tills disagreeing about the shift.
///
/// So this one runs the real thing. A real `LanHubServer` on a real port, real
/// `LanHubClient`s over real sockets, each till with its own `LocalDatabase`
/// and its own `ChangeApplier`, wired the way `di.dart` wires them:
///
///   LocalWriter → ChangeApplier.applyLocalWrite → onLocalChange
///     → LocalChangeRelay.broadcast → LanHubService.broadcastLocalChange
///       ─── socket ───
///     → LocalChangeRelay.apply → ChangeApplier.applyFromPeer → replica
///
/// The only substitution is `LanHubService` itself, whose `init()` wants
/// discovery, leader election and GetIt. Its two roles in this path are
/// one-liners (`broadcastLocalChange` forwards to the socket;
/// `localChange` frames go to `relay.apply`), and both are reproduced verbatim
/// below — see `_Till`.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/branch_shift_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/outbox/branch_shift_outbox.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_client.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_server.dart';
import 'package:mary_ai_pos/core/sync/local_change_relay.dart';

const kBranch = 'br-1';

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

/// One POS terminal: its own replica, its own relay, its own socket.
class _Till {
  final String name;
  late final LocalDatabase db;
  late final ChangeApplier applier;
  late final LocalWriter writer;
  late final LocalChangeRelay relay;
  final LanHubClient client = LanHubClient();

  _Till(this.name) {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(
      db,
      // di.dart:224 — every local write is handed to the relay.
      onLocalChange: ({
        required String entity,
        required String action,
        required String id,
        Map<String, dynamic>? payload,
      }) =>
          relay.broadcast(entity: entity, action: action, id: id, payload: payload),
    );
    relay = LocalChangeRelay(
      applier: applier,
      db: db,
      // di.dart:346 — `send: lanHubService.broadcastLocalChange`, which is
      // `_sendOrBroadcast`, which for a follower is the socket.
      send: client.send,
      terminalId: () => name,
    );
    writer = LocalWriter(db: db, applier: applier, outbox: OutboxStore(db));
  }

  Future<void> connect(int port) async {
    await client.connect(
      '127.0.0.1',
      port: port,
      getCredentials: () async => (token: 't', branchId: kBranch),
    );
    // lan_hub_service.dart:413-419 — an inbound localChange is applied in
    // every role.
    client.onMessage.listen((msg) {
      if (msg.type == LanHubMessageType.localChange) relay.apply(msg);
    });
  }

  BranchShiftQuery get shifts => BranchShiftQuery(db);

  /// Exactly what `ShiftBloc._openShift` writes.
  String openShift({String? id}) {
    final shiftId = id ?? 's-${name.toLowerCase()}';
    writer.create(
      entity: kBranchShiftEntity,
      id: shiftId,
      row: {
        'id': shiftId,
        'branch_id': kBranch,
        'opened_by': 'u-1',
        'closed_by': null,
        'opened_at': DateTime.now().toUtc().toIso8601String(),
        'closed_at': null,
        'opening_cash': '100',
        'opening_card': '0',
        'closing_cash': null,
        'closing_card': null,
      },
      request: {'id': shiftId, 'opening_cash': '100', 'opening_card': '0'},
    );
    return shiftId;
  }

  /// Exactly what `ShiftBloc._closeShift` writes.
  void closeShift(String shiftId, {String cash = '700'}) {
    writer.write(
      entity: kBranchShiftEntity,
      id: shiftId,
      action: kBranchShiftClose,
      merge: true,
      row: {
        'id': shiftId,
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'closed_by': 'u-2',
        'closing_cash': cash,
        'closing_card': '0',
      },
      request: {'closing_cash': cash, 'closing_card': '0'},
    );
  }

  Future<void> dispose() async {
    await client.disconnect();
    db.dispose();
  }
}

void main() {
  group('two tills on one LAN, over a real socket', () {
    late LanHubServer server;
    late _Till a;
    late _Till b;
    late int port;

    setUp(() async {
      port = 19850 + (DateTime.now().microsecond % 90);
      server = LanHubServer();
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
        onBroadcast: (_) {},
      );
      a = _Till('A');
      b = _Till('B');
      await a.connect(port);
      await b.connect(port);
      await _waitUntil(() => server.clientCount == 2);
    });

    tearDown(() async {
      await a.dispose();
      await b.dispose();
      await server.stop();
    });

    test('opening the shift on till A opens it on till B', () async {
      // The question in one assertion: B never touched the shift screen.
      expect(b.shifts.activeShift(kBranch), isNull);

      final shiftId = a.openShift();
      await _waitUntil(() => b.shifts.activeShift(kBranch) != null);

      final onB = b.shifts.activeShift(kBranch)!;
      expect(onB['id'], shiftId);
      expect(onB['branch_id'], kBranch);
      expect(onB['opening_cash'], '100',
          reason: "B should see the float A counted, not a blank shift");
      // And A, obviously.
      expect(a.shifts.activeShift(kBranch)!['id'], shiftId);
    });

    test('closing it on till B closes it on till A', () async {
      final shiftId = a.openShift();
      await _waitUntil(() => b.shifts.activeShift(kBranch) != null);

      // B closes the shift A opened — the cross-terminal case the old
      // per-terminal record could not express at all.
      b.closeShift(shiftId);
      await _waitUntil(() => a.shifts.activeShift(kBranch) == null);

      expect(a.shifts.activeShift(kBranch), isNull,
          reason: 'A is still trading under a shift the branch closed');
      expect(a.shifts.byId(shiftId)!['closing_cash'], '700');
      expect(b.shifts.activeShift(kBranch), isNull);
    });

    test("a till joining later is told the shift by the server, not the LAN",
        () async {
      // Honest about the limit: `localChange` is an event, not a snapshot. A
      // till that was switched off when the shift opened hears nothing, and
      // catches up through `/sync/pull` instead. This pins that boundary so
      // nobody mistakes the LAN path for a substitute for replication.
      final shiftId = a.openShift();
      await _waitUntil(() => b.shifts.activeShift(kBranch) != null);

      final c = _Till('C');
      await c.connect(port);
      await _waitUntil(() => server.clientCount == 3);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(c.shifts.activeShift(kBranch), isNull,
          reason: 'a late joiner gets no replay of past frames — by design');

      // What the feed would deliver, delivered.
      c.applier.applyOne(
        entity: kBranchShiftEntity,
        action: 'update',
        entityId: shiftId,
        payload: a.shifts.byId(shiftId)!,
      );
      expect(c.shifts.activeShift(kBranch)!['id'], shiftId);
      await c.dispose();
    });

    test('the shift does not echo back and forth between tills', () async {
      // `ChangeApplier.applyFromPeer` suppresses re-emission. Without it two
      // tills would bounce the same row forever, and every bounce would queue
      // another outbox op — the venue would report one open shift many times.
      a.openShift();
      await _waitUntil(() => b.shifts.activeShift(kBranch) != null);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(OutboxStore(b.db).pending(), isEmpty,
          reason: 'the receiving till queued a write of its own');
    });
  });
}
