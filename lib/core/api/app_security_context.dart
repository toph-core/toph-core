import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Path to the bundled Let's Encrypt (ISRG) root certificates.
const _kBundledRootsAsset = 'assets/certs/isrg_roots.pem';

/// Builds a [SecurityContext] that trusts the platform's built-in root
/// certificates PLUS the bundled ISRG (Let's Encrypt) roots.
///
/// Why this exists:
/// On Windows, Dart validates TLS against the Windows *system* root store.
/// Some machines — older images, or locked-down kiosks whose automatic root
/// update is firewalled — are missing Let's Encrypt's newer ISRG Root X1/X2.
/// On those machines an HTTPS request to our backend fails with:
///   HandshakeException: CERTIFICATE_VERIFY_FAILED:
///   unable to get local issuer certificate
/// even though the server sends a complete, valid chain (browsers still work
/// because they ship their own root store).
///
/// Bundling the ISRG roots makes the app trust our backend regardless of the
/// machine's system store, WITHOUT disabling certificate verification. We keep
/// `withTrustedRoots: true` so every other host (system CAs) still validates
/// normally; the bundled roots are added on top.
Future<SecurityContext> buildAppSecurityContext() async {
  final context = SecurityContext(withTrustedRoots: true);
  try {
    final pem = await rootBundle.load(_kBundledRootsAsset);
    context.setTrustedCertificatesBytes(pem.buffer.asUint8List());
  } catch (e) {
    // If the roots can't be added (e.g. already present in the platform
    // store, or the asset is unreadable) fall back to platform roots only.
    // We never weaken verification here — worst case is the original
    // platform behavior.
    if (kDebugMode) {
      debugPrint('buildAppSecurityContext: could not add bundled roots: $e');
    }
  }
  return context;
}
