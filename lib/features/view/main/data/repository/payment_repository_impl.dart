import 'dart:math' as math;

import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/pricing/order_totals.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/payment_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — the payment write, on the one
/// outbox and on the replica.
///
/// Two things happen here that did not before.
///
/// **1. The bill closes locally.** The old implementation queued the payment
/// and nothing else: the `orders` row kept `bill_status = 'open'`, so
/// `OrderDetailQuery.liveOrderForTable` — which is what the floor, the order
/// screen and the waiter open-order list all read — still reported a live bill
/// on a table the cashier had just settled. Online the next pull corrected it;
/// offline nothing ever did. Now the settled state is written onto the row in
/// the same transaction that queues the send, so every replica read agrees the
/// bill is closed the instant the receipt prints.
///
/// **2. It replays through the outbox.** `orders/pay` and `orders/cancel`
/// already existed in `core/outbox/orders_outbox.dart` with nothing enqueuing
/// them; these two methods are what they were written for. The retiring
/// `OfflineQueueService` loses its last order-flow caller here.
///
/// ## The shape of the closed row
///
/// It is the server's own, field for field, so the row written here and the row
/// the change feed delivers after the payment lands converge instead of
/// fighting. `PayOrderBill` (`repository/pg/tenantsdb/bills_custom.go`) sets
/// `bill_status = 'paid'`, `status = 'paid'`, `paid_at`, `bill_closed_at`,
/// `payment_type`, `service_applied`, the settled money columns and
/// `change_amount`; every one of those is written below from the numbers the
/// cashier was looking at. `food_cost` is the one column deliberately left out
/// — it needs each good's cost price, is shown nowhere on this path, and the
/// pull fills it in.
///
/// ## Why the write is pending-guarded
///
/// [LocalWriter.write] marks the row in `_pending`, and [ChangeApplier] skips
/// any pull row whose guard is held. Without it the window between "the cashier
/// paid" and "the payment reached the server" is exactly the window in which a
/// pull carrying the server's still-open version of this order would overwrite
/// the paid row and put the bill back on the table. The guard clears when the
/// pay op is acknowledged (`OutboxDrainer._succeed`), after which the server's
/// version is the authoritative one — which is the right order of precedence,
/// because by then the server has the payment too.
class PaymentRepositoryImpl implements PaymentRepository {
  final LocalWriter _writer;

  PaymentRepositoryImpl({required LocalWriter writer}) : _writer = writer;

  @override
  Future<void> pay({
    required String orderId,
    required String tableId,
    required int paidAmount,
    required String paymentType,
    required bool applyService,
    int? discountAmount,
    int? discountPercent,
    int tableCharge = 0,
    OrderTotals? settled,
  }) async {
    // One clock for the whole operation: the same instant is stamped on the
    // local row and sent in the request, so the bill does not move in the
    // archive when the server's version of it arrives.
    final closedAt = DateTime.now().toUtc().toIso8601String();
    // Normalised once: "no discount" is 0 on both paths, so the request and
    // the row cannot disagree about which of the two forms was used.
    final percent = (discountPercent ?? 0) > 0 ? discountPercent! : 0;
    final flat = (discountAmount ?? 0) > 0 ? discountAmount! : 0;

    final request = <String, dynamic>{
      'order_id': orderId,
      'customer_paid_amount': paidAmount.toString(),
      'payment_type': paymentType,
      'apply_service': applyService,
      // §12 rule 1 (the design doc's own "single most safety-critical
      // finding"). Generated once here and baked into the persisted outbox
      // payload, so every replay attempt resends the identical id rather than
      // a fresh one per attempt.
      //
      // Note what actually protects a replay today: `MarkOrderPaid` returns an
      // already-paid order unchanged (its own "idempotency guard"), so a
      // retried POST cannot insert a second `bill_payment`. The API has no
      // `client_payment_id` field at all — `MarkOrderPaidRequest` does not
      // declare it and `encoding/json` drops it silently — so this key is
      // carried for the day the server keys on it, not relied on now.
      'client_payment_id': generateUuidV4(),
      // The moment the cashier closed the check, not the moment the terminal
      // got its network back. `MarkOrderPaidRequest.PaidAt` is optional and
      // the settle SQL is `COALESCE($12, NOW())`, so omitting it means a
      // check paid offline at 22:00 and replayed at 09:00 lands in the next
      // day's archive under the wrong time — and disagrees with the row
      // written below, which would then jump when the pull arrives. Same
      // frozen-clock reasoning as `table_charge`.
      'paid_at': closedAt,
      // Phase 3: pin the table charge to the clock the receipt was printed
      // against. The value is frozen into the persisted payload here, so a
      // replay hours later still bills the minutes the customer actually sat.
      // Strings, not numbers. `MarkOrderPaidRequest` declares these three as
      // `*string` (`internal/model/order.go`), and Echo binds with
      // `encoding/json`, which refuses a JSON number into a string field — so
      // sending `50000` rather than `"50000"` 400s the entire pay request.
      //
      // That failure mode is worse than a lost send: a 4xx is permanent, so
      // the op quarantines, `OutboxDrainer` releases the row's `_pending`
      // guard, and the next pull reopens a bill the cashier has already
      // settled. `customer_paid_amount` above was already a string, which is
      // what made the inconsistency easy to miss.
      if (tableCharge > 0) 'table_charge': tableCharge.toString(),
      if (flat > 0) 'discount_amount': flat.toString(),
      if (percent > 0) 'discount_percent': percent.toString(),
    };

    final row = <String, dynamic>{
      // Present so a pay against an order this terminal has never stored still
      // produces a well-formed row rather than a keyless one.
      'id': orderId,
      'bill_status': 'paid',
      'status': 'paid',
      'paid_at': closedAt,
      'bill_closed_at': closedAt,
      if (paymentType.isNotEmpty) 'payment_type': paymentType,
      'service_applied': applyService,
      'customer_paid_amount': paidAmount,
      // The server derives the split the same way when the request carries no
      // explicit cash/card amounts (`OrderS.MarkOrderPaid`).
      if (paymentType == 'cash') 'cash_amount': paidAmount,
      if (paymentType == 'card') 'card_amount': paidAmount,
      'table_charge': tableCharge,
      // `null`, not omitted: the server writes `discount_percent = $5`
      // unconditionally, so a bill settled without a percentage discount has
      // no percentage on it. Omitting the key would leave a stale one behind
      // from an earlier edit.
      'discount_percent': percent > 0 ? percent : null,
      'discount_amount': settled?.discountValue ?? flat,
      if (settled != null) ...{
        'food_total': settled.itemsAmount,
        // `OrderTotals` reports the service amount even when the toggle
        // excludes it, because the UI labels the toggle with it; the bill
        // settles at 0, exactly as `PayOrderBill`'s `CASE ... ELSE 0` does.
        'service_amount': applyService ? settled.serviceAmount : 0,
        'grand_total': settled.grandTotal,
        'total_amount': settled.grandTotal,
        'change_amount': math.max(paidAmount - settled.grandTotal, 0),
      },
    };

    _writer.write(
      entity: 'orders',
      id: orderId,
      action: 'pay',
      merge: true,
      row: row,
      request: request,
    );
  }

  @override
  Future<void> cancelZeroTotalOrder({
    required String orderId,
    required String tableId,
  }) async {
    // A comped check closes through `/cancel`, and `CancelOrder`
    // (`sqlc/tenants/queries/order.sql`) sets `status = 'cancelled'` and
    // *nothing else* — `bill_status` stays `opened` on the server. So that is
    // all that is written here. Marking the row `closed` locally would look
    // tidier and would be undone by the first pull after the cancel acks,
    // which is the "fighting" this whole shape exists to avoid.
    //
    // The bill still leaves every live read: `OrderDetailQuery` excludes a
    // cancelled order from the open-bill lookups, mirroring the server's own
    // `SetTableFree` on the same path.
    _writer.write(
      entity: 'orders',
      id: orderId,
      action: 'cancel',
      merge: true,
      row: <String, dynamic>{'id': orderId, 'status': 'cancelled'},
      request: <String, dynamic>{'order_id': orderId},
    );
  }
}
