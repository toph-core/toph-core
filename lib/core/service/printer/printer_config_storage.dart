import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';

class PrinterConfigStorage {
  final SharedPreferences _prefs;

  PrinterConfigStorage(this._prefs);

  static const _cashierIpKey = 'cashier_printer_ip';
  static const _kitchenIpKey = 'kitchen_printer_ip';
  static const _portKey = 'printer_port';

  static const defaultCashierIp = '192.168.1.100';
  static const defaultKitchenIp = '192.168.1.101';
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
}
