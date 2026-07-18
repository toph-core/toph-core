import 'package:freezed_annotation/freezed_annotation.dart';

part 'category_model.freezed.dart';
part 'category_model.g.dart';

@freezed
class CategoryModel with _$CategoryModel {
  const factory CategoryModel({
    required String id,
    required String name,
    @JsonKey(name: 'name_i18n') String? nameI18n,
    @JsonKey(name: 'picture_url') String? pictureUrl,
    @JsonKey(name: 'color_code') String? colorCode,
    @JsonKey(name: 'department_id') String? departmentId,
  }) = _CategoryModel;

  factory CategoryModel.fromJson(Map<String, dynamic> json) =>
      _$CategoryModelFromJson(json);
}
