import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';
import 'printer_setting_entry.dart';

/// Printer sozlamalarining **shu qurilmadagi** manzili — sozlamalar ekrani
/// to'g'ridan-to'g'ri shu yerga o'qiydi/yozadi (backendga bog'liq emas).
/// Backenddagi `GET/POST/PUT/DELETE /api/v1/settings/printer-settings` faqat
/// eng yaxshi urinish sifatida, alohida chaqiriladi — muvaffaqiyatsiz bo'lsa
/// ham lokal holat o'zgarmasdan ishlashda davom etadi (`printers_section.dart`).
/// `SyncPrinterSettingsUsecase` (login paytida) hali ham backend ro'yxati
/// bilan almashtirib qo'yishi mumkin — shu sababli faqat lokal saqlangan
/// (backendga hech qachon yuborilmagan) yozuvlar keyingi loginda yo'qolishi
/// mumkin. Hozircha qasddan shunday — sinov bosqichi.
class PrinterConfigStorage {
  PrinterConfigStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _jsonKey = 'printer_settings_entries_v2_json';

  static const defaultPort = 9100;
  static const fallbackCloseCheckIp = '192.168.1.222';

  Future<void> applyPrinterSettingsList(List<PrinterSettingEntry> list) async {
    await _prefs.setString(_jsonKey, PrinterSettingEntry.encodeList(list));
  }

  List<PrinterSettingEntry> _entries() {
    final s = _prefs.getString(_jsonKey);
    if (s == null || s.isEmpty) return [];
    try {
      final decoded = jsonDecode(s) as List<dynamic>;
      return decoded
          .map(
            (e) => PrinterSettingEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Sozlamalar ekrani uchun — to'liq ro'yxat, backendga murojaat qilmasdan.
  List<PrinterSettingEntry> listEntries() => _entries();

  /// `id` bo'yicha yangi yozuvni qo'shadi yoki mavjudini almashtiradi.
  Future<void> upsertEntry(PrinterSettingEntry entry) async {
    final list = _entries();
    final idx = list.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await applyPrinterSettingsList(list);
  }

  Future<void> deleteEntry(String id) async {
    final list = _entries()..removeWhere((e) => e.id == id);
    await applyPrinterSettingsList(list);
  }

  // ─── USB printer names (per-device, never synced to the backend) ─────
  //
  // A `connection_type: usb` entry is shared across the team like any other
  // printer setting, but the Windows-installed printer name it should target
  // only means anything on the one PC its cable is plugged into. So the
  // entry.id -> Windows printer name mapping is device-scoped, exactly like
  // the entries above — OFFLINE_FIRST_EVERYWHERE_PLAN.md §2's one deliberate
  // exception to "one database", not replica state.

  static const _usbNamesKey = 'printer_usb_names_json';

  Map<String, String> _usbNames() {
    final raw = _prefs.getString(_usbNamesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map;
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  String? getUsbPrinterName(String entryId) => _usbNames()[entryId];

  Future<void> saveUsbPrinterName(String entryId, String printerName) async {
    final map = _usbNames()..[entryId] = printerName;
    await _prefs.setString(_usbNamesKey, jsonEncode(map));
  }

  /// One-shot move of the map out of the retiring Hive `pos_cache` box.
  /// No-op once this device has a prefs entry, so it costs one absent-key
  /// lookup per launch and never overwrites a name picked since. Goes when
  /// `CacheService`, its only caller's source, is deleted.
  Future<void> adoptLegacyUsbPrinterNames(Map<String, String> legacy) async {
    if (legacy.isEmpty) return;
    if (_prefs.containsKey(_usbNamesKey)) return;
    await _prefs.setString(_usbNamesKey, jsonEncode(legacy));
  }

  Future<void> removeUsbPrinterName(String entryId) async {
    final map = _usbNames();
    if (map.remove(entryId) != null) {
      await _prefs.setString(_usbNamesKey, jsonEncode(map));
    }
  }

  // ─── Chek kengligi / paper size (per-device, never synced) ───────────
  //
  // XPRINTER_SETUP.md: bir printer "80mm sinf" bo'lsa ham 32 belgi (58mm
  // shabloni) chiqarishi mumkin, boshqasi esa 48 (80mm). Backend
  // `printer-settings`da bunday ustun yo'q, shuning uchun tanlov — USB printer
  // nomi kabi — shu qurilmada `entryId` bo'yicha saqlanadi va keyingi
  // login sinxronizatsiyasida yo'qolmaydi.

  static const _paperSizesKey = 'printer_paper_sizes_json';

  Map<String, String> _paperSizes() {
    final raw = _prefs.getString(_paperSizesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map;
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Saqlangan kod (`'mm58'`/`'mm80'`) yoki `null` (tanlanmagan → 80mm).
  String? getPaperSizeCode(String entryId) => _paperSizes()[entryId];

  /// Bu printer uchun chek kengligi — tanlanmagan bo'lsa 80mm (mavjud xulq).
  PaperSize getPaperSize(String entryId) =>
      paperSizeFromCode(getPaperSizeCode(entryId));

  Future<void> savePaperSizeCode(String entryId, String code) async {
    final map = _paperSizes()..[entryId] = code;
    await _prefs.setString(_paperSizesKey, jsonEncode(map));
  }

  Future<void> removePaperSize(String entryId) async {
    final map = _paperSizes();
    if (map.remove(entryId) != null) {
      await _prefs.setString(_paperSizesKey, jsonEncode(map));
    }
  }

  /// Backend hali ko'rmagan yangi yozuv uchun — vaqt tamg'asi asosida,
  /// shu qurilmada takrorlanmaydigan id.
  String generateLocalId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}';

  /// `GET printer-settings` muvaffaqiyatli yozilgan bo‘lsa `true` (bo‘sh ro‘yxat ham `true`).
  bool get hasPrinterSettingsEntries => _entries().isNotEmpty;

  /// `type: close_check` — to‘lov / smena yopish cheklari.
  PrinterConfig? getCloseCheckPrinter() {
    for (final e in _entries()) {
      if (e.isCloseCheck && e.ip.isNotEmpty && e.port > 0) {
        return PrinterConfig(
          ip: e.ip,
          port: e.port,
          connectionType: e.connectionType,
          entryId: e.id,
          paperSize: getPaperSize(e.id),
        );
      }
    }
    return null;
  }

  PrinterConfig closeCheckConfigOrFallback() =>
      getCloseCheckPrinter() ??
      const PrinterConfig(ip: fallbackCloseCheckIp, port: defaultPort);

  /// Oshxona: `type=category` va `connected_entity_ids` ichida [categoryId] yoki [goodId] mos kelganda.
  /// Mos yozuv yo‘q bo‘lsa `null` — boshqa printerga «tushirish» qilinmaydi.
  PrinterConfig? categoryPrinterForOrNull(
    String categoryId, {
    String? goodId,
  }) {
    final wantCat = categoryId.trim();
    final wantGood = goodId?.trim() ?? '';
    if (wantCat.isEmpty && wantGood.isEmpty) return null;

    final list = _entries();
    if (wantCat.isNotEmpty) {
      for (final e in list) {
        if (!e.isCategory || e.ip.isEmpty || e.port <= 0) continue;
        for (final cid in e.connectedEntityIds) {
          if (_idEq(cid, wantCat)) {
            return PrinterConfig(
              ip: e.ip,
              port: e.port,
              connectionType: e.connectionType,
              entryId: e.id,
              paperSize: getPaperSize(e.id),
            );
          }
        }
      }
    }
    if (wantGood.isNotEmpty) {
      for (final e in list) {
        if (!e.isCategory || e.ip.isEmpty || e.port <= 0) continue;
        for (final cid in e.connectedEntityIds) {
          if (_idEq(cid, wantGood)) {
            return PrinterConfig(
              ip: e.ip,
              port: e.port,
              connectionType: e.connectionType,
              entryId: e.id,
              paperSize: getPaperSize(e.id),
            );
          }
        }
      }
    }
    return null;
  }

  bool _idEq(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}
