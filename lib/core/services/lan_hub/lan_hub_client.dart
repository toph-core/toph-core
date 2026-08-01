import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'lan_hub_message.dart';

typedef LanAuthCredentials = ({String token, String branchId});

class LanHubClient {
  static const defaultPort = 8765;

  WebSocket? _ws;
  String? _serverIp;
  int _port = defaultPort;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  final Random _random = Random();

  /// Re-read fresh on every (re)connect attempt — a token refreshed since the
  /// last attempt (or a different staff member logging in) must be picked up
  /// without needing `LanHubService` to call `connect()` again.
  Future<LanAuthCredentials> Function()? _getCredentials;

  bool _authorized = false;
  String? _lastAuthFailReason;

  static const _baseReconnectDelay = Duration(seconds: 2);
  static const _maxReconnectDelay = Duration(seconds: 30);

  final _controller = StreamController<LanHubMessage>.broadcast();
  Stream<LanHubMessage> get onMessage => _controller.stream;

  /// `true` only once the leader has accepted this terminal's credentials —
  /// a socket that's open but still mid-handshake isn't usable yet.
  bool get isConnected =>
      _ws != null && _ws!.readyState == WebSocket.open && _authorized;

  /// Set when the leader rejects this terminal (bad/expired token, wrong
  /// branch) — surfaced by the settings screen so a manager isn't just told
  /// "disconnected" with no reason.
  String? get lastAuthFailReason => _lastAuthFailReason;

  Future<void> connect(
    String ip, {
    int port = defaultPort,
    required Future<LanAuthCredentials> Function() getCredentials,
  }) async {
    _serverIp = ip;
    _port = port;
    _getCredentials = getCredentials;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed || _serverIp == null) return;
    _authorized = false;
    try {
      _ws = await WebSocket.connect('ws://$_serverIp:$_port').timeout(
        const Duration(seconds: 5),
      );
      _reconnectAttempts = 0;
      if (kDebugMode) print('[LanHub] Connected to $_serverIp:$_port — authenticating');

      _ws!.listen(
        (data) {
          if (data is! String) return;
          final msg = LanHubMessage.tryParse(data);
          if (msg == null) return;
          if (!_authorized) {
            if (msg.type == LanHubMessageType.authOk) {
              _authorized = true;
              _lastAuthFailReason = null;
              if (kDebugMode) print('[LanHub] Authorized by hub');
              return;
            }
            if (msg.type == LanHubMessageType.authFail) {
              _lastAuthFailReason = msg.reason;
              if (kDebugMode) print('[LanHub] Rejected by hub: ${msg.reason}');
              _ws?.close();
              return;
            }
            return; // ignore anything else until authorized
          }
          _controller.add(msg);
        },
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );

      final creds = await _getCredentials!.call();
      _ws!.add(
        LanHubMessage.auth(token: creds.token, branchId: creds.branchId).toJson(),
      );
    } on SocketException catch (e) {
      if (kDebugMode) print('[LanHub] Connect failed: $e');
      _scheduleReconnect();
    } on TimeoutException {
      if (kDebugMode) print('[LanHub] Connect timeout');
      _scheduleReconnect();
    } catch (e) {
      if (kDebugMode) print('[LanHub] Unexpected error: $e');
      _scheduleReconnect();
    }
  }

  void _onDisconnected() {
    _ws = null;
    _authorized = false;
    if (kDebugMode) print('[LanHub] Disconnected from hub');
    _scheduleReconnect();
  }

  /// Exponential backoff with jitter — a flat 5s retry meant every terminal
  /// on a branch would hammer the hub in lockstep right after an outage.
  /// Resets to zero on the next successful connect (see `_doConnect` above).
  Duration _nextReconnectDelay() {
    final exponent = min(_reconnectAttempts, 4);
    final full = _baseReconnectDelay.inMilliseconds * (1 << exponent);
    final capped = min(full, _maxReconnectDelay.inMilliseconds);
    final jitter = _random.nextInt(max(1, (capped * 0.3).round()));
    return Duration(milliseconds: capped + jitter);
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    final delay = _nextReconnectDelay();
    _reconnectAttempts++;
    if (kDebugMode) {
      print(
        '[LanHub] Reconnecting in ${delay.inMilliseconds}ms (attempt $_reconnectAttempts)',
      );
    }
    Future.delayed(delay, _doConnect);
  }

  void send(LanHubMessage message) {
    if (!isConnected) return;
    try {
      _ws!.add(message.toJson());
    } catch (_) {}
  }

  /// Sends a `relayOp` request and waits (bounded by [timeout]) for the
  /// matching `relayOpResult` — returns its raw `result` string, or `null`
  /// if not currently connected, the link drops mid-wait, or no reply
  /// arrives in time. Deliberately returns a bare string rather than an
  /// app-level `RelayOpResult` — this class stays a pure message transport,
  /// same reasoning as `LanHubServer`'s `LanRelayHandler` typedef.
  ///
  /// [timeout] is deliberately well above the leader's own `DioClient`
  /// timeout (30s connect/receive) plus margin for ops that make several
  /// sequential cloud calls (e.g. `cancelLineItems` with multiple line ids,
  /// or `closeShift`'s active-shift lookup before the actual close) — a
  /// follower giving up before the leader's own call could possibly resolve
  /// just means retrying an op that may have already landed. See
  /// offline-first-architecture-plan.md §11 Phase 4 for why that's an
  /// accepted, pre-existing class of risk (no backend idempotency keys),
  /// not one this relay layer invents.
  Future<String?> relayOp({
    required String opId,
    required String opType,
    required String opPayload,
    required String opTableId,
    required String opCreatedAt,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!isConnected) return null;
    final completer = Completer<String?>();
    late final StreamSubscription<LanHubMessage> sub;
    sub = onMessage.listen((msg) {
      if (msg.type == LanHubMessageType.relayOpResult && msg.opId == opId) {
        if (!completer.isCompleted) completer.complete(msg.result);
      }
    });
    try {
      send(
        LanHubMessage.relayOp(
          opId: opId,
          opType: opType,
          opPayload: opPayload,
          opTableId: opTableId,
          opCreatedAt: opCreatedAt,
        ),
      );
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  /// Ulanishni yopadi, ammo qayta ulanishga ruxsat beradi.
  Future<void> disconnect() async {
    await _ws?.close();
    _ws = null;
    _authorized = false;
  }

  /// To'liq o'chirish — qayta ulanish mumkin emas.
  Future<void> dispose() async {
    _disposed = true;
    await _ws?.close();
    _ws = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
