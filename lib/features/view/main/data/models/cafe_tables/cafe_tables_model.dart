import 'package:freezed_annotation/freezed_annotation.dart';

part 'cafe_tables_model.freezed.dart';
part 'cafe_tables_model.g.dart';

enum TableStatus { free, busy, away, none }

@freezed
class CafeTableModel with _$CafeTableModel {
  const factory CafeTableModel({
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
  }) = _CafeTableModel;

  factory CafeTableModel.fromJson(Map<String, dynamic> json) =>
      _$CafeTableModelFromJson(json);
}
