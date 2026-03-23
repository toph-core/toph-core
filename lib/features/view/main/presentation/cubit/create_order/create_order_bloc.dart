import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
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
  //
  CreateOrderBloc({
    required CreateOrderUsecase createOrderUsecase,
    required CreateTakeAwayOrderUsecase createTakeAwayOrderUsecase,
  }) : _createOrderUsecase = createOrderUsecase,
       _createTakeAwayOrderUsecase = createTakeAwayOrderUsecase,
       super(const CreateOrderState()) {
    on<_Started>(_started);
    on<_CreateOrder>(_createOrder);
  }

  void _createOrder(_CreateOrder event, emit) async {
    emit(state.copyWith(status: Status.LOADING));
    if (state.tableId.isEmpty) {
      final response = await _createTakeAwayOrderUsecase.call(
        CreateOrderRequestModel(
          orderType: "takeaway",
          // cashierId: "4e25f6c1-68c0-43bd-bcb2-a130bde2e9e1",
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
          Navigator.pushNamed(navigatorKey.currentContext!, AppRoutes.paymentScreen,arguments: {
            "order_id": r
          });
          emit(state.copyWith(status: Status.SUCCESS, success: true));
        },
      );
    } else {
      final response = await _createOrderUsecase.call(
        CreateOrderRequestModel(
          tableId: state.tableId,
          comment: "Very good",
          guestCount: state.guestCount,
          foods: event.orders,
          status: OrderStatus.open,
          tableStatus: state.tableStatus,
          // cashierId: "4e25f6c1-68c0-43bd-bcb2-a130bde2e9e1",
          orderType: "dine_in"
        ),
      );
      response.fold(
        (l) {
          l.showErrorMsg();
          emit(state.copyWith(status: Status.ERROR, failure: l));
        },
        (r) {
          emit(state.copyWith(status: Status.SUCCESS, success: r));
        },
      );
    }
  }

  void _started(_Started event, emit) => emit(
    CreateOrderState(
      tableId: event.tableId ?? '',
      guestCount: event.guestCount,
      tableStatus: event.tableStatus,
    ),
  );
}
