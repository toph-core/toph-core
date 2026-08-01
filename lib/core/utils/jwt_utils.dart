import 'dart:convert';

/// Decodes the payload of [token] (no signature verification — this app has
/// no local copy of the backend's signing key, so this can only check shape
/// and claims, never prove the token wasn't forged) and reports whether its
/// `exp` claim has passed. Any parse failure is treated as expired — fail
/// closed rather than open.
bool isJwtExpired(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return true;
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map) return true;
    final exp = decoded['exp'];
    if (exp is! num) return true;
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * 1000,
      isUtc: true,
    );
    return DateTime.now().toUtc().isAfter(expiry);
  } catch (_) {
    return true;
  }
}
