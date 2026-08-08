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
/// offline, or LAN-only. The one exception, per §6, is the table-open path:
/// it waits on `LeaseManager.acquireTableLease` before that local commit,
/// since that's the one case where two different local databases might each
/// think they're right.
///
/// A duplicate table-open 409 (the online path used to catch this
/// synchronously and merge into the winning order) is now handled entirely
/// by `OfflineQueueService._execCreateOrder`'s own 409-merge branch at
/// replay time — nothing left for this Bloc to do about it.
class CreateOrderBloc extends Bloc<CreateOrderEvent, CreateOrderState> {
  final OrdersRepository _ordersRepository;
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

    // §6: the one deliberate exception to "UI never waits on anything" —
    // acquire the table lease before the local write.
    final lease = await _leaseManager.acquireTableLease(state.tableId);
    if (!lease.isGranted) {
      showErrorMessage(
        navigatorKey.currentContext!,
        lease.isUnreachable
            ? (lease.unreachableReason ?? "Stol egaligini tekshirib bo'lmadi.")
            : "Bu stol allaqachon boshqa terminalda ochilgan.",
      );
      emit(state.copyWith(status: Status.ERROR));
      return;
    }

    final clientOrderId = generateUuidV4();
    await _ordersRepository.createOrder(
      tableId: state.tableId,
      clientOrderId: clientOrderId,
      guestCount: state.guestCount,
      items: event.orders,
      tableStatus: state.tableStatus,
    );
    // Ephemeral claim cleared the instant this local write is confirmed —
    // same-process callback, not a network round trip (§6 Lease Recovery).
    _leaseManager.releaseTableLease(state.tableId);

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

    final foodTotal = orders.fold<double>(
      0,
      (s, o) => s + (double.tryParse(o.goods.price) ?? 0) * o.quantity,
    );
    final snapshot = ArchiveDetailModel(
      id: clientOrderId,
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

  void _started(_Started event, emit) => emit(
        CreateOrderState(
          tableId: event.tableId ?? '',
          guestCount: event.guestCount,
          tableStatus: event.tableStatus,
        ),
      );
}
