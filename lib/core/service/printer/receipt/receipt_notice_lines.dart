import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Chekda: chek asosida qayta tayyorlamaslik (lotin — barcha kod jadvallarida barqaror).
///
/// MUHIM: parametr sifatida kelgan ro'yxatga `bytes += x` YOZIB BO'LMAYDI —
/// Dart'da bu lokal havolani qayta bog'laydi (`bytes = bytes + x`), chaqiruvchi
/// ro'yxati o'zgarmay qoladi va satrlar chekka umuman chiqmasdi. Shu sabab addAll.
void appendReceiptNoReprepNotice(Generator gen, List<int> bytes) {
  bytes.addAll(gen.hr());
  bytes.addAll(gen.text(
    'ВНИМАНИЕ: по чеку блюдо не готовить повторно.',
    styles: const PosStyles(bold: true, align: PosAlign.center),
    linesAfter: 1,
  ));
  bytes.addAll(gen.text(
    'Кухня и касса вдали от стола.',
    styles: const PosStyles(align: PosAlign.center),
    linesAfter: 1,
  ));
  bytes.addAll(gen.text(
    'Повторная подача только по заказу в POS/системе.',
    styles: const PosStyles(align: PosAlign.center),
    linesAfter: 1,
  ));
}
