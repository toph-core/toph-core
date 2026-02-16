part of 'create_order_bloc.dart';

@freezed
class CreateOrderState with _$CreateOrderState {
  const factory CreateOrderState({
    @Default(Status.UNKNOWN) Status status,
    @Default('') String tableId,
    @Default(false) bool success,
    Failure? failure,
  }) = _CreateOrderState;
}
