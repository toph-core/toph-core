import 'dart:math' as math;

import 'package:mary_ai_pos/core/utils/order_totals.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';

/// Chek summalari — yagona hisob-kitob manbai.
///
/// `ReceiptPreviewModal` (ekrandagi chek) va `CashierReceiptBuilder`
/// (printerga yuboriladigan chek) SHU klass orqali hisoblaydi, shunda
/// ko'rsatilgan chek chop etiladigan chek bilan hech qachon farq qilmaydi.
class ReceiptTotals {
  /// Chop etiladigan mahsulotlar — bekor qilinganlar chiqarib tashlangan.
  final List<OrderFoodEntity> goods;

  /// Mahsulotlar jami (bekor qilinganlarsiz).
  final double subtotal;

  /// Xizmat haqi (server bergan summa, bo'lmasa foizdan hisoblanadi).
  final double serviceAmount;

  /// Soatlik (time-based stol) haq.
  final double hourAmount;

  /// Chegirma qiymati so'mda (foiz bo'lsa preDiscount dan hisoblanadi).
  final double discountValue;

  /// Yakuniy to'lov: subtotal + hourAmount + serviceAmount − discountValue.
  final double toPay;

  const ReceiptTotals._({
    required this.goods,
    required this.subtotal,
    required this.serviceAmount,
    required this.hourAmount,
    required this.discountValue,
    required this.toPay,
  });

  factory ReceiptTotals.fromDetail(
    ArchiveDetailEntity detail, {
    double hourAmount = 0,
    double discountPercent = 0,
    double discountAmount = 0,
  }) {
    final goods =
        detail.goods.where((g) => g.status != 'cancelled').toList();
    // Hisob — `OrderTotals` (backend /pay formulasi): xizmat stol haqiga ham.
    final totals = OrderTotals.fromDetail(
      detail,
      tableCharge: hourAmount,
      discountPercent: discountPercent,
      discountAmount: discountAmount,
    );
    return ReceiptTotals._(
      goods: goods,
      subtotal: totals.itemsAmount.toDouble(),
      serviceAmount: totals.serviceAmount.toDouble(),
      hourAmount: hourAmount,
      discountValue: totals.discountValue.toDouble(),
      toPay: totals.grandTotal.toDouble(),
    );
  }

  /// Foizli yoki fiks chegirma qiymati so'mda.
  static double discountValueOf(
    double preDiscount,
    double discountPercent,
    double discountAmount,
  ) {
    if (discountPercent > 0) {
      final v = preDiscount * discountPercent / 100.0;
      if (v > 0.0001) return v;
    }
    if (discountAmount > 0.0001) return math.min(discountAmount, preDiscount);
    return 0;
  }
}
