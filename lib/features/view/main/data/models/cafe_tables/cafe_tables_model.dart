import 'package:freezed_annotation/freezed_annotation.dart';

part 'cafe_tables_model.freezed.dart';
part 'cafe_tables_model.g.dart';

enum TableStatus { free, busy, away, none }

enum TableShape { rectangle, circle, square }

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
    @JsonKey(name: 'shape', unknownEnumValue: TableShape.rectangle)
    @Default(TableShape.rectangle)
    TableShape shape,
    @JsonKey(name: 'table_type') String? tableType,
    @JsonKey(name: 'price_per_hour', fromJson: pricePerHourFromJson)
    double? pricePerHour,
  }) = _CafeTableModel;

  factory CafeTableModel.fromJson(Map<String, dynamic> json) =>
      _$CafeTableModelFromJson(json);
}

/// `price_per_hour` reaches this model in two shapes, and both are load-bearing.
///
/// The API returns it as a JSON number. A *replicated* row has been through
/// `PayloadNormalizer`, which renders that number as a canonical string before
/// it reaches the replica DB (`price_per_hour` is one of `cafe_tables`'
/// `numericKeys`) — so from disk it arrives as `"50000"`. A row this terminal
/// created itself is the queued outbox request body, stored verbatim and never
/// normalized, so it is still the raw number.
///
/// Parsing both is what keeps a just-created table on the floor plan: a type
/// error here does not surface, it makes `decodeRows` skip the row silently.
double? pricePerHourFromJson(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return double.tryParse(text);
}
