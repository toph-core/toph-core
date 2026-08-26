import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lan_hub_message.dart';
import 'lan_ports.dart';

/// Validates a connecting terminal's presented `(token, branchId)` before its
/// socket is trusted for broadcast. Owned by `LanHubService` (which has the
/// app-level dependencies — token storage, Dio, connectivity — needed to
/// actually check them); this class only enforces the wire-level handshake.
typedef LanAuthValidator = Future<bool> Function(String token, String branchId);

/// Executes one relayed operation and returns a `RelayOpResult.name` string
/// (never a `RelayOpResult` type directly — this transport class stays
/// decoupled from `offline_queue_service.dart`'s vocabulary, same reason
/// `LanAuthValidator` returns a bare `bool` instead of an app-level type).
typedef LanRelayHandler = Future<String> Function(LanHubMessage relayOpMessage);

/// §6: arbitrates one `leaseRequest` and returns the reply to send back —
/// always a `leaseGranted`/`leaseRejected` message, never a raw string
/// (unlike [LanRelayHandler]) since the caller needs the full message,
/// `leaseHeldBy` included, to send straight back over the socket.
typedef LanLeaseHandler = Future<LanHubMessage> Function(LanHubMessage leaseRequestMessage);

/// §6 Lease Recovery: notifies the leader that a follower's lease-holding UI
/// action has finished (committed or abandoned) — best-effort, no reply.
typedef LanLeaseReleaseHandler = void Function(LanHubMessage leaseReleaseMessage);

/// Notified whenever the server receives a broadcast-worthy message (i.e.
/// anything that isn't `auth`/`relayOp`) from any client — **in addition to**
/// it being forwarded to every other client via [_broadcastExcept]. Without
/// this, a `server`-mode terminal has no way to react to its own clients'
/// broadcasts at the app layer (it only ever relayed the raw bytes onward);
/// harmless while the only broadcast type was cosmetic table-status, but a
/// real gap once print-job relay (Phase 5) needs the leader terminal to be
/// able to claim a job too, exactly like any other terminal — see
/// offline-first-architecture-plan.md §11 Phase 5.
typedef LanBroadcastListener = void Function(LanHubMessage message);

class LanHubServer {
  static const defaultPort = kDefaultHubPort;
  static const _authTimeout = Duration(seconds: 5);

  HttpServer? _server;
  int? _boundPort;
  String? _lastBindError;
  final Set<WebSocket> _clients = {};
  LanAuthValidator? _authValidator;
  LanRelayHandler? _onRelayOp;
  LanBroadcastListener? _onBroadcast;
  LanLeaseHandler? _onLeaseRequest;
  LanLeaseReleaseHandler? _onLeaseRelease;

  bool get isRunning => _server != null;
  int get clientCount => _clients.length;

  /// TCP port this hub is actually accepting WebSocket connections on, or null
  /// when nothing is bound. Followers are told this value through the discovery
  /// beacon's `ws_port`, and settings shows it so a fallback is visible.
  int? get boundPort => _boundPort;

  /// Why [start] failed to bind, when [isRunning] is false. Null while healthy.
  ///
  /// This used to be a `kDebugMode` print and nothing else, so a release build
  /// with an occupied port presented as a hub with zero connected clients —
  /// identical to a healthy hub nobody had joined yet.
  String? get lastBindError => _lastBindError;

  /// Reactive mirror of [boundPort]/[lastBindError] for the settings screen,
  /// so a bind outcome shows up without the screen polling for it. Null port
  /// means "not listening"; see [clientCountNotifier] for why one long-lived
  /// notifier per server is correct here.
  final ValueNotifier<int?> boundPortNotifier = ValueNotifier(null);

  /// Reactive mirror of [clientCount] — for a sync-status screen to show a
  /// live peer count in `server` mode without its own polling timer. One
  /// instance per `LanHubServer`, which itself lives for the app's lifetime
  /// (see `LanHubService`'s `_server` field) — surviving `start`/`stop`
  /// cycles is what makes a single long-lived notifier here correct instead
  /// of needing to be re-created on every restart.
  final ValueNotifier<int> clientCountNotifier = ValueNotifier(0);

  void _syncClientCount() => clientCountNotifier.value = _clients.length;

  /// Binds the first free port at or above [port].
  ///
  /// The hub port can move freely because the discovery beacon carries the
  /// real one in `ws_port` — a follower reads it from the announcement instead
  /// of assuming 8765. Only a manually-typed address has to be told, which is
  /// why the settings field accepts `ip:port`.
  Future<void> start({
    int port = defaultPort,
    required LanAuthValidator authValidator,
    required LanRelayHandler onRelayOp,
    LanBroadcastListener? onBroadcast,
    LanLeaseHandler? onLeaseRequest,
    LanLeaseReleaseHandler? onLeaseRelease,
  }) async {
    if (_server != null) return;
    _authValidator = authValidator;
    _onRelayOp = onRelayOp;
    _onBroadcast = onBroadcast;
    _onLeaseRequest = onLeaseRequest;
    _onLeaseRelease = onLeaseRelease;
    Object? lastError;
    for (final candidate in candidatePorts(port)) {
      try {
        final server = await HttpServer.bind(InternetAddress.anyIPv4, candidate);
        server.listen(_handleRequest);
        _server = server;
        _boundPort = candidate;
        _lastBindError = null;
        boundPortNotifier.value = candidate;
        if (kDebugMode) {
          final note = candidate == port ? '' : ' (preferred $port was busy)';
          print('[LanHub] Server started on port $candidate$note');
        }
        return;
      } catch (e) {
        lastError = e;
      }
    }
    _boundPort = null;
    _lastBindError = lastError?.toString() ?? 'bind failed';
    boundPortNotifier.value = null;
    if (kDebugMode) print('[LanHub] Failed to start server: $lastError');
  }

  void _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(request);
    if (kDebugMode) print('[LanHub] Connection pending auth');

    var authorized = false;
    Timer? timeout;

    void reject(String reason) {
      timeout?.cancel();
      try {
        ws.add(LanHubMessage.authFail(reason: reason).toJson());
      } catch (_) {}
      ws.close();
    }

    timeout = Timer(_authTimeout, () {
      if (!authorized) reject('timeout');
    });

    ws.listen(
      (data) async {
        if (data is! String) return;
        if (!authorized) {
          final msg = LanHubMessage.tryParse(data);
          if (msg == null || msg.type != LanHubMessageType.auth) {
            reject('invalid_handshake');
            return;
          }
          final ok = await (_authValidator?.call(
                msg.token ?? '',
                msg.branchId ?? '',
              ) ??
              Future.value(false));
          if (!ok) {
            reject('unauthorized');
            return;
          }
          authorized = true;
          timeout?.cancel();
          _clients.add(ws);
          _syncClientCount();
          if (kDebugMode) {
            print('[LanHub] Client authorized (total: ${_clients.length})');
          }
          try {
            ws.add(LanHubMessage.authOk().toJson());
          } catch (_) {}
          return;
        }
        final msg = LanHubMessage.tryParse(data);
        if (msg != null && msg.type == LanHubMessageType.relayOp) {
          // A relay request is a leader-directed RPC, not broadcast-worthy —
          // answer only the sender, never fan it out to other followers.
          final handler = _onRelayOp;
          final resultName = handler == null
              ? 'retryLater'
              : await handler(msg);
          try {
            ws.add(
              LanHubMessage.relayOpResult(
                opId: msg.opId ?? '',
                result: resultName,
              ).toJson(),
            );
          } catch (_) {}
          return;
        }
        if (msg != null && msg.type == LanHubMessageType.leaseRequest) {
          // Same leader-directed-RPC shape as relayOp above — a lease
          // arbitration concerns exactly the requester and the leader, never
          // other followers.
          final handler = _onLeaseRequest;
          final reply = handler == null
              ? LanHubMessage.leaseRejected(tableId: msg.tableId ?? '')
              : await handler(msg);
          try {
            ws.add(reply.toJson());
          } catch (_) {}
          return;
        }
        if (msg != null && msg.type == LanHubMessageType.leaseRelease) {
          _onLeaseRelease?.call(msg);
          return;
        }
        // Hub clientdan kelgan xabarni barcha boshqa clientlarga yuboradi
        _broadcastExcept(data, ws);
        // ...va bu terminalning o'z ilova qatlamiga ham yetkazadi — server
        // ham (masalan) printer egasi bo'lishi mumkin.
        if (msg != null) _onBroadcast?.call(msg);
      },
      onDone: () {
        _clients.remove(ws);
        _syncClientCount();
        timeout?.cancel();
        if (kDebugMode) print('[LanHub] Client disconnected');
      },
      onError: (_) {
        _clients.remove(ws);
        _syncClientCount();
        timeout?.cancel();
      },
      cancelOnError: true,
    );
  }

  void broadcast(LanHubMessage message) {
    final json = message.toJson();
    var removedAny = false;
    for (final ws in List.of(_clients)) {
      try {
        ws.add(json);
      } catch (_) {
        _clients.remove(ws);
        removedAny = true;
      }
    }
    if (removedAny) _syncClientCount();
  }

  void _broadcastExcept(String json, WebSocket sender) {
    var removedAny = false;
    for (final ws in List.of(_clients)) {
      if (ws == sender) continue;
      try {
        ws.add(json);
      } catch (_) {
        _clients.remove(ws);
        removedAny = true;
      }
    }
    if (removedAny) _syncClientCount();
  }

  Future<void> stop() async {
    // Iterate a snapshot: `await ws.close()` lets each socket's own `onDone`
    // fire and `_clients.remove(ws)` mid-loop, which over the live set would
    // throw ConcurrentModificationError — the same reason `broadcast` and
    // `_broadcastExcept` copy with `List.of`.
    for (final ws in List.of(_clients)) {
      await ws.close();
    }
    _clients.clear();
    _syncClientCount();
    await _server?.close(force: true);
    _server = null;
    _boundPort = null;
    _lastBindError = null;
    boundPortNotifier.value = null;
    _authValidator = null;
    _onRelayOp = null;
    _onBroadcast = null;
    _onLeaseRequest = null;
    _onLeaseRelease = null;
  }
}
