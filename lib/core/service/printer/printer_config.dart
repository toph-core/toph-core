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
    this.timeoutMs = 3000,
  });

  @override
  String toString() => 'PrinterConfig($ip:$port)';
}
