import 'package:freezed_annotation/freezed_annotation.dart';

part 'goods_model.freezed.dart';
part 'goods_model.g.dart';

@freezed
class GoodsModel with _$GoodsModel {
  const factory GoodsModel({
    @JsonKey(name: 'category_id') required String categoryId,
    @JsonKey(name: 'color_code') String? colorCode,
    @JsonKey(name: 'cook_time') required int cookTime,
    @JsonKey(name: 'cost_price') required String costPrice,
    @JsonKey(name: 'department_id') required String departmentId,
    required String description,
    @JsonKey(name: 'description_i18n') String? descriptionI18n,
    required String id,
    required String name,
    @JsonKey(name: 'name_i18n') String? nameI18n,
    @JsonKey(name: 'picture_url') String? pictureUrl,
    required String price,
    required String profit,
    @JsonKey(name: 'profit_margin') required String profitMargin,
  }) = _GoodsModel;

  factory GoodsModel.fromJson(Map<String, dynamic> json) =>
      _$GoodsModelFromJson(json);
}
