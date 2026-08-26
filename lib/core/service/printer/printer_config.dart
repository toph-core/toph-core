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

  const PrinterConfig({
    required this.ip,
    this.port = 9100,
    this.paperSize = PaperSize.mm80,
    this.timeoutMs = 10000,
    this.connectionType = 'cable',
    this.entryId,
    this.windowsPrinterName,
  });

  /// Backend `GET/POST …/printer-settings` — `connection_type`: rasmiy jadvalda
  /// **`cable`** (LAN) va **`wlan`** (Wi‑Fi); default `cable`. Ikkalasi ham
  /// IP:port orqali TCP. **`usb`** — shu qurilmaga to'g'ridan-to'g'ri USB
  /// kabel bilan ulangan printer, Windows spooler orqali (IP shart emas).
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
  }) {
    return PrinterConfig(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      paperSize: paperSize ?? this.paperSize,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      connectionType: connectionType ?? this.connectionType,
      entryId: entryId ?? this.entryId,
      windowsPrinterName: windowsPrinterName ?? this.windowsPrinterName,
    );
  }

  @override
  String toString() =>
      'PrinterConfig($ip:$port, $connectionType${windowsPrinterName != null ? ', win=$windowsPrinterName' : ''})';
}
