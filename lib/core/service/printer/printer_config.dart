import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Chek kengligi (belgi/qator) — printerga qarab tanlanadi. XPRINTER_SETUP.md
/// da o'lchangan haqiqiy holat: Xprinter XP-K200L "80mm sinf" bo'lsa ham,
/// standart shriftda **32 belgi**dan keyin qatorni buzadi — ya'ni 58mm
/// shabloniga to'g'ri keladi. 80mm printerlar esa 48 belgi chiqaradi. Shu
/// sababli kenglik har bir printer uchun alohida tanlanadi.
///
/// Backend `printer-settings`da bu ustun yo'q, shuning uchun USB printer nomi
/// kabi shu qurilmada, `entryId` bo'yicha saqlanadi
/// (`PrinterConfigStorage.getPaperSize`).
const String kPaperSizeCode58 = 'mm58';
const String kPaperSizeCode80 = 'mm80';

/// Saqlangan kod (`'mm58'`/`'mm80'`) → `PaperSize`. Noma'lum/bo'sh qiymat
/// mavjud xulq-atvorni saqlab, 80mm ga tushadi.
PaperSize paperSizeFromCode(String? code) =>
    code == kPaperSizeCode58 ? PaperSize.mm58 : PaperSize.mm80;

/// `PaperSize` → saqlanadigan kod.
String paperSizeToCode(PaperSize size) =>
    size == PaperSize.mm58 ? kPaperSizeCode58 : kPaperSizeCode80;

class PrinterConfig {
  final String ip;
  final int port;
  final PaperSize paperSize;
  final int timeoutMs;

  /// `PrinterSettingEntry.id` this config was resolved from, when it came
  /// from `PrinterConfigStorage` — `null` for ad-hoc configs (e.g. the
  /// hardcoded close-check fallback, or a not-yet-saved Test Printer probe).
  /// Used to look up this device's local USB-printer-name pick (see
  /// [windowsPrinterName]), which is never synced to the backend since a USB
  /// cable only reaches the one PC it's plugged into.
  final String? entryId;

  /// Exact Windows-installed printer name to target when [usesWindowsPrinter]
  /// — set locally per-device (`PrinterConfigStorage.getUsbPrinterName`), not part of
  /// the synced backend record. `null` falls back to the legacy heuristic
  /// (first local printer whose port name starts with "USB").
  final String? windowsPrinterName;

  /// The `cash_register_id` of the POS instance that can physically reach this
  /// printer, or `''` when the printer is unowned and every terminal talks to
  /// it directly.
  ///
  /// This is the field that ends the old "a network printer is reachable from
  /// everywhere" assumption. A kitchen printer on the kitchen's own switch, or
  /// one behind a second access point, answers exactly one machine; a job
  /// raised anywhere else used to burn its socket timeout and fail. With an
  /// owner set, `PrintQueueService` relays the job to that terminal instead —
  /// the same path USB printers have always taken.
  final String ownerCashRegisterId;

  const PrinterConfig({
    required this.ip,
    this.port = 9100,
    this.paperSize = PaperSize.mm80,
    this.timeoutMs = 10000,
    this.connectionType = 'cable',
    this.entryId,
    this.windowsPrinterName,
    this.ownerCashRegisterId = '',
  });

  /// No owner recorded — any terminal prints to it directly, which is the
  /// pre-ownership behaviour and stays the default for ad-hoc configs (the
  /// close-check fallback, a Test Printer probe).
  bool get isUnowned => ownerCashRegisterId.trim().isEmpty;

  /// Whether this terminal, authenticated as [cashRegisterId], is the one that
  /// owns the printer. An unowned printer is nobody's, so this is `false` for
  /// it — callers treat "unowned" and "mine" separately.
  bool isOwnedBy(String cashRegisterId) {
    final owner = ownerCashRegisterId.trim();
    if (owner.isEmpty) return false;
    return owner.toLowerCase() == cashRegisterId.trim().toLowerCase();
  }

  /// Backend `GET/POST …/printer-settings` — `connection_type`: **`cable`**
  /// (LAN), **`wlan`** (Wi‑Fi) va **`usb`**; default `cable`. Birinchi ikkitasi
  /// IP:port orqali TCP. **`usb`** — egasining mashinasiga kabel bilan ulangan,
  /// Windows spooler orqali chop etiladigan printer; unda manzil yo'q, shuning
  /// uchun backend `ip`/`port`ni bo'sh saqlaydi (75_printer_settings_owner).
  final String connectionType;

  /// `usb` — Windows printer spooler orqali (OpenPrinter/WritePrinter),
  /// IP/port ishlatilmaydi.
  bool get usesWindowsPrinter => connectionType.toLowerCase() == 'usb';

  /// Wi-Fi / LAN — ikkalasi ham RAW TCP (IP:port).
  bool get usesNetworkTcp {
    switch (connectionType.toLowerCase()) {
      case 'cable':
      case 'wlan':
      case 'wifi':
      case 'lan':
      case 'ethernet':
        return true;
      default:
        return false;
    }
  }

  PrinterConfig copyWith({
    String? ip,
    int? port,
    PaperSize? paperSize,
    int? timeoutMs,
    String? connectionType,
    String? entryId,
    String? windowsPrinterName,
    String? ownerCashRegisterId,
  }) {
    return PrinterConfig(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      paperSize: paperSize ?? this.paperSize,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      connectionType: connectionType ?? this.connectionType,
      entryId: entryId ?? this.entryId,
      windowsPrinterName: windowsPrinterName ?? this.windowsPrinterName,
      ownerCashRegisterId: ownerCashRegisterId ?? this.ownerCashRegisterId,
    );
  }

  @override
  String toString() =>
      'PrinterConfig($ip:$port, $connectionType${windowsPrinterName != null ? ', win=$windowsPrinterName' : ''})';
}
