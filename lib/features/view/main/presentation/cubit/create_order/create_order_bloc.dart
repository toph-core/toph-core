import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/create_order_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_cubit.dart';

part 'create_order_event.dart';
part 'create_order_state.dart';
part 'create_order_bloc.freezed.dart';

class CreateOrderBloc extends Bloc<CreateOrderEvent, CreateOrderState> {
  late final CreateOrderUsecase _createOrderUsecase;
  //
  CreateOrderBloc({required CreateOrderUsecase createOrderUsecase})
    : _createOrderUsecase = createOrderUsecase, 
      super(const CreateOrderState()) {
    on<_Started>(_started);
    on<_CreateOrder>(_createOrder);
  }

  void _createOrder(_CreateOrder event, emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final response = await _createOrderUsecase.call(
      CreateOrderRequestModel(
        tableId: state.tableId,
        comment: "Very good",
        guestCount: state.guestCount,
        foods: event.orders,
        status: OrderStatus.open,
        tableStatus: state.tableStatus
      ),
    );
    response.fold((l) {
      l.showErrorMsg();
      emit(state.copyWith(status: Status.ERROR, failure: l));
    }, (r) => emit(state.copyWith(status: Status.SUCCESS, success: r)));
  }

  void _started(_Started event, emit) =>
      emit(CreateOrderState(tableId: event.tableId ?? '',guestCount: event.guestCount,tableStatus: event.tableStatus));
}
