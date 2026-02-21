// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_food_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OrderFoodModelImpl _$$OrderFoodModelImplFromJson(Map<String, dynamic> json) =>
    _$OrderFoodModelImpl(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
    );

Map<String, dynamic> _$$OrderFoodModelImplToJson(
        _$OrderFoodModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'quantity': instance.quantity,
      'price': instance.price,
      'comment': instance.comment,
    };
