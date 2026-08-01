import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_line_item/order_line_item_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/waiter_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';

part 'waiter_state.dart';

/// Ofitsiant: `GET /orders/my`. Kassir: `GET /orders` (filial buyurtmalari).
typedef OrdersListMode = WaiterOrdersListMode;

class WaiterCubit extends Cubit<WaiterState> {
  final WaiterLocalRepository _repository;
  final PrinterService _printerService;
  final ShiftBloc _shiftBloc;

  OrdersListMode _ordersListMode = OrdersListMode.myOrders;

  WaiterCubit(this._repository, this._printerService, this._shiftBloc)
    : super(const WaiterState());

  /// Backend message when present (`MessageFailure`), else a fixed fallback —
  /// mirrors every other repository-backed Bloc's message policy rather than
  /// the raw `e.message`/`e.toString()` this Cubit showed before migration.
  String _messageFor(Failure failure, {required String fallback}) {
    if (failure is MessageFailure) return failure.message;
    return fallback;
  }

  void setOrdersListModeForRole(UserRole role) {
    _ordersListMode = role == UserRole.cashier
        ? OrdersListMode.branchOrders
        : OrdersListMode.myOrders;
  }

  /// Loads waiters for the create-bill form (`GET /api/v1/users`, filtered to role waiter).
  Future<void> loadStaffWaiters() async {
    emit(state.copyWith(isLoadingStaff: true));
    final result = await _repository.getStaffWaiters();
    if (isClosed) return;
    result.fold(
      (_) {
        if (!isClosed) emit(state.copyWith(isLoadingStaff: false));
      },
      (waiters) {
        if (!isClosed) {
          emit(state.copyWith(isLoadingStaff: false, staffWaiters: waiters));
        }
      },
    );
  }

  /// Ofitsiant/menejer: `GET /api/v1/orders/my`. Kassir: `GET /api/v1/orders`.
  Future<void> loadOpenOrders({
    String lang = 'uz',
    String scope = 'active',
    int limit = 50,
    int offset = 0,
  }) async {
    emit(state.copyWith(isLoadingOrders: true, errorMessage: null));
    final result = await _repository.getOpenOrders(
      mode: _ordersListMode,
      lang: lang,
      scope: scope,
      limit: limit,
      offset: offset,
    );
    if (isClosed) return;
    result.fold(
      (failure) {
        // Kassir ro'yxatida hamma `status`lar (paid, open, …) API bo'yicha —
        // faqat `open` qoldirmaymiz. Xato bo'lsa oldingi ro'yxat saqlanadi
        // (`openOrders` copyWith'da o'zgarmaydi).
        emit(
          state.copyWith(
            isLoadingOrders: false,
            errorMessage: _messageFor(failure, fallback: 'Xato yuz berdi'),
          ),
        );
      },
      (orders) {
        emit(state.copyWith(openOrders: orders, isLoadingOrders: false));
      },
    );
  }

  void selectOrder(String id) {
    emit(
      state.copyWith(
        selectedOrderId: id,
        panelMode: WaiterPanelMode.billDetail,
        orderLineItems: const [],
        isLoadingOrderItems: true,
        orderItemsEditMode: false,
        cancellingOrderItemId: null,
      ),
    );
    // Fresh order detail (total_amount) is important for time_based tables:
    // order items can be empty but total is still payable.
    loadOrderDetail(id);
    loadOrderItems(id);
  }

  Future<void> loadOrderDetail(String orderId) async {
    if (orderId.isEmpty) return;
    final result = await _repository.getOrderDetail(orderId);
    if (isClosed) return;
    result.fold((_) {}, (fresh) {
      if (fresh == null) return;
      final idx = state.openOrders.indexWhere((o) => o.id == orderId);
      if (idx < 0) return;
      final prev = state.openOrders[idx];
      final merged = _mergeOrder(prev, fresh);
      final nextOrders = [...state.openOrders];
      nextOrders[idx] = merged;
      if (!isClosed) {
        emit(state.copyWith(openOrders: nextOrders));
      }
    });
  }

  OpenOrderModel _mergeOrder(OpenOrderModel prev, OpenOrderModel fresh) {
    return prev.copyWith(
      name: (fresh.name != null && fresh.name!.trim().isNotEmpty)
          ? fresh.name
          : prev.name,
      tableId: (fresh.tableId != null && fresh.tableId!.isNotEmpty)
          ? fresh.tableId
          : prev.tableId,
      orderType: (fresh.orderType != null && fresh.orderType!.isNotEmpty)
          ? fresh.orderType
          : prev.orderType,
      tableType: (fresh.tableType != null && fresh.tableType!.isNotEmpty)
          ? fresh.tableType
          : prev.tableType,
      tableStartedAt: fresh.tableStartedAt ?? prev.tableStartedAt,
      status: (fresh.status != null && fresh.status!.isNotEmpty)
          ? fresh.status
          : prev.status,
      // Prefer API total if present and > 0.
      totalAmount:
          (fresh.totalAmountValue > 0) ? fresh.totalAmount : prev.totalAmount,
      displayTotalAmount: (fresh.displayTotalAmountValue > 0)
          ? fresh.displayTotalAmount
          : prev.displayTotalAmount,
      serviceAmount:
          (fresh.serviceAmount != null && fresh.serviceAmount!.trim().isNotEmpty)
          ? fresh.serviceAmount
          : prev.serviceAmount,
      servicePercent: fresh.servicePercent ?? prev.servicePercent,
      guestCount: fresh.guestCount != 0 ? fresh.guestCount : prev.guestCount,
      // Keep UI-friendly hall/tableNumber if detail endpoint doesn't send them.
      hallName: fresh.hallName.isNotEmpty ? fresh.hallName : prev.hallName,
      tableNumber:
          fresh.tableNumber != 0 ? fresh.tableNumber : prev.tableNumber,
      openedAt: fresh.openedAt ?? prev.openedAt,
    );
  }

  void showCreateForm() {
    emit(
      state.copyWith(
        panelMode: WaiterPanelMode.createForm,
        selectedOrderId: null,
        orderLineItems: const [],
        isLoadingOrderItems: false,
        orderItemsEditMode: false,
        cancellingOrderItemId: null,
      ),
    );
  }

  void closePanel() {
    emit(
      state.copyWith(
        panelMode: WaiterPanelMode.none,
        selectedOrderId: null,
        orderLineItems: const [],
        isLoadingOrderItems: false,
        orderItemsEditMode: false,
        cancellingOrderItemId: null,
      ),
    );
  }

  void toggleOrderItemsEditMode() {
    final order = state.selectedOrder;
    if (order != null && order.isTerminalOrderStatus) return;
    final id = state.selectedOrderId;
    final next = !state.orderItemsEditMode;
    emit(state.copyWith(orderItemsEditMode: next));
    if (next && id != null) {
      loadOrderItems(id);
    }
  }

  Future<void> _enqueueCancelLineItems(
    List<String> lineIds,
    String? comment,
  ) async {
    if (lineIds.isEmpty) return;
    await inject<OfflineQueueService>().enqueue(
      PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.cancelLineItems,
        payload: jsonEncode({
          'line_ids': lineIds,
          if (comment != null && comment.isNotEmpty) 'comment': comment,
        }),
        tableId: '',
        createdAt: DateTime.now(),
      ),
    );
  }

  void _applyOptimisticCancel({
    required String orderId,
    required String orderItemId,
  }) {
    if (state.selectedOrderId != orderId) return;
    final updated = state.orderLineItems
        .map((l) => l.id == orderItemId ? l.copyWith(status: 'cancelled') : l)
        .toList();
    emit(state.copyWith(orderLineItems: updated));
  }

  Future<void> cancelOrderItem({
    required String orderItemId,
    required String orderId,
    String? comment,
  }) async {
    if (orderItemId.isEmpty) return;
    emit(state.copyWith(cancellingOrderItemId: orderItemId));

    final result = await _repository.cancelOrderItem(
      orderItemId: orderItemId,
      comment: comment,
    );
    if (isClosed) return;

    await result.fold(
      (failure) async {
        if (failure is ConnectionFailure) {
          await _enqueueCancelLineItems([orderItemId], comment);
          if (!isClosed) {
            _applyOptimisticCancel(orderId: orderId, orderItemId: orderItemId);
            emit(state.copyWith(cancellingOrderItemId: null));
          }
          return;
        }
        emit(
          state.copyWith(
            cancellingOrderItemId: null,
            errorMessage: _messageFor(failure, fallback: 'Xato yuz berdi'),
          ),
        );
      },
      (_) async {
        emit(state.copyWith(cancellingOrderItemId: null));
        await loadOrderItems(orderId);
        await loadOpenOrders();
      },
    );
  }

  /// Loads saved line items (`GET /api/v1/order-items/order/{id}`).
  Future<void> loadOrderItems(String orderId) async {
    if (orderId.isEmpty) return;
    emit(state.copyWith(isLoadingOrderItems: true, errorMessage: null));
    final result = await _repository.getOrderItems(orderId);
    if (isClosed) return;
    result.fold(
      (failure) {
        emit(
          state.copyWith(
            isLoadingOrderItems: false,
            orderLineItems: const [],
            errorMessage: _messageFor(failure, fallback: 'Xato yuz berdi'),
          ),
        );
      },
      (items) {
        emit(state.copyWith(orderLineItems: items, isLoadingOrderItems: false));
      },
    );
  }

  void showCloseForm() {
    final o = state.selectedOrder;
    if (o != null && o.isTerminalOrderStatus) return;
    final id = state.selectedOrderId;
    if (id != null) {
      // Make sure total_amount is fresh before closing.
      loadOrderDetail(id);
    }
    emit(
      state.copyWith(panelMode: WaiterPanelMode.closeForm, orderItemsEditMode: false),
    );
    if (id != null) {
      loadOrderItems(id);
    }
  }

  void backToBillDetail() {
    emit(state.copyWith(panelMode: WaiterPanelMode.billDetail));
  }

  Future<void> _enqueueAddItems({
    required String tableId,
    required List<OrderItem> items,
  }) async {
    await inject<OfflineQueueService>().enqueue(
      PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.addItems,
        payload: jsonEncode({'items': _itemsToPayload(items)}),
        tableId: tableId,
        createdAt: DateTime.now(),
      ),
    );
  }

  List<Map<String, dynamic>> _itemsToPayload(List<OrderItem> items) => items
      .map(
        (item) => {
          'good_id': item.goods.id,
          'quantity': item.quantity,
          'comment': item.commet,
        },
      )
      .toList();

  void _applyOptimisticAdd({
    required String orderId,
    required List<OrderItem> items,
  }) {
    if (state.selectedOrderId != orderId) return;
    final synthetic = items
        .map(
          (item) => OrderLineItemModel(
            id: generateUuidV4(),
            goodId: item.goods.id,
            quantity: item.quantity,
            price: item.goods.price,
            comment: item.commet.isEmpty ? null : item.commet,
            goodName: item.goods.name,
            status: 'pending',
            createdAt: DateTime.now(),
          ),
        )
        .toList();
    emit(state.copyWith(orderLineItems: [...state.orderLineItems, ...synthetic]));
  }

  Future<void> sendItems({
    required String orderId,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    emit(state.copyWith(isSendingItems: true, errorMessage: null));

    final result = await _repository.sendItems(
      orderId: orderId,
      items: _itemsToPayload(items),
    );
    if (isClosed) return;

    await result.fold(
      (failure) async {
        if (failure is ConnectionFailure) {
          final tableId = state.openOrders
                  .where((o) => o.id == orderId)
                  .firstOrNull
                  ?.tableId ??
              '';
          await _enqueueAddItems(tableId: tableId, items: items);
          if (isClosed) return;
          _applyOptimisticAdd(orderId: orderId, items: items);
          emit(state.copyWith(isSendingItems: false));
          // Fire-and-forget: faqat oshxona cheklari, backend online bo'lmasa
          // ham LAN'dagi oshxona printeri ishlashi mumkin.
          final order = state.openOrders.where((o) => o.id == orderId).firstOrNull;
          if (order != null) {
            unawaited(
              _printerService.printKitchenReceipt(order: order, items: items),
            );
          }
          return;
        }
        emit(
          state.copyWith(
            isSendingItems: false,
            errorMessage: _messageFor(failure, fallback: 'Xato yuz berdi'),
          ),
        );
      },
      (_) async {
        emit(state.copyWith(isSendingItems: false));
        // Fire-and-forget: faqat oshxona cheklari (kategoriya printerlari). Kassa cheki faqat to'lovdan keyin (closeOrder).
        final order = state.openOrders.where((o) => o.id == orderId).firstOrNull;
        if (order != null) {
          unawaited(
            _printerService.printKitchenReceipt(order: order, items: items),
          );
        }
        await loadOrderItems(orderId);
        await loadOpenOrders();
      },
    );
  }

  /// Backend `total_amount` is safe for normal tables only.
  /// For time-based tables, recompute since GET omits the table_charge.
  int _payAmountSom(OpenOrderModel order, List<OrderLineItemModel> lines) {
    final sumLines = lines
        .where((l) => !l.isCancelled)
        .fold<double>(
          0,
          (s, l) => s + (double.tryParse(l.price) ?? 0) * l.quantity,
        );
    final tableCharge = order.tableAmountInt.toDouble();
    final servicePct = order.servicePercent ?? 0;

    if (tableCharge > 0.01) {
      // Service applies to items only — table_charge is not serviced.
      final serviceAmt = (sumLines * servicePct / 100).round();
      return sumLines.round() + tableCharge.round() + serviceAmt;
    }

    final apiTotal = order.totalAmountValue;
    if (apiTotal > 0) return apiTotal.round();

    final serviceAmt = (sumLines * servicePct / 100).round();
    return sumLines.round() + serviceAmt;
  }

  Future<void> _enqueueCloseOrder({
    required String orderId,
    required String tableId,
    required Map<String, dynamic> payBody,
  }) async {
    await inject<OfflineQueueService>().enqueue(
      PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.payOrder,
        payload: jsonEncode({'order_id': orderId, ...payBody}),
        tableId: tableId,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Shared by the online-success and offline-queued paths: printing and the
  /// local "this order is closed" state update don't depend on whether the
  /// `/pay` POST already landed or is sitting in the outbox — the amount was
  /// already computed locally either way.
  void _finishCloseOrderLocally({
    required OpenOrderModel order,
    required String orderId,
    required List<OrderLineItemModel> lineItems,
    required double base,
    required double discountPercent,
    required double discountAmount,
  }) {
    // Cheklarda departament bo'yicha guruhlash uchun cache'dagi goods
    // ro'yxatidan real category/department id larini olamiz.
    final goodsById = <String, Map<String, dynamic>>{
      for (final g in inject<CacheService>().getGoods())
        if (g['id'] != null) g['id'].toString(): g,
    };
    final receiptItems = lineItems.where((l) => !l.isCancelled).map((l) {
      final cached = goodsById[l.goodId];
      return OrderItem(
        goods: GoodsModel(
          categoryId: cached?['category_id']?.toString() ?? '',
          cookTime: 0,
          costPrice: l.price,
          departmentId: cached?['department_id']?.toString() ?? '',
          description: '',
          id: l.goodId,
          name: l.displayName,
          price: l.price,
          profit: '0',
          profitMargin: '0',
        ),
        quantity: l.quantity,
        commet: l.comment ?? '',
      );
    }).toList();
    final sumLines = lineItems
        .where((l) => !l.isCancelled)
        .fold<double>(0, (s, l) => s + (double.tryParse(l.price) ?? 0) * l.quantity);
    final hourAmountForReceipt =
        (order.tableType == 'time_based' && base > sumLines)
        ? (base - sumLines).toDouble()
        : 0.0;
    _printerService.printCashierReceipt(
      order: order,
      items: receiptItems,
      discountPercent: discountPercent,
      discountAmount: discountAmount,
      hourAmount: hourAmountForReceipt,
    );
    final updatedOrders = state.openOrders.where((o) => o.id != orderId).toList();
    emit(
      state.copyWith(
        isClosingOrder: false,
        openOrders: updatedOrders,
        panelMode: WaiterPanelMode.none,
        selectedOrderId: null,
        orderLineItems: const [],
        isLoadingOrderItems: false,
        orderItemsEditMode: false,
        cancellingOrderItemId: null,
      ),
    );
  }

  Future<void> closeOrder(
    PaymentType paymentType, {
    double discountPercent = 0,
    double discountAmount = 0,
  }) async {
    final orderId = state.selectedOrderId;
    final order = state.selectedOrder;
    if (orderId == null || order == null) return;
    final lineItems = state.orderLineItems;
    final base = _payAmountSom(order, lineItems).toDouble();
    // Barcha pozitsiyalar bekor / summa 0 — schyotni yopish kerak (mahsulot qo'shmasdan).
    if (base < 0) {
      emit(state.copyWith(errorMessage: 'Некорректная сумма счёта'));
      return;
    }

    // Backend: customer_paid_amount — chegirmadan oldingi summa; 0 qabul qilinadi.
    final customerPaidAmount = base.round().clamp(0, 1 << 30);

    emit(state.copyWith(isClosingOrder: true, errorMessage: null));

    final payBody = <String, dynamic>{
      'payment_type': paymentType.name,
      'customer_paid_amount': '$customerPaidAmount',
    };
    final hasDiscount = discountPercent > 0 || discountAmount > 0;
    if (hasDiscount) {
      if (discountPercent > 0) {
        payBody['discount_percent'] = discountPercent.toStringAsFixed(0);
      }
      if (discountAmount > 0) {
        payBody['discount_amount'] = discountAmount.round().toString();
      }
      payBody['discount_comment'] = '';
    }

    final result = await _repository.closeOrder(
      orderId: orderId,
      payBody: payBody,
    );
    if (isClosed) return;

    await result.fold(
      (failure) async {
        if (failure is ConnectionFailure) {
          await _enqueueCloseOrder(
            orderId: orderId,
            tableId: order.tableId ?? '',
            payBody: payBody,
          );
          if (isClosed) return;
          _finishCloseOrderLocally(
            order: order,
            orderId: orderId,
            lineItems: lineItems,
            base: base,
            discountPercent: discountPercent,
            discountAmount: discountAmount,
          );
          return;
        }
        emit(
          state.copyWith(
            isClosingOrder: false,
            errorMessage: _messageFor(failure, fallback: 'Xato yuz berdi'),
          ),
        );
      },
      (_) async {
        _finishCloseOrderLocally(
          order: order,
          orderId: orderId,
          lineItems: lineItems,
          base: base,
          discountPercent: discountPercent,
          discountAmount: discountAmount,
        );
        await loadOpenOrders();
      },
    );
  }

  Future<void> _enqueueCreateOrder(Map<String, dynamic> body) async {
    await inject<OfflineQueueService>().enqueue(
      PendingOperation(
        id: OfflineQueueService.newId(),
        type: PendingOperationType.createOrder,
        payload: jsonEncode(body),
        tableId: body['table_id'] as String? ?? '',
        createdAt: DateTime.now(),
      ),
    );
  }

  void _insertCreatedOrder(OpenOrderModel newOrder, {required bool willLoadItems}) {
    emit(
      state.copyWith(
        isCreatingOrder: false,
        openOrders: [newOrder, ...state.openOrders],
        selectedOrderId: newOrder.id,
        panelMode: WaiterPanelMode.billDetail,
        orderLineItems: const [],
        isLoadingOrderItems: willLoadItems,
        orderItemsEditMode: false,
        cancellingOrderItemId: null,
      ),
    );
  }

  Future<void> createOrder({
    required String tableId,
    required String hallName,
    required int tableNumber,
    int guestCount = 1,
    String? name,
    String? waiterId,
  }) async {
    // Check if shift is open before creating orders
    final shiftState = _shiftBloc.state;
    if (shiftState.shift == null) {
      emit(
        state.copyWith(
          isCreatingOrder: false,
          errorMessage: "Smena ochilmagan. Iltimos, avval smenani oching.",
        ),
      );
      return;
    }

    emit(state.copyWith(isCreatingOrder: true, errorMessage: null));

    final clientOrderId = generateUuidV4();
    final body = <String, dynamic>{
      'id': clientOrderId,
      'table_id': tableId,
      'guest_count': guestCount,
      'status': 'open',
    };
    if (waiterId != null && waiterId.isNotEmpty) {
      body['waiter_id'] = waiterId;
    }

    final result = await _repository.createOrder(body);
    if (isClosed) return;

    await result.fold(
      (failure) async {
        if (failure is ConnectionFailure) {
          await _enqueueCreateOrder(body);
          if (isClosed) return;
          _insertCreatedOrder(
            OpenOrderModel(
              id: clientOrderId,
              name: name,
              tableNumber: tableNumber,
              hallName: hallName,
              guestCount: guestCount,
              openedAt: DateTime.now(),
              tableId: tableId,
              status: 'open',
              totalAmount: '0',
              orderType: 'dine_in',
            ),
            willLoadItems: false,
          );
          return;
        }
        emit(
          state.copyWith(
            isCreatingOrder: false,
            errorMessage: _messageFor(failure, fallback: 'Xato yuz berdi'),
          ),
        );
      },
      (created) async {
        if (created.wasExisting) {
          await _openExistingOrder(created.orderId);
          return;
        }
        _insertCreatedOrder(
          OpenOrderModel(
            id: created.orderId,
            name: name,
            tableNumber: tableNumber,
            hallName: hallName,
            guestCount: guestCount,
            openedAt: DateTime.now(),
            tableId: tableId,
            status: 'open',
            totalAmount: created.totalAmount ?? '0',
            serviceAmount: created.serviceAmount,
            servicePercent: created.servicePercent,
            orderType: created.orderType ?? 'dine_in',
          ),
          willLoadItems: true,
        );
        await loadOpenOrders();
        await loadOrderItems(created.orderId);
      },
    );
  }

  /// 409 conflict paytida chaqiriladi: buyurtma `state.openOrders`da
  /// bo'lmasligi mumkin (masalan boshqa ofitsiantniki) — shuning uchun
  /// `selectOrder`dan foydalanmaymiz, balki uni to'g'ridan-to'g'ri yuklab
  /// ro'yxatga qo'shamiz.
  Future<void> _openExistingOrder(String orderId) async {
    final result = await _repository.getOrderDetail(orderId);
    if (isClosed) return;
    await result.fold(
      (_) async {
        emit(state.copyWith(isCreatingOrder: false));
      },
      (existing) async {
        final alreadyListed = state.openOrders.any((o) => o.id == orderId);
        emit(
          state.copyWith(
            isCreatingOrder: false,
            openOrders: (existing != null && !alreadyListed)
                ? [existing, ...state.openOrders]
                : state.openOrders,
            selectedOrderId: orderId,
            panelMode: WaiterPanelMode.billDetail,
            orderLineItems: const [],
            isLoadingOrderItems: true,
            orderItemsEditMode: false,
            cancellingOrderItemId: null,
          ),
        );
        await loadOpenOrders();
        await loadOrderItems(orderId);
      },
    );
  }
}
