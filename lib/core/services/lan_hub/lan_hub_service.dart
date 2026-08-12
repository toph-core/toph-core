import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/core/utils/jwt_utils.dart';
import 'package:mary_ai_pos/core/sync/change_feed_relay.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';

import 'lan_discovery_service.dart';
import 'lan_hub_client.dart';
import 'lan_hub_message.dart';
import 'lan_hub_server.dart';
import 'leader_election_service.dart';

enum LanMode { disabled, server, client }

class LanHubService {
  static const _keyMode = 'lan_mode';
  static const _keyServerIp = 'lan_server_ip';

  final SharedPreferences _prefs;
  final AppTokenStorage _tokenStorage;
  final ConnectivityCubit _connectivity;
  final _server = LanHubServer();
  final _client = LanHubClient();
  final _discovery = LanDiscoveryService();
  StreamSubscription<HubAnnouncement>? _discoverySub;

  final _tableUpdateController =
      StreamController<({String tableId, String status})>.broadcast();

  Stream<({String tableId, String status})> get onRemoteTableUpdate =>
      _tableUpdateController.stream;

  /// Non-null while in `server` mode and a second hub has been heard
  /// broadcasting for this same branch — surfaced as a warning, never acted
  /// on automatically (see [_watchForConflicts]).
  final _hubConflictController = BehaviorSubject<String?>.seeded(null);

  Stream<String?> get onHubConflictChanged => _hubConflictController.stream;

  String? get conflictingHubIp => _hubConflictController.valueOrNull;

  LanHubService(
    this._prefs, {
    required AppTokenStorage tokenStorage,
    required ConnectivityCubit connectivity,
  })  : _tokenStorage = tokenStorage,
        _connectivity = connectivity;

  LanMode get mode {
    final v = _prefs.getString(_keyMode) ?? 'disabled';
    return LanMode.values.firstWhere((e) => e.name == v,
        orElse: () => LanMode.disabled);
  }

  /// Reactive mirror of [mode] — for a sync-status screen that wants to show
  /// the current role without its own polling timer. Seeded lazily (not at
  /// field-initialization time) since `mode` reads `_prefs`, which is set in
  /// the constructor body's initializer list, not before it.
  BehaviorSubject<LanMode>? _modeController;
  BehaviorSubject<LanMode> get _modeStream =>
      _modeController ??= BehaviorSubject<LanMode>.seeded(mode);

  Stream<LanMode> get onModeChanged => _modeStream.stream;

  Future<void> setMode(LanMode mode) async {
    await _prefs.setString(_keyMode, mode.name);
    if (!_modeStream.isClosed) _modeStream.add(mode);
  }

  String get serverIp => _prefs.getString(_keyServerIp) ?? '';

  Future<void> setServerIp(String ip) => _prefs.setString(_keyServerIp, ip);

  /// App start da chaqiriladi. Callers must wait until every DI registration
  /// this transitively needs (notably `UserBloc`, for branch id) is done —
  /// `client` mode connects immediately if a server IP is already saved, and
  /// that connect attempt reads the current user via `inject<UserBloc>()`.
  Future<void> init() async {
    switch (mode) {
      case LanMode.server:
        await _server.start(
          authValidator: _validateIncomingAuth,
          onRelayOp: _handleRelayOp,
          // Bo'lmasa server o'z clientlaridan kelgan broadcastlarni faqat
          // boshqa clientlarga uzatadi, lekin o'zi hech qachon ko'rmaydi —
          // masalan bu terminal biror USB printerga egalik qilsa, boshqa
          // client'dan kelgan print-job e'lonini eshitolmay qoladi.
          onBroadcast: _handleRemoteMessage,
          // §6: resolved lazily (LeaseManager is registered after
          // LanHubService in di.dart, same DI-ordering reason as
          // `inject<UserBloc>()` elsewhere in this file).
          onLeaseRequest: (msg) => inject<LeaseManager>().handleLeaseRequestAsLeader(msg),
          onLeaseRelease: (msg) => inject<LeaseManager>().handleLeaseReleaseAsLeader(msg),
        );
        // §7: once LeaderElectionService owns this terminal's UDP discovery
        // socket as its heartbeat channel, running the plain warn-only
        // conflict watcher at the same time would try to double-bind the same
        // port. Since Phase 6 election is on by default, so this branch is now
        // the exception rather than the rule — it runs only where the kill
        // switch has been thrown.
        //
        // Asked through `isEnabledIn` rather than reading the key here: this
        // used to apply its own `?? false`, which would have silently become a
        // second, contradictory default the moment the real one flipped.
        if (!LeaderElectionService.isEnabledIn(_prefs)) {
          await _watchForConflicts();
        }
        break;
      case LanMode.client:
        final ip = serverIp;
        if (ip.isNotEmpty) {
          await _client.connect(ip, getCredentials: _readOwnCredentials);
          _client.onMessage.listen(_handleRemoteMessage);
        }
        break;
      case LanMode.disabled:
        break;
    }
  }

  /// Starts this leader's own discovery beacon (so a `client` running
  /// [discoverHubs] can find it) and, on the same socket, starts watching
  /// for any *other* hub announcing itself for this same branch — a split-
  /// brain signal that two terminals are both configured as `server` at
  /// once. Deliberately detect-and-warn only: automatically demoting one
  /// side would need picking a "winner" with no reliable criteria, and this
  /// architecture already accepts a single leader as a known point of
  /// failure — resolving *which* terminal stays the leader is a call for
  /// whoever's staffing the branch, not this service.
  Future<void> _watchForConflicts() async {
    final myBranchId = inject<UserBloc>().state.userMOdel?.branchId ?? '';
    if (myBranchId.isEmpty) return;
    await _discovery.startAnnouncing(
      branchId: myBranchId,
      wsPort: LanHubServer.defaultPort,
    );
    await _discoverySub?.cancel();
    _discoverySub = _discovery.onAnnouncement.listen((a) {
      if (a.branchId != myBranchId) return;
      if (kDebugMode) print('[LanHub] Conflicting hub detected at ${a.ip}');
      if (!_hubConflictController.isClosed) _hubConflictController.add(a.ip);
    });
  }

  /// Client-side helper: listens for hub broadcasts on this LAN for
  /// [timeout] and returns any distinct IPs heard for this terminal's own
  /// branch — lets the settings screen offer a picker instead of requiring
  /// an IP be typed in by hand. Manual entry stays available as a fallback
  /// (a network that blocks UDP broadcast, or a hub not yet reached by a
  /// scan, still needs it). Safe to call regardless of current [mode]: while
  /// in `client` mode the discovery socket isn't otherwise in use (the
  /// standing conflict watch above only ever runs under `server`), so this
  /// always starts from a clean, dedicated scan and fully stops afterward.
  Future<List<String>> discoverHubs({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final myBranchId = inject<UserBloc>().state.userMOdel?.branchId ?? '';
    if (myBranchId.isEmpty) return [];
    final found = <String>{};
    final sub = _discovery.onAnnouncement.listen((a) {
      if (a.branchId == myBranchId) found.add(a.ip);
    });
    try {
      await _discovery.startListening();
      await Future.delayed(timeout);
    } finally {
      await sub.cancel();
      await _discovery.stop();
    }
    return found.toList();
  }

  Future<LanAuthCredentials> _readOwnCredentials() async {
    final token = await _tokenStorage.readAccessToken() ?? '';
    final branchId = inject<UserBloc>().state.userMOdel?.branchId ?? '';
    return (token: token, branchId: branchId);
  }

  /// Rejects anything that isn't a live token for THIS branch. Strong check
  /// (round-trip to the cloud) when this leader itself has connectivity;
  /// falls back to a local, signature-less "not expired" check when it
  /// doesn't — refusing every follower just because the leader's own cloud
  /// link is briefly down would defeat LAN-only operation, the one scenario
  /// this whole mechanism exists for.
  Future<bool> _validateIncomingAuth(String token, String branchId) async {
    if (token.isEmpty || branchId.isEmpty) return false;
    final myBranchId = inject<UserBloc>().state.userMOdel?.branchId ?? '';
    if (myBranchId.isEmpty || branchId != myBranchId) return false;

    if (_connectivity.isOnline) {
      try {
        final verifyDio = Dio(BaseOptions(baseUrl: BASE_URL));
        final res = await verifyDio.get(
          ListAPI.user,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        final data = res.data is Map ? res.data['data'] : null;
        if (data is! Map) return false;
        final remoteBranchId = data['branch_id']?.toString() ?? '';
        return remoteBranchId.isNotEmpty && remoteBranchId == myBranchId;
      } catch (e) {
        if (kDebugMode) print('[LanHub] Online auth check failed, falling back: $e');
        // Fall through to the offline check below rather than hard-reject —
        // this failure is about reaching the cloud, not about the token.
      }
    }
    return !isJwtExpired(token);
  }

  /// Leader side of the sole-uplink relay (Phase 4): reconstructs a
  /// `PendingOperation` from a follower's relayed request and executes it
  /// against the cloud right now via this leader's own connectivity/session,
  /// through the exact same per-type logic `syncAll` uses for its own queue.
  /// Never touches this leader's own outbox — the follower owns that
  /// bookkeeping and decides what to do with the result.
  Future<String> _handleRelayOp(LanHubMessage msg) async {
    try {
      PendingOperationType? type;
      for (final t in PendingOperationType.values) {
        if (t.name == msg.opType) {
          type = t;
          break;
        }
      }
      if (type == null) return RelayOpResult.terminalFailure.name;
      final op = PendingOperation(
        id: msg.opId ?? '',
        type: type,
        payload: msg.opPayload ?? '{}',
        tableId: msg.opTableId ?? '',
        createdAt:
            DateTime.tryParse(msg.opCreatedAt ?? '') ?? DateTime.now().toUtc(),
      );
      final result = await inject<OfflineQueueService>().executeRelayedOp(
        inject<DioClient>(),
        op,
      );
      return result.name;
    } catch (e) {
      if (kDebugMode) print('[LanHub] relay exec error: $e');
      return RelayOpResult.retryLater.name;
    }
  }

  RelayOpResult? _parseRelayResult(String? name) {
    if (name == null) return null;
    for (final r in RelayOpResult.values) {
      if (r.name == name) return r;
    }
    return null;
  }

  /// Follower side of the sole-uplink relay (Phase 4): asks the leader to
  /// execute [op] right now instead of posting to the cloud directly. Called
  /// from `OfflineQueueService.relayViaLan`'s per-op loop.
  Future<RelayOpResult?> relayOperation(PendingOperation op) async {
    final resultName = await _client.relayOp(
      opId: op.id,
      opType: op.type.name,
      opPayload: op.payload,
      opTableId: op.tableId,
      opCreatedAt: op.createdAt.toUtc().toIso8601String(),
    );
    return _parseRelayResult(resultName);
  }

  /// §6: follower side of the lease protocol — `LeaseManager.acquireTableLease`
  /// delegates here in `client` mode, mirroring how [relayOperation] above
  /// delegates to `_client.relayOp`.
  Future<LanHubMessage?> requestLease({
    required String tableId,
    required String terminalId,
  }) =>
      _client.requestLease(tableId: tableId, terminalId: terminalId);

  void releaseLease({required String tableId, required String terminalId}) {
    _client.releaseLease(tableId: tableId, terminalId: terminalId);
  }

  void _handleRemoteMessage(LanHubMessage msg) {
    switch (msg.type) {
      case LanHubMessageType.tableStatus:
        if (msg.tableId != null && msg.status != null) {
          _tableUpdateController.add((tableId: msg.tableId!, status: msg.status!));
        }
        break;
      case LanHubMessageType.changeFeed:
        // Followers only. A leader hearing this would be a second leader
        // announcing, which epoch fencing handles — not something to apply.
        if (mode == LanMode.client &&
            msg.feedBody != null &&
            msg.feedFromCursor != null) {
          inject<ChangeFeedRelay>()
              .apply(body: msg.feedBody!, fromCursor: msg.feedFromCursor!);
        }
        break;
      case LanHubMessageType.printJobAnnounce:
        if (msg.printJobId != null &&
            msg.printJobType != null &&
            msg.printEntryId != null &&
            msg.printPayloadBase64 != null) {
          inject<PrintQueueService>().onRemoteAnnounce(
            jobId: msg.printJobId!,
            jobType: msg.printJobType!,
            entryId: msg.printEntryId!,
            payloadBase64: msg.printPayloadBase64!,
          );
        }
        break;
      case LanHubMessageType.printJobClaim:
        if (msg.printJobId != null) {
          inject<PrintQueueService>().onRemoteClaim(msg.printJobId!);
        }
        break;
      case LanHubMessageType.printJobResult:
        if (msg.printJobId != null && msg.printResult != null) {
          inject<PrintQueueService>().onRemoteResult(
            msg.printJobId!,
            msg.printResult!,
            msg.printError,
          );
        }
        break;
      default:
        break;
    }
  }

  /// Stol holati o'zgarganda chaqiriladi (order create / pay).
  void tableStatusChanged(String tableId, String status) {
    final msg = LanHubMessage.tableStatus(tableId: tableId, status: status);
    if (kDebugMode) {
      print('[LanHub] tableStatusChanged: $tableId → $status (mode: ${mode.name})');
    }
    _sendOrBroadcast(msg);
  }

  /// Follower-or-leader-agnostic broadcast helper (Phase 5 print relay) —
  /// mirrors [tableStatusChanged]'s own mode switch exactly, since a print
  /// job's originator can just as easily be the `server` terminal itself as
  /// any `client`.
  void _sendOrBroadcast(LanHubMessage msg) {
    switch (mode) {
      case LanMode.server:
        _server.broadcast(msg);
        break;
      case LanMode.client:
        _client.send(msg);
        break;
      case LanMode.disabled:
        break;
    }
  }

  /// Hands one applied pull batch to every follower (Phase 5).
  ///
  /// Server mode only, and deliberately not routed through [_sendOrBroadcast]:
  /// that helper falls back to sending upstream when this terminal is a
  /// client, which for a change feed would mean a follower telling its leader
  /// what the world looks like. The feed flows one way.
  void broadcastChangeFeed({
    required String body,
    required int fromCursor,
  }) {
    if (mode != LanMode.server) return;
    if (_server.clientCount == 0) return;
    _server.broadcast(
      LanHubMessage.changeFeed(body: body, fromCursor: fromCursor),
    );
  }

  /// Whether a print job could currently be relayed to another terminal at
  /// all — `disabled` mode has no hub connection to broadcast over.
  bool get canRelayPrintJobs => mode != LanMode.disabled;

  void broadcastPrintJobAnnounce({
    required String jobId,
    required String jobType,
    required String entryId,
    required String payloadBase64,
  }) {
    _sendOrBroadcast(
      LanHubMessage.printJobAnnounce(
        jobId: jobId,
        jobType: jobType,
        entryId: entryId,
        payloadBase64: payloadBase64,
      ),
    );
  }

  void broadcastPrintJobClaim(String jobId) {
    _sendOrBroadcast(LanHubMessage.printJobClaim(jobId: jobId));
  }

  void broadcastPrintJobResult(String jobId, String result, String? error) {
    _sendOrBroadcast(
      LanHubMessage.printJobResult(jobId: jobId, result: result, error: error),
    );
  }

  int get clientCount => _server.clientCount;
  bool get isClientConnected => _client.isConnected;
  String? get lastAuthFailReason => _client.lastAuthFailReason;

  /// Reactive mirror of [clientCount] (`server` mode peer count) — passed
  /// straight through from `LanHubServer`, which owns the actual `Set` of
  /// connected sockets.
  ValueListenable<int> get clientCountListenable => _server.clientCountNotifier;

  /// Reactive mirror of [isClientConnected] — for `client` mode only, used by
  /// the app-wide "operating solo" indicator so it doesn't need its own
  /// polling timer.
  Stream<bool> get onClientConnectionChanged => _client.connectionState;

  /// Rejim o'zgarganda — eski server/clientni to'xtatib qayta ishga tushirish.
  Future<void> restart() async {
    await _server.stop();
    await _client.disconnect();
    await _discoverySub?.cancel();
    _discoverySub = null;
    await _discovery.stop();
    if (!_hubConflictController.isClosed) _hubConflictController.add(null);
    await init();
  }

  Future<void> dispose() async {
    await _server.stop();
    await _client.dispose();
    await _discoverySub?.cancel();
    await _discovery.dispose();
    if (!_hubConflictController.isClosed) await _hubConflictController.close();
    if (!_tableUpdateController.isClosed) {
      await _tableUpdateController.close();
    }
    final modeController = _modeController;
    if (modeController != null && !modeController.isClosed) {
      await modeController.close();
    }
  }
}
