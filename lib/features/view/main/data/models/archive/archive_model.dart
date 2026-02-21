import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';

part 'archive_model.freezed.dart';
part 'archive_model.g.dart';

@freezed
class ArchiveModel with _$ArchiveModel implements ArchiveEntity {
  const ArchiveModel._();

  const factory ArchiveModel({
    @Default('') String id,
    @JsonKey(name: 'bil_no') @Default(0) int bilNumber,
    @JsonKey(name: "bill_status") @Default(OrderStatus.NONE) OrderStatus status,
    @JsonKey(name: "opened_at") DateTime? opened,
    @JsonKey(name: 'table_number') @Default(0) int tableNumber,
    @JsonKey(name: 'grand_total') @Default(0) int totalPrice,
  }) = _ArchiveModel;

  factory ArchiveModel.fromJson(Map<String, dynamic> json) =>
      _$ArchiveModelFromJson(json);

}

class ArchiveEntityListConverter
    implements JsonConverter<List<ArchiveEntity>, List<dynamic>> {
  const ArchiveEntityListConverter();

  @override
  List<ArchiveEntity> fromJson(List<dynamic> json) {
    return json
        .whereType<Map>()
        .map((item) => ArchiveModel.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  List<dynamic> toJson(List<ArchiveEntity> object) {
    return object
        .map(
          (item) =>
              item is ArchiveModel
                  ? item.toJson()
                  : {
                    'id': item.id,
                    'bil_number': item.bilNumber,
                    'status': item.status.name.toLowerCase(),
                    'opened': item.opened?.toIso8601String(),
                    'table_number': item.tableNumber,
                    'total_price': item.totalPrice,
                  },
        )
        .toList();
  }
}
