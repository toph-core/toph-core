import 'dart:io';

import 'package:flutter/foundation.dart';

/// One IPv4 address this terminal currently holds, tagged with the interface
/// it belongs to (`wlan0`, `eth0`, `en0`, …) so a manager reading it off the
/// Hub screen can tell the Wi-Fi address from the docker bridge.
typedef LocalAddress = ({String interface, String ip, bool isPrivateLan});

/// Interface-name prefixes that are almost never the address another POS
/// terminal can dial: container bridges, VM host-only networks, VPN tunnels.
/// A hub bound to `InternetAddress.anyIPv4` does listen on these too, which is
/// exactly why UDP discovery can hand a client an address that answers no
/// connection — see `LanDiscoveryService`, which reports the datagram's source
/// address without knowing which interface it left by.
const _virtualPrefixes = [
  'docker',
  'br-',
  'veth',
  'virbr',
  'vbox',
  'vmnet',
  'tun',
  'tap',
  'utun',
  'zt',
  'wg',
];

bool _looksVirtual(String name) {
  final n = name.toLowerCase();
  return _virtualPrefixes.any(n.startsWith);
}

/// True for the RFC1918 ranges a venue LAN actually uses. Anything else — a
/// 169.254 link-local, a CGNAT 100.64, a public address — is still listed, just
/// ranked below these, because it is far less likely to be the one to type in.
bool _isPrivateLan(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 192 && b == 168) return true;
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

/// Every non-loopback IPv4 address this device is reachable at, best candidate
/// first: real private-LAN addresses on physical interfaces, then anything
/// else, then virtual/container interfaces last.
///
/// Surfaced on the Hub settings screen so a client that auto-discovery pointed
/// at the wrong interface can be given the right address by hand.
Future<List<LocalAddress>> listLocalIpv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: true,
      type: InternetAddressType.IPv4,
    );
    final out = <LocalAddress>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback) continue;
        out.add((
          interface: iface.name,
          ip: addr.address,
          isPrivateLan: _isPrivateLan(addr.address),
        ));
      }
    }
    out.sort((a, b) {
      final aRank = _rank(a);
      final bRank = _rank(b);
      if (aRank != bRank) return aRank.compareTo(bRank);
      return a.ip.compareTo(b.ip);
    });
    return out;
  } catch (e) {
    if (kDebugMode) print('[LanHub] Failed to list local addresses: $e');
    return [];
  }
}

int _rank(LocalAddress a) {
  if (_looksVirtual(a.interface)) return 2;
  return a.isPrivateLan ? 0 : 1;
}
