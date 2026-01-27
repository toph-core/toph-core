// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_usecase.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$LoginRequestStateImpl _$$LoginRequestStateImplFromJson(
        Map<String, dynamic> json) =>
    _$LoginRequestStateImpl(
      password: json['password'] as String,
      phoneNumber: json['phone_number'] as String,
    );

Map<String, dynamic> _$$LoginRequestStateImplToJson(
        _$LoginRequestStateImpl instance) =>
    <String, dynamic>{
      'password': instance.password,
      'phone_number': instance.phoneNumber,
    };
