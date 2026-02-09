// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cafe_tables_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CafeTableModelImpl _$$CafeTableModelImplFromJson(Map<String, dynamic> json) =>
    _$CafeTableModelImpl(
      id: json['id'] as String,
      hallId: json['hall_id'] as String,
      number: (json['number'] as num).toInt(),
      posX: (json['pos_x'] as num).toDouble(),
      posY: (json['pos_y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      capacity: (json['capacity'] as num).toInt(),
      status: $enumDecodeNullable(_$TableStatusEnumMap, json['status']) ??
          TableStatus.free,
    );

Map<String, dynamic> _$$CafeTableModelImplToJson(
        _$CafeTableModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'hall_id': instance.hallId,
      'number': instance.number,
      'pos_x': instance.posX,
      'pos_y': instance.posY,
      'width': instance.width,
      'height': instance.height,
      'rotation': instance.rotation,
      'capacity': instance.capacity,
      'status': _$TableStatusEnumMap[instance.status]!,
    };

const _$TableStatusEnumMap = {
  TableStatus.free: 'free',
  TableStatus.busy: 'busy',
};
