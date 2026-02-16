import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';

import '../../../presentation/cubit/detail/detail_cubit.dart';

part 'create_order_request_model.freezed.dart';

@freezed
class CreateOrderRequestModel with _$CreateOrderRequestModel {
  const factory CreateOrderRequestModel({
    @Default('') String cashierId,
    @Default('') String comment,
    @Default(0) int guestCount,
    @Default([]) List<OrderItem> foods,
    @Default(OrderStatus.NONE) OrderStatus status,
    @Default('') String tableId,
  }) = _CreateOrderRequestModel;

  const CreateOrderRequestModel._();

  Map<String, dynamic> request() => {
    "cashier_id": cashierId,
    "comment": comment,
    "guest_count": guestCount,
    "items": List.generate(foods.length, (index) => {
        "comment": "zo'r",
        "good_id": foods[index].goods.id,
        "quantity": foods[index].quantity,
      },),
    "status": status.name.toLowerCase(),
    "table_id": tableId,
  };
}
