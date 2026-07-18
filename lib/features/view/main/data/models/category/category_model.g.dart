// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CategoryModelImpl _$$CategoryModelImplFromJson(Map<String, dynamic> json) =>
    _$CategoryModelImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      nameI18n: json['name_i18n'] as String?,
      pictureUrl: json['picture_url'] as String?,
      colorCode: json['color_code'] as String?,
      departmentId: json['department_id'] as String?,
    );

Map<String, dynamic> _$$CategoryModelImplToJson(_$CategoryModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'name_i18n': instance.nameI18n,
      'picture_url': instance.pictureUrl,
      'color_code': instance.colorCode,
      'department_id': instance.departmentId,
    };
