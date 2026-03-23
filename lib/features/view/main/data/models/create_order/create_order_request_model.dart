import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';

import '../../../presentation/cubit/detail/detail_bloc.dart';

part 'create_order_request_model.freezed.dart';

@freezed
class CreateOrderRequestModel with _$CreateOrderRequestModel {
  const factory CreateOrderRequestModel({
    @Default('') String cashierId,
    @Default('') String comment,
    @Default(0) int guestCount,
    @Default([]) List<OrderItem> foods,
    @Default(OrderStatus.none) OrderStatus status,
    @Default('') String tableId,
    @Default(TableStatus.none) TableStatus tableStatus,
    @Default('') String orderType,
  }) = _CreateOrderRequestModel;

  const CreateOrderRequestModel._();

  Map<String, dynamic> request() => {
    // "cashier_id": cashierId,
    "comment": comment,
    "guest_count": guestCount,
    "items": List.generate(
      foods.length,
      (index) => {
        "comment": comment,
        "good_id": foods[index].goods.id,
        "quantity": foods[index].quantity,
      },
    ),
    "status": status.name.toLowerCase(),
    "order_type": orderType,
    "table_id": tableId,
  };

  Map<String, dynamic> createOrder() => {
    // "cashier_id": cashierId,
    "order_type": "takeaway",
    "items": List.generate(
      foods.length,
      (index) => {
        "comment": comment,
        "good_id": foods[index].goods.id,
        "quantity": foods[index].quantity,
      },
    ),
  };
}
