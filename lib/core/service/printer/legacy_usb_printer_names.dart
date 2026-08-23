import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// One-shot reader for the USB printer names left in the retired Hive
/// `pos_cache` box, so a device upgrading to the replica build keeps the
/// Windows printer each of its USB entries points at.
///
/// This is all that survives of `CacheService`. Everything else that box held
/// was a mirror of server state, which the replica now holds properly; the
/// USB name is the one genuinely device-scoped value in it, and it exists
/// nowhere else — losing it means a cashier re-picking their printer in
/// settings. `PrinterConfigStorage.adoptLegacyUsbPrinterNames` calls this once
/// per launch and no-ops the moment prefs hold a value, so the cost is one
/// absent-key lookup.
///
/// Delete this file, its call in `di.dart`, and `adoptLegacyUsbPrinterNames`
/// once every terminal in the field has run a build containing them.
class LegacyUsbPrinterNames {
  static const _boxName = 'pos_cache';
  static const _key = 'cache_usb_printer_names';

  const LegacyUsbPrinterNames._();

  /// The stored entry.id -> Windows printer name map, or empty when the box
  /// never existed, was already cleared, or holds something unparseable.
  /// Never throws: a failed migration must not stop the app from starting.
  static Future<Map<String, String>> read() async {
    try {
      if (!await Hive.boxExists(_boxName)) return const {};
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_key);
      if (raw is! String || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      if (kDebugMode) debugPrint('[LegacyUsbPrinterNames] read: $e');
      return const {};
    }
  }
}
