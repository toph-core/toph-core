import 'dart:math' as math;

import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 3 — the local calculation engine.
///
/// Three entry points, deliberately distinct:
///
/// * [OrderTotals.compute] — the **pure engine**. Every input is a plain local
///   number; nothing here reads a server-supplied aggregate. This is meant to
///   be the same formula the backend re-derives and enforces at pay time, so
///   that a locally-computed total survives replay unchanged.
///
///   Transcribed from `OFFLINE_FIRST_EVERYWHERE_PLAN.md` §"Phase 3", which
///   cites `order.go:2023-2027`. **Not diffed against that source** — the
///   backend is a separate repository and is not checked out here. If the two
///   ever disagree the server wins at pay time and the cashier sees the total
///   move after a replay, so this is the first place to look when that
///   happens.
/// * [OrderTotals.fromDetail] — the **read-path adapter** over an
///   [ArchiveDetailEntity]. Still consults server aggregates (`grand_total`,
///   `service_amount`) for already-synced and archived orders, where the
///   server's recorded number *is* the historical truth. See the Phase 4 seam
///   note on [fromDetail].
/// * [OrderTotals.forPayment] — the **single input-assembly point** for the
///   payment screen. Its whole reason to exist is that the displayed total and
///   the charged total must be the same number; before it, the screen and
///   `PaymentBloc._payment` each assembled their own subset of the inputs and
///   silently disagreed whenever a discount or the service toggle was in play.
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

  /// The pure local engine — `order.go`'s pay-time formula, in Dart:
  ///
  /// ```
  /// itemsAmount   = Σ (qty × price)                              // non-cancelled
  /// tableCharge   = (activeSeconds / 3600) × pricePerHour        // 0 if not time-based
  /// serviceAmount = round(itemsAmount × servicePercent / 100)    // NOT on tableCharge
  /// baseTotal     = itemsAmount + tableCharge + serviceAmount
  /// discount      = pct > 0 ? round(baseTotal × pct / 100) : min(flat, baseTotal)
  /// grandTotal    = max(baseTotal − discount, 0)
  /// ```
  ///
  /// `double` arithmetic with [num.round] at the points the Go code rounds —
  /// not `Decimal`, which would diverge from the server on the half-up
  /// boundary. Service is charged on food only; the table charge is never
  /// serviced.
  ///
  /// [includeService] `false` drops service from [baseTotal] but still reports
  /// it in [serviceAmount], because the UI needs the excluded amount to label
  /// its toggle.
  factory OrderTotals.compute({
    required double itemsAmount,
    double tableCharge = 0,
    double servicePercent = 0,
    double discountPercent = 0,
    double discountAmount = 0,
    bool includeService = true,
  }) {
    final itemsInt = itemsAmount.round();
    final tableInt = tableCharge.round();
    final serviceInt = (itemsAmount * servicePercent / 100).round();

    final base = math.max(
      itemsInt + tableInt + (includeService ? serviceInt : 0),
      0,
    );
    final discount = _discountOn(base, discountPercent, discountAmount);

    return OrderTotals._(
      itemsAmount: itemsInt,
      tableCharge: tableInt,
      serviceAmount: serviceInt,
      baseTotal: base,
      discountValue: discount,
      grandTotal: math.max(base - discount, 0),
    );
  }

  static int _discountOn(int base, double percent, double flat) {
    if (percent > 0) return (base * percent / 100).round();
    if (flat > 0) return math.min(flat.round(), base);
    return 0;
  }

  /// Read-path adapter over a server-shaped order detail.
  ///
  /// Optional extras mirror payment UI:
  /// - [offlineExtra] — pending offline line totals added on top of the core total
  /// - [discountPercent] / [discountAmount] — mutually exclusive in practice
  /// - [includeService] — when false, service is excluded from the payable total
  /// - [servicePercentFallback] — used only for service **display** / exclusion
  ///   amount when API percent is 0 (does not change the no-table-charge path
  ///   that trusts API `grand_total`)
  ///
  /// **Phase 4 seam.** The no-table-charge branch below trusts `grand_total`
  /// when no line is cancelled. For an order that synced once and was then
  /// edited offline that value is stale, and the locally-added items are
  /// invisible to it — today [offlineExtra] papers over exactly that, by
  /// summing the not-yet-synced `addItems` ops still sitting in the legacy Hive
  /// queue. When Phase 4 moves item writes onto the outbox that queue empties,
  /// [offlineExtra] goes to 0, and the paper comes off: the screen would show a
  /// stale total and undercharge. Phase 4 must switch this path to
  /// [OrderTotals.compute] over the local `order_items` rows *in the same
  /// change* that migrates the writes — the two are one unit, not two steps.
  /// Left as-is here on purpose: flipping what customers are charged is not
  /// something to do in a phase whose tests cannot be executed.
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
      serviceInt = (foodSum * pct / 100).round();
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

    final discount = _discountOn(base, discountPercent, discountAmount);

    return OrderTotals._(
      itemsAmount: itemsInt + offlineExtra.round(),
      tableCharge: tableInt,
      serviceAmount: serviceInt,
      baseTotal: base,
      discountValue: discount,
      grandTotal: math.max(base - discount, 0),
    );
  }

  /// The one place payment inputs are assembled.
  ///
  /// The payment screen renders [grandTotal] and `PaymentBloc` charges it —
  /// both through this call, from the same state, so the two cannot drift.
  /// [discountRaw] is the numpad's string exactly as it sits in
  /// `PaymentState.discountAmount`; [discountType] decides whether it lands as
  /// a percentage or a flat so'm amount, which is the demux each caller used to
  /// re-derive on its own.
  factory OrderTotals.forPayment({
    required ArchiveDetailEntity detail,
    double tableCharge = 0,
    double offlineExtra = 0,
    double servicePercent = 0,
    DiscountType discountType = DiscountType.money,
    String discountRaw = '0',
    bool includeService = true,
  }) {
    final entered = (int.tryParse(discountRaw) ?? 0).toDouble();
    final isPercent = discountType == DiscountType.percent;
    return OrderTotals.fromDetail(
      detail,
      tableCharge: tableCharge,
      offlineExtra: offlineExtra,
      servicePercentFallback: servicePercent,
      discountPercent: isPercent ? entered : 0,
      discountAmount: isPercent ? 0 : entered,
      includeService: includeService,
    );
  }
}
