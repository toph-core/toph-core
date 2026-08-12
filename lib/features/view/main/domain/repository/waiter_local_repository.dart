import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_line_item/order_line_item_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart' show OrderItem;

enum WaiterOrdersListMode { myOrders, branchOrders }

class WaiterCreateOrderResult {
  final String orderId;

  /// `true` when this order wasn't newly created — a local open bill already
  /// existed for the same table and [orderId] was recovered from it instead.
  /// (The old network path recovered it from a server 409; a replay-time 409
  /// is merged by `OfflineQueueService`'s existing conflict branch.)
  final bool wasExisting;

  final double? servicePercent;
  final String? totalAmount;
  final String? serviceAmount;
  final String? orderType;

  /// LAN_HUB_AND_LEASING_PLAN.md §9.3: `true` when the table-open went
  /// ahead without lease arbitration because the LAN leader was
  /// unreachable — the caller should surface a visible "egalik
  /// tekshirilmadi" warning, not treat it as a clean grant.
  final bool leaseUnverified;

  const WaiterCreateOrderResult(
    this.orderId, {
    this.wasExisting = false,
    this.servicePercent,
    this.totalAmount,
    this.serviceAmount,
    this.orderType,
    this.leaseUnverified = false,
  });
}

/// What `WaiterCubit` depends on for its reads and writes.
///
/// CLIENT_FACING_OFFLINE_PLAN.md §5: this used to describe itself as "a pure
/// online transport" — every read a live GET, every write a direct POST with
/// the outbox only as the Cubit's failure fallback. It is now the inverse,
/// the same local-first shape `OrdersRepository`/`PaymentRepository` already
/// have: reads are synthesized from `LocalDatabase` (the order-detail box
/// SyncEngine hydrates and local creates write), writes delegate to those
/// same correct repositories (one create path, one add-items path, one pay
/// path — `closeOrder` goes through `PaymentRepository.pay`, not a second
/// parallel `/pay` POST). No Dio anywhere.
abstract class WaiterLocalRepository {
  /// Open orders synthesized from the local order-detail box + tables/halls.
  /// [mode] is accepted for call-site compatibility but both modes currently
  /// serve the same local set — the box isn't waiter-scoped (flagged in
  /// EXECUTION_CONCERNS.md).
  Future<Either<Failure, List<OpenOrderModel>>> getOpenOrders({
    required WaiterOrdersListMode mode,
    String lang,
    String scope,
    int limit,
    int offset,
  });

  /// `Right(null)` when no local bill matches [orderId] — treated as
  /// "nothing to merge," not an error.
  Future<Either<Failure, OpenOrderModel?>> getOrderDetail(String orderId);

  Future<Either<Failure, List<OrderLineItemModel>>> getOrderItems(
    String orderId,
  );

  /// Staff list from the SyncEngine-hydrated users box, filtered to waiters.
  Future<Either<Failure, List<UserModel>>> getStaffWaiters();

  /// Local commit: marks the line cancelled in the local bill and enqueues
  /// the cancel through `OrdersRepository.cancelLineItems`.
  Future<Either<Failure, bool>> cancelOrderItem({
    required String orderItemId,
    String? comment,
  });

  /// Local commit through `OrdersRepository.addItems` (same op, same
  /// idempotency keys, same LAN broadcast the cashier flow uses), plus a
  /// local bill patch so the added items are durable immediately.
  Future<Either<Failure, bool>> sendItems({
    required String orderId,
    required String tableId,
    required List<OrderItem> items,
  });

  /// One pay path, not two: delegates to `PaymentRepository.pay()` and
  /// finishes the close locally (bill evicted, table freed + broadcast).
  Future<Either<Failure, bool>> closeOrder({
    required String orderId,
    required String tableId,
    required int paidAmount,
    required String paymentType,
    double discountPercent,
    double discountAmount,

    /// Frozen table charge carried on the order, pinned into the pay payload
    /// for the same reason `PaymentRepository.pay` pins it.
    int tableCharge,
  });

  /// Local commit, gated by the same table lease `CreateOrderBloc` awaits
  /// (LAN_HUB_AND_LEASING_PLAN.md §5/§8 — this path must not bypass the
  /// double-booking guard): a rejection returns a `Failure`, an unreachable
  /// leader allows the open with `leaseUnverified` set. On grant/allow:
  /// enqueues the create (client-generated id, optional waiter binding),
  /// writes the local bill snapshot, marks the table busy.
  Future<Either<Failure, WaiterCreateOrderResult>> createOrder({
    required String tableId,
    required int guestCount,
    String? waiterId,
  });
}
