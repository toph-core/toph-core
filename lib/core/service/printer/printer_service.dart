import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

import 'printer_config.dart';
import 'printer_config_storage.dart';
import 'receipt/cashier_receipt_builder.dart';
import 'receipt/kitchen_receipt_builder.dart';
import 'receipt/shift_close_receipt_builder.dart';

class PrinterService {
  PrinterService(this._storage);

  final PrinterConfigStorage _storage;

  /// TCP orqali yuborish; juda kichik bo‘laklar ESC/raster oqimini sindirishi mumkin.
  static const _socketChunkBytes = 8192;

  static List<List<int>> _socketSendChunks(List<int> bytes) {
    if (bytes.isEmpty) return [bytes];
    if (bytes.length <= _socketChunkBytes) return [bytes];
    return bytes.splitByLength(_socketChunkBytes);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// `type: close_check` printer — to‘liq kassir cheki.
  Future<void> printCashierReceipt({
    required OpenOrderModel order,
    required List<OrderItem> items,
    double discountPercent = 0,
    double discountAmount = 0,
  }) async {
    // Summa 0 / barcha pozitsiyalar bekor — yopilgan schyot uchun bo‘sh chek ham chop etiladi.
    try {
      final config = _storage.closeCheckConfigOrFallback();
      final bytes = await CashierReceiptBuilder.build(
        order: order,
        items: items,
        paperSize: config.paperSize,
        discountPercent: discountPercent,
        discountAmount: discountAmount,
      );
      final r = await _connectAndPrint(config, bytes);
      if (!r.ok) {
        _notifyPrinterFailed(
          config,
          title: 'Kassir cheki chop etilmadi',
          printerRole: 'close_check printer (backend)',
          detail: r.error,
        );
      }
    } catch (e, st) {
      debugPrint('[PrinterService] Kassir cheki xatosi: $e\n$st');
      final config = _storage.closeCheckConfigOrFallback();
      _notifyPrinterFailed(
        config,
        title: 'Kassir cheki tayyorlashda xato',
        printerRole: 'close_check printer (backend)',
        detail: e.toString(),
      );
    }
  }

  /// Smena yopilishi — `close_check` printer.
  Future<void> printShiftCloseReceipt({
    required String shiftId,
    required DateTime? openedAt,
    required int closingCard,
    required String cashierLabel,
  }) async {
    try {
      final config = _storage.closeCheckConfigOrFallback();
      final bytes = await ShiftCloseReceiptBuilder.build(
        shiftId: shiftId,
        openedAt: openedAt,
        closingCard: closingCard,
        cashierLabel: cashierLabel,
        paperSize: config.paperSize,
      );
      final r = await _connectAndPrint(config, bytes);
      if (!r.ok) {
        _notifyPrinterFailed(
          config,
          title: 'Smena yopilish cheki chop etilmadi',
          printerRole: 'close_check printer (backend)',
          detail: r.error,
        );
      }
    } catch (e, st) {
      debugPrint('[PrinterService] Smena yopilish cheki: $e\n$st');
      final config = _storage.closeCheckConfigOrFallback();
      _notifyPrinterFailed(
        config,
        title: 'Smena cheki tayyorlashda xato',
        printerRole: 'close_check printer (backend)',
        detail: e.toString(),
      );
    }
  }

  /// `type: category` bo‘yicha guruhlab, har bir printerga alohida oshxona cheki.
  /// Printeri sozlanmagan kategoriya pozitsiyalari o‘tkaziladi (boshqa printerga qo‘shilmaydi).
  Future<void> printKitchenReceipt({
    required OpenOrderModel order,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    final byKey = <String, List<OrderItem>>{};
    final cfgByKey = <String, PrinterConfig>{};
    for (final item in items) {
      final cfg = _storage.categoryPrinterForOrNull(
        item.goods.categoryId,
        goodId: item.goods.id,
      );
      if (cfg == null) {
        debugPrint(
          '[PrinterService] Oshxona printeri yo\'q, o\'tkazildi: ${item.goods.name} '
          '(category_id=${item.goods.categoryId}, good_id=${item.goods.id})',
        );
        continue;
      }
      final k = '${cfg.ip}:${cfg.port}';
      cfgByKey[k] = cfg;
      byKey.putIfAbsent(k, () => []).add(item);
    }
    if (byKey.isEmpty) {
      debugPrint(
        '[PrinterService] Oshxona cheki: barcha pozitsiyalar uchun printer topilmadi — chop etilmadi.',
      );
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        if (!_storage.hasPrinterSettingsEntries) {
          showStructuredErrorDismissible(
            ctx,
            title: 'Oshxona cheki chop etilmadi',
            icon: Icons.cloud_off_outlined,
            paragraphs: const [
              'Printer sozlamalari ilovaga yuklanmagan.',
              'Odatda sabab — kassa foydalanuvchisida GET /settings/printer-settings ruxsati yo‘q (403). '
                  'Backendda ushbu endpoint uchun cashier (yoki POS) roliga ruxsat bering yoki admin akkaunti bilan kirganda sinxronlang.',
            ],
          );
        } else {
          showStructuredErrorDismissible(
            ctx,
            title: 'Oshxona cheki chop etilmadi',
            icon: Icons.category_outlined,
            paragraphs: const [
              'Tanlangan mahsulotlarning hech biri printer sozlamalaridagi kategoriya yoki mahsulot ro‘yxatiga mos kelmayapti.',
            ],
          );
        }
      }
      return;
    }
    try {
      for (final k in byKey.keys) {
        final config = cfgByKey[k]!;
        final sub = byKey[k]!;
        final bytes = await KitchenReceiptBuilder.build(
          order: order,
          items: sub,
          paperSize: config.paperSize,
        );
        final r = await _connectAndPrint(config, bytes);
        if (!r.ok) {
          _notifyPrinterFailed(
            config,
            title: 'Oshxona cheki chop etilmadi',
            printerRole: 'category printer (backend) ${config.ip}',
            detail: r.error,
          );
          return;
        }
      }
    } catch (e, st) {
      debugPrint('[PrinterService] Oshxona cheki xatosi: $e\n$st');
      PrinterConfig? config;
      for (final item in items) {
        config = _storage.categoryPrinterForOrNull(
          item.goods.categoryId,
          goodId: item.goods.id,
        );
        if (config != null) break;
      }
      if (config != null) {
        _notifyPrinterFailed(
          config,
          title: 'Oshxona cheki tayyorlashda xato',
          printerRole: 'category printer (backend)',
          detail: e.toString(),
        );
      }
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _notifyPrinterFailed(
    PrinterConfig config, {
    required String title,
    required String printerRole,
    String? detail,
  }) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final timeoutSec = config.timeoutMs ~/ 1000;
    final paragraphs = <String>[
      printerRole,
      'Manzil: ${config.ip}:${config.port}  •  timeout: ${timeoutSec}s',
      if (detail != null && detail.trim().isNotEmpty) detail.trim(),
      'Tarmoq, printer yoqilishi va IP/port (odatda 9100)ni tekshiring.',
    ];

    showStructuredErrorDismissible(
      ctx,
      title: title,
      icon: Icons.print_disabled_rounded,
      paragraphs: paragraphs,
    );
  }

  /// TCP socket orqali printer'ga ulanib bytes yuboradi.
  /// Printer offline bo'lsa [maxRetries] marta qayta urinadi.
  Future<({bool ok, String? error})> _connectAndPrint(
    PrinterConfig config,
    List<int> bytes, {
    int maxRetries = 2,
  }) async {
    if (!config.usesNetworkTcp) {
      debugPrint(
        '[PrinterService] connection_type=${config.connectionType} — TCP chop qo‘llab-quvvatlanmaydi.',
      );
      return (
        ok: false,
        error:
            'Printer ulanish turi «${config.connectionType}» hozircha qo‘llab-quvvatlanmaydi. '
            'Ilova faqat tarmoq printerlari (API: cable, wlan) uchun IP:port orqali chop etadi.',
      );
    }

    int attempt = 0;
    String? lastSocketMessage;
    while (attempt <= maxRetries) {
      try {
        final socket = await Socket.connect(
          config.ip,
          config.port,
          timeout: Duration(milliseconds: config.timeoutMs),
        );

        // 250 bayt — raster (logo) va boshqa buyruqlarni o‘rtadan uzib, printer
        // qolganini matn sifatida chop etishi mumkin. Katta bo‘lak yoki bitta yuborish.
        final chunks = _socketSendChunks(bytes);
        await socket.addStream(Stream.fromIterable(chunks));
        await socket.flush();
        await socket.close();
        socket.destroy();

        debugPrint('[PrinterService] Chek yuborildi → ${config.ip}:${config.port}');
        return (ok: true, error: null);
      } on SocketException catch (e) {
        lastSocketMessage = _formatSocketException(e);
        attempt++;
        if (attempt > maxRetries) {
          debugPrint(
            '[PrinterService] Printer ${config.ip} offline ($lastSocketMessage). '
            '$maxRetries urinishdan keyin bekor qilindi.',
          );
          return (ok: false, error: lastSocketMessage);
        }
        debugPrint('[PrinterService] Ulanish xatosi, qayta urinish $attempt/$maxRetries...');
        await Future.delayed(const Duration(seconds: 1));
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[PrinterService] Yuborish xatosi: $e\n$st');
        }
        return (ok: false, error: e.toString());
      }
    }
    return (ok: false, error: 'Ulanib bo\'lmadi (${config.ip}:${config.port})');
  }

  /// Android/iOS ba'zida `message` bo'sh; `osError` — "Network is unreachable" va h.k.
  static String _formatSocketException(SocketException e) {
    final m = e.message.trim();
    final os = e.osError;
    if (os != null) {
      final osPart = '${os.message} (kod ${os.errorCode})';
      return m.isNotEmpty ? '$m — $osPart' : osPart;
    }
    if (m.isNotEmpty) return m;
    return e.toString();
  }
}
