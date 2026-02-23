// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'archive_detail_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ArchiveDetailModelImpl _$$ArchiveDetailModelImplFromJson(
        Map<String, dynamic> json) =>
    _$ArchiveDetailModelImpl(
      id: json['id'] as String? ?? '',
      bilNumber: (json['bill_no'] as num?)?.toInt() ?? 0,
      status: $enumDecodeNullable(_$OrderStatusEnumMap, json['bill_status']) ??
          OrderStatus.none,
      opened: json['opened_at'] == null
          ? null
          : DateTime.parse(json['opened_at'] as String),
      tableId: json['table_id'] as String? ?? '',
      tableNumber: (json['table_number'] as num?)?.toInt() ?? 0,
      goods: json['items'] == null
          ? const []
          : const OrderFoodEntityListConverter()
              .fromJson(json['items'] as List),
    );

Map<String, dynamic> _$$ArchiveDetailModelImplToJson(
        _$ArchiveDetailModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bill_no': instance.bilNumber,
      'bill_status': _$OrderStatusEnumMap[instance.status]!,
      'opened_at': instance.opened?.toIso8601String(),
      'table_id': instance.tableId,
      'table_number': instance.tableNumber,
      'items': const OrderFoodEntityListConverter().toJson(instance.goods),
    };

const _$OrderStatusEnumMap = {
  OrderStatus.opened: 'opened',
  OrderStatus.pending: 'pending',
  OrderStatus.none: 'none',
};
