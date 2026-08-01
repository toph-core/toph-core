import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// One hub's self-announcement, as heard by a listener on the LAN.
typedef HubAnnouncement = ({
  String ip,
  int port,
  String branchId,
  DateTime heardAt,
});

/// Lightweight UDP broadcast beacon — lets a `client` terminal find its
/// leader's IP automatically instead of a manager typing it in by hand, and
/// lets a `server` terminal notice a second leader on the same branch
/// (split-brain) without any central coordinator. Deliberately not
/// mDNS/Bonjour or a pub.dev discovery package: the rest of this LAN hub is
/// already hand-rolled raw `dart:io` sockets (`LanHubServer`/`LanHubClient`),
/// and a plain UDP broadcast needs nothing more than that same primitive
/// plus one extra port.
///
/// Not authenticated — an announcement only ever carries a branch id, never
/// a token, and is used to populate a picker or raise a warning, never to
/// authorize anything by itself. The real handshake still goes through
/// `LanHubServer`'s existing JWT-based `auth` exchange over the WebSocket
/// once a terminal decides (manually or via this picker) which IP to dial.
class LanDiscoveryService {
  static const defaultPort = 8766;
  static const _announceInterval = Duration(seconds: 2);
  static const _magic = 'mary_ai_pos_hub';

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  int _activePort = defaultPort;
  final _announcements = StreamController<HubAnnouncement>.broadcast();

  /// Per-process random id stamped on every announcement this instance
  /// sends, so a server that is simultaneously announcing and listening
  /// (for the conflict guard) can filter out hearing its own broadcast —
  /// there's no other stable "is this me" signal available from a UDP
  /// datagram's source address alone (it may show up as a local interface
  /// address rather than something obviously self-referential).
  final String _instanceId = _generateInstanceId();

  Stream<HubAnnouncement> get onAnnouncement => _announcements.stream;

  bool get isActive => _socket != null;

  static String _generateInstanceId() {
    final rand = Random();
    return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  /// Leader side: broadcasts `{branchId, wsPort}` every 2s so any terminal
  /// listening — a `client` running [discoverHubs]-style scan, or another
  /// `server` watching for a conflicting duplicate — can hear this hub
  /// exists without being told its IP in advance.
  Future<void> startAnnouncing({
    required String branchId,
    required int wsPort,
    int port = defaultPort,
  }) async {
    await _ensureSocket(port);
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(_announceInterval, (_) {
      _send(branchId: branchId, wsPort: wsPort);
    });
    _send(branchId: branchId, wsPort: wsPort); // birinchi announce darhol
  }

  /// Listener-only side: starts receiving broadcasts onto [onAnnouncement]
  /// without sending anything. Used both for a one-off `client` discovery
  /// scan and (implicitly, via [startAnnouncing] reusing the same socket)
  /// for a `server`'s standing conflict watch.
  Future<void> startListening({int port = defaultPort}) async {
    await _ensureSocket(port);
  }

  Future<void> _ensureSocket(int port) async {
    if (_socket != null) return;
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _activePort = port;
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onEvent);
      if (kDebugMode) print('[LanDiscovery] Listening on UDP $port');
    } catch (e) {
      if (kDebugMode) print('[LanDiscovery] Failed to bind UDP $port: $e');
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    try {
      final map = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (map['magic'] != _magic) return;
      if (map['instance_id'] == _instanceId) return; // o'zimning e'lonim
      final branchId = map['branch_id'] as String?;
      final wsPort = map['ws_port'] as int?;
      if (branchId == null || branchId.isEmpty || wsPort == null) return;
      if (_announcements.isClosed) return;
      _announcements.add((
        ip: datagram.address.address,
        port: wsPort,
        branchId: branchId,
        heardAt: DateTime.now(),
      ));
    } catch (_) {
      // Boshqa ilova/qurilmaning shu portdagi UDP trafigi bo'lishi mumkin —
      // jim tashlab yuborish, xato sifatida ko'tarmaslik.
    }
  }

  void _send({required String branchId, required int wsPort}) {
    final socket = _socket;
    if (socket == null) return;
    final payload = utf8.encode(jsonEncode({
      'magic': _magic,
      'instance_id': _instanceId,
      'branch_id': branchId,
      'ws_port': wsPort,
    }));
    try {
      socket.send(payload, InternetAddress('255.255.255.255'), _activePort);
    } catch (_) {}
  }

  /// Stops announcing (if this instance was) and releases the UDP socket —
  /// safe to call whether or not [startAnnouncing]/[startListening] ran.
  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> dispose() async {
    await stop();
    if (!_announcements.isClosed) await _announcements.close();
  }
}
