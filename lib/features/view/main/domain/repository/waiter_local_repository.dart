import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_line_item/order_line_item_model.dart';

enum WaiterOrdersListMode { myOrders, branchOrders }

class WaiterCreateOrderResult {
  final String orderId;

  /// `true` when this order wasn't newly created — the server returned 409
  /// because the table already had one, and [orderId] was recovered from the
  /// conflict response instead.
  final bool wasExisting;

  final double? servicePercent;
  final String? totalAmount;
  final String? serviceAmount;
  final String? orderType;

  const WaiterCreateOrderResult(
    this.orderId, {
    this.wasExisting = false,
    this.servicePercent,
    this.totalAmount,
    this.serviceAmount,
    this.orderType,
  });
}

/// What `WaiterCubit` depends on instead of calling `DioClient` directly.
///
/// This is a pure online transport — cache-first fallback exists only for
/// [getOpenOrders] (the list screen itself). Detail/line-item reads
/// ([getOrderDetail], [getOrderItems]) are deliberately live-only: unlike
/// archive history, an open order keeps changing, and a stale cached item
/// list could understate what a guest owes. Deciding what to do about a
/// write failing offline (queue it, per offline-first-architecture-plan.md
/// §11 Phase 1's precedent in `detail_bloc.dart`/`create_order_bloc.dart`/
/// `payment_bloc.dart`) is the Cubit's job, not this repository's — mutation
/// methods here just attempt the call and report `Either<Failure, T>`.
abstract class WaiterLocalRepository {
  Future<Either<Failure, List<OpenOrderModel>>> getOpenOrders({
    required WaiterOrdersListMode mode,
    String lang,
    String scope,
    int limit,
    int offset,
  });

  /// `Right(null)` when the order doesn't exist / response was malformed —
  /// treated as "nothing to merge," not an error, matching the Cubit's
  /// pre-existing silent-skip behavior.
  Future<Either<Failure, OpenOrderModel?>> getOrderDetail(String orderId);

  Future<Either<Failure, List<OrderLineItemModel>>> getOrderItems(
    String orderId,
  );

  Future<Either<Failure, List<UserModel>>> getStaffWaiters();

  Future<Either<Failure, bool>> cancelOrderItem({
    required String orderItemId,
    String? comment,
  });

  Future<Either<Failure, bool>> sendItems({
    required String orderId,
    required List<Map<String, dynamic>> items,
  });

  Future<Either<Failure, bool>> closeOrder({
    required String orderId,
    required Map<String, dynamic> payBody,
  });

  /// [body] is the full request body (already includes a client-generated
  /// `id` for idempotent retry/offline-queue replay). On a 409 conflict, the
  /// existing order id is recovered from the response and returned with
  /// `wasExisting: true` instead of surfacing an error.
  Future<Either<Failure, WaiterCreateOrderResult>> createOrder(
    Map<String, dynamic> body,
  );
}
