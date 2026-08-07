import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/utils/order_conflict_helper.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_food/order_food_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_take_away_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';

part 'create_order_event.dart';
part 'create_order_state.dart';
part 'create_order_bloc.freezed.dart';

class CreateOrderBloc extends Bloc<CreateOrderEvent, CreateOrderState> {
  late final CreateOrderUsecase _createOrderUsecase;
  late final CreateTakeAwayOrderUsecase _createTakeAwayOrderUsecase;
  final ConnectivityCubit _connectivity;
  final OfflineQueueService _queue;
  final LanHubService _lanHub;
  final MainRepository _mainRepository;
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
    required CreateOrderUsecase createOrderUsecase,
    required CreateTakeAwayOrderUsecase createTakeAwayOrderUsecase,
    required ConnectivityCubit connectivity,
    required OfflineQueueService queue,
    required LanHubService lanHub,
    required MainRepository mainRepository,
    required PrinterService printerService,
    required ShiftBloc shiftBloc,
  })  : _createOrderUsecase = createOrderUsecase,
        _createTakeAwayOrderUsecase = createTakeAwayOrderUsecase,
        _connectivity = connectivity,
        _queue = queue,
        _lanHub = lanHub,
        _mainRepository = mainRepository,
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
      // Same client-generated-id idempotency pattern as dine-in below: the
      // id is fixed once, before the online attempt, so a connection-failure
      // fallback into the offline queue replays under the SAME id rather
      // than risking a second order server-side if the original request
      // actually landed before the response was lost.
      final clientOrderId = generateUuidV4();

      if (!_connectivity.isOnline) {
        await _handleOfflineTakeaway(
          event.orders,
          emit,
          clientOrderId: clientOrderId,
        );
        return;
      }

      final response = await _createTakeAwayOrderUsecase.call(
        CreateOrderRequestModel(
          id: clientOrderId,
          orderType: "takeaway",
          foods: event.orders,
        ),
      );
      await response.fold(
        (l) async {
          if (l is ConnectionFailure) {
            await _handleOfflineTakeaway(
              event.orders,
              emit,
              clientOrderId: clientOrderId,
            );
            return;
          }
          showErrorMessage(
            navigatorKey.currentContext!,
            l.getLocalizedMessage(navigatorKey.currentContext!),
          );
          emit(state.copyWith(status: Status.ERROR, failure: l));
        },
        (r) async {
          // Fire-and-forget: oshxona cheki (kategoriya printerlari).
          unawaited(_printerService.printKitchenReceiptFor(
            tableLine: 'С собой',
            guestCount: state.guestCount,
            items: event.orders,
            orderId: r,
          ));
          Navigator.pushNamed(
            navigatorKey.currentContext!,
            AppRoutes.paymentScreen,
            arguments: {"order_id": r},
          );
          emit(state.copyWith(status: Status.SUCCESS, success: true));
        },
      );
      return;
    }

    // ── Dine-in ────────────────────────────────────────────────
    if (!_connectivity.isOnline) {
      await _handleOfflineOrder(event.orders, emit);
      return;
    }

    // Generated once per create attempt so a connection-failure retry (below)
    // replays under the SAME id rather than risking a second order server-side
    // if the original request actually landed before the response was lost.
    final clientOrderId = generateUuidV4();

    // Kalit qoida: agar `_activeOrderId` bog'langan bo'lsa — server'da
    // mavjud buyurtmaga item qo'shamiz (POST /api/v1/order-items).
    // `state.tableStatus` free bo'lsa ham shunday ishlaydi — UI holati
    // eskirgan bo'lsa ham 409 conflict yuz bermaydi.
    if (_activeOrderId != null) {
      await _addItemsToExistingOrder(
        orderId: _activeOrderId!,
        orders: event.orders,
        emit: emit,
      );
      return;
    }

    // Qo'shimcha himoya: stol busy lekin orderId hali bog'lanmagan — POST
    // /orders qilmaymiz (409 oldini olish). Foydalanuvchi ekranni yangilab
    // qayta urinsin (fetchBillOrders activeOrderId ni yozib qo'yadi).
    if (state.tableStatus == TableStatus.busy) {
      showErrorMessage(
        navigatorKey.currentContext!,
        "Buyurtma ID topilmadi. Ekranni yangilab qayta urinib ko'ring.",
      );
      emit(state.copyWith(status: Status.ERROR));
      return;
    }

    final request = CreateOrderRequestModel(
      id: clientOrderId,
      tableId: state.tableId,
      comment: "Very good",
      guestCount: state.guestCount,
      foods: event.orders,
      status: OrderStatus.open,
      tableStatus: state.tableStatus,
      orderType: "dine_in",
    );

    final response = await _createOrderUsecase.call(request);
    response.fold(
      (l) async {
        if (l is ConnectionFailure) {
          await _handleOfflineOrder(
            event.orders,
            emit,
            clientOrderId: clientOrderId,
          );
          return;
        }
        // 409 Conflict: stol allaqachon faol buyurtmaga ega. Xato ko'rsatish
        // o'rniga mavjud buyurtmaga bog'lanib, itemlarni o'shanga qo'shamiz —
        // shu orqali orphan/duplicate bill hosil bo'lishining oldi olinadi.
        if (l is MessageFailure) {
          final existingId = extractExistingOrderIdFromConflict(l.message);
          if (existingId != null && existingId.isNotEmpty) {
            bindActiveOrder(existingId);
            await _addItemsToExistingOrder(
              orderId: existingId,
              orders: event.orders,
              emit: emit,
            );
            return;
          }
        }
        l.showErrorMsg();
        emit(state.copyWith(status: Status.ERROR, failure: l));
      },
      (r) {
        _lanHub.tableStatusChanged(state.tableId, TableStatus.busy.name);
        // Fire-and-forget: oshxona cheki (kategoriya printerlari).
        // Eslatma: yangi dine-in order yaratilganda backend ID qaytarmaydi
        // (faqat bool) — shuning uchun bu yerda orderId yo'q.
        unawaited(_printerService.printKitchenReceiptFor(
          tableLine: _kitchenTableLine,
          guestCount: state.guestCount,
          items: event.orders,
        ));
        emit(state.copyWith(status: Status.SUCCESS, success: r));
      },
    );
  }

  Future<void> _addItemsToExistingOrder({
    required String orderId,
    required List<OrderItem> orders,
    required Emitter<CreateOrderState> emit,
  }) async {
    // Generated once so a connection-failure retry below (offline fallback)
    // replays under the SAME ids — same reasoning as clientOrderId above,
    // now for AddOrderItems' own idempotency key (order_items.client_item_id,
    // §13 risk #2). Without this, a response lost after the request already
    // committed server-side would fall into the offline queue with FRESH
    // ids that don't match anything already created — defeating the dedup.
    final itemClientIds = List.generate(orders.length, (_) => generateUuidV4());
    try {
      final result = await _mainRepository.createOrderItems(
        orderId: orderId,
        items: [
          for (var i = 0; i < orders.length; i++)
            {
              'comment': orders[i].comment,
              'good_id': orders[i].goods.id,
              'quantity': orders[i].quantity,
              'client_item_id': itemClientIds[i],
            },
        ],
      );
      final failure = result.fold((f) => f, (_) => null);
      if (failure != null) throw failure;
      _lanHub.tableStatusChanged(state.tableId, TableStatus.busy.name);
      // Fire-and-forget: oshxona cheki (kategoriya printerlari).
      unawaited(_printerService.printKitchenReceiptFor(
        tableLine: _kitchenTableLine,
        guestCount: state.guestCount,
        items: orders,
        orderId: orderId,
      ));
      emit(state.copyWith(status: Status.SUCCESS, success: true));
    } catch (e) {
      if (e is Failure && e.isConnectivityIssue) {
        await _handleOfflineOrder(
          orders,
          emit,
          orderId: orderId,
          itemClientIds: itemClientIds,
        );
        return;
      }
      showErrorMessage(
        navigatorKey.currentContext!,
        e is Failure ? e.getLocalizedMessage(navigatorKey.currentContext!) : 'Xato yuz berdi',
      );
      emit(state.copyWith(status: Status.ERROR));
    }
  }

  Future<void> _handleOfflineOrder(
    List<OrderItem> orders,
    Emitter<CreateOrderState> emit, {
    String? orderId,
    String? clientOrderId,
    List<String>? itemClientIds,
  }) async {
    final tableId = state.tableId;
    final createdAt = DateTime.now();

    if (state.tableStatus == TableStatus.busy) {
      // Mavjud orderga item qo'shish. client_item_id — backendning
      // AddOrderItems idempotency kaliti (order_items.client_item_id, §13
      // risk #2): shu id qayta yuborilsa (masalan, outbox operatsiyani
      // qayta ursa), backend takroriy item yaratmaydi. Agar bu chaqiruv bir
      // muvaffaqiyatsiz onlayn urinishdan keyin kelayotgan bo'lsa (ya'ni
      // caller `itemClientIds` uzatgan bo'lsa), o'sha aynan bir xil id'lar
      // qayta ishlatiladi — aks holda javob yo'qolgan-u so'rov aslida
      // serverga yetib borgan holatda, bu yerda yangi id generatsiya qilish
      // dedupni buzib, ikkinchi marta item yaratib qo'yardi.
      final ids = itemClientIds ??
          List.generate(orders.length, (_) => generateUuidV4());
      final payload = {
        'items': [
          for (var i = 0; i < orders.length; i++)
            {
              'comment': orders[i].comment,
              'good_id': orders[i].goods.id,
              'quantity': orders[i].quantity,
              'client_item_id': ids[i],
            },
        ],
      };
      await _queue.enqueue(PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.addItems,
        payload: jsonEncode(payload),
        tableId: tableId,
        createdAt: createdAt,
      ));
    } else {
      // Yangi order yaratish — clientOrderId bo'lsa (allaqachon online urinish
      // muvaffaqiyatsiz bo'lgan) o'shani qayta ishlatamiz, aks holda yangisini
      // generatsiya qilamiz.
      final request = CreateOrderRequestModel(
        id: clientOrderId ?? generateUuidV4(),
        tableId: tableId,
        comment: "Very good",
        guestCount: state.guestCount,
        foods: orders,
        status: OrderStatus.open,
        tableStatus: state.tableStatus,
        orderType: "dine_in",
      );
      await _queue.enqueue(PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.createOrder,
        payload: jsonEncode(request.request()),
        tableId: tableId,
        createdAt: createdAt,
      ));
    }

    // Optimistic: stol band deb belgilash + LAN broadcast
    _lanHub.tableStatusChanged(tableId, TableStatus.busy.name);
    // Backend offline bo'lsa ham LAN'dagi oshxona printeri ishlashi mumkin —
    // chek hozir chiqadi; queue sync paytida takror chop etilmaydi.
    unawaited(_printerService.printKitchenReceiptFor(
      tableLine: _kitchenTableLine,
      guestCount: state.guestCount,
      items: orders,
      orderId: orderId ?? _activeOrderId,
    ));
    emit(state.copyWith(status: Status.SUCCESS, success: true));
  }

  /// Takeaway's offline path — no table to mark busy (nothing to broadcast
  /// over LAN), and unlike dine-in there's no later "open the table" flow to
  /// pay through, since takeaway pays immediately. Instead of skipping
  /// payment until reconnection, this builds a local order-detail snapshot
  /// from what was just entered and caches it under [clientOrderId] — the
  /// same key `PaymentBloc._onGetDetail`'s orderId branch now checks first
  /// (cache-first, mirroring its existing tableId branch) — so the cashier
  /// can take payment right away exactly as they would online. The payment
  /// itself then queues through `PaymentBloc`'s already-existing
  /// `ConnectionFailure` → `payOrder` outbox path once attempted; the
  /// `createOrder` op below syncs first in the same `syncAll` pass (see
  /// `OfflineQueueService.syncAll`'s fixed op-type ordering), so by the time
  /// `payOrder` replays, the order already exists server-side under this
  /// same client id.
  Future<void> _handleOfflineTakeaway(
    List<OrderItem> orders,
    Emitter<CreateOrderState> emit, {
    required String clientOrderId,
  }) async {
    final request = CreateOrderRequestModel(
      id: clientOrderId,
      orderType: "takeaway",
      foods: orders,
    );
    await _queue.enqueue(PendingOperation(
      id: OfflineQueueService.newId(),
      type: PendingOperationType.createOrder,
      payload: jsonEncode(request.createOrder()),
      tableId: '',
      createdAt: DateTime.now(),
    ));

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
    await inject<CacheService>().saveOrderDetail(clientOrderId, snapshot.toJson());

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
