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
  });
}
