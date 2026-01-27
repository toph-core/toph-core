// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'login_usecase.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

LoginRequest _$LoginRequestFromJson(Map<String, dynamic> json) {
  return _LoginRequestState.fromJson(json);
}

/// @nodoc
mixin _$LoginRequest {
  String get password => throw _privateConstructorUsedError;
  @JsonKey(name: 'phone_number')
  String get phoneNumber => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $LoginRequestCopyWith<LoginRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LoginRequestCopyWith<$Res> {
  factory $LoginRequestCopyWith(
          LoginRequest value, $Res Function(LoginRequest) then) =
      _$LoginRequestCopyWithImpl<$Res, LoginRequest>;
  @useResult
  $Res call(
      {String password, @JsonKey(name: 'phone_number') String phoneNumber});
}

/// @nodoc
class _$LoginRequestCopyWithImpl<$Res, $Val extends LoginRequest>
    implements $LoginRequestCopyWith<$Res> {
  _$LoginRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? password = null,
    Object? phoneNumber = null,
  }) {
    return _then(_value.copyWith(
      password: null == password
          ? _value.password
          : password // ignore: cast_nullable_to_non_nullable
              as String,
      phoneNumber: null == phoneNumber
          ? _value.phoneNumber
          : phoneNumber // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$LoginRequestStateImplCopyWith<$Res>
    implements $LoginRequestCopyWith<$Res> {
  factory _$$LoginRequestStateImplCopyWith(_$LoginRequestStateImpl value,
          $Res Function(_$LoginRequestStateImpl) then) =
      __$$LoginRequestStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String password, @JsonKey(name: 'phone_number') String phoneNumber});
}

/// @nodoc
class __$$LoginRequestStateImplCopyWithImpl<$Res>
    extends _$LoginRequestCopyWithImpl<$Res, _$LoginRequestStateImpl>
    implements _$$LoginRequestStateImplCopyWith<$Res> {
  __$$LoginRequestStateImplCopyWithImpl(_$LoginRequestStateImpl _value,
      $Res Function(_$LoginRequestStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? password = null,
    Object? phoneNumber = null,
  }) {
    return _then(_$LoginRequestStateImpl(
      password: null == password
          ? _value.password
          : password // ignore: cast_nullable_to_non_nullable
              as String,
      phoneNumber: null == phoneNumber
          ? _value.phoneNumber
          : phoneNumber // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$LoginRequestStateImpl implements _LoginRequestState {
  const _$LoginRequestStateImpl(
      {required this.password,
      @JsonKey(name: 'phone_number') required this.phoneNumber});

  factory _$LoginRequestStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$LoginRequestStateImplFromJson(json);

  @override
  final String password;
  @override
  @JsonKey(name: 'phone_number')
  final String phoneNumber;

  @override
  String toString() {
    return 'LoginRequest(password: $password, phoneNumber: $phoneNumber)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LoginRequestStateImpl &&
            (identical(other.password, password) ||
                other.password == password) &&
            (identical(other.phoneNumber, phoneNumber) ||
                other.phoneNumber == phoneNumber));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, password, phoneNumber);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LoginRequestStateImplCopyWith<_$LoginRequestStateImpl> get copyWith =>
      __$$LoginRequestStateImplCopyWithImpl<_$LoginRequestStateImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LoginRequestStateImplToJson(
      this,
    );
  }
}

abstract class _LoginRequestState implements LoginRequest {
  const factory _LoginRequestState(
          {required final String password,
          @JsonKey(name: 'phone_number') required final String phoneNumber}) =
      _$LoginRequestStateImpl;

  factory _LoginRequestState.fromJson(Map<String, dynamic> json) =
      _$LoginRequestStateImpl.fromJson;

  @override
  String get password;
  @override
  @JsonKey(name: 'phone_number')
  String get phoneNumber;
  @override
  @JsonKey(ignore: true)
  _$$LoginRequestStateImplCopyWith<_$LoginRequestStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
