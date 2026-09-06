import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_client.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_server.dart';

/// Exercises the real `dart:io` `HttpServer`/`WebSocket` pair over loopback —
/// not mocks — since neither class has ever been run against a live
/// connection before (offline-first-architecture-plan.md §11 Phase 4 flagged
/// this as the biggest gap between "analyzes clean" and "actually works").
/// `LanHubService`'s app-level decisions (branch lookup via `UserBloc`, the
/// online/offline validator split, `OfflineQueueService` wiring) aren't
/// covered here — those need the DI graph and are a separate, larger effort;
/// this covers the wire protocol itself: handshake accept/reject, timeout,
/// and relay request/response correlation.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('LanHub wire protocol', () {
    late LanHubServer server;
    var port = 19765;

    setUp(() {
      // A fresh port per test avoids waiting on the previous test's TIME_WAIT
      // socket teardown.
      port++;
      server = LanHubServer();
    });

    tearDown(() async {
      await server.stop();
    });

    test('valid same-branch token is accepted and can broadcast', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async =>
            token == 'good-token' && branchId == 'branch-1',
        onRelayOp: (_) async => 'synced',
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 'good-token', branchId: 'branch-1'),
      );

      await _waitUntil(() => client.isConnected);
      expect(client.isConnected, isTrue);
      expect(server.clientCount, 1);

      final received = <LanHubMessage>[];
      client.onMessage.listen(received.add);
      server.broadcast(
        LanHubMessage.tableStatus(tableId: 't1', status: 'busy'),
      );
      await _waitUntil(() => received.isNotEmpty);
      expect(received.single.type, LanHubMessageType.tableStatus);
      expect(received.single.tableId, 't1');

      await client.dispose();
    });

    test('a localChange from one follower reaches the leader and every other '
        'follower, in one hop', () async {
      // The seam `local_change_relay_test.dart` cannot reach: that suite moves
      // frames between terminals by hand. This proves the real server actually
      // carries a `localChange` — fanning it out to the *other* clients while
      // also handing it to its own app layer, which is what makes a follower's
      // write visible venue-wide without the cloud.
      final leaderSaw = <LanHubMessage>[];
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
        onBroadcast: leaderSaw.add,
      );

      final writer = LanHubClient();
      final other = LanHubClient();
      await writer.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'branch-1'),
      );
      await other.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'branch-1'),
      );
      await _waitUntil(() => server.clientCount == 2);

      final otherSaw = <LanHubMessage>[];
      final writerSaw = <LanHubMessage>[];
      other.onMessage.listen(otherSaw.add);
      writer.onMessage.listen(writerSaw.add);

      writer.send(LanHubMessage.localChange(
        entity: 'orders',
        action: 'create',
        entityId: 'o-1',
        payloadJson: '{"id":"o-1","bill_status":"open"}',
        origin: 'till-a',
      ));

      await _waitUntil(() => leaderSaw.isNotEmpty && otherSaw.isNotEmpty);

      expect(leaderSaw.single.type, LanHubMessageType.localChange);
      expect(leaderSaw.single.changeEntityId, 'o-1');
      expect(leaderSaw.single.changeOrigin, 'till-a');
      expect(otherSaw.single.changeEntityId, 'o-1');
      expect(
        otherSaw.single.changePayload,
        '{"id":"o-1","bill_status":"open"}',
        reason: 'the payload must survive the wire byte for byte — the '
            'receiver hands it to the same applier the cloud path uses',
      );
      expect(
        writerSaw,
        isEmpty,
        reason: 'the sender must not get its own change back, or it would '
            'apply what it already wrote',
      );

      await writer.dispose();
      await other.dispose();
    });

    test('a timerAction crosses the wire with its record intact', () async {
      final leaderSaw = <LanHubMessage>[];
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
        onBroadcast: leaderSaw.add,
      );

      final waiterTill = LanHubClient();
      await waiterTill.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'branch-1'),
      );
      await _waitUntil(() => waiterTill.isConnected);

      waiterTill.send(LanHubMessage.timerAction(
        orderId: 'o-1',
        action: 'pause',
        recordJson: '{"state":"paused","accumulated_active_sec":3600}',
      ));
      await _waitUntil(() => leaderSaw.isNotEmpty);

      expect(leaderSaw.single.type, LanHubMessageType.timerAction);
      expect(leaderSaw.single.timerOrderId, 'o-1');
      expect(leaderSaw.single.timerActionName, 'pause');
      expect(
        leaderSaw.single.timerRecord,
        '{"state":"paused","accumulated_active_sec":3600}',
        reason: 'the accumulator is money — it must survive the wire exactly',
      );

      await waiterTill.dispose();
    });

    test('wrong-branch token is rejected with a reason, never joins broadcast set', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => branchId == 'branch-1',
        onRelayOp: (_) async => 'synced',
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 'x', branchId: 'wrong-branch'),
      );

      await _waitUntil(() => client.lastAuthFailReason != null);
      expect(client.isConnected, isFalse);
      expect(client.lastAuthFailReason, 'unauthorized');
      expect(server.clientCount, 0);

      await client.dispose();
    });

    test('the token/branchId the validator sees match exactly what the client sent', () async {
      // LanHubServer itself has no opinion on empty/malformed credentials —
      // that's entirely the injected validator's call (see LanHubService's
      // own empty-check for the actual app-level policy). What this class
      // owns is faithfully carrying the client's fields through the wire
      // protocol to the validator, which is what this test actually checks.
      String? seenToken;
      String? seenBranch;
      await server.start(
        port: port,
        authValidator: (token, branchId) async {
          seenToken = token;
          seenBranch = branchId;
          return false;
        },
        onRelayOp: (_) async => 'synced',
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 'exact-token', branchId: 'exact-branch'),
      );

      await _waitUntil(() => client.lastAuthFailReason != null);
      expect(seenToken, 'exact-token');
      expect(seenBranch, 'exact-branch');

      await client.dispose();
    });

    test('relays an op end-to-end and correlates the result by opId', () async {
      final receivedTypes = <String?>[];
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (msg) async {
          receivedTypes.add(msg.opType);
          return 'synced';
        },
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);

      final result = await client.relayOp(
        opId: 'op-1',
        opType: 'payOrder',
        opPayload: '{"order_id":"abc"}',
        opTableId: '',
        opCreatedAt: DateTime.now().toUtc().toIso8601String(),
      );

      expect(result, 'synced');
      expect(receivedTypes, ['payOrder']);

      await client.dispose();
    });

    test('two sequential relayed ops on the same connection do not cross-talk', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (msg) async {
          // Echo back the op type as the "result" so the test can tell
          // which request produced which reply.
          return msg.opType == 'createOrder' ? 'synced' : 'terminalFailure';
        },
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);

      final r1 = await client.relayOp(
        opId: 'op-1',
        opType: 'createOrder',
        opPayload: '{}',
        opTableId: 't1',
        opCreatedAt: DateTime.now().toIso8601String(),
      );
      final r2 = await client.relayOp(
        opId: 'op-2',
        opType: 'cancelLineItems',
        opPayload: '{}',
        opTableId: '',
        opCreatedAt: DateTime.now().toIso8601String(),
      );

      expect(r1, 'synced');
      expect(r2, 'terminalFailure');

      await client.dispose();
    });

    test('relay times out cleanly if the leader never replies', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) => Completer<String>().future, // never completes
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);

      final result = await client.relayOp(
        opId: 'op-1',
        opType: 'payOrder',
        opPayload: '{}',
        opTableId: '',
        opCreatedAt: DateTime.now().toIso8601String(),
        timeout: const Duration(milliseconds: 300),
      );

      expect(result, isNull);

      await client.dispose();
    });

    test('a connection that never authenticates is dropped after the auth timeout', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      final raw = await WebSocket.connect('ws://127.0.0.1:$port');
      var closed = false;
      raw.listen((_) {}, onDone: () => closed = true);

      // LanHubServer's auth timeout is a fixed 5s — this deliberately waits
      // it out rather than exercising a shortened one, to test the real
      // constant rather than a test-only stand-in.
      await _waitUntil(
        () => closed,
        timeout: const Duration(seconds: 8),
      );
      expect(server.clientCount, 0);
    });

    test('a print-job announce from one client reaches another client with fields intact (Phase 5)', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      final sender = LanHubClient();
      final receiver = LanHubClient();
      await sender.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await receiver.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => sender.isConnected && receiver.isConnected);

      final received = <LanHubMessage>[];
      receiver.onMessage.listen(received.add);
      sender.send(
        LanHubMessage.printJobAnnounce(
          jobId: 'job-1',
          jobType: 'cashier',
          entryId: 'entry-9',
          payloadBase64: 'aGVsbG8=',
        ),
      );

      await _waitUntil(() => received.isNotEmpty);
      expect(received.single.type, LanHubMessageType.printJobAnnounce);
      expect(received.single.printJobId, 'job-1');
      expect(received.single.printEntryId, 'entry-9');
      expect(received.single.printPayloadBase64, 'aGVsbG8=');

      await sender.dispose();
      await receiver.dispose();
    });

    test('the server itself receives a broadcast-worthy message via onBroadcast, not just its other clients (Phase 5)', () async {
      final serverSideReceived = <LanHubMessage>[];
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
        onBroadcast: serverSideReceived.add,
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);

      client.send(
        LanHubMessage.printJobClaim(jobId: 'job-2', terminalId: 'peer'),
      );

      await _waitUntil(() => serverSideReceived.isNotEmpty);
      expect(serverSideReceived.single.type, LanHubMessageType.printJobClaim);
      expect(serverSideReceived.single.printJobId, 'job-2');

      await client.dispose();
    });

    test('clientCountNotifier tracks connects and disconnects (Phase 6 sync-status UI)', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      final seen = <int>[];
      server.clientCountNotifier.addListener(
        () => seen.add(server.clientCountNotifier.value),
      );
      expect(server.clientCountNotifier.value, 0);

      final clientA = LanHubClient();
      await clientA.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => server.clientCountNotifier.value == 1);

      final clientB = LanHubClient();
      await clientB.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => server.clientCountNotifier.value == 2);

      await clientA.dispose();
      await _waitUntil(() => server.clientCountNotifier.value == 1);

      expect(
        seen,
        containsAllInOrder([1, 2, 1]),
        reason: 'notifier should have fired for each connect/disconnect, in order',
      );

      await clientB.dispose();
    });

    // ── Deterministic resilience tests (§11 Phase 6) ──────────────────────
    // The plan's own Phase 6 scope named five categories: partition
    // simulation, clock-skew, leader-kill-mid-transaction, duplicate-
    // delivery, and a full-shift soak test. The first three are covered
    // here and in print_queue_service_test.dart's matching group, using the
    // same real-socket harness as the rest of this file. Clock-skew was
    // investigated rather than built: this codebase has no wall-clock-
    // dependent correctness left to skew — Phase 6's own no-TTL decision
    // means offline auth doesn't expire, `PrintJob`'s claim/lease timers are
    // `Timer`s (event-loop-scheduled, immune to `DateTime.now()` changes,
    // unlike a deadline computed from a stored timestamp), and
    // `client_created_at` is sent to the backend for it to reconcile, not
    // used for any local ordering decision. A full-shift soak test (real
    // hours, many operations) doesn't fit a unit-test process without a
    // fake-clock/dependency-injection refactor this slice didn't attempt —
    // left for the real-hardware pass already flagged repeatedly across
    // Phases 4-6, not silently dropped.
    test('leader-kill-mid-relay: killing the server while a relayOp is in flight resolves via timeout, not a hang', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        // Deliberately slow — long enough that this test's own stop() call
        // below reliably lands before any reply would ever be sent, so this
        // is testing "the leader process is gone," not "the leader is slow"
        // (that's the pre-existing "relay times out cleanly" test above).
        onRelayOp: (_) async {
          await Future.delayed(const Duration(seconds: 5));
          return 'synced';
        },
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);

      final relayFuture = client.relayOp(
        opId: 'op-killed',
        opType: 'payOrder',
        opPayload: '{}',
        opTableId: '',
        opCreatedAt: DateTime.now().toIso8601String(),
        timeout: const Duration(milliseconds: 400),
      );

      // Kill the leader mid-flight — a real process-loss/crash, not just a
      // slow handler. The socket drops; relayOp has no separate "disconnect"
      // hook (see LanHubClient.relayOp's doc comment reasoning: giving up
      // early only matters for retry cost, never for correctness, since the
      // op stays in the outbox either way), so this proves the bound is the
      // explicit `timeout` param, not something that depends on the socket
      // noticing the drop.
      await Future.delayed(const Duration(milliseconds: 50));
      await server.stop();

      final sw = Stopwatch()..start();
      final result = await relayFuture;
      sw.stop();

      expect(result, isNull);
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'must resolve at the timeout, not hang until some other event',
      );

      await client.dispose();
    });

    test('partition-then-heal: a follower reconnects on its own once the leader comes back on the same port', () async {
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);

      // Simulate a LAN partition: the leader drops off the network entirely.
      await server.stop();
      await _waitUntil(() => !client.isConnected);

      // Heals: the leader (or its replacement — same effect from a
      // follower's point of view) comes back on the same port.
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      // LanHubClient's own exponential backoff starts at ~2s(+jitter) — no
      // action from this test triggers the retry, proving reconnection is
      // fully automatic, not something the caller has to notice and drive.
      await _waitUntil(
        () => client.isConnected,
        timeout: const Duration(seconds: 8),
      );

      expect(client.isConnected, isTrue);
      await client.dispose();
    });

    test('duplicate broadcast delivery: a printJobClaim delivered twice on the wire only reaches the app layer as two separate messages (dedup is PrintQueueService\'s job, not the transport\'s)', () async {
      // The transport layer (LanHubServer/Client) makes no at-most-once
      // promise — it's a plain broadcast relay. This test documents that
      // boundary explicitly: sending the same message twice really does
      // arrive twice here. `print_queue_service_test.dart`'s matching
      // "duplicate delivery" group is what proves the *application* layer
      // (`PrintQueueService.onRemoteClaim`/`onRemoteResult`) is where
      // idempotency actually lives, via each job's own state guard — this
      // test exists so that claim isn't just assumed.
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      final sender = LanHubClient();
      final receiver = LanHubClient();
      await sender.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await receiver.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => sender.isConnected && receiver.isConnected);

      final received = <LanHubMessage>[];
      receiver.onMessage
          .where((m) => m.type == LanHubMessageType.printJobClaim)
          .listen(received.add);

      sender.send(LanHubMessage.printJobClaim(jobId: 'job-dup', terminalId: 'peer'));
      sender.send(LanHubMessage.printJobClaim(jobId: 'job-dup', terminalId: 'peer'));

      await _waitUntil(() => received.length == 2);
      expect(received.every((m) => m.printJobId == 'job-dup'), isTrue);

      await sender.dispose();
      await receiver.dispose();
    });

    test('disconnect() does not auto-reconnect, but a later connect() still can', () async {
      // Regression: `disconnect()` closes the socket, whose `onDone` used to
      // call `_scheduleReconnect()` unconditionally — so an intentional close
      // (e.g. LanHubService.restart() demoting a client to disabled/server, or
      // pointing it at a new leader) silently revived the link ~2s later. The
      // fix gates auto-reconnect on an intent flag that disconnect() clears.
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      final client = LanHubClient();
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);
      expect(server.clientCount, 1);

      await client.disconnect();
      await _waitUntil(() => server.clientCount == 0);
      expect(client.isConnected, isFalse);

      // Wait well past the ~2s(+jitter) base reconnect delay: a stray
      // auto-reconnect would have re-joined by now. It must not.
      await Future.delayed(const Duration(milliseconds: 3500));
      expect(
        client.isConnected,
        isFalse,
        reason: 'disconnect() must not schedule an auto-reconnect',
      );
      expect(server.clientCount, 0);

      // An explicit connect() after a disconnect still works — disconnect only
      // suppresses the *automatic* retry, it does not permanently kill the
      // client (that is dispose()).
      await client.connect(
        '127.0.0.1',
        port: port,
        getCredentials: () async => (token: 't', branchId: 'b'),
      );
      await _waitUntil(() => client.isConnected);
      expect(server.clientCount, 1);

      await client.dispose();
    });

    test('stop() with multiple connected clients tears down cleanly, no ConcurrentModificationError', () async {
      // Regression: stop() iterated the live `_clients` set while awaiting each
      // socket close, and a socket's own `onDone` removing itself mid-loop
      // could throw ConcurrentModificationError. It now iterates a snapshot.
      await server.start(
        port: port,
        authValidator: (token, branchId) async => true,
        onRelayOp: (_) async => 'synced',
      );

      final clients = [
        for (var i = 0; i < 4; i++) LanHubClient(),
      ];
      for (final c in clients) {
        await c.connect(
          '127.0.0.1',
          port: port,
          getCredentials: () async => (token: 't', branchId: 'b'),
        );
      }
      await _waitUntil(() => server.clientCount == clients.length);

      // Must complete without throwing.
      await server.stop();
      expect(server.clientCount, 0);

      // Clean up the clients (they will each try to auto-reconnect after the
      // genuine drop; dispose cancels those pending timers).
      for (final c in clients) {
        await c.dispose();
      }
    });
  });
}
