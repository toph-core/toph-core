import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_food/order_food_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';

part 'create_order_event.dart';
part 'create_order_state.dart';
part 'create_order_bloc.freezed.dart';

/// offline-first-target-architecture.md §4/§6/§9 (V1). Every write here is a
/// single local commit through `OrdersRepository` (outbox enqueue) that
/// returns without ever awaiting the network — the UI's "success" and the
/// local commit are the same event, whether this terminal is online,
/// offline, or LAN-only. The §6 table-open lease wait that used to be the
/// one exception is currently commented out per CLIENT_FACING_OFFLINE_PLAN.md
/// carve-out #2 — table-open is a pure local write for now, and the
/// double-booking race the lease guarded is deferred to its own later piece
/// of work (see offline-first-target-architecture.md §6's follow-up note).
///
/// A duplicate table-open 409 (the online path used to catch this
/// synchronously and merge into the winning order) is now handled entirely
/// by `OfflineQueueService._execCreateOrder`'s own 409-merge branch at
/// replay time — nothing left for this Bloc to do about it.
class CreateOrderBloc extends Bloc<CreateOrderEvent, CreateOrderState> {
  final OrdersRepository _ordersRepository;
  // Kept (not deleted) while the lease calls are commented out — carve-out
  // #2 keeps LeaseManager wired so re-enabling is a two-line uncomment.
  // ignore: unused_field
  final LeaseManager _leaseManager;
  final LanHubService _lanHub;
  final PrinterService _printerService;
  final ShiftBloc _shiftBloc;

  // Active order ID for busy tables — set via bindActiveOrder()
  String? _activeOrderId;

  void bindActiveOrder(String orderId) => _activeOrderId = orderId;

  // Oshxona cheki header'i uchun stol raqami — bindActiveOrder() singari UI
  // dan bog'lanadi (state freezed, regen talab qilmaslik uchun oddiy field).
  int _tableNumber = 0;

  void bindTableNumber(int number) => _tableNumber = number;

  String get _kitchenTableLine =>
      _tableNumber > 0 ? 'Стол: $_tableNumber' : 'Стол: —';

  CreateOrderBloc({
    required OrdersRepository ordersRepository,
    required LeaseManager leaseManager,
    required LanHubService lanHub,
    required PrinterService printerService,
    required ShiftBloc shiftBloc,
  })  : _ordersRepository = ordersRepository,
        _leaseManager = leaseManager,
        _lanHub = lanHub,
        _printerService = printerService,
        _shiftBloc = shiftBloc,
        super(const CreateOrderState()) {
    on<_Started>(_started);
    on<_CreateOrder>(_createOrder);
  }

  void _createOrder(_CreateOrder event, emit) async {
    emit(state.copyWith(status: Status.LOADING));

    // Check if shift is open before creating orders
    final shiftState = _shiftBloc.state;
    if (shiftState.shift == null) {
      showErrorMessage(
        navigatorKey.currentContext!,
        "Smena ochilmagan. Iltimos, avval smenani oching.",
      );
      emit(state.copyWith(status: Status.ERROR));
      return;
    }

    if (state.tableId.isEmpty) {
      // ── Takeaway ─────────────────────────────────────────────────
      final clientOrderId = generateUuidV4();
      await _handleTakeaway(event.orders, emit, clientOrderId: clientOrderId);
      return;
    }

    // ── Dine-in ────────────────────────────────────────────────
    // Kalit qoida: agar `_activeOrderId` bog'langan bo'lsa — mavjud
    // buyurtmaga item qo'shamiz. `state.tableStatus` free bo'lsa ham shunday
    // ishlaydi — UI holati eskirgan bo'lsa ham muammo bo'lmaydi, chunki bu
    // endi ham network-await emas, faqat lokal yozuv.
    if (_activeOrderId != null) {
      await _addItemsToExistingOrder(
        orderId: _activeOrderId!,
        orders: event.orders,
        emit: emit,
      );
      return;
    }

    // Qo'shimcha himoya: stol busy lekin orderId hali bog'lanmagan.
    // Foydalanuvchi ekranni yangilab qayta urinsin (fetchBillOrders
    // activeOrderId ni yozib qo'yadi).
    if (state.tableStatus == TableStatus.busy) {
      showErrorMessage(
        navigatorKey.currentContext!,
        "Buyurtma ID topilmadi. Ekranni yangilab qayta urinib ko'ring.",
      );
      emit(state.copyWith(status: Status.ERROR));
      return;
    }

    // CLIENT_FACING_OFFLINE_PLAN.md carve-out #2: the lease wait is
    // commented out (NOT deleted — LeaseManager and its service stay
    // intact). Table-open is a pure local write like everything else for
    // now; the double-booking race this guarded against is picked back up
    // later as its own piece of work. See EXECUTION_CONCERNS.md and the
    // follow-up note in offline-first-target-architecture.md §6.
    // final lease = await _leaseManager.acquireTableLease(state.tableId);
    // if (!lease.isGranted) {
    //   showErrorMessage(
    //     navigatorKey.currentContext!,
    //     lease.isUnreachable
    //         ? (lease.unreachableReason ?? "Stol egaligini tekshirib bo'lmadi.")
    //         : "Bu stol allaqachon boshqa terminalda ochilgan.",
    //   );
    //   emit(state.copyWith(status: Status.ERROR));
    //   return;
    // }

    final clientOrderId = generateUuidV4();
    await _ordersRepository.createOrder(
      tableId: state.tableId,
      clientOrderId: clientOrderId,
      guestCount: state.guestCount,
      items: event.orders,
      tableStatus: state.tableStatus,
    );
    // Local order-detail snapshot, keyed by tableId — same shape
    // `_handleTakeaway` below already writes for its own clientOrderId key.
    // Without this, `DetailBloc.fetchBillOrders`'s only source for
    // `activeOrderId` was its narrow live-fetch fallback, which silently
    // no-ops while offline (see that method's doc comment) — so this table
    // would show "busy" locally but "Buyurtma ID topilmadi" on every
    // add-items attempt until connectivity returned and a fetch finally
    // landed. Writing the snapshot here means `watchOrderDetail(tableId)`
    // resolves `activeOrderId` immediately, offline or not.
    await _ordersRepository.saveOrderDetailSnapshot(
      state.tableId,
      _buildLocalOrderSnapshot(id: clientOrderId, orders: event.orders).toJson(),
    );
    bindActiveOrder(clientOrderId);
    // Lease release commented out together with the acquire above
    // (carve-out #2) — nothing is held, so there is nothing to release.
    // _leaseManager.releaseTableLease(state.tableId);

    // Fire-and-forget: oshxona cheki (kategoriya printerlari).
    unawaited(_printerService.printKitchenReceiptFor(
      tableLine: _kitchenTableLine,
      guestCount: state.guestCount,
      items: event.orders,
    ));
    emit(state.copyWith(status: Status.SUCCESS, success: true));
  }

  Future<void> _addItemsToExistingOrder({
    required String orderId,
    required List<OrderItem> orders,
    required Emitter<CreateOrderState> emit,
  }) async {
    await _ordersRepository.addItems(
      tableId: state.tableId,
      orderId: orderId,
      items: orders,
    );
    _lanHub.tableStatusChanged(state.tableId, TableStatus.busy.name);
    // Fire-and-forget: oshxona cheki (kategoriya printerlari).
    unawaited(_printerService.printKitchenReceiptFor(
      tableLine: _kitchenTableLine,
      guestCount: state.guestCount,
      items: orders,
      orderId: orderId,
    ));
    emit(state.copyWith(status: Status.SUCCESS, success: true));
  }

  /// Takeaway has no table to lease/mark busy, and unlike dine-in there's no
  /// later "open the table" flow to pay through, since takeaway pays
  /// immediately. This builds a local order-detail snapshot from what was
  /// just entered and saves it under [clientOrderId] — the same key
  /// `PaymentBloc`'s orderId branch reads (cache-first, via the same
  /// `OrdersRepository.watchOrderDetail`) — so the cashier can take payment
  /// right away exactly as they would online. The payment itself then
  /// queues through `PaymentRepository`'s own local-first `pay()`; the
  /// `createOrder` op below syncs first in the same `syncAll` pass (see
  /// `OfflineQueueService.syncAll`'s fixed op-type ordering), so by the time
  /// `payOrder` replays, the order already exists server-side under this
  /// same client id.
  Future<void> _handleTakeaway(
    List<OrderItem> orders,
    Emitter<CreateOrderState> emit, {
    required String clientOrderId,
  }) async {
    await _ordersRepository.createTakeawayOrder(
      clientOrderId: clientOrderId,
      guestCount: state.guestCount,
      items: orders,
    );

    final snapshot = _buildLocalOrderSnapshot(id: clientOrderId, orders: orders);
    await _ordersRepository.saveOrderDetailSnapshot(clientOrderId, snapshot.toJson());

    // Fire-and-forget: oshxona cheki (kategoriya printerlari).
    unawaited(_printerService.printKitchenReceiptFor(
      tableLine: 'С собой',
      guestCount: state.guestCount,
      items: orders,
      orderId: clientOrderId,
    ));

    Navigator.pushNamed(
      navigatorKey.currentContext!,
      AppRoutes.paymentScreen,
      arguments: {"order_id": clientOrderId},
    );
    emit(state.copyWith(status: Status.SUCCESS, success: true));
  }

  /// Local order-detail snapshot built purely from what the cashier just
  /// entered — no server round trip. Used by both the dine-in "new order"
  /// path and takeaway (`_handleTakeaway`), which save it under different
  /// keys (tableId vs. clientOrderId respectively).
  ArchiveDetailModel _buildLocalOrderSnapshot({
    required String id,
    required List<OrderItem> orders,
  }) {
    final foodTotal = orders.fold<double>(
      0,
      (s, o) => s + (double.tryParse(o.goods.price) ?? 0) * o.quantity,
    );
    return ArchiveDetailModel(
      id: id,
      status: OrderStatus.open,
      opened: DateTime.now(),
      guestCount: state.guestCount.toDouble(),
      foodTotal: foodTotal,
      goods: [
        for (final o in orders)
          OrderFoodModel(
            goodId: o.goods.id,
            name: o.goods.name,
            quantity: o.quantity,
            price: (double.tryParse(o.goods.price) ?? 0).round(),
            comment: o.comment,
          ) as OrderFoodEntity,
      ],
    );
  }

  void _started(_Started event, emit) => emit(
        CreateOrderState(
          tableId: event.tableId ?? '',
          guestCount: event.guestCount,
          tableStatus: event.tableStatus,
        ),
      );
}
