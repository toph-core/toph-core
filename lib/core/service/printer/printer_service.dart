import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

import 'printer_config.dart';
import 'printer_config_storage.dart';
import 'receipt/cashier_receipt_builder.dart';
import 'receipt/kitchen_receipt_builder.dart';

class PrinterService {
  final PrinterConfigStorage _storage;

  PrinterService(this._storage);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Kassir printeriga to'liq chek (narxlar + jami) chiqaradi.
  /// [closeOrder] chaqirilgandan keyin ishlatiladi.
  Future<void> printCashierReceipt({
    required OpenOrderModel order,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    try {
      final config = _storage.getCashierConfig();
      final bytes = await CashierReceiptBuilder.build(
        order: order,
        items: items,
        paperSize: config.paperSize,
      );
      await _connectAndPrint(config, bytes);
    } catch (e) {
      debugPrint('[PrinterService] Kassir cheki xatosi: $e');
    }
  }

  /// Oshxona printeriga soddalashtirilgan chek (narxsiz) chiqaradi.
  /// [sendItems] chaqirilgandan keyin ishlatiladi.
  Future<void> printKitchenReceipt({
    required OpenOrderModel order,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    try {
      final config = _storage.getKitchenConfig();
      final bytes = await KitchenReceiptBuilder.build(
        order: order,
        items: items,
        paperSize: config.paperSize,
      );
      await _connectAndPrint(config, bytes);
    } catch (e) {
      debugPrint('[PrinterService] Oshxona cheki xatosi: $e');
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  /// TCP socket orqali printer'ga ulanib bytes yuboradi.
  /// Printer offline bo'lsa [maxRetries] marta qayta urinadi, keyin silent fail.
  Future<void> _connectAndPrint(
    PrinterConfig config,
    List<int> bytes, {
    int maxRetries = 2,
  }) async {
    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        final socket = await Socket.connect(
          config.ip,
          config.port,
          timeout: Duration(milliseconds: config.timeoutMs),
        );

        // bytes'ni 250 ta bo'lakka bo'lib yuborish (printer buffer overflow'dan saqlanish)
        final chunks = bytes.splitByLength(250);
        await socket.addStream(Stream.fromIterable(chunks));
        await socket.flush();
        await socket.close();
        socket.destroy();

        debugPrint('[PrinterService] Chek yuborildi → ${config.ip}:${config.port}');
        return;
      } on SocketException catch (e) {
        attempt++;
        if (attempt > maxRetries) {
          debugPrint(
            '[PrinterService] Printer ${config.ip} offline (${e.message}). '
            '$maxRetries urinishdan keyin bekor qilindi.',
          );
          return;
        }
        debugPrint('[PrinterService] Ulanish xatosi, qayta urinish $attempt/$maxRetries...');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }
}
