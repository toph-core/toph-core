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
    await _rekeyDeviceLocalState(from: _entries(), to: list);
    await _prefs.setString(_jsonKey, PrinterSettingEntry.encodeList(list));
  }

  /// Carries this device's per-entry state across a change of entry id.
  ///
  /// A printer added on this terminal gets a local id (`generateLocalId`)
  /// because the push to the backend is best-effort and its response is not
  /// waited on. The backend assigns its own UUID, and the next login's
  /// `SyncPrinterSettingsUsecase` replaces the whole list with the server's —
  /// at which point the two maps keyed by entry id, the USB printer name and
  /// the paper size, point at an id nothing has any more.
  ///
  /// For a USB printer that is not cosmetic: the Windows printer name is the
  /// only thing that says *which* attached printer to drive, and without it
  /// `PrintQueueService` will not even claim a job for that entry. So a printer
  /// that worked before the sync would quietly stop working after it.
  ///
  /// Matching is on identity rather than id — the same tuple the backend's own
  /// `uq_printer_settings_identity_active` uses, minus the branch, which a
  /// terminal cannot see. `name` is required for USB precisely so this stays
  /// unambiguous. Anything that does not match is left alone: a stale entry in
  /// either map costs one unused key, while a wrong match would send tickets to
  /// the wrong printer.
  Future<void> _rekeyDeviceLocalState({
    required List<PrinterSettingEntry> from,
    required List<PrinterSettingEntry> to,
  }) async {
    if (from.isEmpty || to.isEmpty) return;

    final survivingIds = to.map((e) => e.id).toSet();
    final byIdentity = <String, String>{
      for (final e in to) _identityKey(e): e.id,
    };

    final usbNames = _usbNames();
    final paperSizes = _paperSizes();
    var usbChanged = false;
    var paperChanged = false;

    for (final old in from) {
      if (survivingIds.contains(old.id)) continue;
      final newId = byIdentity[_identityKey(old)];
      if (newId == null || newId == old.id) continue;

      final usbName = usbNames[old.id];
      if (usbName != null && !usbNames.containsKey(newId)) {
        usbNames[newId] = usbName;
        usbChanged = true;
      }
      final paperSize = paperSizes[old.id];
      if (paperSize != null && !paperSizes.containsKey(newId)) {
        paperSizes[newId] = paperSize;
        paperChanged = true;
      }
    }

    if (usbChanged) {
      await _prefs.setString(_usbNamesKey, jsonEncode(usbNames));
    }
    if (paperChanged) {
      await _prefs.setString(_paperSizesKey, jsonEncode(paperSizes));
    }
  }

  /// What makes two printer records "the same printer" regardless of id.
  static String _identityKey(PrinterSettingEntry e) => [
        e.ownerCashRegisterId.trim().toLowerCase(),
        e.type.trim().toLowerCase(),
        e.connectionType.trim().toLowerCase(),
        e.ip.trim().toLowerCase(),
        e.port,
        e.name.trim().toLowerCase(),
      ].join('|');

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

  /// `id` bo'yicha yozuv, topilmasa `null`.
  PrinterSettingEntry? entryById(String id) {
    if (id.isEmpty) return null;
    for (final e in _entries()) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ─── This POS instance's identity ───────────────────────────────────────
  //
  // Printer ownership is keyed on `cash_register_id`, not on the LAN's
  // `print_terminal_id`. The cash register is the one POS-instance identity
  // the *server* knows — it is a claim on every POS token — so the backend can
  // record it, the web admin can assign it, and a printer keeps its owner
  // across a reinstall. `print_terminal_id` is a random hex string in one
  // machine's prefs that regenerates the moment the app is reinstalled.
  //
  // `LoginDataScopeService` already writes the claim, on every successful
  // login, into `pos_last_auth_context` — plain `SharedPreferences`, not
  // secure storage (see `AppTokenStorage._secureKeys`). Reading it back here
  // rather than re-decoding the JWT keeps this class synchronous, which
  // everything on the print path depends on.

  /// `TokensStorageKeys.lastAuthContext` — takrorlanmasin deb shu yerda ham
  /// yozib qo'yilgan; ikkalasi bir xil bo'lishi shart.
  static const _authContextKey = 'pos_last_auth_context';

  /// Shu terminal kirgan kassa identifikatori — egalikni aniqlash uchun.
  /// Login bo'lmagan holatda `''` (hech qanday printer «meniki» bo'lmaydi,
  /// egasizlari esa avvalgidek to'g'ridan-to'g'ri ishlaydi).
  String get myCashRegisterId {
    final raw = _prefs.getString(_authContextKey);
    if (raw == null || raw.isEmpty) return '';
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return '';
      return json['cash_register_id']?.toString().trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Bu printer shu terminalniki (egasi aynan shu kassa).
  bool isOwnedByThisTerminal(PrinterSettingEntry entry) =>
      entry.isOwnedBy(myCashRegisterId);

  /// `entryId` bo'yicha xuddi shu tekshiruv — `PrintQueueService` LAN'dan
  /// kelgan e'lonni faqat `entryId` bilan biladi.
  bool ownsEntryId(String entryId) {
    final entry = entryById(entryId);
    if (entry == null) return false;
    return isOwnedByThisTerminal(entry);
  }

  /// `entryId` uchun to'liq chop etish konfiguratsiyasi — LAN orqali kelgan
  /// ishni bajarayotgan terminal e'londa faqat `entryId` oladi va nishonni shu
  /// yerdan tiklaydi. Yozuv topilmasa `null` («meniki emas»).
  PrinterConfig? configForEntryId(String entryId) {
    final entry = entryById(entryId);
    if (entry == null) return null;
    return _configFor(entry);
  }

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

  /// Yozuvdan chop etish konfiguratsiyasi — egasi, chek kengligi va (USB
  /// bo'lsa) shu qurilmadagi Windows printer nomi bilan birga.
  PrinterConfig _configFor(PrinterSettingEntry e) => PrinterConfig(
        ip: e.ip,
        port: e.port,
        connectionType: e.connectionType,
        entryId: e.id,
        paperSize: getPaperSize(e.id),
        ownerCashRegisterId: e.ownerCashRegisterId,
        windowsPrinterName: e.isAddressless ? getUsbPrinterName(e.id) : null,
      );

  /// Yozuv chop etish uchun yaroqli: manzilsiz (USB) bo'lsa manzil talab
  /// qilinmaydi, aks holda IP va port bo'lishi shart.
  bool _isUsable(PrinterSettingEntry e) =>
      e.isAddressless || (e.ip.isNotEmpty && e.port > 0);

  /// `type: close_check` — to‘lov / smena yopish cheklari.
  ///
  /// Bir nechta mos yozuv bo'lsa shu terminalning o'ziniki birinchi tanlanadi:
  /// har bir kassaning o'z chek printeri bo'lgan zalda ro'yxatdagi birinchi
  /// yozuv (ya'ni qo'shni kassaning printeri) tanlansa, har bir chek keraksiz
  /// ravishda LAN orqali qo'shni terminalga yuborilar edi.
  PrinterConfig? getCloseCheckPrinter() {
    final usable = _entries().where((e) => e.isCloseCheck && _isUsable(e));
    if (usable.isEmpty) return null;

    final mine = usable.where(isOwnedByThisTerminal);
    if (mine.isNotEmpty) return _configFor(mine.first);

    final unowned = usable.where((e) => e.isUnowned);
    if (unowned.isNotEmpty) return _configFor(unowned.first);

    // Faqat boshqa terminalning printeri qoldi — `PrintQueueService` uni LAN
    // orqali egasiga uzatadi.
    return _configFor(usable.first);
  }

  PrinterConfig closeCheckConfigOrFallback() =>
      getCloseCheckPrinter() ??
      const PrinterConfig(ip: fallbackCloseCheckIp, port: defaultPort);

  /// Oshxona: `type=category` va `connected_entity_ids` ichida [categoryId] yoki [goodId] mos kelganda.
  /// Mos yozuv yo‘q bo‘lsa `null` — boshqa printerga «tushirish» qilinmaydi.
  ///
  /// Kategoriya bo'yicha moslik goods bo'yicha moslikdan ustun; teng darajadagi
  /// bir nechta nomzod ichida esa — [getCloseCheckPrinter] kabi — shu
  /// terminalning printeri, keyin egasizi, oxirida boshqa terminalniki
  /// (u LAN orqali egasiga uzatiladi).
  PrinterConfig? categoryPrinterForOrNull(
    String categoryId, {
    String? goodId,
  }) {
    final wantCat = categoryId.trim();
    final wantGood = goodId?.trim() ?? '';
    if (wantCat.isEmpty && wantGood.isEmpty) return null;

    final candidates = _entries().where((e) => e.isCategory && _isUsable(e));

    for (final want in [wantCat, wantGood]) {
      if (want.isEmpty) continue;
      final matches = candidates
          .where((e) => e.connectedEntityIds.any((cid) => _idEq(cid, want)))
          .toList();
      if (matches.isEmpty) continue;
      return _configFor(_preferOwnTerminal(matches));
    }
    return null;
  }

  /// Bir nechta yaroqli nomzoddan bittasini tanlaydi: avval shu terminalniki,
  /// so'ng egasizi, oxirida ro'yxatdagi birinchisi.
  PrinterSettingEntry _preferOwnTerminal(List<PrinterSettingEntry> matches) {
    for (final e in matches) {
      if (isOwnedByThisTerminal(e)) return e;
    }
    for (final e in matches) {
      if (e.isUnowned) return e;
    }
    return matches.first;
  }

  bool _idEq(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}
