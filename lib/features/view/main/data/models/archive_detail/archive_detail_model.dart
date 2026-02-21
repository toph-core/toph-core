import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_food/order_food_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';

part 'archive_detail_model.freezed.dart';
part 'archive_detail_model.g.dart';

@freezed
class ArchiveDetailModel
    with _$ArchiveDetailModel
    implements ArchiveDetailEntity {
  const ArchiveDetailModel._();

  const factory ArchiveDetailModel({
    @Default('') String id,
    @JsonKey(name: 'bil_no') @Default(0) int bilNumber,
    @JsonKey(name: "bill_status") @Default(OrderStatus.NONE) OrderStatus status,
    @JsonKey(name: "opened_at") DateTime? opened,
    @JsonKey(name: 'table_id') @Default('') String tableId,
    @JsonKey(name: 'table_number') @Default(0) int tableNumber,
    @JsonKey(name: "items") @OrderFoodEntityListConverter() @Default([]) List<OrderFoodEntity> foods,
  }) = _ArchiveDetailModel;

  factory ArchiveDetailModel.fromJson(Map<String, dynamic> json) =>
      _$ArchiveDetailModelFromJson(json);

}
