// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'archive_detail_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ArchiveDetailModel _$ArchiveDetailModelFromJson(Map<String, dynamic> json) {
  return _ArchiveDetailModel.fromJson(json);
}

/// @nodoc
mixin _$ArchiveDetailModel {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'bil_no')
  int get bilNumber => throw _privateConstructorUsedError;
  @JsonKey(name: "bill_status")
  OrderStatus get status => throw _privateConstructorUsedError;
  @JsonKey(name: "opened_at")
  DateTime? get opened => throw _privateConstructorUsedError;
  @JsonKey(name: 'table_id')
  String get tableId => throw _privateConstructorUsedError;
  @JsonKey(name: 'table_number')
  int get tableNumber => throw _privateConstructorUsedError;
  @JsonKey(name: "items")
  @OrderFoodEntityListConverter()
  List<OrderFoodEntity> get foods => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ArchiveDetailModelCopyWith<ArchiveDetailModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ArchiveDetailModelCopyWith<$Res> {
  factory $ArchiveDetailModelCopyWith(
          ArchiveDetailModel value, $Res Function(ArchiveDetailModel) then) =
      _$ArchiveDetailModelCopyWithImpl<$Res, ArchiveDetailModel>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'bil_no') int bilNumber,
      @JsonKey(name: "bill_status") OrderStatus status,
      @JsonKey(name: "opened_at") DateTime? opened,
      @JsonKey(name: 'table_id') String tableId,
      @JsonKey(name: 'table_number') int tableNumber,
      @JsonKey(name: "items")
      @OrderFoodEntityListConverter()
      List<OrderFoodEntity> foods});
}

/// @nodoc
class _$ArchiveDetailModelCopyWithImpl<$Res, $Val extends ArchiveDetailModel>
    implements $ArchiveDetailModelCopyWith<$Res> {
  _$ArchiveDetailModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? bilNumber = null,
    Object? status = null,
    Object? opened = freezed,
    Object? tableId = null,
    Object? tableNumber = null,
    Object? foods = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      bilNumber: null == bilNumber
          ? _value.bilNumber
          : bilNumber // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as OrderStatus,
      opened: freezed == opened
          ? _value.opened
          : opened // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      tableId: null == tableId
          ? _value.tableId
          : tableId // ignore: cast_nullable_to_non_nullable
              as String,
      tableNumber: null == tableNumber
          ? _value.tableNumber
          : tableNumber // ignore: cast_nullable_to_non_nullable
              as int,
      foods: null == foods
          ? _value.foods
          : foods // ignore: cast_nullable_to_non_nullable
              as List<OrderFoodEntity>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ArchiveDetailModelImplCopyWith<$Res>
    implements $ArchiveDetailModelCopyWith<$Res> {
  factory _$$ArchiveDetailModelImplCopyWith(_$ArchiveDetailModelImpl value,
          $Res Function(_$ArchiveDetailModelImpl) then) =
      __$$ArchiveDetailModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'bil_no') int bilNumber,
      @JsonKey(name: "bill_status") OrderStatus status,
      @JsonKey(name: "opened_at") DateTime? opened,
      @JsonKey(name: 'table_id') String tableId,
      @JsonKey(name: 'table_number') int tableNumber,
      @JsonKey(name: "items")
      @OrderFoodEntityListConverter()
      List<OrderFoodEntity> foods});
}

/// @nodoc
class __$$ArchiveDetailModelImplCopyWithImpl<$Res>
    extends _$ArchiveDetailModelCopyWithImpl<$Res, _$ArchiveDetailModelImpl>
    implements _$$ArchiveDetailModelImplCopyWith<$Res> {
  __$$ArchiveDetailModelImplCopyWithImpl(_$ArchiveDetailModelImpl _value,
      $Res Function(_$ArchiveDetailModelImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? bilNumber = null,
    Object? status = null,
    Object? opened = freezed,
    Object? tableId = null,
    Object? tableNumber = null,
    Object? foods = null,
  }) {
    return _then(_$ArchiveDetailModelImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      bilNumber: null == bilNumber
          ? _value.bilNumber
          : bilNumber // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as OrderStatus,
      opened: freezed == opened
          ? _value.opened
          : opened // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      tableId: null == tableId
          ? _value.tableId
          : tableId // ignore: cast_nullable_to_non_nullable
              as String,
      tableNumber: null == tableNumber
          ? _value.tableNumber
          : tableNumber // ignore: cast_nullable_to_non_nullable
              as int,
      foods: null == foods
          ? _value._foods
          : foods // ignore: cast_nullable_to_non_nullable
              as List<OrderFoodEntity>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ArchiveDetailModelImpl extends _ArchiveDetailModel {
  const _$ArchiveDetailModelImpl(
      {this.id = '',
      @JsonKey(name: 'bil_no') this.bilNumber = 0,
      @JsonKey(name: "bill_status") this.status = OrderStatus.NONE,
      @JsonKey(name: "opened_at") this.opened,
      @JsonKey(name: 'table_id') this.tableId = '',
      @JsonKey(name: 'table_number') this.tableNumber = 0,
      @JsonKey(name: "items")
      @OrderFoodEntityListConverter()
      final List<OrderFoodEntity> foods = const []})
      : _foods = foods,
        super._();

  factory _$ArchiveDetailModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$ArchiveDetailModelImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  @JsonKey(name: 'bil_no')
  final int bilNumber;
  @override
  @JsonKey(name: "bill_status")
  final OrderStatus status;
  @override
  @JsonKey(name: "opened_at")
  final DateTime? opened;
  @override
  @JsonKey(name: 'table_id')
  final String tableId;
  @override
  @JsonKey(name: 'table_number')
  final int tableNumber;
  final List<OrderFoodEntity> _foods;
  @override
  @JsonKey(name: "items")
  @OrderFoodEntityListConverter()
  List<OrderFoodEntity> get foods {
    if (_foods is EqualUnmodifiableListView) return _foods;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_foods);
  }

  @override
  String toString() {
    return 'ArchiveDetailModel(id: $id, bilNumber: $bilNumber, status: $status, opened: $opened, tableId: $tableId, tableNumber: $tableNumber, foods: $foods)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ArchiveDetailModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.bilNumber, bilNumber) ||
                other.bilNumber == bilNumber) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.opened, opened) || other.opened == opened) &&
            (identical(other.tableId, tableId) || other.tableId == tableId) &&
            (identical(other.tableNumber, tableNumber) ||
                other.tableNumber == tableNumber) &&
            const DeepCollectionEquality().equals(other._foods, _foods));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, bilNumber, status, opened,
      tableId, tableNumber, const DeepCollectionEquality().hash(_foods));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ArchiveDetailModelImplCopyWith<_$ArchiveDetailModelImpl> get copyWith =>
      __$$ArchiveDetailModelImplCopyWithImpl<_$ArchiveDetailModelImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ArchiveDetailModelImplToJson(
      this,
    );
  }
}

abstract class _ArchiveDetailModel extends ArchiveDetailModel {
  const factory _ArchiveDetailModel(
      {final String id,
      @JsonKey(name: 'bil_no') final int bilNumber,
      @JsonKey(name: "bill_status") final OrderStatus status,
      @JsonKey(name: "opened_at") final DateTime? opened,
      @JsonKey(name: 'table_id') final String tableId,
      @JsonKey(name: 'table_number') final int tableNumber,
      @JsonKey(name: "items")
      @OrderFoodEntityListConverter()
      final List<OrderFoodEntity> foods}) = _$ArchiveDetailModelImpl;
  const _ArchiveDetailModel._() : super._();

  factory _ArchiveDetailModel.fromJson(Map<String, dynamic> json) =
      _$ArchiveDetailModelImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'bil_no')
  int get bilNumber;
  @override
  @JsonKey(name: "bill_status")
  OrderStatus get status;
  @override
  @JsonKey(name: "opened_at")
  DateTime? get opened;
  @override
  @JsonKey(name: 'table_id')
  String get tableId;
  @override
  @JsonKey(name: 'table_number')
  int get tableNumber;
  @override
  @JsonKey(name: "items")
  @OrderFoodEntityListConverter()
  List<OrderFoodEntity> get foods;
  @override
  @JsonKey(ignore: true)
  _$$ArchiveDetailModelImplCopyWith<_$ArchiveDetailModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
