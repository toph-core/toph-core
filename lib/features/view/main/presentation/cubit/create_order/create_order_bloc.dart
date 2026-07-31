import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/utils/order_conflict_helper.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
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
  final DioClient _client;
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
    required DioClient client,
    required PrinterService printerService,
    required ShiftBloc shiftBloc,
  })  : _createOrderUsecase = createOrderUsecase,
        _createTakeAwayOrderUsecase = createTakeAwayOrderUsecase,
        _connectivity = connectivity,
        _queue = queue,
        _lanHub = lanHub,
        _client = client,
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
      // ── Takeaway — always requires online ──────────────────────
      final response = await _createTakeAwayOrderUsecase.call(
        CreateOrderRequestModel(
          orderType: "takeaway",
          foods: event.orders,
        ),
      );
      response.fold(
        (l) {
          showErrorMessage(
            navigatorKey.currentContext!,
            l.getLocalizedMessage(navigatorKey.currentContext!),
          );
          emit(state.copyWith(status: Status.ERROR, failure: l));
        },
        (r) {
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
          await _handleOfflineOrder(event.orders, emit);
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
    try {
      await _client.post(
        ListAPI.orderItemsCreate,
        data: {
          'order_id': orderId,
          'items': orders
              .map((o) => {
                    'comment': o.comment,
                    'good_id': o.goods.id,
                    'quantity': o.quantity,
                  })
              .toList(),
        },
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
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        await _handleOfflineOrder(orders, emit, orderId: orderId);
        return;
      }
      showErrorMessage(
        navigatorKey.currentContext!,
        e.message ?? 'Xato yuz berdi',
      );
      emit(state.copyWith(status: Status.ERROR));
    }
  }

  Future<void> _handleOfflineOrder(
    List<OrderItem> orders,
    Emitter<CreateOrderState> emit, {
    String? orderId,
  }) async {
    final tableId = state.tableId;
    final createdAt = DateTime.now();

    if (state.tableStatus == TableStatus.busy) {
      // Mavjud orderga item qo'shish
      final payload = {
        'items': orders
            .map((o) => {
                  'comment': o.comment,
                  'good_id': o.goods.id,
                  'quantity': o.quantity,
                })
            .toList(),
      };
      await _queue.enqueue(PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.addItems,
        payload: jsonEncode(payload),
        tableId: tableId,
        createdAt: createdAt,
      ));
    } else {
      // Yangi order yaratish
      final request = CreateOrderRequestModel(
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

  void _started(_Started event, emit) => emit(
        CreateOrderState(
          tableId: event.tableId ?? '',
          guestCount: event.guestCount,
          tableStatus: event.tableStatus,
        ),
      );
}
