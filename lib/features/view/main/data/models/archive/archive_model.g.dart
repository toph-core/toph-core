// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'archive_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ArchiveModelImpl _$$ArchiveModelImplFromJson(Map<String, dynamic> json) =>
    _$ArchiveModelImpl(
      id: json['id'] as String? ?? '',
      bilNumber: (json['bil_no'] as num?)?.toInt() ?? 0,
      status: $enumDecodeNullable(_$OrderStatusEnumMap, json['bill_status']) ??
          OrderStatus.NONE,
      opened: json['opened_at'] == null
          ? null
          : DateTime.parse(json['opened_at'] as String),
      tableNumber: (json['table_number'] as num?)?.toInt() ?? 0,
      totalPrice: (json['grand_total'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$ArchiveModelImplToJson(_$ArchiveModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bil_no': instance.bilNumber,
      'bill_status': _$OrderStatusEnumMap[instance.status]!,
      'opened_at': instance.opened?.toIso8601String(),
      'table_number': instance.tableNumber,
      'grand_total': instance.totalPrice,
    };

const _$OrderStatusEnumMap = {
  OrderStatus.OPEN: 'OPEN',
  OrderStatus.PENDING: 'PENDING',
  OrderStatus.NONE: 'NONE',
};
