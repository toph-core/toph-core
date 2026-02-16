part of 'create_order_bloc.dart';

@freezed
class CreateOrderEvent with _$CreateOrderEvent {
  const factory CreateOrderEvent.started({required String tableId}) = _Started;
  const factory CreateOrderEvent.createOrder({required List<OrderItem> orders}) = _CreateOrder;

}