import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_discovery_service.dart';

/// Exercises the real UDP broadcast beacon over loopback — not mocks, same
/// reasoning as `lan_hub_test.dart`: this is the one piece of Phase 4 that
/// never touches an authenticated connection at all, so a wire-level bug
/// here (e.g. hearing your own broadcast, or a stale timer surviving `stop`)
/// would be invisible to `flutter analyze` and to every other LAN test.
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
  group('LanDiscoveryService', () {
    var port = 29866;

    setUp(() {
      // Fresh port per test avoids waiting on the previous test's socket
      // teardown, same reasoning as LanHubServer's test port bump.
      port++;
    });

    test('a listener hears an announcer\'s broadcast with the right fields', () async {
      final announcer = LanDiscoveryService();
      final listener = LanDiscoveryService();
      addTearDown(() async {
        await announcer.dispose();
        await listener.dispose();
      });

      final heard = <HubAnnouncement>[];
      listener.onAnnouncement.listen(heard.add);
      await listener.startListening(port: port);
      await announcer.startAnnouncing(
        branchId: 'branch-1',
        wsPort: 8765,
        port: port,
      );

      await _waitUntil(() => heard.isNotEmpty);
      expect(heard.single.branchId, 'branch-1');
      expect(heard.single.port, 8765);
      expect(heard.single.ip, isNotEmpty);
    });

    test('an announcer never surfaces its own broadcast, even though it also listens', () async {
      final hub = LanDiscoveryService();
      // An independent third party on the same port proves the broadcast
      // really was sent and really is being delivered on this network —
      // without this, a completely broken send path would also produce an
      // empty `heard` list below and this test would pass for the wrong
      // reason.
      final witness = LanDiscoveryService();
      addTearDown(() async {
        await hub.dispose();
        await witness.dispose();
      });

      final heard = <HubAnnouncement>[];
      final witnessed = <HubAnnouncement>[];
      hub.onAnnouncement.listen(heard.add);
      witness.onAnnouncement.listen(witnessed.add);
      await witness.startListening(port: port);
      await hub.startAnnouncing(branchId: 'branch-1', wsPort: 8765, port: port);

      await _waitUntil(() => witnessed.isNotEmpty);
      expect(heard, isEmpty);
    });

    test('two different hubs on two different branches are both heard, distinctly', () async {
      final hubA = LanDiscoveryService();
      final hubB = LanDiscoveryService();
      final listener = LanDiscoveryService();
      addTearDown(() async {
        await hubA.dispose();
        await hubB.dispose();
        await listener.dispose();
      });

      final heard = <HubAnnouncement>[];
      listener.onAnnouncement.listen(heard.add);
      await listener.startListening(port: port);
      await hubA.startAnnouncing(branchId: 'branch-A', wsPort: 8765, port: port);
      await hubB.startAnnouncing(branchId: 'branch-B', wsPort: 8765, port: port);

      await _waitUntil(
        () => heard.any((a) => a.branchId == 'branch-A') &&
            heard.any((a) => a.branchId == 'branch-B'),
      );
    });

    test('heartbeatExtra fields (role/priority/epoch/terminalId) reach the listener, and update per tick', () async {
      // offline-first-target-architecture.md §7: LeaderElectionService rides
      // this exact beacon as its heartbeat channel — a listener must see the
      // leader-only fields, and see them change (e.g. an epoch bump) without
      // the announce timer needing to restart.
      final announcer = LanDiscoveryService();
      final listener = LanDiscoveryService();
      addTearDown(() async {
        await announcer.dispose();
        await listener.dispose();
      });

      var epoch = 1;
      final heard = <HubAnnouncement>[];
      listener.onAnnouncement.listen(heard.add);
      await listener.startListening(port: port);
      await announcer.startAnnouncing(
        branchId: 'branch-1',
        wsPort: 8765,
        port: port,
        heartbeatExtra: () => (
          role: 'leader',
          priority: 42,
          epoch: epoch,
          terminalId: 'terminal-A',
        ),
      );

      await _waitUntil(() => heard.isNotEmpty);
      expect(heard.first.role, 'leader');
      expect(heard.first.priority, 42);
      expect(heard.first.epoch, 1);
      expect(heard.first.terminalId, 'terminal-A');

      epoch = 2;
      heard.clear();
      await _waitUntil(() => heard.any((a) => a.epoch == 2), timeout: const Duration(seconds: 4));
    });

    test('an announcement with no heartbeatExtra leaves the new fields null (backward compatible)', () async {
      final announcer = LanDiscoveryService();
      final listener = LanDiscoveryService();
      addTearDown(() async {
        await announcer.dispose();
        await listener.dispose();
      });

      final heard = <HubAnnouncement>[];
      listener.onAnnouncement.listen(heard.add);
      await listener.startListening(port: port);
      await announcer.startAnnouncing(branchId: 'branch-1', wsPort: 8765, port: port);

      await _waitUntil(() => heard.isNotEmpty);
      expect(heard.first.role, isNull);
      expect(heard.first.priority, isNull);
      expect(heard.first.epoch, isNull);
      expect(heard.first.terminalId, isNull);
    });

    test('stop() halts further announcements', () async {
      final announcer = LanDiscoveryService();
      final listener = LanDiscoveryService();
      addTearDown(() async {
        await announcer.dispose();
        await listener.dispose();
      });

      final heard = <HubAnnouncement>[];
      listener.onAnnouncement.listen(heard.add);
      await listener.startListening(port: port);
      await announcer.startAnnouncing(
        branchId: 'branch-1',
        wsPort: 8765,
        port: port,
      );
      await _waitUntil(() => heard.isNotEmpty);

      await announcer.stop();
      heard.clear();
      // The announce interval is 2s — wait comfortably past two cycles to
      // be confident the periodic timer really stopped, not just that this
      // check ran between ticks.
      await Future.delayed(const Duration(seconds: 5));
      expect(heard, isEmpty);
    });
  });
}
