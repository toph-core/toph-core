// BACKEND_SYNC_PLAN.md §7 — first-ever test coverage for
// LeaderElectionService, written BEFORE any enable path is acted on (the
// plan's own ordering): epoch fencing (stale ignored, higher adopted),
// candidate stand-down on a live heartbeat, leader-death election and
// claim, and the new deterministic terminal-id tiebreak for the
// equal-epoch simultaneous-claim collision.
//
// Uses the service's own injectable seams (discovery, terminalId, branchId,
// timing knobs) plus hand-written fakes — no mocking package, matching the
// suite's convention.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_discovery_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/leader_election_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeDiscovery implements LanDiscoveryService {
  final controller = StreamController<HubAnnouncement>.broadcast(sync: true);
  bool listening = false;
  bool announcing = false;
  String? announcedBranchId;

  @override
  Stream<HubAnnouncement> get onAnnouncement => controller.stream;

  @override
  Future<void> startListening({int port = LanDiscoveryService.defaultPort}) async {
    listening = true;
  }

  @override
  Future<void> startAnnouncing({
    required String branchId,
    required int wsPort,
    int port = LanDiscoveryService.defaultPort,
    ({String? role, int? priority, int? epoch, String? terminalId})
        Function()? heartbeatExtra,
  }) async {
    announcing = true;
    announcedBranchId = branchId;
  }

  @override
  void stopAnnouncing() {
    announcing = false;
  }

  @override
  Future<void> stop() async {
    announcing = false;
    listening = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class FakeLanHub implements LanHubService {
  LanMode fakeMode = LanMode.disabled;
  String fakeServerIp = '';
  int restarts = 0;

  @override
  LanMode get mode => fakeMode;

  @override
  Future<void> setMode(LanMode mode) async {
    fakeMode = mode;
  }

  @override
  String get serverIp => fakeServerIp;

  @override
  Future<void> setServerIp(String ip) async {
    fakeServerIp = ip;
  }

  @override
  Future<void> restart() async {
    restarts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

HubAnnouncement announcement({
  required String terminalId,
  required int epoch,
  String ip = '10.0.0.9',
  String branchId = 'branch-1',
  String role = 'leader',
}) =>
    (
      ip: ip,
      port: 8765,
      branchId: branchId,
      heardAt: DateTime.now(),
      role: role,
      priority: 500,
      epoch: epoch,
      terminalId: terminalId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDiscovery discovery;
  late FakeLanHub lanHub;
  late SharedPreferences prefs;

  Future<LeaderElectionService> build({
    bool enabled = true,
    int startingEpoch = 0,
    String myTerminalId = 'terminal-m',
  }) async {
    SharedPreferences.setMockInitialValues({
      LeaderElectionService.electionEnabledKey: enabled,
      'lan_election_epoch': startingEpoch,
      // Fixed priority so the election wait is deterministic (~2ms factor).
      'lan_election_priority': 999,
    });
    prefs = await SharedPreferences.getInstance();
    discovery = FakeDiscovery();
    lanHub = FakeLanHub();
    return LeaderElectionService(
      lanHub: lanHub,
      prefs: prefs,
      discovery: discovery,
      terminalId: () => myTerminalId,
      branchId: () => 'branch-1',
      heartbeatInterval: const Duration(milliseconds: 100),
      missedBeatsBeforeDead: 3,
      baseElectionWait: const Duration(milliseconds: 100),
    );
  }

  test('disabled service never starts (role stays idle)', () async {
    final svc = await build(enabled: false);
    await svc.start();
    expect(svc.role, ElectionRole.idle);
    expect(discovery.listening, isFalse);
  });

  test('starts as follower — never claims at t=0 just because it heard nothing',
      () async {
    final svc = await build();
    await svc.start();
    expect(svc.role, ElectionRole.follower);
    expect(discovery.listening, isTrue);
    await svc.stop();
  });

  test('leader silence past the deadline elects and claims a new epoch', () async {
    final svc = await build(startingEpoch: 4);
    fakeAsync((async) {
      svc.start();
      async.flushMicrotasks();
      expect(svc.role, ElectionRole.follower);

      // 3 missed 100ms beats -> candidate, then the short election wait
      // (~100ms base + ~2ms priority factor + <300ms jitter) -> leader.
      async.elapse(const Duration(milliseconds: 450));
      expect(svc.role, isIn([ElectionRole.candidate, ElectionRole.leader]));
      async.elapse(const Duration(milliseconds: 600));
      async.flushMicrotasks();

      expect(svc.role, ElectionRole.leader);
      expect(prefs.getInt('lan_election_epoch'), 5); // fenced: 4 -> 5
      expect(lanHub.fakeMode, LanMode.server);
      expect(discovery.announcing, isTrue);
      expect(discovery.announcedBranchId, 'branch-1');
    });
  });

  test('a live equal-epoch heartbeat stands a candidate down (transient miss)',
      () async {
    final svc = await build(startingEpoch: 4);
    fakeAsync((async) {
      svc.start();
      async.flushMicrotasks();

      // Enough silence to become candidate but not to claim yet.
      async.elapse(const Duration(milliseconds: 320));
      expect(svc.role, ElectionRole.candidate);

      discovery.controller.add(announcement(terminalId: 'terminal-x', epoch: 4));
      async.flushMicrotasks();
      expect(svc.role, ElectionRole.follower);
      expect(svc.currentLeaderIp, '10.0.0.9');

      // The cancelled claim does not fire later. Asserted against a leader
      // that keeps beating, because that is what "the miss was transient"
      // means — this used to elapse two silent seconds and expect no
      // election, which only held while the watchdog was measuring a clock
      // `fakeAsync` never moved. Real silence *should* elect; see below.
      for (var i = 0; i < 20; i++) {
        async.elapse(const Duration(milliseconds: 100));
        discovery.controller
            .add(announcement(terminalId: 'terminal-x', epoch: 4));
        async.flushMicrotasks();
      }
      expect(svc.role, ElectionRole.follower);
    });
  });

  test('a terminal that stood down elects again if the silence resumes',
      () async {
    // The other half of the transient-miss case: standing down is a deferral,
    // not a permanent forfeit. A terminal that yielded to a heartbeat and then
    // hears nothing further must still take over — otherwise a leader dying
    // moments after one beat leaves the venue with no leader at all.
    final svc = await build(startingEpoch: 4);
    fakeAsync((async) {
      svc.start();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 320));
      discovery.controller.add(announcement(terminalId: 'terminal-x', epoch: 4));
      async.flushMicrotasks();
      expect(svc.role, ElectionRole.follower);

      // Now the leader really is gone.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(svc.role, ElectionRole.leader);
      expect(prefs.getInt('lan_election_epoch'), 5);
    });
  });

  test('higher epoch adopts immediately; lower (stale) epoch is ignored',
      () async {
    final svc = await build(startingEpoch: 4);
    fakeAsync((async) {
      svc.start();
      async.flushMicrotasks();

      // Stale epoch: ignored entirely — no adoption, no leader ip.
      discovery.controller.add(
        announcement(terminalId: 'terminal-old', epoch: 3, ip: '10.0.0.3'),
      );
      async.flushMicrotasks();
      expect(svc.currentLeaderIp, isNull);

      // Higher epoch: adopted — epoch persisted, follower of the announcer.
      discovery.controller.add(
        announcement(terminalId: 'terminal-new', epoch: 9, ip: '10.0.0.9'),
      );
      async.flushMicrotasks();
      expect(prefs.getInt('lan_election_epoch'), 9);
      expect(svc.role, ElectionRole.follower);
      expect(lanHub.fakeMode, LanMode.client);
      expect(lanHub.fakeServerIp, '10.0.0.9');
    });
  });

  group('equal-epoch simultaneous-claim tiebreak (§7 gap 2)', () {
    test('leader stands down for a lexicographically smaller terminal id',
        () async {
      final svc = await build(startingEpoch: 4, myTerminalId: 'terminal-m');
      fakeAsync((async) {
        svc.start();
        async.flushMicrotasks();
        // Become leader via silence.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(svc.role, ElectionRole.leader);
        final claimedEpoch = prefs.getInt('lan_election_epoch')!;

        // A peer claims the SAME epoch as leader with a smaller id — the
        // deterministic loser here is us.
        discovery.controller.add(announcement(
          terminalId: 'terminal-a',
          epoch: claimedEpoch,
          ip: '10.0.0.2',
        ));
        async.flushMicrotasks();

        expect(svc.role, ElectionRole.follower);
        expect(lanHub.fakeMode, LanMode.client);
        expect(lanHub.fakeServerIp, '10.0.0.2');
        expect(discovery.announcing, isFalse); // heartbeat stopped
      });
    });

    test('leader keeps leadership against a larger terminal id', () async {
      final svc = await build(startingEpoch: 4, myTerminalId: 'terminal-m');
      fakeAsync((async) {
        svc.start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(svc.role, ElectionRole.leader);
        final claimedEpoch = prefs.getInt('lan_election_epoch')!;

        discovery.controller.add(announcement(
          terminalId: 'terminal-z',
          epoch: claimedEpoch,
          ip: '10.0.0.7',
        ));
        async.flushMicrotasks();

        // Deterministic winner: unchanged role, still announcing.
        expect(svc.role, ElectionRole.leader);
        expect(lanHub.fakeMode, LanMode.server);
        expect(discovery.announcing, isTrue);
      });
    });

    test('a non-leader equal-epoch announcement does not trigger the tiebreak',
        () async {
      final svc = await build(startingEpoch: 4, myTerminalId: 'terminal-m');
      fakeAsync((async) {
        svc.start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(svc.role, ElectionRole.leader);
        final claimedEpoch = prefs.getInt('lan_election_epoch')!;

        discovery.controller.add(announcement(
          terminalId: 'terminal-a',
          epoch: claimedEpoch,
          ip: '10.0.0.2',
          role: 'follower',
        ));
        async.flushMicrotasks();
        expect(svc.role, ElectionRole.leader);
      });
    });
  });

  test('own echoed announcement is ignored', () async {
    final svc = await build(startingEpoch: 4, myTerminalId: 'terminal-m');
    fakeAsync((async) {
      svc.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(svc.role, ElectionRole.leader);
      final claimedEpoch = prefs.getInt('lan_election_epoch')!;

      discovery.controller.add(announcement(
        terminalId: 'terminal-m',
        epoch: claimedEpoch,
        ip: '10.0.0.5',
      ));
      async.flushMicrotasks();
      expect(svc.role, ElectionRole.leader);
    });
  });
}
