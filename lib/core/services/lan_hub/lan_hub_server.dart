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

class LanHubServer {
  static const defaultPort = 8765;
  static const _authTimeout = Duration(seconds: 5);

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  LanAuthValidator? _authValidator;
  LanRelayHandler? _onRelayOp;

  bool get isRunning => _server != null;
  int get clientCount => _clients.length;

  Future<void> start({
    int port = defaultPort,
    required LanAuthValidator authValidator,
    required LanRelayHandler onRelayOp,
  }) async {
    if (_server != null) return;
    _authValidator = authValidator;
    _onRelayOp = onRelayOp;
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
      },
      onDone: () {
        _clients.remove(ws);
        timeout?.cancel();
        if (kDebugMode) print('[LanHub] Client disconnected');
      },
      onError: (_) {
        _clients.remove(ws);
        timeout?.cancel();
      },
      cancelOnError: true,
    );
  }

  void broadcast(LanHubMessage message) {
    final json = message.toJson();
    for (final ws in List.of(_clients)) {
      try {
        ws.add(json);
      } catch (_) {
        _clients.remove(ws);
      }
    }
  }

  void _broadcastExcept(String json, WebSocket sender) {
    for (final ws in List.of(_clients)) {
      if (ws == sender) continue;
      try {
        ws.add(json);
      } catch (_) {
        _clients.remove(ws);
      }
    }
  }

  Future<void> stop() async {
    for (final ws in _clients) {
      await ws.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    _authValidator = null;
    _onRelayOp = null;
  }
}
