// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'branch_shift_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

BranchShiftModel _$BranchShiftModelFromJson(Map<String, dynamic> json) {
  return _BranchShiftModel.fromJson(json);
}

/// @nodoc
mixin _$BranchShiftModel {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'branch_id')
  String get branchId => throw _privateConstructorUsedError;
  @JsonKey(name: 'opened_by')
  String? get openedBy => throw _privateConstructorUsedError;
  @JsonKey(name: 'closed_by')
  String? get closedBy => throw _privateConstructorUsedError;
  @JsonKey(name: 'opened_at', fromJson: _parseLocal)
  DateTime? get openedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'closed_at', fromJson: _parseLocal)
  DateTime? get closedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex)
  int get openingCash => throw _privateConstructorUsedError;
  @JsonKey(name: 'opening_card', fromJson: _parseIntFlex)
  int get openingCard => throw _privateConstructorUsedError;
  @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex)
  int get closingCash => throw _privateConstructorUsedError;
  @JsonKey(name: 'closing_card', fromJson: _parseIntFlex)
  int get closingCard => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at', fromJson: _parseLocal)
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at', fromJson: _parseLocal)
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BranchShiftModelCopyWith<BranchShiftModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BranchShiftModelCopyWith<$Res> {
  factory $BranchShiftModelCopyWith(
          BranchShiftModel value, $Res Function(BranchShiftModel) then) =
      _$BranchShiftModelCopyWithImpl<$Res, BranchShiftModel>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'branch_id') String branchId,
      @JsonKey(name: 'opened_by') String? openedBy,
      @JsonKey(name: 'closed_by') String? closedBy,
      @JsonKey(name: 'opened_at', fromJson: _parseLocal) DateTime? openedAt,
      @JsonKey(name: 'closed_at', fromJson: _parseLocal) DateTime? closedAt,
      @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex) int openingCash,
      @JsonKey(name: 'opening_card', fromJson: _parseIntFlex) int openingCard,
      @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex) int closingCash,
      @JsonKey(name: 'closing_card', fromJson: _parseIntFlex) int closingCard,
      String? notes,
      @JsonKey(name: 'created_at', fromJson: _parseLocal) DateTime? createdAt,
      @JsonKey(name: 'updated_at', fromJson: _parseLocal) DateTime? updatedAt});
}

/// @nodoc
class _$BranchShiftModelCopyWithImpl<$Res, $Val extends BranchShiftModel>
    implements $BranchShiftModelCopyWith<$Res> {
  _$BranchShiftModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? branchId = null,
    Object? openedBy = freezed,
    Object? closedBy = freezed,
    Object? openedAt = freezed,
    Object? closedAt = freezed,
    Object? openingCash = null,
    Object? openingCard = null,
    Object? closingCash = null,
    Object? closingCard = null,
    Object? notes = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      branchId: null == branchId
          ? _value.branchId
          : branchId // ignore: cast_nullable_to_non_nullable
              as String,
      openedBy: freezed == openedBy
          ? _value.openedBy
          : openedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      closedBy: freezed == closedBy
          ? _value.closedBy
          : closedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      openedAt: freezed == openedAt
          ? _value.openedAt
          : openedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      closedAt: freezed == closedAt
          ? _value.closedAt
          : closedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      openingCash: null == openingCash
          ? _value.openingCash
          : openingCash // ignore: cast_nullable_to_non_nullable
              as int,
      openingCard: null == openingCard
          ? _value.openingCard
          : openingCard // ignore: cast_nullable_to_non_nullable
              as int,
      closingCash: null == closingCash
          ? _value.closingCash
          : closingCash // ignore: cast_nullable_to_non_nullable
              as int,
      closingCard: null == closingCard
          ? _value.closingCard
          : closingCard // ignore: cast_nullable_to_non_nullable
              as int,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BranchShiftModelImplCopyWith<$Res>
    implements $BranchShiftModelCopyWith<$Res> {
  factory _$$BranchShiftModelImplCopyWith(_$BranchShiftModelImpl value,
          $Res Function(_$BranchShiftModelImpl) then) =
      __$$BranchShiftModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'branch_id') String branchId,
      @JsonKey(name: 'opened_by') String? openedBy,
      @JsonKey(name: 'closed_by') String? closedBy,
      @JsonKey(name: 'opened_at', fromJson: _parseLocal) DateTime? openedAt,
      @JsonKey(name: 'closed_at', fromJson: _parseLocal) DateTime? closedAt,
      @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex) int openingCash,
      @JsonKey(name: 'opening_card', fromJson: _parseIntFlex) int openingCard,
      @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex) int closingCash,
      @JsonKey(name: 'closing_card', fromJson: _parseIntFlex) int closingCard,
      String? notes,
      @JsonKey(name: 'created_at', fromJson: _parseLocal) DateTime? createdAt,
      @JsonKey(name: 'updated_at', fromJson: _parseLocal) DateTime? updatedAt});
}

/// @nodoc
class __$$BranchShiftModelImplCopyWithImpl<$Res>
    extends _$BranchShiftModelCopyWithImpl<$Res, _$BranchShiftModelImpl>
    implements _$$BranchShiftModelImplCopyWith<$Res> {
  __$$BranchShiftModelImplCopyWithImpl(_$BranchShiftModelImpl _value,
      $Res Function(_$BranchShiftModelImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? branchId = null,
    Object? openedBy = freezed,
    Object? closedBy = freezed,
    Object? openedAt = freezed,
    Object? closedAt = freezed,
    Object? openingCash = null,
    Object? openingCard = null,
    Object? closingCash = null,
    Object? closingCard = null,
    Object? notes = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_$BranchShiftModelImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      branchId: null == branchId
          ? _value.branchId
          : branchId // ignore: cast_nullable_to_non_nullable
              as String,
      openedBy: freezed == openedBy
          ? _value.openedBy
          : openedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      closedBy: freezed == closedBy
          ? _value.closedBy
          : closedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      openedAt: freezed == openedAt
          ? _value.openedAt
          : openedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      closedAt: freezed == closedAt
          ? _value.closedAt
          : closedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      openingCash: null == openingCash
          ? _value.openingCash
          : openingCash // ignore: cast_nullable_to_non_nullable
              as int,
      openingCard: null == openingCard
          ? _value.openingCard
          : openingCard // ignore: cast_nullable_to_non_nullable
              as int,
      closingCash: null == closingCash
          ? _value.closingCash
          : closingCash // ignore: cast_nullable_to_non_nullable
              as int,
      closingCard: null == closingCard
          ? _value.closingCard
          : closingCard // ignore: cast_nullable_to_non_nullable
              as int,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BranchShiftModelImpl extends _BranchShiftModel {
  const _$BranchShiftModelImpl(
      {this.id = '',
      @JsonKey(name: 'branch_id') this.branchId = '',
      @JsonKey(name: 'opened_by') this.openedBy,
      @JsonKey(name: 'closed_by') this.closedBy,
      @JsonKey(name: 'opened_at', fromJson: _parseLocal) this.openedAt,
      @JsonKey(name: 'closed_at', fromJson: _parseLocal) this.closedAt,
      @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex)
      this.openingCash = 0,
      @JsonKey(name: 'opening_card', fromJson: _parseIntFlex)
      this.openingCard = 0,
      @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex)
      this.closingCash = 0,
      @JsonKey(name: 'closing_card', fromJson: _parseIntFlex)
      this.closingCard = 0,
      this.notes,
      @JsonKey(name: 'created_at', fromJson: _parseLocal) this.createdAt,
      @JsonKey(name: 'updated_at', fromJson: _parseLocal) this.updatedAt})
      : super._();

  factory _$BranchShiftModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$BranchShiftModelImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  @JsonKey(name: 'branch_id')
  final String branchId;
  @override
  @JsonKey(name: 'opened_by')
  final String? openedBy;
  @override
  @JsonKey(name: 'closed_by')
  final String? closedBy;
  @override
  @JsonKey(name: 'opened_at', fromJson: _parseLocal)
  final DateTime? openedAt;
  @override
  @JsonKey(name: 'closed_at', fromJson: _parseLocal)
  final DateTime? closedAt;
  @override
  @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex)
  final int openingCash;
  @override
  @JsonKey(name: 'opening_card', fromJson: _parseIntFlex)
  final int openingCard;
  @override
  @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex)
  final int closingCash;
  @override
  @JsonKey(name: 'closing_card', fromJson: _parseIntFlex)
  final int closingCard;
  @override
  final String? notes;
  @override
  @JsonKey(name: 'created_at', fromJson: _parseLocal)
  final DateTime? createdAt;
  @override
  @JsonKey(name: 'updated_at', fromJson: _parseLocal)
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'BranchShiftModel(id: $id, branchId: $branchId, openedBy: $openedBy, closedBy: $closedBy, openedAt: $openedAt, closedAt: $closedAt, openingCash: $openingCash, openingCard: $openingCard, closingCash: $closingCash, closingCard: $closingCard, notes: $notes, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BranchShiftModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.branchId, branchId) ||
                other.branchId == branchId) &&
            (identical(other.openedBy, openedBy) ||
                other.openedBy == openedBy) &&
            (identical(other.closedBy, closedBy) ||
                other.closedBy == closedBy) &&
            (identical(other.openedAt, openedAt) ||
                other.openedAt == openedAt) &&
            (identical(other.closedAt, closedAt) ||
                other.closedAt == closedAt) &&
            (identical(other.openingCash, openingCash) ||
                other.openingCash == openingCash) &&
            (identical(other.openingCard, openingCard) ||
                other.openingCard == openingCard) &&
            (identical(other.closingCash, closingCash) ||
                other.closingCash == closingCash) &&
            (identical(other.closingCard, closingCard) ||
                other.closingCard == closingCard) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      branchId,
      openedBy,
      closedBy,
      openedAt,
      closedAt,
      openingCash,
      openingCard,
      closingCash,
      closingCard,
      notes,
      createdAt,
      updatedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BranchShiftModelImplCopyWith<_$BranchShiftModelImpl> get copyWith =>
      __$$BranchShiftModelImplCopyWithImpl<_$BranchShiftModelImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BranchShiftModelImplToJson(
      this,
    );
  }
}

abstract class _BranchShiftModel extends BranchShiftModel {
  const factory _BranchShiftModel(
      {final String id,
      @JsonKey(name: 'branch_id') final String branchId,
      @JsonKey(name: 'opened_by') final String? openedBy,
      @JsonKey(name: 'closed_by') final String? closedBy,
      @JsonKey(name: 'opened_at', fromJson: _parseLocal)
      final DateTime? openedAt,
      @JsonKey(name: 'closed_at', fromJson: _parseLocal)
      final DateTime? closedAt,
      @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex)
      final int openingCash,
      @JsonKey(name: 'opening_card', fromJson: _parseIntFlex)
      final int openingCard,
      @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex)
      final int closingCash,
      @JsonKey(name: 'closing_card', fromJson: _parseIntFlex)
      final int closingCard,
      final String? notes,
      @JsonKey(name: 'created_at', fromJson: _parseLocal)
      final DateTime? createdAt,
      @JsonKey(name: 'updated_at', fromJson: _parseLocal)
      final DateTime? updatedAt}) = _$BranchShiftModelImpl;
  const _BranchShiftModel._() : super._();

  factory _BranchShiftModel.fromJson(Map<String, dynamic> json) =
      _$BranchShiftModelImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'branch_id')
  String get branchId;
  @override
  @JsonKey(name: 'opened_by')
  String? get openedBy;
  @override
  @JsonKey(name: 'closed_by')
  String? get closedBy;
  @override
  @JsonKey(name: 'opened_at', fromJson: _parseLocal)
  DateTime? get openedAt;
  @override
  @JsonKey(name: 'closed_at', fromJson: _parseLocal)
  DateTime? get closedAt;
  @override
  @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex)
  int get openingCash;
  @override
  @JsonKey(name: 'opening_card', fromJson: _parseIntFlex)
  int get openingCard;
  @override
  @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex)
  int get closingCash;
  @override
  @JsonKey(name: 'closing_card', fromJson: _parseIntFlex)
  int get closingCard;
  @override
  String? get notes;
  @override
  @JsonKey(name: 'created_at', fromJson: _parseLocal)
  DateTime? get createdAt;
  @override
  @JsonKey(name: 'updated_at', fromJson: _parseLocal)
  DateTime? get updatedAt;
  @override
  @JsonKey(ignore: true)
  _$$BranchShiftModelImplCopyWith<_$BranchShiftModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
