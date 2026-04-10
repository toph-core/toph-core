import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

/// Kassir cheki — narxlar, jami summa, xizmat to'lovi bilan to'liq chek.
class CashierReceiptBuilder {
  CashierReceiptBuilder._();

  static final _numFmt = NumberFormat('#,##0', 'uz');

  static String _fmt(num value) => _numFmt.format(value);

  /// [paperSize] odatda `PaperSize.mm80` — 80mm qog'oz (48 belgi kenglik).
  static Future<List<int>> build({
    required OpenOrderModel order,
    required List<OrderItem> items,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(paperSize, profile);
    final now = DateTime.now();
    final timeFmt = DateFormat('dd.MM.yyyy  HH:mm');

    List<int> bytes = [];

    // ── Header ──────────────────────────────────────────────────────────────
    bytes += gen.text(
      'MARY AI POS',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += gen.text(
      'KASSIR CHEKI',
      styles: const PosStyles(align: PosAlign.center),
      linesAfter: 1,
    );

    // ── Order info ───────────────────────────────────────────────────────────
    bytes += gen.text(timeFmt.format(now));
    bytes += gen.row([
      PosColumn(text: 'Zal:', width: 4),
      PosColumn(text: order.hallName, width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Stol:', width: 4),
      PosColumn(text: '${order.tableNumber}', width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Mehmon:', width: 4),
      PosColumn(text: '${order.guestCount}', width: 8),
    ]);

    bytes += gen.hr();

    // ── Items ────────────────────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(
        text: 'Taom',
        width: 6,
        styles: const PosStyles(bold: true, underline: true),
      ),
      PosColumn(
        text: 'Soni',
        width: 2,
        styles: const PosStyles(bold: true, align: PosAlign.center),
      ),
      PosColumn(
        text: 'Summa',
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
        PosColumn(text: name, width: 6),
        PosColumn(
          text: 'x${item.quantity}',
          width: 2,
          styles: const PosStyles(align: PosAlign.center),
        ),
        PosColumn(
          text: _fmt(lineTotal),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += gen.hr();

    // ── Totals ───────────────────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(
        text: 'Jami:',
        width: 8,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: _fmt(subtotal),
        width: 4,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    final servicePercent = order.servicePercent ?? 0;
    if (servicePercent > 0) {
      final serviceAmount = subtotal * servicePercent / 100;
      bytes += gen.row([
        PosColumn(
          text: 'Xizmat (${servicePercent.toStringAsFixed(0)}%):',
          width: 8,
        ),
        PosColumn(
          text: _fmt(serviceAmount),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      final total = subtotal + serviceAmount;
      bytes += gen.hr();
      bytes += gen.row([
        PosColumn(
          text: "TO'LOV:",
          width: 8,
          styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        PosColumn(
          text: _fmt(total),
          width: 4,
          styles: const PosStyles(
            bold: true,
            align: PosAlign.right,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      ]);
    } else {
      bytes += gen.hr();
      bytes += gen.row([
        PosColumn(
          text: "TO'LOV:",
          width: 8,
          styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        PosColumn(
          text: _fmt(subtotal),
          width: 4,
          styles: const PosStyles(
            bold: true,
            align: PosAlign.right,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      ]);
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    bytes += gen.feed(1);
    bytes += gen.text(
      'Tashrifingiz uchun rahmat!',
      styles: const PosStyles(align: PosAlign.center),
      linesAfter: 1,
    );
    bytes += gen.cut();

    return bytes;
  }
}
