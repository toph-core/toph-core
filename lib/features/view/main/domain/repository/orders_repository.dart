import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart' show OrderItem;

/// offline-first-target-architecture.md §9 (V1/V3/V6) — the shared
/// LocalRepository behind `CreateOrderBloc`'s table-open/add-items paths and
/// `DetailBloc`'s existing-item add/cancel/qty paths. Every write method
/// here follows §4's flow exactly: a single local commit (enqueue the
/// outbox op — order/bill state itself is written back by
/// `SyncEngine`/replay, not optimistically reconstructed here, since this
/// codebase's create/add-item responses don't return enough to rebuild an
/// authoritative bill row) that returns the instant the local commit is
/// done, never awaiting the network. Whether the corresponding cloud call
/// ever lands is invisible to every caller of this interface.
abstract class OrdersRepository {
  /// §1.2/V6: order/bill detail, read-only reactive view. Keyed by tableId
  /// for dine-in, by clientOrderId for takeaway (mirrors
  /// `CacheService.getOrderDetail`'s existing dual-key usage before this
  /// repository existed).
  Stream<ArchiveDetailModel?> watchOrderDetail(String key);

  /// Synchronous snapshot — for a one-off read that doesn't want to hold a
  /// subscription open (e.g. a kitchen-receipt print decision).
  ArchiveDetailModel? getOrderDetail(String key);

  Future<void> evictOrderDetail(String key);

  /// For a locally-originated snapshot with no server round trip yet (the
  /// takeaway offline flow's synthetic bill preview) — writes the given
  /// already-shaped JSON directly, same shape `watchOrderDetail`/
  /// `getOrderDetail` decode.
  Future<void> saveOrderDetailSnapshot(String key, Map<String, dynamic> json);

  /// Dine-in table-open. [tableStatus] is the table's status as the UI last
  /// saw it (kept as a parameter, not re-derived here, matching the existing
  /// `CreateOrderRequestModel.tableStatus` field the backend already
  /// expects).
  ///
  /// [waiterId] binds the opening waiter, for the waiter-app table-open path.
  /// It rides in the create body (the server accepts it) and the local order
  /// row; the cashier path leaves it null.
  Future<void> createOrder({
    required String tableId,
    required String clientOrderId,
    required int guestCount,
    required List<OrderItem> items,
    required TableStatus tableStatus,
    String? waiterId,
  });

  Future<void> createTakeawayOrder({
    required String clientOrderId,
    required int guestCount,
    required List<OrderItem> items,
  });

  /// Adds items to an already-open order. [itemClientIds], when given, reuse
  /// a caller-generated idempotency key set (e.g. the same ids a preceding
  /// now-abandoned online attempt already used) rather than minting fresh
  /// ones — see `create_order_bloc.dart`'s existing comment on this for why
  /// that matters (§13 risk #2).
  Future<void> addItems({
    required String tableId,
    required String orderId,
    required List<OrderItem> items,
    List<String>? itemClientIds,
  });

  Future<void> cancelLineItems({
    required List<String> lineIds,
    String? comment,
  });

  /// CLIENT_FACING_OFFLINE_PLAN.md §7: move an open order to another table —
  /// a local commit (bill row re-keyed to the target table, both tables'
  /// statuses patched, outbox enqueue) shaped exactly like the other write
  /// methods here, replacing `transfer_table_dialog`'s old awaited direct
  /// network call.
  Future<void> transferTable({
    required String orderId,
    required String sourceTableId,
    required String targetTableId,
  });
}
