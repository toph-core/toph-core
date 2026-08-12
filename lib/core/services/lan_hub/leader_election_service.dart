import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lan_discovery_service.dart';
import 'lan_hub_server.dart';
import 'lan_hub_service.dart';

/// offline-first-target-architecture.md §7 — automatic leader failover.
///
/// **On by default** as of Phase 6 (see [enabledByDefault]). A venue's
/// terminals coordinate themselves: they elect a leader, replace a dead one
/// without anyone touching a setting, and LAN mode stops being something a
/// manager configures by hand.
///
/// It shipped disabled because the design doc asked for a canary against real
/// multi-terminal hardware first, and this sandbox has none. What replaced
/// that canary is `test/leader_takeover_test.dart` — real service instances on
/// a shared bus, covering the criterion the doc actually cared about: kill the
/// leader mid-service and another terminal takes over, with no manual step and
/// no second leader. That is a narrower guarantee than a live venue, and it is
/// stated here rather than implied: hardware behaviour on a congested or
/// partitioned network is still unproven.
///
/// [setEnabled] survives as a kill switch for exactly that reason. It is no
/// longer an operator-facing toggle — there is no switch in settings any more,
/// because the choice is not one a cashier should be making mid-service — but
/// a venue where this misbehaves must be recoverable without a rebuild.
///
/// Reuses the discovery beacon as the heartbeat channel (§7: "the discovery
/// beacon becomes the heartbeat channel, not a separate mechanism") — when
/// enabled, this owns that UDP socket instead of
/// `LanHubService._watchForConflicts`' plain warn-only watcher (see the
/// gate in `LanHubService.init()`), since two sockets can't bind the same
/// UDP port in one process.
enum ElectionRole { idle, follower, candidate, leader }

class LeaderElectionService {
  static const electionEnabledKey = 'lan_election_enabled';
  static const _keyEpoch = 'lan_election_epoch';
  static const _keyPriority = 'lan_election_priority';

  final LanHubService _lanHub;
  final SharedPreferences _prefs;
  final LanDiscoveryService _discovery;
  final String Function() _myTerminalId;
  final String Function() _myBranchId;
  final Random _random = Random();

  /// ~2-3s per §7's concrete timing.
  final Duration heartbeatInterval;

  /// 3 consecutive misses (~6-9s) before a leader is considered dead, per §7.
  final int missedBeatsBeforeDead;

  /// Minimum wait before a candidate claims — priority shortens this per
  /// terminal (see [_startElection]), it never lengthens it beyond this.
  final Duration baseElectionWait;

  LeaderElectionService({
    required LanHubService lanHub,
    required SharedPreferences prefs,
    LanDiscoveryService? discovery,
    String Function()? terminalId,
    String Function()? branchId,
    this.heartbeatInterval = const Duration(seconds: 3),
    this.missedBeatsBeforeDead = 3,
    this.baseElectionWait = const Duration(seconds: 1),
  })  : _lanHub = lanHub,
        _prefs = prefs,
        _discovery = discovery ?? LanDiscoveryService(),
        _myTerminalId =
            terminalId ?? (() => inject<PrintQueueService>().terminalId),
        _myBranchId =
            branchId ?? (() => inject<UserBloc>().state.userMOdel?.branchId ?? '');

  /// On by default as of Phase 6.
  ///
  /// The venue coordinates itself: terminals elect a leader, a dead leader is
  /// replaced without anyone touching a setting, and LAN mode stops being a
  /// thing a manager configures by hand.
  static const enabledByDefault = true;

  /// Reads the flag from [prefs] applying [enabledByDefault].
  ///
  /// Static because `LanHubService` needs the same answer before
  /// `LeaderElectionService` is registered, and it used to get it by reading
  /// the key itself with its own `?? false` — two defaults for one decision,
  /// and exactly the duplicate-path failure §9 exists to prevent. Flipping the
  /// default without this would have left a fresh install running the election
  /// *and* the conflict watcher, both binding the same discovery socket.
  static bool isEnabledIn(SharedPreferences prefs) =>
      prefs.getBool(electionEnabledKey) ?? enabledByDefault;

  bool get isEnabled => isEnabledIn(_prefs);

  /// Kill switch. Starts/stops immediately rather than requiring a restart.
  ///
  /// Not wired to any UI as of Phase 6 — see the class doc for why it is still
  /// here.
  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(electionEnabledKey, value);
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  int get _epoch => _prefs.getInt(_keyEpoch) ?? 0;
  Future<void> _persistEpoch(int epoch) => _prefs.setInt(_keyEpoch, epoch);

  /// Open question 3 (design doc, "Open questions"): configured per-terminal
  /// vs. derived automatically — left unresolved there, so this picks the
  /// simpler of the two (a random fallback, persisted once) rather than
  /// deciding the deferred question. [setPriority] lets a settings screen
  /// override it later without this class needing to change.
  int get priority {
    final existing = _prefs.getInt(_keyPriority);
    if (existing != null) return existing;
    final generated = 1 + _random.nextInt(999);
    unawaited(_prefs.setInt(_keyPriority, generated));
    return generated;
  }

  Future<void> setPriority(int value) => _prefs.setInt(_keyPriority, value);

  ElectionRole _role = ElectionRole.idle;
  ElectionRole get role => _role;

  String? _currentLeaderIp;
  String? get currentLeaderIp => _currentLeaderIp;

  final _roleController = StreamController<ElectionRole>.broadcast();
  Stream<ElectionRole> get onRoleChanged => _roleController.stream;
  void _setRole(ElectionRole r) {
    _role = r;
    if (!_roleController.isClosed) _roleController.add(r);
  }

  Timer? _watchdog;
  Timer? _electionTimer;

  /// Consecutive watchdog ticks with no heartbeat from the branch.
  ///
  /// Counted rather than measured against the wall clock, which is what this
  /// used to do (`DateTime.now().difference(lastHeard)`). Two reasons. The
  /// watchdog already fires on [heartbeatInterval], so the tick *is* the unit
  /// — comparing timestamps re-derived it from a second, unrelated source. And
  /// that source moves on its own: an NTP correction stepping the clock
  /// backwards leaves the difference permanently under the deadline, so a
  /// terminal would never notice a dead leader, while a forward step elects
  /// instantly over a leader that is fine. POS terminals do get corrected.
  ///
  /// A counter driven by the timer cannot do either. It also made this class
  /// testable under `fakeAsync`, which advances timers but not `DateTime.now()`
  /// — the reason the election tests could not observe a leader-death at all.
  int _missedBeats = 0;
  StreamSubscription<HubAnnouncement>? _sub;

  bool get _isRunning => _sub != null;

  Future<void> start() async {
    if (!isEnabled || _isRunning) return;
    final branchId = _myBranchId();
    if (branchId.isEmpty) return;
    await _discovery.startListening();
    _sub = _discovery.onAnnouncement.listen((a) => _onAnnouncement(a, branchId));
    // §7 "Reconnection re-discovery is non-blocking": start as a plain
    // follower and let the first heartbeat window pass before ever
    // considering an election — never claim just because nothing's been
    // heard yet at t=0. Local UI/reads/writes are unaffected either way,
    // this class only ever runs on background timers.
    _missedBeats = 0;
    _setRole(ElectionRole.follower);
    _watchdog = Timer.periodic(heartbeatInterval, (_) => _checkLeaderAlive());
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _watchdog?.cancel();
    _watchdog = null;
    _electionTimer?.cancel();
    _electionTimer = null;
    await _discovery.stop();
    _setRole(ElectionRole.idle);
  }

  void _onAnnouncement(HubAnnouncement a, String myBranchId) {
    if (a.branchId != myBranchId) return;
    final heardEpoch = a.epoch ?? 0;
    if (heardEpoch < _epoch) return; // stale — a leader from a past epoch
    _missedBeats = 0;

    if (heardEpoch > _epoch) {
      // Higher epoch always wins immediately, on both sides (§7).
      unawaited(_adopt(a, heardEpoch));
      return;
    }

    // Equal epoch: the presumed leader (or an equal-epoch peer) is still
    // announcing. If we were mid-election on the belief it was dead, that
    // belief was wrong (a transient miss, not an actual failure) — stand
    // down instead of claiming over a leader that's still there.
    if (a.terminalId == _myTerminalId()) return;
    if (_role == ElectionRole.candidate) {
      _electionTimer?.cancel();
      _setRole(ElectionRole.follower);
    }
    if (_role != ElectionRole.leader) {
      _currentLeaderIp = a.ip;
      return;
    }
    // BACKEND_SYNC_PLAN.md §7 gap 2 — the deterministic tiebreak that was
    // missing. We are LEADER and a *different* terminal announces the same
    // epoch as leader: the exact landing spot for two candidates that both
    // computed the same new epoch and claimed before hearing each other.
    // Resolve it the same way on both sides — lexicographically smaller
    // terminal id wins — so a simultaneous-claim collision converges
    // deterministically instead of however timing falls out. (The loser
    // stands down and adopts the winner; the winner ignores the loser's
    // announcement and keeps announcing, which is what makes the loser's
    // side of this same comparison fire.) A genuine long-lived segment
    // split still surfaces via LanHubService's conflict warning; this only
    // auto-resolves the symmetric-claim race.
    final peerId = a.terminalId;
    if (peerId == null || peerId.isEmpty) return; // pre-§7 announcer — ignore
    if ((a.role ?? '') != 'leader') return;
    if (peerId.compareTo(_myTerminalId()) < 0) {
      if (kDebugMode) {
        print('[LeaderElection] Equal-epoch collision at epoch $_epoch — '
            'standing down for $peerId (deterministic tiebreak)');
      }
      unawaited(_adopt(a, heardEpoch));
    }
  }

  Future<void> _adopt(HubAnnouncement a, int epoch) async {
    _electionTimer?.cancel();
    await _persistEpoch(epoch);
    _currentLeaderIp = a.ip;
    if (a.terminalId == _myTerminalId()) return; // our own claim, echoed back
    final alreadyFollowingThisLeader =
        _lanHub.mode == LanMode.client && _lanHub.serverIp == a.ip;
    if (alreadyFollowingThisLeader && _role == ElectionRole.follower) return;
    await _becomeFollower(a.ip);
  }

  Future<void> _becomeFollower(String leaderIp) async {
    if (kDebugMode) print('[LeaderElection] Adopting leader at $leaderIp (epoch $_epoch)');
    // If we were announcing as leader (tiebreak stand-down), stop the
    // heartbeat but keep the socket listening — no-op otherwise.
    _discovery.stopAnnouncing();
    _setRole(ElectionRole.follower);
    await _lanHub.setServerIp(leaderIp);
    await _lanHub.setMode(LanMode.client);
    await _lanHub.restart();
  }

  void _checkLeaderAlive() {
    if (!isEnabled) return;
    if (_role == ElectionRole.leader || _role == ElectionRole.candidate) {
      return; // we ARE the heartbeat source, or already electing
    }
    _missedBeats++;
    if (_missedBeats < missedBeatsBeforeDead) return;
    _startElection();
  }

  /// Bully-algorithm collision avoidance, no vote round, no quorum (§7):
  /// higher priority claims sooner; a candidate that hears a higher/equal
  /// claim during its own wait stands down (`_onAnnouncement` above cancels
  /// [_electionTimer] and reverts the role).
  void _startElection() {
    _setRole(ElectionRole.candidate);
    final priorityFactor = (2000 / (priority + 1)).round();
    final jitter = _random.nextInt(300);
    final wait = baseElectionWait + Duration(milliseconds: priorityFactor + jitter);
    _electionTimer?.cancel();
    _electionTimer = Timer(wait, _claimLeadership);
  }

  Future<void> _claimLeadership() async {
    if (_role != ElectionRole.candidate) return; // stood down while waiting
    final branchId = _myBranchId();
    if (branchId.isEmpty) return;
    final newEpoch = _epoch + 1;
    await _persistEpoch(newEpoch);
    if (kDebugMode) print('[LeaderElection] Claiming leadership at epoch $newEpoch');
    _setRole(ElectionRole.leader);
    _currentLeaderIp = null; // this terminal IS the leader now
    await _lanHub.setMode(LanMode.server);
    await _lanHub.restart();
    await _discovery.startAnnouncing(
      branchId: branchId,
      wsPort: LanHubServer.defaultPort,
      heartbeatExtra: () => (
        role: 'leader',
        priority: priority,
        epoch: _epoch,
        terminalId: _myTerminalId(),
      ),
    );
  }

  Future<void> dispose() async {
    await stop();
    await _discovery.dispose();
    if (!_roleController.isClosed) await _roleController.close();
  }
}
