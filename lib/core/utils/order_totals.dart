import 'dart:math' as math;

import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';

/// Buyurtma yakuniy summasi — backend `POST /orders/{id}/pay` bilan
/// bir xil formula (docs/order-total-calculation.md §1):
///
/// ```
/// service     = ROUND((items + table) × percent / 100)   // stol haqiga ham xizmat
/// base_total  = items + table + service
/// discount    = percent ? ROUND(base × %/100) : flat
/// grand_total = MAX(base − discount, 0)
/// ```
///
/// To'lov ekrani, `PaymentBloc` va chek (`ReceiptTotals`) faqat shu klass
/// orqali hisoblashi shart — aks holda ko'rsatilgan summa server talab
/// qiladigan summadan farq qilib, "insufficient payment" xatosi chiqadi.
class OrderTotals {
  /// Mahsulotlar jami (bekor qilinganlarsiz) + offline navbatdagi qo'shimchalar.
  final int itemsAmount;

  /// Time-based stol haqi (soatlik).
  final int tableCharge;

  /// Xizmat haqi — mahsulot VA stol haqi ustidan.
  final int serviceAmount;

  /// itemsAmount + tableCharge + serviceAmount (chegirmadan oldin).
  final int baseTotal;

  /// Chegirma so'mda (foiz bo'lsa baseTotal dan, fiks bo'lsa baseTotal bilan cheklangan).
  final int discountValue;

  /// Yakuniy to'lov — server `/pay` da aynan shu summani talab qiladi.
  final int grandTotal;

  const OrderTotals._({
    required this.itemsAmount,
    required this.tableCharge,
    required this.serviceAmount,
    required this.baseTotal,
    required this.discountValue,
    required this.grandTotal,
  });

  factory OrderTotals.fromDetail(
    ArchiveDetailEntity detail, {
    double tableCharge = 0,
    double offlineExtra = 0,
    double servicePercentFallback = 0,
    double discountPercent = 0,
    double discountAmount = 0,
    bool includeService = true,
  }) {
    double items = offlineExtra;
    for (final g in detail.goods) {
      if (g.status == 'cancelled') continue;
      items += g.price * g.quantity;
    }

    // Read-path (`GET /orders/{id}`) `service_amount`/`grand_total` stol
    // haqiga xizmatni QO'SHMAYDI (guide §7/§9) — stol haqi bor bo'lsa
    // server bergan qiymatga ishonmay, foizdan qayta hisoblaymiz.
    double pct = detail.servicePercent > 0
        ? detail.servicePercent
        : servicePercentFallback;
    double service;
    if (!includeService) {
      service = 0;
    } else if (tableCharge > 0.01) {
      if (pct <= 0 && detail.serviceAmount > 0.01 && items > 0) {
        // Foiz kelmagan — read-path service_amount faqat mahsulotlarga
        // hisoblangan, foizni undan tiklaymiz.
        pct = detail.serviceAmount / items * 100;
      }
      service = pct > 0 ? (items + tableCharge) * pct / 100 : 0;
    } else {
      service = detail.serviceAmount > 0.01
          ? detail.serviceAmount
          : (pct > 0 ? items * pct / 100 : 0);
    }

    final itemsInt = items.round();
    final tableInt = tableCharge.round();
    final serviceInt = service.round();
    int base = itemsInt + tableInt + serviceInt;

    // Himoya: bills javobida items bo'sh, lekin grand_total bor bo'lsa
    // (eski xatti-harakat) — jamini yo'qotmaymiz.
    if (base == 0 && detail.goods.isEmpty && detail.grandTotal > 0.01) {
      base = detail.grandTotal.round();
    }

    final int discount;
    if (discountPercent > 0) {
      discount = (base * discountPercent / 100).round();
    } else if (discountAmount > 0) {
      discount = math.min(discountAmount.round(), base);
    } else {
      discount = 0;
    }

    return OrderTotals._(
      itemsAmount: itemsInt,
      tableCharge: tableInt,
      serviceAmount: serviceInt,
      baseTotal: base,
      discountValue: discount,
      grandTotal: math.max(base - discount, 0),
    );
  }
}
