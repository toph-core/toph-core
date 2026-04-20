import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_take_away_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

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

  // Active order ID for busy tables — set via bindActiveOrder()
  String? _activeOrderId;

  void bindActiveOrder(String orderId) => _activeOrderId = orderId;

  CreateOrderBloc({
    required CreateOrderUsecase createOrderUsecase,
    required CreateTakeAwayOrderUsecase createTakeAwayOrderUsecase,
    required ConnectivityCubit connectivity,
    required OfflineQueueService queue,
    required LanHubService lanHub,
    required DioClient client,
  })  : _createOrderUsecase = createOrderUsecase,
        _createTakeAwayOrderUsecase = createTakeAwayOrderUsecase,
        _connectivity = connectivity,
        _queue = queue,
        _lanHub = lanHub,
        _client = client,
        super(const CreateOrderState()) {
    on<_Started>(_started);
    on<_CreateOrder>(_createOrder);
  }

  void _createOrder(_CreateOrder event, emit) async {
    emit(state.copyWith(status: Status.LOADING));

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

    // Busy table: add items to existing order (POST /api/v1/order-items)
    if (state.tableStatus == TableStatus.busy && _activeOrderId != null) {
      try {
        await _client.post(
          ListAPI.orderItemsCreate,
          data: {
            'order_id': _activeOrderId,
            'items': event.orders
                .map((o) => {
                      'comment': '',
                      'good_id': o.goods.id,
                      'quantity': o.quantity,
                    })
                .toList(),
          },
        );
        _lanHub.tableStatusChanged(state.tableId, TableStatus.busy.name);
        emit(state.copyWith(status: Status.SUCCESS, success: true));
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          await _handleOfflineOrder(event.orders, emit);
          return;
        }
        showErrorMessage(
          navigatorKey.currentContext!,
          e.message ?? 'Xato yuz berdi',
        );
        emit(state.copyWith(status: Status.ERROR));
      }
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
        l.showErrorMsg();
        emit(state.copyWith(status: Status.ERROR, failure: l));
      },
      (r) {
        _lanHub.tableStatusChanged(state.tableId, TableStatus.busy.name);
        emit(state.copyWith(status: Status.SUCCESS, success: r));
      },
    );
  }

  Future<void> _handleOfflineOrder(
    List<OrderItem> orders,
    Emitter<CreateOrderState> emit,
  ) async {
    final tableId = state.tableId;
    final createdAt = DateTime.now();

    if (state.tableStatus == TableStatus.busy) {
      // Mavjud orderga item qo'shish
      final payload = {
        'items': orders
            .map((o) => {
                  'comment': '',
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
