import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

const _kBundledRootsAsset = 'assets/certs/isrg_roots.pem';

Future<SecurityContext> buildAppSecurityContext() async {
  final context = SecurityContext(withTrustedRoots: true);
  try {
    final pem = await rootBundle.load(_kBundledRootsAsset);
    context.setTrustedCertificatesBytes(pem.buffer.asUint8List());
  } catch (e) {
    if (kDebugMode) {
      debugPrint('buildAppSecurityContext: $e');
    }
  }
  return context;
}

