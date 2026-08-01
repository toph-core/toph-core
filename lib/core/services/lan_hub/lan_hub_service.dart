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
import 'package:mary_ai_pos/core/utils/jwt_utils.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lan_discovery_service.dart';
import 'lan_hub_client.dart';
import 'lan_hub_message.dart';
import 'lan_hub_server.dart';

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

  Future<void> setMode(LanMode mode) => _prefs.setString(_keyMode, mode.name);

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
        );
        // Server o'zi ham broadcastni eshitadi (lekin client emas)
        await _watchForConflicts();
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

  void _handleRemoteMessage(LanHubMessage msg) {
    if (msg.type == LanHubMessageType.tableStatus &&
        msg.tableId != null &&
        msg.status != null) {
      _tableUpdateController.add((tableId: msg.tableId!, status: msg.status!));
    }
  }

  /// Stol holati o'zgarganda chaqiriladi (order create / pay).
  void tableStatusChanged(String tableId, String status) {
    final msg = LanHubMessage.tableStatus(tableId: tableId, status: status);
    if (kDebugMode) {
      print('[LanHub] tableStatusChanged: $tableId → $status (mode: ${mode.name})');
    }
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

  int get clientCount => _server.clientCount;
  bool get isClientConnected => _client.isConnected;
  String? get lastAuthFailReason => _client.lastAuthFailReason;

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
  }
}
