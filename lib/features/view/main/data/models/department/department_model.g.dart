// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'department_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DepartmentModelImpl _$$DepartmentModelImplFromJson(
        Map<String, dynamic> json) =>
    _$DepartmentModelImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      nameI18n: json['name_i18n'] as String?,
      pictureUrl: json['picture_url'] as String?,
      colorCode: json['color_code'] as String?,
      storageId: json['storage_id'] as String?,
    );

Map<String, dynamic> _$$DepartmentModelImplToJson(
        _$DepartmentModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'name_i18n': instance.nameI18n,
      'picture_url': instance.pictureUrl,
      'color_code': instance.colorCode,
      'storage_id': instance.storageId,
    };
