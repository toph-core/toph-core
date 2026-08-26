/// Port policy for the whole LAN hub stack.
///
/// Nothing here binds anything — it only decides *which* ports to try, so the
/// server, the client and the discovery beacon all agree on the same rule
/// without importing each other.
///
/// Both ports used to be `static const` on their own service, which made a
/// busy port unrecoverable: no fallback, no setting, and (because every bind
/// failure was swallowed) no way to even see it had happened. A venue with any
/// other software on 8765/8766 had a LAN stack that silently did nothing.
library;

/// Preferred WebSocket port for `LanHubServer` — the leader's actual data
/// channel. Safe to move freely: the discovery beacon carries the real port in
/// its `ws_port` field, so followers learn it rather than assume it.
const kDefaultHubPort = 8765;

/// Preferred UDP port for `LanDiscoveryService`.
///
/// Unlike the hub port this one is a *rendezvous* — a hub that quietly moved to
/// a different UDP port than its listeners would never be heard, so it cannot
/// simply float. [candidatePorts] plus the send-to-every-candidate rule in
/// `LanDiscoveryService._send` is what makes moving it safe: a terminal binds
/// whichever candidate it can get, and broadcasts to all of them.
const kDefaultDiscoveryPort = 8766;

/// How many consecutive ports a bind may walk before giving up.
///
/// Deliberately small. The span is also the discovery beacon's per-tick
/// datagram count (one broadcast per candidate), so widening it costs real
/// packets every 2s; ten is far past any plausible run of occupied ports while
/// staying cheap.
const kPortScanSpan = 10;

/// [preferred] first, then the next [span] - 1 ports above it.
///
/// Ascending and contiguous on purpose: it makes the set a terminal binds and
/// the set it broadcasts to derivable from one number, so two terminals with
/// the same configured preference always overlap even when they end up bound
/// to different ports.
List<int> candidatePorts(int preferred, {int span = kPortScanSpan}) {
  final base = normalizePort(preferred);
  return [
    for (var i = 0; i < span; i++)
      if (base + i <= 65535) base + i,
  ];
}

/// Clamps to the range a user could plausibly type into the settings field.
/// Below 1024 needs privileges this app does not have on desktop, and the span
/// above must stay addressable.
int normalizePort(int port) {
  if (port < 1024) return 1024;
  if (port > 65535 - kPortScanSpan) return 65535 - kPortScanSpan;
  return port;
}

/// Parses a manually-typed hub address, accepting either `192.168.1.5` or
/// `192.168.1.5:8770`. Returns a null port when none was given, leaving the
/// caller to apply its own default rather than guessing one here.
({String ip, int? port})? parseHostPort(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final colon = text.lastIndexOf(':');
  if (colon < 0) return (ip: text, port: null);
  final ip = text.substring(0, colon).trim();
  final port = int.tryParse(text.substring(colon + 1).trim());
  if (ip.isEmpty || port == null || port < 1 || port > 65535) return null;
  return (ip: ip, port: port);
}
