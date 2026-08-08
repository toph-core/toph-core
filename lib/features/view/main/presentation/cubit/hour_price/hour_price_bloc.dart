import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hour_price/hour_price_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/hour_price_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';

part 'hour_price_event.dart';
part 'hour_price_state.dart';
part 'hour_price_bloc.freezed.dart';

/// CLIENT_FACING_OFFLINE_PLAN.md §6: previously a direct, uncached network
/// fetch (`GET /orders/{id}/hour-price`). The local timer record (plan §2's
/// new box) already carries everything this bloc's one consumer needs —
/// price-per-hour and the locally-computed amount due — so this reads that
/// instead of the wire. The `orderId` the started event carries has always
/// really been a *table* id at the one historical call shape (the old
/// datasource resolved it via `getOrderIdWithTableId` first), so both keys
/// are tried.
class HourPriceBloc extends Bloc<HourPriceEvent, HourPriceState> {
  final TableTimerLocalRepository _timerRepository;

  HourPriceBloc({required TableTimerLocalRepository timerRepository})
    : _timerRepository = timerRepository,
      super(const HourPriceState()) {
    on<_Started>(_started);
    on<_GetPrice>(_getPrice);
  }

  void _started(_Started event, emit) {
    emit(HourPriceState(orderId: event.orderId));
    add(const _GetPrice());
  }

  void _getPrice(_GetPrice event, emit) async {
    final key = state.orderId;
    if (key == null) return;
    emit(state.copyWith(status: Status.LOADING));
    var timer =
        (await _timerRepository.getTimer(key)).fold((_) => null, (r) => r);
    timer ??= await _timerRepository.watchTimerForTable(key).first;
    if (timer == null) {
      emit(state.copyWith(status: Status.ERROR));
      return;
    }
    final HourPriceResponseEntity price = HourPriceResponseModel(
      tableId: (timer.currentTableId?.isNotEmpty ?? false)
          ? timer.currentTableId!
          : timer.tableId,
      perHour: double.tryParse(timer.pricePerHour ?? '') ?? 0,
      totalPrice:
          double.tryParse(timer.currentAmount ?? timer.finalAmount ?? '') ?? 0,
    );
    emit(state.copyWith(status: Status.SUCCESS, price: price));
  }
}
