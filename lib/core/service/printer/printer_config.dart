import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class PrinterConfig {
  final String ip;
  final int port;
  final PaperSize paperSize;
  final int timeoutMs;

  const PrinterConfig({
    required this.ip,
    this.port = 9100,
    this.paperSize = PaperSize.mm80,
    this.timeoutMs = 10000,
    this.connectionType = 'cable',
  });

  /// Backend `GET/POST …/printer-settings` — `connection_type`: rasmiy jadvalda
  /// **`cable`** (LAN) va **`wlan`** (Wi‑Fi); default `cable`. Ikkalasi ham
  /// IP:port orqali TCP — sozlamalar formasi ikkalasida ham IP talab qiladi,
  /// haqiqiy Windows USB spooler printeri uchun alohida (IP'siz) tanlov yo'q.
  final String connectionType;

  /// `usb` — hozircha sozlamalar formasida yo'q (ikkala mavjud tanlov —
  /// `cable`/`wlan` — IP:port TCP). Kelajakda haqiqiy IP'siz Windows USB
  /// spooler printeri qo'shilsa, shu qiymat orqali yoqiladi.
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

  @override
  String toString() => 'PrinterConfig($ip:$port, $connectionType)';
}
