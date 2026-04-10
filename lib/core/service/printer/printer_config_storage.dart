import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';
import 'printer_settings_model.dart';

class PrinterConfigStorage {
  final SharedPreferences _prefs;

  PrinterConfigStorage(this._prefs);

  static const _cashierIpKey = 'cashier_printer_ip';
  static const _kitchenIpKey = 'kitchen_printer_ip';
  static const _portKey = 'printer_port';

  static const defaultCashierIp = '192.168.123.100';
  static const defaultKitchenIp = '192.168.1.222';
  static const defaultPort = 9100;

  PrinterConfig getCashierConfig() => PrinterConfig(
        ip: _prefs.getString(_cashierIpKey) ?? defaultCashierIp,
        port: _prefs.getInt(_portKey) ?? defaultPort,
      );

  PrinterConfig getKitchenConfig() => PrinterConfig(
        ip: _prefs.getString(_kitchenIpKey) ?? defaultKitchenIp,
        port: _prefs.getInt(_portKey) ?? defaultPort,
      );

  Future<void> saveCashierIp(String ip) =>
      _prefs.setString(_cashierIpKey, ip);

  Future<void> saveKitchenIp(String ip) =>
      _prefs.setString(_kitchenIpKey, ip);

  Future<void> savePort(int port) => _prefs.setInt(_portKey, port);

  /// API dan kelgan qiymatlar bilan faqat to‘ldirilgan maydonlarni yangilaydi.
  Future<void> applyFromApi(PrinterSettingsModel settings) async {
    final c = settings.cashierIp;
    if (c != null && c.isNotEmpty) await saveCashierIp(c);
    final k = settings.kitchenIp;
    if (k != null && k.isNotEmpty) await saveKitchenIp(k);
    final p = settings.port;
    if (p != null && p > 0) await savePort(p);
  }
}
