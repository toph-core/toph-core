// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'payment_bloc.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PaymentEvent {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String tableId) started,
    required TResult Function() getDetail,
    required TResult Function(PaymentType paymentType) updatePaymentType,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String tableId)? started,
    TResult? Function()? getDetail,
    TResult? Function(PaymentType paymentType)? updatePaymentType,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String tableId)? started,
    TResult Function()? getDetail,
    TResult Function(PaymentType paymentType)? updatePaymentType,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetDetail value) getDetail,
    required TResult Function(_UpdatePaymentType value) updatePaymentType,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetDetail value)? getDetail,
    TResult? Function(_UpdatePaymentType value)? updatePaymentType,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetDetail value)? getDetail,
    TResult Function(_UpdatePaymentType value)? updatePaymentType,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PaymentEventCopyWith<$Res> {
  factory $PaymentEventCopyWith(
          PaymentEvent value, $Res Function(PaymentEvent) then) =
      _$PaymentEventCopyWithImpl<$Res, PaymentEvent>;
}

/// @nodoc
class _$PaymentEventCopyWithImpl<$Res, $Val extends PaymentEvent>
    implements $PaymentEventCopyWith<$Res> {
  _$PaymentEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$StartedImplCopyWith<$Res> {
  factory _$$StartedImplCopyWith(
          _$StartedImpl value, $Res Function(_$StartedImpl) then) =
      __$$StartedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String tableId});
}

/// @nodoc
class __$$StartedImplCopyWithImpl<$Res>
    extends _$PaymentEventCopyWithImpl<$Res, _$StartedImpl>
    implements _$$StartedImplCopyWith<$Res> {
  __$$StartedImplCopyWithImpl(
      _$StartedImpl _value, $Res Function(_$StartedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tableId = null,
  }) {
    return _then(_$StartedImpl(
      tableId: null == tableId
          ? _value.tableId
          : tableId // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$StartedImpl implements _Started {
  const _$StartedImpl({required this.tableId});

  @override
  final String tableId;

  @override
  String toString() {
    return 'PaymentEvent.started(tableId: $tableId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StartedImpl &&
            (identical(other.tableId, tableId) || other.tableId == tableId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, tableId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$StartedImplCopyWith<_$StartedImpl> get copyWith =>
      __$$StartedImplCopyWithImpl<_$StartedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String tableId) started,
    required TResult Function() getDetail,
    required TResult Function(PaymentType paymentType) updatePaymentType,
  }) {
    return started(tableId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String tableId)? started,
    TResult? Function()? getDetail,
    TResult? Function(PaymentType paymentType)? updatePaymentType,
  }) {
    return started?.call(tableId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String tableId)? started,
    TResult Function()? getDetail,
    TResult Function(PaymentType paymentType)? updatePaymentType,
    required TResult orElse(),
  }) {
    if (started != null) {
      return started(tableId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetDetail value) getDetail,
    required TResult Function(_UpdatePaymentType value) updatePaymentType,
  }) {
    return started(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetDetail value)? getDetail,
    TResult? Function(_UpdatePaymentType value)? updatePaymentType,
  }) {
    return started?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetDetail value)? getDetail,
    TResult Function(_UpdatePaymentType value)? updatePaymentType,
    required TResult orElse(),
  }) {
    if (started != null) {
      return started(this);
    }
    return orElse();
  }
}

abstract class _Started implements PaymentEvent {
  const factory _Started({required final String tableId}) = _$StartedImpl;

  String get tableId;
  @JsonKey(ignore: true)
  _$$StartedImplCopyWith<_$StartedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$GetDetailImplCopyWith<$Res> {
  factory _$$GetDetailImplCopyWith(
          _$GetDetailImpl value, $Res Function(_$GetDetailImpl) then) =
      __$$GetDetailImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$GetDetailImplCopyWithImpl<$Res>
    extends _$PaymentEventCopyWithImpl<$Res, _$GetDetailImpl>
    implements _$$GetDetailImplCopyWith<$Res> {
  __$$GetDetailImplCopyWithImpl(
      _$GetDetailImpl _value, $Res Function(_$GetDetailImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$GetDetailImpl implements _GetDetail {
  const _$GetDetailImpl();

  @override
  String toString() {
    return 'PaymentEvent.getDetail()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$GetDetailImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String tableId) started,
    required TResult Function() getDetail,
    required TResult Function(PaymentType paymentType) updatePaymentType,
  }) {
    return getDetail();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String tableId)? started,
    TResult? Function()? getDetail,
    TResult? Function(PaymentType paymentType)? updatePaymentType,
  }) {
    return getDetail?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String tableId)? started,
    TResult Function()? getDetail,
    TResult Function(PaymentType paymentType)? updatePaymentType,
    required TResult orElse(),
  }) {
    if (getDetail != null) {
      return getDetail();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetDetail value) getDetail,
    required TResult Function(_UpdatePaymentType value) updatePaymentType,
  }) {
    return getDetail(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetDetail value)? getDetail,
    TResult? Function(_UpdatePaymentType value)? updatePaymentType,
  }) {
    return getDetail?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetDetail value)? getDetail,
    TResult Function(_UpdatePaymentType value)? updatePaymentType,
    required TResult orElse(),
  }) {
    if (getDetail != null) {
      return getDetail(this);
    }
    return orElse();
  }
}

abstract class _GetDetail implements PaymentEvent {
  const factory _GetDetail() = _$GetDetailImpl;
}

/// @nodoc
abstract class _$$UpdatePaymentTypeImplCopyWith<$Res> {
  factory _$$UpdatePaymentTypeImplCopyWith(_$UpdatePaymentTypeImpl value,
          $Res Function(_$UpdatePaymentTypeImpl) then) =
      __$$UpdatePaymentTypeImplCopyWithImpl<$Res>;
  @useResult
  $Res call({PaymentType paymentType});
}

/// @nodoc
class __$$UpdatePaymentTypeImplCopyWithImpl<$Res>
    extends _$PaymentEventCopyWithImpl<$Res, _$UpdatePaymentTypeImpl>
    implements _$$UpdatePaymentTypeImplCopyWith<$Res> {
  __$$UpdatePaymentTypeImplCopyWithImpl(_$UpdatePaymentTypeImpl _value,
      $Res Function(_$UpdatePaymentTypeImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? paymentType = null,
  }) {
    return _then(_$UpdatePaymentTypeImpl(
      paymentType: null == paymentType
          ? _value.paymentType
          : paymentType // ignore: cast_nullable_to_non_nullable
              as PaymentType,
    ));
  }
}

/// @nodoc

class _$UpdatePaymentTypeImpl implements _UpdatePaymentType {
  const _$UpdatePaymentTypeImpl({required this.paymentType});

  @override
  final PaymentType paymentType;

  @override
  String toString() {
    return 'PaymentEvent.updatePaymentType(paymentType: $paymentType)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdatePaymentTypeImpl &&
            (identical(other.paymentType, paymentType) ||
                other.paymentType == paymentType));
  }

  @override
  int get hashCode => Object.hash(runtimeType, paymentType);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdatePaymentTypeImplCopyWith<_$UpdatePaymentTypeImpl> get copyWith =>
      __$$UpdatePaymentTypeImplCopyWithImpl<_$UpdatePaymentTypeImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String tableId) started,
    required TResult Function() getDetail,
    required TResult Function(PaymentType paymentType) updatePaymentType,
  }) {
    return updatePaymentType(paymentType);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String tableId)? started,
    TResult? Function()? getDetail,
    TResult? Function(PaymentType paymentType)? updatePaymentType,
  }) {
    return updatePaymentType?.call(paymentType);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String tableId)? started,
    TResult Function()? getDetail,
    TResult Function(PaymentType paymentType)? updatePaymentType,
    required TResult orElse(),
  }) {
    if (updatePaymentType != null) {
      return updatePaymentType(paymentType);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetDetail value) getDetail,
    required TResult Function(_UpdatePaymentType value) updatePaymentType,
  }) {
    return updatePaymentType(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetDetail value)? getDetail,
    TResult? Function(_UpdatePaymentType value)? updatePaymentType,
  }) {
    return updatePaymentType?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetDetail value)? getDetail,
    TResult Function(_UpdatePaymentType value)? updatePaymentType,
    required TResult orElse(),
  }) {
    if (updatePaymentType != null) {
      return updatePaymentType(this);
    }
    return orElse();
  }
}

abstract class _UpdatePaymentType implements PaymentEvent {
  const factory _UpdatePaymentType({required final PaymentType paymentType}) =
      _$UpdatePaymentTypeImpl;

  PaymentType get paymentType;
  @JsonKey(ignore: true)
  _$$UpdatePaymentTypeImplCopyWith<_$UpdatePaymentTypeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PaymentState {
  Status get status => throw _privateConstructorUsedError;
  Status get detailStatus => throw _privateConstructorUsedError;
  ArchiveDetailEntity? get detail => throw _privateConstructorUsedError;
  String get tableId => throw _privateConstructorUsedError;
  TextEditingController? get textController =>
      throw _privateConstructorUsedError;
  PaymentType get paymentType => throw _privateConstructorUsedError;
  String get enterSum => throw _privateConstructorUsedError;
  Failure? get failure => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $PaymentStateCopyWith<PaymentState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PaymentStateCopyWith<$Res> {
  factory $PaymentStateCopyWith(
          PaymentState value, $Res Function(PaymentState) then) =
      _$PaymentStateCopyWithImpl<$Res, PaymentState>;
  @useResult
  $Res call(
      {Status status,
      Status detailStatus,
      ArchiveDetailEntity? detail,
      String tableId,
      TextEditingController? textController,
      PaymentType paymentType,
      String enterSum,
      Failure? failure});
}

/// @nodoc
class _$PaymentStateCopyWithImpl<$Res, $Val extends PaymentState>
    implements $PaymentStateCopyWith<$Res> {
  _$PaymentStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? detailStatus = null,
    Object? detail = freezed,
    Object? tableId = null,
    Object? textController = freezed,
    Object? paymentType = null,
    Object? enterSum = null,
    Object? failure = freezed,
  }) {
    return _then(_value.copyWith(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as Status,
      detailStatus: null == detailStatus
          ? _value.detailStatus
          : detailStatus // ignore: cast_nullable_to_non_nullable
              as Status,
      detail: freezed == detail
          ? _value.detail
          : detail // ignore: cast_nullable_to_non_nullable
              as ArchiveDetailEntity?,
      tableId: null == tableId
          ? _value.tableId
          : tableId // ignore: cast_nullable_to_non_nullable
              as String,
      textController: freezed == textController
          ? _value.textController
          : textController // ignore: cast_nullable_to_non_nullable
              as TextEditingController?,
      paymentType: null == paymentType
          ? _value.paymentType
          : paymentType // ignore: cast_nullable_to_non_nullable
              as PaymentType,
      enterSum: null == enterSum
          ? _value.enterSum
          : enterSum // ignore: cast_nullable_to_non_nullable
              as String,
      failure: freezed == failure
          ? _value.failure
          : failure // ignore: cast_nullable_to_non_nullable
              as Failure?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PaymentStateImplCopyWith<$Res>
    implements $PaymentStateCopyWith<$Res> {
  factory _$$PaymentStateImplCopyWith(
          _$PaymentStateImpl value, $Res Function(_$PaymentStateImpl) then) =
      __$$PaymentStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {Status status,
      Status detailStatus,
      ArchiveDetailEntity? detail,
      String tableId,
      TextEditingController? textController,
      PaymentType paymentType,
      String enterSum,
      Failure? failure});
}

/// @nodoc
class __$$PaymentStateImplCopyWithImpl<$Res>
    extends _$PaymentStateCopyWithImpl<$Res, _$PaymentStateImpl>
    implements _$$PaymentStateImplCopyWith<$Res> {
  __$$PaymentStateImplCopyWithImpl(
      _$PaymentStateImpl _value, $Res Function(_$PaymentStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? detailStatus = null,
    Object? detail = freezed,
    Object? tableId = null,
    Object? textController = freezed,
    Object? paymentType = null,
    Object? enterSum = null,
    Object? failure = freezed,
  }) {
    return _then(_$PaymentStateImpl(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as Status,
      detailStatus: null == detailStatus
          ? _value.detailStatus
          : detailStatus // ignore: cast_nullable_to_non_nullable
              as Status,
      detail: freezed == detail
          ? _value.detail
          : detail // ignore: cast_nullable_to_non_nullable
              as ArchiveDetailEntity?,
      tableId: null == tableId
          ? _value.tableId
          : tableId // ignore: cast_nullable_to_non_nullable
              as String,
      textController: freezed == textController
          ? _value.textController
          : textController // ignore: cast_nullable_to_non_nullable
              as TextEditingController?,
      paymentType: null == paymentType
          ? _value.paymentType
          : paymentType // ignore: cast_nullable_to_non_nullable
              as PaymentType,
      enterSum: null == enterSum
          ? _value.enterSum
          : enterSum // ignore: cast_nullable_to_non_nullable
              as String,
      failure: freezed == failure
          ? _value.failure
          : failure // ignore: cast_nullable_to_non_nullable
              as Failure?,
    ));
  }
}

/// @nodoc

class _$PaymentStateImpl implements _PaymentState {
  const _$PaymentStateImpl(
      {this.status = Status.UNKNOWN,
      this.detailStatus = Status.UNKNOWN,
      this.detail,
      this.tableId = '',
      this.textController,
      this.paymentType = PaymentType.cash,
      this.enterSum = '',
      this.failure});

  @override
  @JsonKey()
  final Status status;
  @override
  @JsonKey()
  final Status detailStatus;
  @override
  final ArchiveDetailEntity? detail;
  @override
  @JsonKey()
  final String tableId;
  @override
  final TextEditingController? textController;
  @override
  @JsonKey()
  final PaymentType paymentType;
  @override
  @JsonKey()
  final String enterSum;
  @override
  final Failure? failure;

  @override
  String toString() {
    return 'PaymentState(status: $status, detailStatus: $detailStatus, detail: $detail, tableId: $tableId, textController: $textController, paymentType: $paymentType, enterSum: $enterSum, failure: $failure)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PaymentStateImpl &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.detailStatus, detailStatus) ||
                other.detailStatus == detailStatus) &&
            (identical(other.detail, detail) || other.detail == detail) &&
            (identical(other.tableId, tableId) || other.tableId == tableId) &&
            (identical(other.textController, textController) ||
                other.textController == textController) &&
            (identical(other.paymentType, paymentType) ||
                other.paymentType == paymentType) &&
            (identical(other.enterSum, enterSum) ||
                other.enterSum == enterSum) &&
            (identical(other.failure, failure) || other.failure == failure));
  }

  @override
  int get hashCode => Object.hash(runtimeType, status, detailStatus, detail,
      tableId, textController, paymentType, enterSum, failure);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PaymentStateImplCopyWith<_$PaymentStateImpl> get copyWith =>
      __$$PaymentStateImplCopyWithImpl<_$PaymentStateImpl>(this, _$identity);
}

abstract class _PaymentState implements PaymentState {
  const factory _PaymentState(
      {final Status status,
      final Status detailStatus,
      final ArchiveDetailEntity? detail,
      final String tableId,
      final TextEditingController? textController,
      final PaymentType paymentType,
      final String enterSum,
      final Failure? failure}) = _$PaymentStateImpl;

  @override
  Status get status;
  @override
  Status get detailStatus;
  @override
  ArchiveDetailEntity? get detail;
  @override
  String get tableId;
  @override
  TextEditingController? get textController;
  @override
  PaymentType get paymentType;
  @override
  String get enterSum;
  @override
  Failure? get failure;
  @override
  @JsonKey(ignore: true)
  _$$PaymentStateImplCopyWith<_$PaymentStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
