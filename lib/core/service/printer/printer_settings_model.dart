/// API javobidagi printer manzillari (backend nomlari farq qilishi mumkin — [fromJson] aliaslar bilan o‘qiydi).
class PrinterSettingsModel {
  const PrinterSettingsModel({
    this.cashierIp,
    this.kitchenIp,
    this.port,
  });

  final String? cashierIp;
  final String? kitchenIp;
  final int? port;

  factory PrinterSettingsModel.fromJson(Map<String, dynamic> json) {
    String? pickIp(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    int? pickPort() {
      for (final k in ['printer_port', 'port', 'printerPort']) {
        final v = json[k];
        if (v == null) continue;
        if (v is int) return v;
        final p = int.tryParse(v.toString());
        if (p != null && p > 0) return p;
      }
      return null;
    }

    return PrinterSettingsModel(
      cashierIp: pickIp([
        'cashier_printer_ip',
        'cashier_ip',
        'cashierPrinterIp',
        'cashierIp',
      ]),
      kitchenIp: pickIp([
        'kitchen_printer_ip',
        'kitchen_ip',
        'kitchenPrinterIp',
        'kitchenIp',
      ]),
      port: pickPort(),
    );
  }
}
