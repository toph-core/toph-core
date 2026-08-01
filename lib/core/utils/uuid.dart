import 'dart:math';

/// RFC 4122 v4 (random) UUID generator. Hand-rolled rather than pulling in the
/// `uuid` package — the backend's `CreateOrderRequest.id` example is a
/// standard UUID shape and may validate against it, so this needs to produce
/// a real one, but the algorithm is ~10 lines and not worth a new dependency.
String generateUuidV4() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx

  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
