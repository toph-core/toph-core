import 'dart:math' as math;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_esc_pos_helper.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_notice_lines.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_som_format.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

/// Kassir cheki — narxlar, jami summa, xizmat to'lovi bilan to'liq chek.
/// Summalar: [ReceiptSomFormat] (ASCII) — `uz` locale minglik belgisi printerda "garbled" bo'lmasin.
/// Shrift: Fenix PDF Arial o'rniga ESC/POS Font A (thermal).
class CashierReceiptBuilder {
  CashierReceiptBuilder._();

  static String _fmt(num value) => ReceiptSomFormat.formatInt(value);

  /// `service_amount` → `service_percent` × mahsulot → `total_amount − mahsulot`.
  static double _servicePart(OpenOrderModel order, double subtotal) {
    final explicit = order.serviceAmountValue;
    if (explicit > 0.0001) return explicit;
    final sp = order.servicePercent;
    if (sp != null && sp > 0) return subtotal * sp / 100.0;
    final tot = order.totalAmountValue;
    if (tot > subtotal + 0.01) return tot - subtotal;
    return 0;
  }

  static String _serviceLabel(
    OpenOrderModel order,
    double subtotal,
    double service,
  ) {
    final sp = order.servicePercent;
    if (sp != null && sp > 0) {
      final ps = sp == sp.roundToDouble() ? '${sp.round()}' : '$sp';
      return 'Обслужение ($ps%):';
    }
    if (subtotal > 0.01 && service > 0.01) {
      final approx = (service / subtotal * 100).round();
      return 'Обслужение (~$approx%):';
    }
    return 'Обслужение:';
  }

  /// Chegirma faqat `> 0` bo'lsa chiqariladi; foiz — xizmat + mahsulot jami ustidan.
  static double _discountValue(
    double preDiscount,
    double discountPercent,
    double discountAmount,
  ) {
    if (discountPercent > 0) {
      final v = preDiscount * discountPercent / 100.0;
      if (v > 0.0001) return v;
    }
    if (discountAmount > 0.0001) {
      return math.min(discountAmount, preDiscount);
    }
    return 0;
  }

  /// [paperSize] odatda `PaperSize.mm80` — 80mm qog'oz (48 belgi kenglik).
  /// [hourAmount] — soatlik jadval uchun qo'shimcha haq (0 bo'lsa chiqarilmaydi).
  static Future<List<int>> build({
    required OpenOrderModel order,
    required List<OrderItem> items,
    PaperSize paperSize = PaperSize.mm80,
    double discountPercent = 0,
    double discountAmount = 0,
    double hourAmount = 0,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = receiptGenerator(paperSize, profile);
    final now = DateTime.now();
    final timeFmt = DateFormat('dd.MM.yyyy  HH:mm');

    List<int> bytes = [];
    bytes += receiptEncodingPreamble(gen);

    // ── Header ──────────────────────────────────────────────────────────────
    bytes += gen.text(
      'КАССИРСКИЙ ЧЕК',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
      linesAfter: 1,
    );

    // ── Order info ───────────────────────────────────────────────────────────
    bytes += gen.text(timeFmt.format(now));
    bytes += gen.row([
      PosColumn(text: 'Зал:', width: 4),
      PosColumn(text: order.hallName, width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Стол:', width: 4),
      PosColumn(text: '${order.tableNumber}', width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Гости:', width: 4),
      PosColumn(text: '${order.guestCount}', width: 8),
    ]);

    bytes += gen.hr();

    // ── Items ────────────────────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(
        text: 'Блюдо',
        width: 6,
        styles: const PosStyles(bold: true, underline: true),
      ),
      PosColumn(
        text: 'Кол',
        width: 2,
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
      PosColumn(
        text: 'Сумма',
        width: 4,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    double subtotal = 0;
    for (final item in items) {
      final price = double.tryParse(item.goods.price) ?? 0;
      final lineTotal = price * item.quantity;
      subtotal += lineTotal;

      // Nom 24 belgidan uzun bo'lsa qisqartiriladi
      final name = item.goods.name.length > 22
          ? '${item.goods.name.substring(0, 20)}..'
          : item.goods.name;

      bytes += gen.row([
        PosColumn(
          text: name,
          width: 6,
          styles: const PosStyles(height: PosTextSize.size1, width: PosTextSize.size1),
        ),
        PosColumn(
          text: 'x${item.quantity}',
          width: 2,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ),
        ),
        PosColumn(
          text: _fmt(lineTotal),
          width: 4,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ),
        ),
      ]);
    }

    bytes += gen.hr();

    // ── Totals: mahsulot, soatlik (>0), xizmat (>0), chegirma (>0), to'lov ────
    bytes += gen.row([
      PosColumn(
        text: 'Итого:',
        width: 8,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: _fmt(subtotal),
        width: 4,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    if (hourAmount > 0.0001) {
      bytes += gen.row([
        PosColumn(text: 'Pochasovaya:', width: 8),
        PosColumn(
          text: _fmt(hourAmount),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    final serviceRaw = _servicePart(order, subtotal);
    final serviceAmt = serviceRaw > 0.0001 ? serviceRaw : 0.0;
    if (serviceAmt > 0) {
      bytes += gen.row([
        PosColumn(
          text: _serviceLabel(order, subtotal, serviceAmt),
          width: 8,
        ),
        PosColumn(
          text: _fmt(serviceAmt),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    final preDiscount = subtotal + hourAmount + serviceAmt;
    final discountVal = _discountValue(
      preDiscount,
      discountPercent,
      discountAmount,
    );
    if (discountVal > 0.0001) {
      final discLabel = discountPercent > 0
          ? 'Скидка (${discountPercent == discountPercent.roundToDouble() ? discountPercent.round().toString() : discountPercent.toStringAsFixed(1)}%):'
          : 'Скидка:';
      bytes += gen.row([
        PosColumn(text: discLabel, width: 8),
        PosColumn(
          text: _fmt(discountVal),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    final toPay = (preDiscount - discountVal).clamp(0.0, double.infinity);

    bytes += gen.hr();
    bytes += gen.row([
      PosColumn(
        text: 'К ОПЛАТЕ:',
        width: 8,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      ),
      PosColumn(
        text: _fmt(toPay.round()),
        width: 4,
        styles: const PosStyles(
          bold: true,
          align: PosAlign.right,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      ),
    ]);

    // ── Footer ───────────────────────────────────────────────────────────────
    appendReceiptNoReprepNotice(gen, bytes);
    bytes += gen.feed(1);
    // Fenix: "Xaridingiz uchun rahmat!" — qator uzunligi 80mm uchun ikkiga bo'linadi.
    bytes += gen.text(
      'Спасибо за покупку!',
      styles: const PosStyles(align: PosAlign.center, bold: true),
      linesAfter: 1,
    );
    bytes += gen.cut();

    return bytes;
  }

  /// To'lov ekranidan keyin chek — [ArchiveDetailEntity] asosida.
  static Future<List<int>> buildFromDetail({
    required ArchiveDetailEntity detail,
    PaperSize paperSize = PaperSize.mm80,
    double hourAmount = 0,
    double discountPercent = 0,
    double discountAmount = 0,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = receiptGenerator(paperSize, profile);
    final now = DateTime.now();
    final timeFmt = DateFormat('dd.MM.yyyy  HH:mm');

    List<int> bytes = [];
    bytes += receiptEncodingPreamble(gen);

    bytes += gen.text(
      'КАССИРСКИЙ ЧЕК',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
      linesAfter: 1,
    );

    bytes += gen.text(timeFmt.format(now));
    bytes += gen.row([
      PosColumn(text: 'Зал:', width: 4),
      PosColumn(text: detail.hallName, width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Стол:', width: 4),
      PosColumn(text: '${detail.tableNumber.toInt()}', width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Гости:', width: 4),
      PosColumn(text: '${detail.guestCount.toInt()}', width: 8),
    ]);

    bytes += gen.hr();

    bytes += gen.row([
      PosColumn(text: 'Блюдо', width: 6, styles: const PosStyles(bold: true, underline: true)),
      PosColumn(text: 'Кол', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
      PosColumn(text: 'Сумма', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);

    double subtotal = 0;
    for (final g in detail.goods.where((g) => g.status != 'cancelled')) {
      final lineTotal = g.price * g.quantity;
      subtotal += lineTotal;
      final name = g.name.length > 22 ? '${g.name.substring(0, 20)}..' : g.name;
      bytes += gen.row([
        PosColumn(text: name, width: 6),
        PosColumn(text: 'x${g.quantity}', width: 2, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text: _fmt(lineTotal), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += gen.hr();

    bytes += gen.row([
      PosColumn(text: 'Итого:', width: 8, styles: const PosStyles(bold: true)),
      PosColumn(text: _fmt(subtotal), width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);

    if (hourAmount > 0.0001) {
      bytes += gen.row([
        PosColumn(text: 'Pochasovaya:', width: 8),
        PosColumn(text: _fmt(hourAmount), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    final serviceAmt = detail.serviceAmount > 0.0001
        ? detail.serviceAmount
        : (detail.servicePercent > 0 ? subtotal * detail.servicePercent / 100 : 0.0);
    if (serviceAmt > 0.0001) {
      final label = detail.servicePercent > 0
          ? 'Обслужение (${detail.servicePercent.toInt()}%):'
          : 'Обслужение:';
      bytes += gen.row([
        PosColumn(text: label, width: 8),
        PosColumn(text: _fmt(serviceAmt), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    final preDiscount = subtotal + hourAmount + serviceAmt;
    final discVal = _discountValue(preDiscount, discountPercent, discountAmount);
    if (discVal > 0.0001) {
      final discLabel = discountPercent > 0 ? 'Скидка (${discountPercent.toInt()}%):' : 'Скидка:';
      bytes += gen.row([
        PosColumn(text: discLabel, width: 8),
        PosColumn(text: _fmt(discVal), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    final toPay = (preDiscount - discVal).clamp(0.0, double.infinity);

    bytes += gen.hr();
    bytes += gen.row([
      PosColumn(text: 'К ОПЛАТЕ:', width: 8, styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size1)),
      PosColumn(text: _fmt(toPay.round()), width: 4, styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size2, width: PosTextSize.size1)),
    ]);

    appendReceiptNoReprepNotice(gen, bytes);
    bytes += gen.feed(1);
    bytes += gen.text('Спасибо за покупку!', styles: const PosStyles(align: PosAlign.center, bold: true), linesAfter: 1);
    bytes += gen.cut();

    return bytes;
  }
}
