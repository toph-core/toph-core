import 'package:mary_ai_pos/core/pricing/order_totals.dart';

/// offline-first-target-architecture.md §9 (V2) + §12 rule 1.
///
/// A single local commit (replica row + outbox enqueue) that returns
/// immediately, same §4 flow as `OrdersRepository`. Also closes §12's
/// safety-critical finding: `payOrder`'s payload previously had no
/// client-generated idempotency key at all, unlike every other write in this
/// app — a retried POST (e.g. a timeout after the charge actually landed
/// server-side) had nothing for the backend to dedupe a duplicate charge on.
/// [pay] now generates one.
///
/// ## The bill closes here, not when the payment syncs
///
/// Both methods write the closed state onto the local `orders` row as part of
/// the same commit that queues the send. Before that, the only thing a payment
/// changed locally was the table-occupancy overlay: the `orders` row kept
/// `bill_status = 'open'`, so `OrderDetailQuery.liveOrderForTable` still
/// reported a live bill on a table the cashier had just settled. Online that
/// self-corrected on the next pull; offline — the state this architecture
/// exists to make correct — it never did.
abstract class PaymentRepository {
  Future<void> pay({
    required String orderId,
    required String tableId,
    required int paidAmount,
    required String paymentType,
    required bool applyService,
    int? discountAmount,
    int? discountPercent,

    /// The locally-computed time-based table charge, in so'm.
    ///
    /// Sent so the server prices the check against the clock the customer was
    /// actually charged on. Without it the backend re-derives the charge from
    /// its own timer when the queued pay replays, which for an offline check
    /// is a *later* clock than the one on the receipt — the customer is billed
    /// for the minutes between closing the table and the terminal coming back
    /// online.
    int tableCharge = 0,

    /// The totals the receipt was printed against, when the caller has them.
    ///
    /// Only the settled *state* of the bill needs the arguments above; these
    /// are the settled *numbers* — food total, service, discount, grand total —
    /// and they exist so the locally-closed row carries the same figures the
    /// cashier just handed the customer, rather than zeros until the payment
    /// syncs and a pull fills them in. The server recomputes all of them at
    /// pay time from the same formula (`OrderTotals` is a transcription of it),
    /// so the row a later pull delivers agrees with the one written here.
    ///
    /// Optional because a caller that has not assembled them (the waiter
    /// close-order path) can still close the bill correctly — it just leaves
    /// the money columns for the pull.
    OrderTotals? settled,
  });

  /// A fully-discounted/comped check closed with nothing due — `/cancel`,
  /// not `/pay`, per the existing zero-total special case.
  Future<void> cancelZeroTotalOrder({
    required String orderId,
    required String tableId,
  });
}
