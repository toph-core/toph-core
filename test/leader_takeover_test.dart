/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 definition of done: "Kill the leader
/// mid-service: another terminal takes over with no UI change and no manual
/// step."
///
/// That criterion gates turning election on by default, and nothing tested it —
/// the existing suite drives one service against hand-fed announcements, which
/// can show that the rules are right but not that two terminals running them
/// converge. These run real instances against a shared bus and let them talk.
///
/// The fakes are deliberately thin: a broadcast bus that every terminal both
/// publishes to and hears (UDP, including its own echo), and a timer that
/// re-emits the leader's `heartbeatExtra` on the service's own beat, which is
/// what makes a leader's silence mean something when it stops.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_discovery_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_ports.dart';
import 'package:mary_ai_pos/core/services/lan_hub/leader_election_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _beat = Duration(milliseconds: 100);

/// The shared LAN segment.
class Bus {
  final controller = StreamController<HubAnnouncement>.broadcast(sync: true);
  void publish(HubAnnouncement a) {
    if (!controller.isClosed) controller.add(a);
  }
}

/// One terminal's view of [Bus]. Announcing starts a beat that republishes
/// whatever the service's `heartbeatExtra` reports, so a terminal that stops
/// announcing genuinely goes quiet on the wire.
class BusDiscovery implements LanDiscoveryService {
  final Bus bus;
  final String ip;
  BusDiscovery(this.bus, this.ip);

  Timer? _timer;
  String? _branchId;
  ({String? role, int? priority, int? epoch, String? terminalId}) Function()?
      _extra;

  /// Simulates the terminal dropping off the network without a clean stop —
  /// power cut, cable pulled. Timers keep running; nothing reaches the bus.
  bool unplugged = false;

  @override
  Stream<HubAnnouncement> get onAnnouncement => bus.controller.stream;

  @override
  Future<void> startListening({int port = LanDiscoveryService.defaultPort}) async {}

  @override
  Future<void> startAnnouncing({
    required String branchId,
    required int wsPort,
    int port = LanDiscoveryService.defaultPort,
    ({String? role, int? priority, int? epoch, String? terminalId})
        Function()? heartbeatExtra,
  }) async {
    _branchId = branchId;
    _extra = heartbeatExtra;
    _timer?.cancel();
    _timer = Timer.periodic(_beat, (_) {
      if (unplugged) return;
      final e = _extra?.call();
      bus.publish((
        ip: ip,
        port: wsPort,
        branchId: _branchId!,
        heardAt: DateTime.now(),
        role: e?.role,
        priority: e?.priority,
        epoch: e?.epoch,
        terminalId: e?.terminalId,
      ));
    });
  }

  @override
  void stopAnnouncing() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> stop() async => stopAnnouncing();

  @override
  Future<void> dispose() async => stop();

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

class FakeLanHub implements LanHubService {
  LanMode fakeMode = LanMode.disabled;
  String fakeServerIp = '';

  /// Port fields added with the configurable/auto-fallback port work. The
  /// election service reads these on every start and adopt, so a fake missing
  /// them fails as `noSuchMethod` rather than a useful assertion.
  int fakeServerPort = kDefaultHubPort;

  @override
  int get serverPort => fakeServerPort;

  @override
  Future<void> setServerPort(int port) async => fakeServerPort = port;

  @override
  int get preferredHubPort => kDefaultHubPort;

  @override
  int get preferredDiscoveryPort => kDefaultDiscoveryPort;

  /// Null — these fakes never bind a real socket, so the election service
  /// falls back to [preferredHubPort] when announcing, exactly as it would on
  /// a terminal whose server has not come up yet.
  @override
  int? get activeHubPort => null;

  @override
  LanMode get mode => fakeMode;
  @override
  Future<void> setMode(LanMode m) async => fakeMode = m;
  @override
  String get serverIp => fakeServerIp;
  @override
  Future<void> setServerIp(String ip) async => fakeServerIp = ip;
  @override
  Future<void> restart() async {}
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

/// Per-terminal preference store. The real `SharedPreferences` is a process
/// singleton, which would have these terminals sharing one epoch counter — the
/// one piece of state that must be per-terminal for any of this to mean
/// anything.
class FakePrefs implements SharedPreferences {
  final Map<String, Object> _values;
  FakePrefs(this._values);

  @override
  bool? getBool(String key) => _values[key] as bool?;
  @override
  int? getInt(String key) => _values[key] as int?;
  @override
  String? getString(String key) => _values[key] as String?;
  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

class Terminal {
  final String id;
  final BusDiscovery discovery;
  final FakeLanHub hub;
  final FakePrefs prefs;
  final LeaderElectionService service;

  Terminal._(this.id, this.discovery, this.hub, this.prefs, this.service);

  factory Terminal(
    Bus bus, {
    required String id,
    required String ip,
    required int priority,
    int epoch = 0,
  }) {
    final discovery = BusDiscovery(bus, ip);
    final hub = FakeLanHub();
    final prefs = FakePrefs({
      LeaderElectionService.electionEnabledKey: true,
      'lan_election_epoch': epoch,
      'lan_election_priority': priority,
    });
    return Terminal._(
      id,
      discovery,
      hub,
      prefs,
      LeaderElectionService(
        lanHub: hub,
        prefs: prefs,
        discovery: discovery,
        terminalId: () => id,
        branchId: () => 'branch-1',
        heartbeatInterval: _beat,
        missedBeatsBeforeDead: 3,
        baseElectionWait: _beat,
      ),
    );
  }

  ElectionRole get role => service.role;
  int get epoch => prefs.getInt('lan_election_epoch')!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Bus bus;

  setUp(() => bus = Bus());

  /// Priorities are spread far enough apart that the election wait cannot
  /// invert: the factor is `2000 / (priority + 1)`, so 999 waits ~2ms against
  /// 99's ~20ms and 9's ~200ms, while jitter tops out at 300ms... which is why
  /// the gaps below are hundreds of ms, not tens.
  List<Terminal> venue({int count = 2}) {
    const priorities = [999, 9, 4];
    return [
      for (var i = 0; i < count; i++)
        Terminal(bus,
            id: 'terminal-${String.fromCharCode(97 + i)}',
            ip: '10.0.0.${i + 1}',
            priority: priorities[i]),
    ];
  }

  test('a venue starting cold converges on exactly one leader', () {
    final terminals = venue(count: 3);
    fakeAsync((async) {
      for (final t in terminals) {
        t.service.start();
      }
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      final leaders =
          terminals.where((t) => t.role == ElectionRole.leader).toList();
      expect(leaders, hasLength(1));
      // The highest priority claims first, and everyone else hears it before
      // their own wait expires.
      expect(leaders.single.id, 'terminal-a');
      for (final t in terminals.where((t) => t.id != 'terminal-a')) {
        expect(t.role, ElectionRole.follower, reason: t.id);
      }
    });
  });

  test('killing the leader mid-service promotes another terminal', () {
    final terminals = venue(count: 3);
    final a = terminals[0], b = terminals[1], c = terminals[2];
    fakeAsync((async) {
      for (final t in terminals) {
        t.service.start();
      }
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(a.role, ElectionRole.leader);
      final epochUnderA = a.epoch;

      // Power cut. No clean shutdown, no goodbye message — the leader simply
      // stops being heard.
      a.discovery.unplugged = true;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      final leaders = [b, c].where((t) => t.role == ElectionRole.leader);
      expect(leaders, hasLength(1), reason: 'exactly one terminal takes over');
      expect(leaders.single.id, 'terminal-b', reason: 'next-highest priority');
      expect(c.role, ElectionRole.follower);

      // Fenced: the new leader claims a strictly higher epoch, so the old
      // leader's announcements can never win on a tie if it comes back.
      expect(b.epoch, greaterThan(epochUnderA));
      expect(b.hub.fakeMode, LanMode.server);
      expect(c.hub.fakeMode, LanMode.client);
      expect(c.hub.fakeServerIp, '10.0.0.2');
    });
  });

  test('the revived old leader stands down instead of splitting the venue', () {
    final terminals = venue(count: 2);
    final a = terminals[0], b = terminals[1];
    fakeAsync((async) {
      for (final t in terminals) {
        t.service.start();
      }
      async.elapse(const Duration(seconds: 3));
      expect(a.role, ElectionRole.leader);

      a.discovery.unplugged = true;
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(b.role, ElectionRole.leader);

      // The original leader comes back believing it still holds the venue —
      // it never learned otherwise. It is still announcing its own stale epoch.
      a.discovery.unplugged = false;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      // b's higher epoch wins on arrival, so a demotes itself with no
      // intervention and the venue keeps one leader throughout.
      expect(a.role, ElectionRole.follower);
      expect(b.role, ElectionRole.leader);
      expect(a.hub.fakeMode, LanMode.client);
      expect(a.hub.fakeServerIp, '10.0.0.2');
    });
  });

  test('a transient blip does not trigger a handover', () {
    // One missed beat is not a death. A venue that re-elected on every dropped
    // packet would churn the hub connection constantly.
    final terminals = venue(count: 2);
    final a = terminals[0], b = terminals[1];
    fakeAsync((async) {
      for (final t in terminals) {
        t.service.start();
      }
      async.elapse(const Duration(seconds: 3));
      expect(a.role, ElectionRole.leader);

      a.discovery.unplugged = true;
      async.elapse(const Duration(milliseconds: 150));
      a.discovery.unplugged = false;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(a.role, ElectionRole.leader);
      expect(b.role, ElectionRole.follower);
    });
  });
}
