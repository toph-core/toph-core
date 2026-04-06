import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_line_item/order_line_item_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_staff_waiters_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

part 'waiter_state.dart';

/// Ofitsiant: `GET /orders/my`. Kassir: `GET /orders` (filial buyurtmalari).
enum OrdersListMode { myOrders, branchOrders }

class WaiterCubit extends Cubit<WaiterState> {
  final DioClient _client;
  final GetStaffWaitersUsecase _getStaffWaitersUsecase;

  OrdersListMode _ordersListMode = OrdersListMode.myOrders;

  WaiterCubit(this._client, this._getStaffWaitersUsecase)
      : super(const WaiterState());

  void setOrdersListModeForRole(UserRole role) {
    _ordersListMode = role == UserRole.cashier
        ? OrdersListMode.branchOrders
        : OrdersListMode.myOrders;
  }

  /// Loads waiters for the create-bill form (`GET /api/v1/users`, filtered to role waiter).
  Future<void> loadStaffWaiters() async {
    emit(state.copyWith(isLoadingStaff: true));
    final result = await _getStaffWaitersUsecase(NoParams());
    if (isClosed) return;
    result.fold(
      (_) {
        if (!isClosed) emit(state.copyWith(isLoadingStaff: false));
      },
      (waiters) {
        if (!isClosed) {
          emit(state.copyWith(
            isLoadingStaff: false,
            staffWaiters: waiters,
          ));
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
    try {
      final Response<dynamic> response;
      if (_ordersListMode == OrdersListMode.branchOrders) {
        response = await _client.get(
          ListAPI.orders,
          queryParameters: {
            'lang': lang,
            'limit': limit,
            'offset': offset,
          },
        );
      } else {
        response = await _client.get(
          ListAPI.ordersMy,
          queryParameters: {
            'lang': lang,
            'scope': scope,
            'limit': limit,
            'offset': offset,
          },
        );
      }
      if (isClosed) return;
      final rawData = response.data['data'];
      List<dynamic> list;
      if (rawData is List) {
        list = rawData;
      } else if (rawData is Map && rawData['data'] is List) {
        list = rawData['data'] as List;
      } else {
        list = [];
      }
      final orders = list
          .map((e) => OpenOrderModel.fromJson(e as Map<String, dynamic>))
          .toList();
      // Kassir ro‘yxatida hamma `status`lar (paid, open, …) API bo‘yicha — faqat `open` qoldirmaymiz.
      if (!isClosed) {
        emit(state.copyWith(openOrders: orders, isLoadingOrders: false));
      }
    } on DioException catch (e) {
      if (kDebugMode) print('WaiterCubit.loadOpenOrders error: $e');
      if (!isClosed) {
        emit(state.copyWith(isLoadingOrders: false, errorMessage: e.message));
      }
    } catch (e) {
      if (kDebugMode) print('WaiterCubit.loadOpenOrders error: $e');
      if (!isClosed) {
        emit(state.copyWith(isLoadingOrders: false, errorMessage: e.toString()));
      }
    }
  }

  void selectOrder(String id) {
    emit(state.copyWith(
      selectedOrderId: id,
      panelMode: WaiterPanelMode.billDetail,
      orderLineItems: const [],
      isLoadingOrderItems: true,
      orderItemsEditMode: false,
      cancellingOrderItemId: null,
    ));
    loadOrderItems(id);
  }

  void showCreateForm() {
    emit(state.copyWith(
      panelMode: WaiterPanelMode.createForm,
      selectedOrderId: null,
      orderLineItems: const [],
      isLoadingOrderItems: false,
      orderItemsEditMode: false,
      cancellingOrderItemId: null,
    ));
  }

  void closePanel() {
    emit(state.copyWith(
      panelMode: WaiterPanelMode.none,
      selectedOrderId: null,
      orderLineItems: const [],
      isLoadingOrderItems: false,
      orderItemsEditMode: false,
      cancellingOrderItemId: null,
    ));
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

  Future<void> cancelOrderItem({
    required String orderItemId,
    required String orderId,
  }) async {
    if (orderItemId.isEmpty) return;
    emit(state.copyWith(cancellingOrderItemId: orderItemId));
    try {
      await _client.post(
        ListAPI.orderItemCancel(orderItemId),
        queryParameters: {'lang': 'uz'},
        data: <String, dynamic>{},
      );
      if (isClosed) return;
      emit(state.copyWith(cancellingOrderItemId: null));
      await loadOrderItems(orderId);
      await loadOpenOrders();
    } on DioException catch (e) {
      if (kDebugMode) print('WaiterCubit.cancelOrderItem error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          cancellingOrderItemId: null,
          errorMessage: e.message ?? 'Xato yuz berdi',
        ));
      }
    } catch (e) {
      if (kDebugMode) print('WaiterCubit.cancelOrderItem error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          cancellingOrderItemId: null,
          errorMessage: e.toString(),
        ));
      }
    }
  }

  /// Loads saved line items (`GET /api/v1/order-items/order/{id}`).
  Future<void> loadOrderItems(String orderId) async {
    if (orderId.isEmpty) return;
    emit(state.copyWith(isLoadingOrderItems: true, errorMessage: null));
    try {
      final response = await _client.get(
        ListAPI.orderItemsListByOrder(orderId),
        queryParameters: {'lang': 'uz'},
      );
      if (isClosed) return;
      final raw = response.data['data'];
      List<dynamic> list;
      if (raw is List) {
        list = raw;
      } else if (raw is Map<String, dynamic>) {
        if (raw['items'] is List) {
          list = raw['items'] as List;
        } else if (raw['order'] is Map) {
          final o = raw['order'] as Map;
          if (o['items'] is List) {
            list = o['items'] as List;
          } else {
            list = [];
          }
        } else {
          list = [];
        }
      } else {
        list = [];
      }
      final items = list
          .whereType<Map>()
          .map(
            (e) => OrderLineItemModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
      if (!isClosed) {
        emit(state.copyWith(
          orderLineItems: items,
          isLoadingOrderItems: false,
        ));
      }
    } on DioException catch (e) {
      if (kDebugMode) print('WaiterCubit.loadOrderItems error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          isLoadingOrderItems: false,
          orderLineItems: const [],
          errorMessage: e.message,
        ));
      }
    } catch (e) {
      if (kDebugMode) print('WaiterCubit.loadOrderItems error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          isLoadingOrderItems: false,
          orderLineItems: const [],
          errorMessage: e.toString(),
        ));
      }
    }
  }

  void showCloseForm() {
    final o = state.selectedOrder;
    if (o != null && o.isTerminalOrderStatus) return;
    emit(state.copyWith(
      panelMode: WaiterPanelMode.closeForm,
      orderItemsEditMode: false,
    ));
    final id = state.selectedOrderId;
    if (id != null) {
      loadOrderItems(id);
    }
  }

  void backToBillDetail() {
    emit(state.copyWith(panelMode: WaiterPanelMode.billDetail));
  }

  Future<void> sendItems({
    required String orderId,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    emit(state.copyWith(isSendingItems: true, errorMessage: null));
    try {
      await _client.post(
        ListAPI.orderItems(orderId),
        queryParameters: {'lang': 'uz'},
        data: {
          'items': items
              .map((item) => {
                    'good_id': item.goods.id,
                    'quantity': item.quantity,
                    'comment': item.commet,
                  })
              .toList(),
        },
      );
      if (!isClosed) {
        emit(state.copyWith(isSendingItems: false));
        await loadOrderItems(orderId);
        await loadOpenOrders();
      }
    } on DioException catch (e) {
      if (kDebugMode) print('WaiterCubit.sendItems error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          isSendingItems: false,
          errorMessage: e.message ?? 'Xato yuz berdi',
        ));
      }
    } catch (e) {
      if (kDebugMode) print('WaiterCubit.sendItems error: $e');
      if (!isClosed) {
        emit(state.copyWith(isSendingItems: false, errorMessage: e.toString()));
      }
    }
  }

  /// Backend `total_amount` bo‘lsa — to‘lov shu summaga teng (`customer_paid_amount`).
  int _payAmountSom(OpenOrderModel order, List<OrderLineItemModel> lines) {
    final sumLines = lines
        .where((l) => !l.isCancelled)
        .fold<double>(
          0,
          (s, l) => s + (double.tryParse(l.price) ?? 0) * l.quantity,
        );
    final apiTotal = order.totalAmountValue;
    if (apiTotal > 0) return apiTotal.round();
    return sumLines.round();
  }

  Future<void> closeOrder(PaymentType paymentType) async {
    final orderId = state.selectedOrderId;
    final order = state.selectedOrder;
    if (orderId == null || order == null) return;
    final amount = _payAmountSom(order, state.orderLineItems);
    if (amount <= 0) {
      if (!isClosed) {
        emit(state.copyWith(
          errorMessage: 'To\'lov summasi 0 — schyotni yopib bo\'lmaydi',
        ));
      }
      return;
    }
    emit(state.copyWith(isClosingOrder: true, errorMessage: null));
    try {
      await _client.post(ListAPI.payToOrder(orderId), data: {
        'payment_type': paymentType.name,
        'customer_paid_amount': '$amount',
        'discount_amount': '0',
        'discount_comment': '',
        'discount_percent': '0',
      });
      if (isClosed) return;
      final updatedOrders =
          state.openOrders.where((o) => o.id != orderId).toList();
      emit(state.copyWith(
        isClosingOrder: false,
        openOrders: updatedOrders,
        panelMode: WaiterPanelMode.none,
        selectedOrderId: null,
        orderLineItems: const [],
        isLoadingOrderItems: false,
        orderItemsEditMode: false,
        cancellingOrderItemId: null,
      ));
      await loadOpenOrders();
    } on DioException catch (e) {
      if (kDebugMode) print('WaiterCubit.closeOrder error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          isClosingOrder: false,
          errorMessage: e.message ?? 'Xato yuz berdi',
        ));
      }
    } catch (e) {
      if (kDebugMode) print('WaiterCubit.closeOrder error: $e');
      if (!isClosed) {
        emit(state.copyWith(isClosingOrder: false, errorMessage: e.toString()));
      }
    }
  }

  Future<void> createOrder({
    required String tableId,
    required String hallName,
    required int tableNumber,
    int guestCount = 1,
    String? name,
    String? waiterId,
  }) async {
    emit(state.copyWith(isCreatingOrder: true, errorMessage: null));
    try {
      final body = <String, dynamic>{
        'table_id': tableId,
        'guest_count': guestCount,
        'status': 'open',
      };
      if (waiterId != null && waiterId.isNotEmpty) {
        body['waiter_id'] = waiterId;
      }
      final response = await _client.post(ListAPI.orders, data: body);
      if (isClosed) return;
      final raw = response.data['data'];
      final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final orderId = data['id'] as String? ?? '';
      double? sp;
      final rawSp = data['service_percent'];
      if (rawSp is num) {
        sp = rawSp.toDouble();
      } else if (rawSp != null) {
        sp = double.tryParse(rawSp.toString());
      }
      final newOrder = OpenOrderModel(
        id: orderId,
        name: name,
        tableNumber: tableNumber,
        hallName: hallName,
        guestCount: guestCount,
        openedAt: DateTime.now(),
        tableId: tableId,
        status: 'open',
        totalAmount: data['total_amount']?.toString() ?? '0',
        serviceAmount: data['service_amount']?.toString(),
        servicePercent: sp,
        orderType: data['order_type'] as String? ?? 'dine_in',
      );
      emit(state.copyWith(
        isCreatingOrder: false,
        openOrders: [newOrder, ...state.openOrders],
        selectedOrderId: orderId,
        panelMode: WaiterPanelMode.billDetail,
        orderLineItems: const [],
        isLoadingOrderItems: true,
        orderItemsEditMode: false,
        cancellingOrderItemId: null,
      ));
      await loadOpenOrders();
      await loadOrderItems(orderId);
    } on DioException catch (e) {
      if (kDebugMode) print('WaiterCubit.createOrder error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          isCreatingOrder: false,
          errorMessage: e.message ?? 'Xato yuz berdi',
        ));
      }
    } catch (e) {
      if (kDebugMode) print('WaiterCubit.createOrder error: $e');
      if (!isClosed) {
        emit(state.copyWith(isCreatingOrder: false, errorMessage: e.toString()));
      }
    }
  }
}
