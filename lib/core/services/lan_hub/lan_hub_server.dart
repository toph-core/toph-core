import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lan_hub_message.dart';

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
  static const defaultPort = 8765;
  static const _authTimeout = Duration(seconds: 5);

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  LanAuthValidator? _authValidator;
  LanRelayHandler? _onRelayOp;
  LanBroadcastListener? _onBroadcast;

  bool get isRunning => _server != null;
  int get clientCount => _clients.length;

  /// Reactive mirror of [clientCount] — for a sync-status screen to show a
  /// live peer count in `server` mode without its own polling timer. One
  /// instance per `LanHubServer`, which itself lives for the app's lifetime
  /// (see `LanHubService`'s `_server` field) — surviving `start`/`stop`
  /// cycles is what makes a single long-lived notifier here correct instead
  /// of needing to be re-created on every restart.
  final ValueNotifier<int> clientCountNotifier = ValueNotifier(0);

  void _syncClientCount() => clientCountNotifier.value = _clients.length;

  Future<void> start({
    int port = defaultPort,
    required LanAuthValidator authValidator,
    required LanRelayHandler onRelayOp,
    LanBroadcastListener? onBroadcast,
  }) async {
    if (_server != null) return;
    _authValidator = authValidator;
    _onRelayOp = onRelayOp;
    _onBroadcast = onBroadcast;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handleRequest);
      if (kDebugMode) print('[LanHub] Server started on port $port');
    } catch (e) {
      if (kDebugMode) print('[LanHub] Failed to start server: $e');
    }
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
    for (final ws in _clients) {
      await ws.close();
    }
    _clients.clear();
    _syncClientCount();
    await _server?.close(force: true);
    _server = null;
    _authValidator = null;
    _onRelayOp = null;
    _onBroadcast = null;
  }
}
