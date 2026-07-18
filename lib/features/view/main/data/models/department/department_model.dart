import 'package:freezed_annotation/freezed_annotation.dart';

part 'department_model.freezed.dart';
part 'department_model.g.dart';

@freezed
class DepartmentModel with _$DepartmentModel {
  const factory DepartmentModel({
    required String id,
    required String name,
    @JsonKey(name: 'name_i18n') String? nameI18n,
    @JsonKey(name: 'picture_url') String? pictureUrl,
    @JsonKey(name: 'color_code') String? colorCode,
    @JsonKey(name: 'storage_id') String? storageId,
  }) = _DepartmentModel;

  factory DepartmentModel.fromJson(Map<String, dynamic> json) =>
      _$DepartmentModelFromJson(json);
}
