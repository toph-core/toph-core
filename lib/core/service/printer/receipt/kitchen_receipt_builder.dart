import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_esc_pos_helper.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_notice_lines.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

/// Oshxona cheki — faqat taom nomi va miqdori, narxsiz.
class KitchenReceiptBuilder {
  KitchenReceiptBuilder._();

  /// [OpenOrderModel] mavjud oqimlar (waiter) uchun qulaylik wrapper'i.
  static Future<List<int>> build({
    required OpenOrderModel order,
    required List<OrderItem> items,
    PaperSize paperSize = PaperSize.mm80,
  }) =>
      buildWithHeader(
        tableLine: 'Стол: ${order.tableNumber}',
        hallName: order.hallName,
        guestCount: order.guestCount,
        items: items,
        paperSize: paperSize,
      );

  /// Kassir oqimlari uchun — to'liq [OpenOrderModel] shart emas.
  /// [tableLine] — birinchi qator matni ('Стол: 5' yoki 'С собой').
  /// [waiterName] — buyurtmani qabul qilgan/qo'shgan foydalanuvchi.
  /// [orderNumber] — buyurtma raqami (mavjud bo'lsa).
  static Future<List<int>> buildWithHeader({
    required String tableLine,
    required List<OrderItem> items,
    String hallName = '',
    int guestCount = 0,
    PaperSize paperSize = PaperSize.mm80,
    String waiterName = '',
    String? orderNumber,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = receiptGenerator(paperSize, profile);
    final time = DateFormat('HH:mm').format(DateTime.now());

    List<int> bytes = [];
    bytes += receiptEncodingPreamble(gen);

    // ── Header ──────────────────────────────────────────────────────────────
    bytes += gen.text(
      '** КУХОННЫЙ ЧЕК **',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );

    bytes += gen.row([
      PosColumn(
        text: tableLine,
        width: 8,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: time,
        width: 4,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (hallName.isNotEmpty) {
      bytes += gen.text('Зал: $hallName');
    }

    if (orderNumber != null && orderNumber.isNotEmpty) {
      bytes += gen.text('Заказ №: $orderNumber');
    }

    if (waiterName.isNotEmpty) {
      bytes += gen.text('Официант: $waiterName');
    }

    bytes += gen.hr();

    // ── Items — katta shrift, narxsiz ────────────────────────────────────────
    for (final item in items) {
      final name = item.goods.name.length > 28
          ? '${item.goods.name.substring(0, 26)}..'
          : item.goods.name;

      bytes += gen.row([
        PosColumn(
          text: name,
          width: 9,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: 'x${item.quantity}',
          width: 3,
          styles: const PosStyles(bold: true, align: PosAlign.right),
        ),
      ]);

      // Waiter oqimi izohni `commet` da, kassir oqimlari `comment` da yuboradi.
      final note = item.commet.isNotEmpty ? item.commet : item.comment;
      if (note.isNotEmpty) {
        bytes += gen.text(
          '  >> $note',
          styles: const PosStyles(underline: true),
        );
      }
    }

    bytes += gen.hr();

    // ── Footer ───────────────────────────────────────────────────────────────
    if (guestCount > 0) {
      bytes += gen.text('Гостей: $guestCount');
    }
    appendReceiptNoReprepNotice(gen, bytes);
    bytes += gen.feed(2);
    bytes += gen.cut();

    return bytes;
  }
}
