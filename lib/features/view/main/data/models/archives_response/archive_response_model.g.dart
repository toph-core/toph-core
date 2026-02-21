// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'archive_response_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ArchiveResponseModelImpl _$$ArchiveResponseModelImplFromJson(
        Map<String, dynamic> json) =>
    _$ArchiveResponseModelImpl(
      archives:
          const ArchiveEntityListConverter().fromJson(json['archives'] as List),
      pagination: const PaginationResponseEntityConverter()
          .fromJson(json['pagination'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$ArchiveResponseModelImplToJson(
        _$ArchiveResponseModelImpl instance) =>
    <String, dynamic>{
      'archives': const ArchiveEntityListConverter().toJson(instance.archives),
      'pagination':
          const PaginationResponseEntityConverter().toJson(instance.pagination),
    };
