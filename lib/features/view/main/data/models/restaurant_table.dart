import 'package:freezed_annotation/freezed_annotation.dart';

part 'restaurant_table.freezed.dart';
part 'restaurant_table.g.dart';

enum TableStatus { free, busy }

@freezed
class RestaurantTable with _$RestaurantTable {
  const factory RestaurantTable({
    required String id,
    @JsonKey(name: 'hall_id') required String hallId,
    required int number,
    @JsonKey(name: 'pos_x') required double posX,
    @JsonKey(name: 'pos_y') required double posY,
    required double width,
    required double height,
    required double rotation,
    required int capacity,
    @Default(TableStatus.free) TableStatus status,
  }) = _RestaurantTable;

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      _$RestaurantTableFromJson(json);
}
