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
        orderId: order.id,
      );

  /// Kassir oqimlari uchun — to'liq [OpenOrderModel] shart emas.
  /// [tableLine] — birinchi qator matni ('Стол: 5' yoki 'С собой').
  /// [waiterName] — buyurtmani qabul qilgan/qo'shgan foydalanuvchi.
  /// [orderNumber] — chek raqami (bilNumber, mavjud bo'lsa).
  /// [orderId] — buyurtma ID (bilNumber hali noma'lum bo'lganda ham izlash uchun).
  /// [categoryNames] — categoryId -> nom, pozitsiyalarni kategoriya bo'yicha
  /// guruhlab, har bir guruh oldidan qalin sarlavha chiqarish uchun.
  static Future<List<int>> buildWithHeader({
    required String tableLine,
    required List<OrderItem> items,
    String hallName = '',
    int guestCount = 0,
    PaperSize paperSize = PaperSize.mm80,
    String waiterName = '',
    String? orderNumber,
    String? orderId,
    Map<String, String> categoryNames = const {},
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = receiptGenerator(paperSize, profile);
    final now = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

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

    bytes += gen.text(tableLine, styles: const PosStyles(bold: false));
    bytes += gen.text('Время: $now', styles: const PosStyles(bold: false));

    if (hallName.isNotEmpty) {
      bytes += gen.text('Зал: $hallName', styles: const PosStyles(bold: false));
    }

    if (orderNumber != null && orderNumber.isNotEmpty) {
      bytes += gen.text(
        'Чек №: $orderNumber',
        styles: const PosStyles(bold: false),
      );
    }

    if (orderId != null && orderId.isNotEmpty) {
      bytes += gen.text(
        'ID заказа: $orderId',
        styles: const PosStyles(bold: false),
      );
    }

    if (waiterName.isNotEmpty) {
      bytes += gen.text(
        'Официант: $waiterName',
        styles: const PosStyles(bold: false),
      );
    }

    bytes += gen.hr();

    // ── Items — kategoriya bo'yicha guruhlab, katta shrift, narxsiz ─────────
    final grouped = <String, List<OrderItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.goods.categoryId, () => []).add(item);
    }

    var firstGroup = true;
    for (final entry in grouped.entries) {
      final categoryName = categoryNames[entry.key];
      if (!firstGroup) bytes += gen.text('');
      firstGroup = false;

      bytes += gen.text(
        (categoryName != null && categoryName.isNotEmpty)
            ? categoryName.toUpperCase()
            : 'ДРУГОЕ',
        styles: const PosStyles(bold: true, reverse: true),
      );

      for (final item in entry.value) {
        final name = item.goods.name.length > 28
            ? '${item.goods.name.substring(0, 26)}..'
            : item.goods.name;

        bytes += gen.row([
          PosColumn(
            text: name,
            width: 9,
            styles: const PosStyles(bold: false),
          ),
          PosColumn(
            text: 'x${item.quantity}',
            width: 3,
            styles: const PosStyles(bold: false, align: PosAlign.right),
          ),
        ]);

        // Waiter oqimi izohni `commet` da, kassir oqimlari `comment` da yuboradi.
        final note = item.commet.isNotEmpty ? item.commet : item.comment;
        if (note.isNotEmpty) {
          bytes += gen.text(
            '  >> $note',
            styles: const PosStyles(bold: false, underline: true),
          );
        }
      }
    }

    bytes += gen.hr();

    // ── Footer ───────────────────────────────────────────────────────────────
    if (guestCount > 0) {
      bytes += gen.text('Гостей: $guestCount', styles: const PosStyles(bold: false));
    }
    appendReceiptNoReprepNotice(gen, bytes);
    bytes += gen.feed(2);
    bytes += gen.cut();

    return bytes;
  }
}
