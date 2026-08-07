import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// One hub's self-announcement, as heard by a listener on the LAN.
///
/// [role]/[priority]/[epoch]/[terminalId] are optional — populated only by a
/// `LeaderElectionService` (§7) using this same beacon as its heartbeat
/// channel, per the design doc's explicit "the discovery beacon becomes the
/// heartbeat channel, not a separate mechanism." A plain conflict-watch
/// announcer (`LanHubService._watchForConflicts`, pre-§7) or an old build on
/// the same LAN simply never sets them, and [tryParse] below leaves them
/// null rather than failing — this type must stay parseable both ways.
typedef HubAnnouncement = ({
  String ip,
  int port,
  String branchId,
  DateTime heardAt,
  String? role,
  int? priority,
  int? epoch,
  String? terminalId,
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
  ///
  /// [heartbeatExtra], when given, is called fresh on every tick (not just
  /// once at start) so a `LeaderElectionService` (§7) can ride this same
  /// beacon as its heartbeat channel while its own `role`/`epoch` change
  /// over time — e.g. an epoch bump on becoming leader — without needing to
  /// restart the announce timer.
  Future<void> startAnnouncing({
    required String branchId,
    required int wsPort,
    int port = defaultPort,
    ({String? role, int? priority, int? epoch, String? terminalId})
        Function()? heartbeatExtra,
  }) async {
    await _ensureSocket(port);
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(_announceInterval, (_) {
      final extra = heartbeatExtra?.call();
      _send(
        branchId: branchId,
        wsPort: wsPort,
        role: extra?.role,
        priority: extra?.priority,
        epoch: extra?.epoch,
        terminalId: extra?.terminalId,
      );
    });
    final extra = heartbeatExtra?.call();
    _send(
      branchId: branchId,
      wsPort: wsPort,
      role: extra?.role,
      priority: extra?.priority,
      epoch: extra?.epoch,
      terminalId: extra?.terminalId,
    ); // birinchi announce darhol
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
        role: map['role'] as String?,
        priority: map['priority'] as int?,
        epoch: map['epoch'] as int?,
        terminalId: map['terminal_id'] as String?,
      ));
    } catch (_) {
      // Boshqa ilova/qurilmaning shu portdagi UDP trafigi bo'lishi mumkin —
      // jim tashlab yuborish, xato sifatida ko'tarmaslik.
    }
  }

  void _send({
    required String branchId,
    required int wsPort,
    String? role,
    int? priority,
    int? epoch,
    String? terminalId,
  }) {
    final socket = _socket;
    if (socket == null) return;
    final payload = utf8.encode(jsonEncode({
      'magic': _magic,
      'instance_id': _instanceId,
      'branch_id': branchId,
      'ws_port': wsPort,
      if (role != null) 'role': role,
      if (priority != null) 'priority': priority,
      if (epoch != null) 'epoch': epoch,
      if (terminalId != null) 'terminal_id': terminalId,
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
