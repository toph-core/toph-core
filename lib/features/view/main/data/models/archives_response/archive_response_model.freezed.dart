// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'archive_response_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ArchiveResponseModel _$ArchiveResponseModelFromJson(Map<String, dynamic> json) {
  return _ArchiveResponseModel.fromJson(json);
}

/// @nodoc
mixin _$ArchiveResponseModel {
  @ArchiveEntityListConverter()
  List<ArchiveEntity> get archives => throw _privateConstructorUsedError;
  @PaginationResponseEntityConverter()
  PaginationResponseEntity get pagination => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ArchiveResponseModelCopyWith<ArchiveResponseModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ArchiveResponseModelCopyWith<$Res> {
  factory $ArchiveResponseModelCopyWith(ArchiveResponseModel value,
          $Res Function(ArchiveResponseModel) then) =
      _$ArchiveResponseModelCopyWithImpl<$Res, ArchiveResponseModel>;
  @useResult
  $Res call(
      {@ArchiveEntityListConverter() List<ArchiveEntity> archives,
      @PaginationResponseEntityConverter()
      PaginationResponseEntity pagination});
}

/// @nodoc
class _$ArchiveResponseModelCopyWithImpl<$Res,
        $Val extends ArchiveResponseModel>
    implements $ArchiveResponseModelCopyWith<$Res> {
  _$ArchiveResponseModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? archives = null,
    Object? pagination = null,
  }) {
    return _then(_value.copyWith(
      archives: null == archives
          ? _value.archives
          : archives // ignore: cast_nullable_to_non_nullable
              as List<ArchiveEntity>,
      pagination: null == pagination
          ? _value.pagination
          : pagination // ignore: cast_nullable_to_non_nullable
              as PaginationResponseEntity,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ArchiveResponseModelImplCopyWith<$Res>
    implements $ArchiveResponseModelCopyWith<$Res> {
  factory _$$ArchiveResponseModelImplCopyWith(_$ArchiveResponseModelImpl value,
          $Res Function(_$ArchiveResponseModelImpl) then) =
      __$$ArchiveResponseModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@ArchiveEntityListConverter() List<ArchiveEntity> archives,
      @PaginationResponseEntityConverter()
      PaginationResponseEntity pagination});
}

/// @nodoc
class __$$ArchiveResponseModelImplCopyWithImpl<$Res>
    extends _$ArchiveResponseModelCopyWithImpl<$Res, _$ArchiveResponseModelImpl>
    implements _$$ArchiveResponseModelImplCopyWith<$Res> {
  __$$ArchiveResponseModelImplCopyWithImpl(_$ArchiveResponseModelImpl _value,
      $Res Function(_$ArchiveResponseModelImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? archives = null,
    Object? pagination = null,
  }) {
    return _then(_$ArchiveResponseModelImpl(
      archives: null == archives
          ? _value._archives
          : archives // ignore: cast_nullable_to_non_nullable
              as List<ArchiveEntity>,
      pagination: null == pagination
          ? _value.pagination
          : pagination // ignore: cast_nullable_to_non_nullable
              as PaginationResponseEntity,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ArchiveResponseModelImpl extends _ArchiveResponseModel {
  const _$ArchiveResponseModelImpl(
      {@ArchiveEntityListConverter()
      required final List<ArchiveEntity> archives,
      @PaginationResponseEntityConverter() required this.pagination})
      : _archives = archives,
        super._();

  factory _$ArchiveResponseModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$ArchiveResponseModelImplFromJson(json);

  final List<ArchiveEntity> _archives;
  @override
  @ArchiveEntityListConverter()
  List<ArchiveEntity> get archives {
    if (_archives is EqualUnmodifiableListView) return _archives;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_archives);
  }

  @override
  @PaginationResponseEntityConverter()
  final PaginationResponseEntity pagination;

  @override
  String toString() {
    return 'ArchiveResponseModel(archives: $archives, pagination: $pagination)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ArchiveResponseModelImpl &&
            const DeepCollectionEquality().equals(other._archives, _archives) &&
            (identical(other.pagination, pagination) ||
                other.pagination == pagination));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, const DeepCollectionEquality().hash(_archives), pagination);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ArchiveResponseModelImplCopyWith<_$ArchiveResponseModelImpl>
      get copyWith =>
          __$$ArchiveResponseModelImplCopyWithImpl<_$ArchiveResponseModelImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ArchiveResponseModelImplToJson(
      this,
    );
  }
}

abstract class _ArchiveResponseModel extends ArchiveResponseModel {
  const factory _ArchiveResponseModel(
          {@ArchiveEntityListConverter()
          required final List<ArchiveEntity> archives,
          @PaginationResponseEntityConverter()
          required final PaginationResponseEntity pagination}) =
      _$ArchiveResponseModelImpl;
  const _ArchiveResponseModel._() : super._();

  factory _ArchiveResponseModel.fromJson(Map<String, dynamic> json) =
      _$ArchiveResponseModelImpl.fromJson;

  @override
  @ArchiveEntityListConverter()
  List<ArchiveEntity> get archives;
  @override
  @PaginationResponseEntityConverter()
  PaginationResponseEntity get pagination;
  @override
  @JsonKey(ignore: true)
  _$$ArchiveResponseModelImplCopyWith<_$ArchiveResponseModelImpl>
      get copyWith => throw _privateConstructorUsedError;
}
