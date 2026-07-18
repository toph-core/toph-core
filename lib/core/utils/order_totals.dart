import 'dart:math' as math;

import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';

/// Single source of truth for order totals displayed / paid on the POS.
///
/// Formula matches [PaymentBloc.effectiveTotal] on main (see
/// `order-total-calculation.md`):
///
/// - With [tableCharge] > 0: never trust API `grand_total` / `service_amount`;
///   recompute service on (items + table).
/// - Without table charge: prefer API `grand_total` when no cancelled lines;
///   otherwise items + service from `service_amount` or percent.
class OrderTotals {
  /// Non-cancelled line items (+ optional offline extras folded into items).
  final int itemsAmount;

  /// Time-based table charge (so'm, rounded).
  final int tableCharge;

  /// Service fee used for display / toggle; may differ from API when table
  /// charge forces a recomputation.
  final int serviceAmount;

  /// Total before discount (and after optional service exclusion).
  final int baseTotal;

  /// Discount in so'm (capped at [baseTotal] for flat discounts).
  final int discountValue;

  /// Amount due after discount — what `/pay` should receive as the target.
  final int grandTotal;

  const OrderTotals._({
    required this.itemsAmount,
    required this.tableCharge,
    required this.serviceAmount,
    required this.baseTotal,
    required this.discountValue,
    required this.grandTotal,
  });

  /// Builds totals from an order detail using main's authoritative rules.
  ///
  /// Optional extras mirror payment UI:
  /// - [offlineExtra] — pending offline line totals added on top of the core total
  /// - [discountPercent] / [discountAmount] — mutually exclusive in practice
  /// - [includeService] — when false, service is excluded from the payable total
  /// - [servicePercentFallback] — used only for service **display** / exclusion
  ///   amount when API percent is 0 (does not change the no-table-charge path
  ///   that trusts API `grand_total`)
  factory OrderTotals.fromDetail(
    ArchiveDetailEntity detail, {
    double tableCharge = 0,
    double offlineExtra = 0,
    double servicePercentFallback = 0,
    double discountPercent = 0,
    double discountAmount = 0,
    bool includeService = true,
  }) {
    final foodSum = detail.goods
        .where((g) => g.status != 'cancelled')
        .fold(0.0, (s, g) => s + g.price * g.quantity);

    final itemsInt = foodSum.round();
    final tableInt = tableCharge.round();

    late final int serviceInt;
    late final int coreTotal;

    if (tableCharge > 0.01) {
      var pct = detail.servicePercent;
      if (pct <= 0 && foodSum > 0.01 && detail.serviceAmount > 0.01) {
        pct = detail.serviceAmount / foodSum * 100;
      }
      if (pct <= 0 && servicePercentFallback > 0) {
        pct = servicePercentFallback;
      }
      serviceInt = ((foodSum + tableCharge) * pct / 100).round();
      coreTotal = (foodSum + tableCharge).round() + serviceInt;
    } else {
      final hasCancelled = detail.goods.any((g) => g.status == 'cancelled');
      final pct = detail.servicePercent > 0
          ? detail.servicePercent
          : servicePercentFallback;
      serviceInt = detail.serviceAmount > 0.01
          ? detail.serviceAmount.round()
          : (foodSum * pct / 100).round();

      if (!hasCancelled && detail.grandTotal > 0.01) {
        coreTotal = detail.grandTotal.round();
      } else {
        coreTotal = itemsInt + serviceInt;
      }
    }

    var base = includeService
        ? coreTotal + offlineExtra.round()
        : math.max(coreTotal - serviceInt, 0) + offlineExtra.round();

    // Empty-goods bills fallback (rare): preserve API grand when nothing else.
    if (base == 0 &&
        detail.goods.isEmpty &&
        offlineExtra.abs() < 0.01 &&
        detail.grandTotal > 0.01) {
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
      itemsAmount: itemsInt + offlineExtra.round(),
      tableCharge: tableInt,
      serviceAmount: serviceInt,
      baseTotal: base,
      discountValue: discount,
      grandTotal: math.max(base - discount, 0),
    );
  }
}
