/// offline-first-target-architecture.md §9 (V2) + §12 rule 1.
///
/// A single local commit (outbox enqueue) that returns immediately, same
/// §4 flow as `OrdersRepository`. Also closes §12's safety-critical finding:
/// `payOrder`'s payload previously had no client-generated idempotency key
/// at all, unlike every other write in this app — a retried POST (e.g. a
/// timeout after the charge actually landed server-side) had nothing for
/// the backend to dedupe a duplicate charge on. [pay] now generates one.
abstract class PaymentRepository {
  Future<void> pay({
    required String orderId,
    required String tableId,
    required int paidAmount,
    required String paymentType,
    required bool applyService,
    int? discountAmount,
    int? discountPercent,
  });

  /// A fully-discounted/comped check closed with nothing due — `/cancel`,
  /// not `/pay`, per the existing zero-total special case.
  Future<void> cancelZeroTotalOrder({
    required String orderId,
    required String tableId,
  });
}
