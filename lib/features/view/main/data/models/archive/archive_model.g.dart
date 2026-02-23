// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'archive_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ArchiveModelImpl _$$ArchiveModelImplFromJson(Map<String, dynamic> json) =>
    _$ArchiveModelImpl(
      id: json['id'] as String? ?? '',
      bilNumber: json['bill_no'] == null ? 0 : parseInt(json['bill_no']),
      status: $enumDecodeNullable(_$OrderStatusEnumMap, json['bill_status']) ??
          OrderStatus.none,
      opened: json['opened_at'] == null
          ? null
          : DateTime.parse(json['opened_at'] as String),
      tableNumber:
          json['table_number'] == null ? 0 : parseInt(json['table_number']),
      totalPrice:
          json['grand_total'] == null ? 0 : parseInt(json['grand_total']),
      goodsTotal: json['food_total'] == null ? 0 : parseInt(json['food_total']),
      serviceAmount:
          json['service_amount'] == null ? 0 : parseInt(json['service_amount']),
      goodsQuantity: (json['quantity'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$ArchiveModelImplToJson(_$ArchiveModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bill_no': instance.bilNumber,
      'bill_status': _$OrderStatusEnumMap[instance.status]!,
      'opened_at': instance.opened?.toIso8601String(),
      'table_number': instance.tableNumber,
      'grand_total': instance.totalPrice,
      'food_total': instance.goodsTotal,
      'service_amount': instance.serviceAmount,
      'quantity': instance.goodsQuantity,
    };

const _$OrderStatusEnumMap = {
  OrderStatus.opened: 'opened',
  OrderStatus.pending: 'pending',
  OrderStatus.none: 'none',
};
