import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/core/utils/jwt_utils.dart';
import 'package:mary_ai_pos/core/sync/change_feed_relay.dart';
import 'package:mary_ai_pos/core/sync/replica_repair.dart';
import 'package:mary_ai_pos/core/sync/local_change_relay.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';

import 'lan_discovery_service.dart';
import 'local_ip_lookup.dart';
import 'lan_hub_client.dart';
import 'lan_hub_message.dart';
import 'lan_hub_server.dart';
import 'lan_ports.dart';
import 'leader_election_service.dart';

enum LanMode { disabled, server, client }

/// One hub found by a settings-screen scan: the address to dial *and* the port
/// it announced. The port matters now that a hub may have fallen back off its
/// preferred one — a picker that returned bare IPs would send the follower to
/// a closed port.
typedef DiscoveredHub = ({String ip, int port});

class LanHubService {
  static const _keyMode = 'lan_mode';
  static const _keyServerIp = 'lan_server_ip';
  static const _keyServerPort = 'lan_server_port';
  static const _keyHubPort = 'lan_hub_port';
  static const _keyDiscoveryPort = 'lan_discovery_port';

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

  /// The one, lifelong subscription to `_client.onMessage`. Attached here in
  /// the constructor — never per-`init()` — because `_client` outlives every
  /// `restart()`/`init()` cycle and `onMessage` is a *broadcast* stream: a
  /// fresh `listen` on each client-mode `init()` (as this used to do) stacked
  /// another live handler that was never cancelled, so after a couple of
  /// leader changes every remote localChange / timer / print / table message
  /// was applied two or three times over. One subscription for the object's
  /// life is the whole point.
  StreamSubscription<LanHubMessage>? _clientMessageSub;

  LanHubService(
    this._prefs, {
    required AppTokenStorage tokenStorage,
    required ConnectivityCubit connectivity,
  })  : _tokenStorage = tokenStorage,
        _connectivity = connectivity {
    _clientMessageSub = _client.onMessage.listen(_handleRemoteMessage);
  }

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

  /// Port a `client` dials on [serverIp]. Set from a discovery announcement's
  /// `ws_port` (so a hub that fell back to 8766 is still reachable) or from an
  /// `ip:port` typed into settings.
  int get serverPort => _prefs.getInt(_keyServerPort) ?? preferredHubPort;

  Future<void> setServerPort(int port) =>
      _prefs.setInt(_keyServerPort, normalizePort(port));

  /// Operator-configured *preference*, not necessarily what is in use — the
  /// actual bound port is [activeHubPort], which may have walked upward if
  /// this one was occupied.
  int get preferredHubPort =>
      normalizePort(_prefs.getInt(_keyHubPort) ?? kDefaultHubPort);

  Future<void> setPreferredHubPort(int port) =>
      _prefs.setInt(_keyHubPort, normalizePort(port));

  int get preferredDiscoveryPort =>
      normalizePort(_prefs.getInt(_keyDiscoveryPort) ?? kDefaultDiscoveryPort);

  Future<void> setPreferredDiscoveryPort(int port) =>
      _prefs.setInt(_keyDiscoveryPort, normalizePort(port));

  /// TCP port the hub is actually listening on right now, or null when it is
  /// not listening — either not in `server` mode, or every candidate port was
  /// busy (see [hubBindError]).
  int? get activeHubPort => _server.boundPort;

  String? get hubBindError => _server.lastBindError;

  ValueListenable<int?> get activeHubPortListenable => _server.boundPortNotifier;

  /// UDP port the discovery beacon is bound to. Read from whichever service
  /// currently owns the socket: with leader election enabled that is
  /// `LeaderElectionService`'s own instance, so this reports null here and the
  /// election service is asked instead — see [discoveryPortReporter].
  int? get activeDiscoveryPort =>
      _discovery.boundPort ?? discoveryPortReporter?.call();

  String? get discoveryBindError => _discovery.lastBindError;

  /// Set by `di.dart` to `LeaderElectionService`'s bound-port getter, so the
  /// settings screen can show one discovery port regardless of which service
  /// owns the socket. A plain callback rather than a dependency because
  /// `LeaderElectionService` is constructed *with* this service and injecting
  /// it back would be a cycle.
  int? Function()? discoveryPortReporter;

  /// App start da chaqiriladi. Callers must wait until every DI registration
  /// this transitively needs (notably `UserBloc`, for branch id) is done —
  /// `client` mode connects immediately if a server IP is already saved, and
  /// that connect attempt reads the current user via `inject<UserBloc>()`.
  Future<void> init() async {
    switch (mode) {
      case LanMode.server:
        await _server.start(
          port: preferredHubPort,
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
          // No `onMessage.listen` here — the sole subscription is attached
          // once in the constructor and survives every restart (see
          // `_clientMessageSub`). Re-subscribing per init() was the leak.
          await _client.connect(
            ip,
            port: serverPort,
            getCredentials: _readOwnCredentials,
          );
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
      // The port actually bound, not the constant — a hub that fell back must
      // advertise where it really is, or followers dial a closed port.
      wsPort: activeHubPort ?? preferredHubPort,
      port: preferredDiscoveryPort,
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
  Future<List<DiscoveredHub>> discoverHubs({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final myBranchId = inject<UserBloc>().state.userMOdel?.branchId ?? '';
    if (myBranchId.isEmpty) return [];
    // Keyed by ip so a hub heard several times collapses to one entry, while
    // the announced `ws_port` is kept rather than discarded — dropping it was
    // what forced every discovered hub to be dialled on the default port.
    final found = <String, int>{};
    final sub = _discovery.onAnnouncement.listen((a) {
      if (a.branchId == myBranchId) found[a.ip] = a.port;
    });
    try {
      await _discovery.startListening(port: preferredDiscoveryPort);
      await Future.delayed(timeout);
    } finally {
      await sub.cancel();
      await _discovery.stop();
    }
    return [
      for (final e in found.entries) (ip: e.key, port: e.value),
    ];
  }

  /// Port this terminal's hub listens on when in `server` mode — the one
  /// actually bound where there is one, falling back to the configured
  /// preference so the settings card can still show what *would* be used.
  int get hubPort => activeHubPort ?? preferredHubPort;

  /// Leader side of the manual-entry fallback: every IPv4 address this device
  /// is reachable at, best candidate first. `discoverHubs` above answers "what
  /// can this client hear?", which is the wrong question when the hub is
  /// announcing from an interface no client can dial (a docker bridge, a VPN
  /// tunnel — the hub binds `anyIPv4`, so it answers on all of them). This
  /// answers "what should I type in?" from the hub's own side, where the
  /// interface names are known.
  Future<List<LocalAddress>> localAddresses() => listLocalIpv4Addresses();

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
          final stats = inject<ChangeFeedRelay>()
              .apply(body: msg.feedBody!, fromCursor: msg.feedFromCursor!);
          // A follower applies the leader's batch through the same applier as a
          // cloud pull, and refuses rows the same way — but this result used to
          // be dropped, so a delete refused here was never recorded and the
          // follower's replica stayed diverged for good. It is the only inbound
          // feed a follower has, so this is the only place that refusal can be
          // seen.
          if (stats != null && stats.refusedEntities.isNotEmpty) {
            try {
              inject<ReplicaRepair>().noteRefused(stats.refusedEntities);
            } catch (_) {
              // A terminal wired without the repair path replicates exactly as
              // before; it simply never repairs.
            }
          }
        }
        break;
      case LanHubMessageType.localChange:
        // Applied in every role, unlike `changeFeed` above. A leader hearing
        // this is hearing a follower's own write, which is exactly what it
        // needs; `LanHubServer` has already passed the same bytes on to the
        // other followers, and `ChangeApplier.applyFromPeer` makes sure this
        // terminal does not send them round again.
        inject<LocalChangeRelay>().apply(msg);
        break;
      case LanHubMessageType.timerAction:
        // Every role, same as localChange: a timer can be paused from any
        // terminal, and `LanHubServer` has already passed this on to the rest.
        inject<LocalChangeRelay>().applyTimer(msg);
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
          inject<PrintQueueService>().onRemoteClaim(
            msg.printJobId!,
            msg.printTerminalId ?? '',
          );
        }
        break;
      case LanHubMessageType.printJobGrant:
        if (msg.printJobId != null && msg.printTerminalId != null) {
          inject<PrintQueueService>().onRemoteGrant(
            msg.printJobId!,
            msg.printTerminalId!,
          );
        }
        break;
      case LanHubMessageType.printerSettings:
        // Every role, like `localChange`: a printer hangs off whichever
        // terminal it is plugged into, leader or follower, and the hub has
        // already passed this on to the rest.
        final entries = msg.printerEntries;
        final peer = msg.printTerminalId;
        if (entries != null && peer != null && peer.isNotEmpty) {
          unawaited(_applyPeerPrinterSettings(peer, entries));
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

  Future<void> _applyPeerPrinterSettings(String peer, String entriesJson) async {
    try {
      final decoded = jsonDecode(entriesJson);
      if (decoded is! List) return;
      await inject<PrinterConfigStorage>().applyPeerPrinterSettings(
        peerTerminalId: peer,
        entries: PrinterSettingEntry.listFromJsonList(decoded),
      );
    } catch (e) {
      if (kDebugMode) print('[LanHub] printerSettings parse xatosi: $e');
    }
  }

  /// Tells the rest of the venue which printers are attached to **this**
  /// terminal, so a job for one of them is relayed here instead of being
  /// dialled from a machine that cannot reach it.
  ///
  /// Sent when the hub link comes up, when the peer set changes, and after any
  /// local printer-settings change (`di.dart` wires the first two, the
  /// settings screen the third) — the same three moments the print relay's own
  /// `retryPendingRelays` cares about. Cheap enough to repeat: a handful of
  /// rows, and the receiver's merge is idempotent.
  ///
  /// Only this terminal's own entries go out. What it learned from a peer
  /// stays where it was learned — echoing it back would let a printer's owner
  /// drift around the venue.
  void announcePrinterSettings() {
    if (mode == LanMode.disabled) return;
    final storage = inject<PrinterConfigStorage>();
    _sendOrBroadcast(
      LanHubMessage.printerSettings(
        terminalId: inject<PrintQueueService>().terminalId,
        cashRegisterId: storage.myCashRegisterId,
        entriesJson: PrinterSettingEntry.encodeList(
          storage.entriesOwnedByThisTerminal(),
        ),
      ),
    );
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

  /// Hands one locally-committed row to every other terminal in the venue.
  ///
  /// Unlike [broadcastChangeFeed], this runs in **both** roles and routes
  /// through [_sendOrBroadcast]: a follower's write has to travel upstream to
  /// the leader, which then fans it out to the remaining followers
  /// (`LanHubServer._broadcastExcept`, plus `onBroadcast` for the leader's own
  /// app layer). The cloud feed flows one way because only the leader has it;
  /// a local write can originate anywhere, so this one does not.
  void broadcastLocalChange(LanHubMessage message) => _sendOrBroadcast(message);

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

  void broadcastPrintJobClaim(String jobId, String terminalId) {
    _sendOrBroadcast(
      LanHubMessage.printJobClaim(jobId: jobId, terminalId: terminalId),
    );
  }

  /// The originator naming the one terminal allowed to print [jobId].
  void broadcastPrintJobGrant(String jobId, String terminalId) {
    _sendOrBroadcast(
      LanHubMessage.printJobGrant(jobId: jobId, terminalId: terminalId),
    );
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
    await _clientMessageSub?.cancel();
    _clientMessageSub = null;
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
