// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'archives_bloc.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ArchivesEvent {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() started,
    required TResult Function() getArchived,
    required TResult Function(Status status) statusChanged,
    required TResult Function(ArchivesResponseEntity archives) archivesUpdated,
    required TResult Function(Failure? failure) failureChanged,
    required TResult Function(String value) searchChanged,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? started,
    TResult? Function()? getArchived,
    TResult? Function(Status status)? statusChanged,
    TResult? Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult? Function(Failure? failure)? failureChanged,
    TResult? Function(String value)? searchChanged,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? started,
    TResult Function()? getArchived,
    TResult Function(Status status)? statusChanged,
    TResult Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult Function(Failure? failure)? failureChanged,
    TResult Function(String value)? searchChanged,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetArchived value) getArchived,
    required TResult Function(_StatusChanged value) statusChanged,
    required TResult Function(_ArchivesUpdated value) archivesUpdated,
    required TResult Function(_FailureChanged value) failureChanged,
    required TResult Function(_SearchChanged value) searchChanged,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetArchived value)? getArchived,
    TResult? Function(_StatusChanged value)? statusChanged,
    TResult? Function(_ArchivesUpdated value)? archivesUpdated,
    TResult? Function(_FailureChanged value)? failureChanged,
    TResult? Function(_SearchChanged value)? searchChanged,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetArchived value)? getArchived,
    TResult Function(_StatusChanged value)? statusChanged,
    TResult Function(_ArchivesUpdated value)? archivesUpdated,
    TResult Function(_FailureChanged value)? failureChanged,
    TResult Function(_SearchChanged value)? searchChanged,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ArchivesEventCopyWith<$Res> {
  factory $ArchivesEventCopyWith(
          ArchivesEvent value, $Res Function(ArchivesEvent) then) =
      _$ArchivesEventCopyWithImpl<$Res, ArchivesEvent>;
}

/// @nodoc
class _$ArchivesEventCopyWithImpl<$Res, $Val extends ArchivesEvent>
    implements $ArchivesEventCopyWith<$Res> {
  _$ArchivesEventCopyWithImpl(this._value, this._then);

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
}

/// @nodoc
class __$$StartedImplCopyWithImpl<$Res>
    extends _$ArchivesEventCopyWithImpl<$Res, _$StartedImpl>
    implements _$$StartedImplCopyWith<$Res> {
  __$$StartedImplCopyWithImpl(
      _$StartedImpl _value, $Res Function(_$StartedImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$StartedImpl implements _Started {
  const _$StartedImpl();

  @override
  String toString() {
    return 'ArchivesEvent.started()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$StartedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() started,
    required TResult Function() getArchived,
    required TResult Function(Status status) statusChanged,
    required TResult Function(ArchivesResponseEntity archives) archivesUpdated,
    required TResult Function(Failure? failure) failureChanged,
    required TResult Function(String value) searchChanged,
  }) {
    return started();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? started,
    TResult? Function()? getArchived,
    TResult? Function(Status status)? statusChanged,
    TResult? Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult? Function(Failure? failure)? failureChanged,
    TResult? Function(String value)? searchChanged,
  }) {
    return started?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? started,
    TResult Function()? getArchived,
    TResult Function(Status status)? statusChanged,
    TResult Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult Function(Failure? failure)? failureChanged,
    TResult Function(String value)? searchChanged,
    required TResult orElse(),
  }) {
    if (started != null) {
      return started();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetArchived value) getArchived,
    required TResult Function(_StatusChanged value) statusChanged,
    required TResult Function(_ArchivesUpdated value) archivesUpdated,
    required TResult Function(_FailureChanged value) failureChanged,
    required TResult Function(_SearchChanged value) searchChanged,
  }) {
    return started(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetArchived value)? getArchived,
    TResult? Function(_StatusChanged value)? statusChanged,
    TResult? Function(_ArchivesUpdated value)? archivesUpdated,
    TResult? Function(_FailureChanged value)? failureChanged,
    TResult? Function(_SearchChanged value)? searchChanged,
  }) {
    return started?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetArchived value)? getArchived,
    TResult Function(_StatusChanged value)? statusChanged,
    TResult Function(_ArchivesUpdated value)? archivesUpdated,
    TResult Function(_FailureChanged value)? failureChanged,
    TResult Function(_SearchChanged value)? searchChanged,
    required TResult orElse(),
  }) {
    if (started != null) {
      return started(this);
    }
    return orElse();
  }
}

abstract class _Started implements ArchivesEvent {
  const factory _Started() = _$StartedImpl;
}

/// @nodoc
abstract class _$$GetArchivedImplCopyWith<$Res> {
  factory _$$GetArchivedImplCopyWith(
          _$GetArchivedImpl value, $Res Function(_$GetArchivedImpl) then) =
      __$$GetArchivedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$GetArchivedImplCopyWithImpl<$Res>
    extends _$ArchivesEventCopyWithImpl<$Res, _$GetArchivedImpl>
    implements _$$GetArchivedImplCopyWith<$Res> {
  __$$GetArchivedImplCopyWithImpl(
      _$GetArchivedImpl _value, $Res Function(_$GetArchivedImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$GetArchivedImpl implements _GetArchived {
  const _$GetArchivedImpl();

  @override
  String toString() {
    return 'ArchivesEvent.getArchived()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$GetArchivedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() started,
    required TResult Function() getArchived,
    required TResult Function(Status status) statusChanged,
    required TResult Function(ArchivesResponseEntity archives) archivesUpdated,
    required TResult Function(Failure? failure) failureChanged,
    required TResult Function(String value) searchChanged,
  }) {
    return getArchived();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? started,
    TResult? Function()? getArchived,
    TResult? Function(Status status)? statusChanged,
    TResult? Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult? Function(Failure? failure)? failureChanged,
    TResult? Function(String value)? searchChanged,
  }) {
    return getArchived?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? started,
    TResult Function()? getArchived,
    TResult Function(Status status)? statusChanged,
    TResult Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult Function(Failure? failure)? failureChanged,
    TResult Function(String value)? searchChanged,
    required TResult orElse(),
  }) {
    if (getArchived != null) {
      return getArchived();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetArchived value) getArchived,
    required TResult Function(_StatusChanged value) statusChanged,
    required TResult Function(_ArchivesUpdated value) archivesUpdated,
    required TResult Function(_FailureChanged value) failureChanged,
    required TResult Function(_SearchChanged value) searchChanged,
  }) {
    return getArchived(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetArchived value)? getArchived,
    TResult? Function(_StatusChanged value)? statusChanged,
    TResult? Function(_ArchivesUpdated value)? archivesUpdated,
    TResult? Function(_FailureChanged value)? failureChanged,
    TResult? Function(_SearchChanged value)? searchChanged,
  }) {
    return getArchived?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetArchived value)? getArchived,
    TResult Function(_StatusChanged value)? statusChanged,
    TResult Function(_ArchivesUpdated value)? archivesUpdated,
    TResult Function(_FailureChanged value)? failureChanged,
    TResult Function(_SearchChanged value)? searchChanged,
    required TResult orElse(),
  }) {
    if (getArchived != null) {
      return getArchived(this);
    }
    return orElse();
  }
}

abstract class _GetArchived implements ArchivesEvent {
  const factory _GetArchived() = _$GetArchivedImpl;
}

/// @nodoc
abstract class _$$StatusChangedImplCopyWith<$Res> {
  factory _$$StatusChangedImplCopyWith(
          _$StatusChangedImpl value, $Res Function(_$StatusChangedImpl) then) =
      __$$StatusChangedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Status status});
}

/// @nodoc
class __$$StatusChangedImplCopyWithImpl<$Res>
    extends _$ArchivesEventCopyWithImpl<$Res, _$StatusChangedImpl>
    implements _$$StatusChangedImplCopyWith<$Res> {
  __$$StatusChangedImplCopyWithImpl(
      _$StatusChangedImpl _value, $Res Function(_$StatusChangedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
  }) {
    return _then(_$StatusChangedImpl(
      null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as Status,
    ));
  }
}

/// @nodoc

class _$StatusChangedImpl implements _StatusChanged {
  const _$StatusChangedImpl(this.status);

  @override
  final Status status;

  @override
  String toString() {
    return 'ArchivesEvent.statusChanged(status: $status)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StatusChangedImpl &&
            (identical(other.status, status) || other.status == status));
  }

  @override
  int get hashCode => Object.hash(runtimeType, status);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$StatusChangedImplCopyWith<_$StatusChangedImpl> get copyWith =>
      __$$StatusChangedImplCopyWithImpl<_$StatusChangedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() started,
    required TResult Function() getArchived,
    required TResult Function(Status status) statusChanged,
    required TResult Function(ArchivesResponseEntity archives) archivesUpdated,
    required TResult Function(Failure? failure) failureChanged,
    required TResult Function(String value) searchChanged,
  }) {
    return statusChanged(status);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? started,
    TResult? Function()? getArchived,
    TResult? Function(Status status)? statusChanged,
    TResult? Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult? Function(Failure? failure)? failureChanged,
    TResult? Function(String value)? searchChanged,
  }) {
    return statusChanged?.call(status);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? started,
    TResult Function()? getArchived,
    TResult Function(Status status)? statusChanged,
    TResult Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult Function(Failure? failure)? failureChanged,
    TResult Function(String value)? searchChanged,
    required TResult orElse(),
  }) {
    if (statusChanged != null) {
      return statusChanged(status);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetArchived value) getArchived,
    required TResult Function(_StatusChanged value) statusChanged,
    required TResult Function(_ArchivesUpdated value) archivesUpdated,
    required TResult Function(_FailureChanged value) failureChanged,
    required TResult Function(_SearchChanged value) searchChanged,
  }) {
    return statusChanged(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetArchived value)? getArchived,
    TResult? Function(_StatusChanged value)? statusChanged,
    TResult? Function(_ArchivesUpdated value)? archivesUpdated,
    TResult? Function(_FailureChanged value)? failureChanged,
    TResult? Function(_SearchChanged value)? searchChanged,
  }) {
    return statusChanged?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetArchived value)? getArchived,
    TResult Function(_StatusChanged value)? statusChanged,
    TResult Function(_ArchivesUpdated value)? archivesUpdated,
    TResult Function(_FailureChanged value)? failureChanged,
    TResult Function(_SearchChanged value)? searchChanged,
    required TResult orElse(),
  }) {
    if (statusChanged != null) {
      return statusChanged(this);
    }
    return orElse();
  }
}

abstract class _StatusChanged implements ArchivesEvent {
  const factory _StatusChanged(final Status status) = _$StatusChangedImpl;

  Status get status;
  @JsonKey(ignore: true)
  _$$StatusChangedImplCopyWith<_$StatusChangedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ArchivesUpdatedImplCopyWith<$Res> {
  factory _$$ArchivesUpdatedImplCopyWith(_$ArchivesUpdatedImpl value,
          $Res Function(_$ArchivesUpdatedImpl) then) =
      __$$ArchivesUpdatedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({ArchivesResponseEntity archives});
}

/// @nodoc
class __$$ArchivesUpdatedImplCopyWithImpl<$Res>
    extends _$ArchivesEventCopyWithImpl<$Res, _$ArchivesUpdatedImpl>
    implements _$$ArchivesUpdatedImplCopyWith<$Res> {
  __$$ArchivesUpdatedImplCopyWithImpl(
      _$ArchivesUpdatedImpl _value, $Res Function(_$ArchivesUpdatedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? archives = null,
  }) {
    return _then(_$ArchivesUpdatedImpl(
      null == archives
          ? _value.archives
          : archives // ignore: cast_nullable_to_non_nullable
              as ArchivesResponseEntity,
    ));
  }
}

/// @nodoc

class _$ArchivesUpdatedImpl implements _ArchivesUpdated {
  const _$ArchivesUpdatedImpl(this.archives);

  @override
  final ArchivesResponseEntity archives;

  @override
  String toString() {
    return 'ArchivesEvent.archivesUpdated(archives: $archives)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ArchivesUpdatedImpl &&
            (identical(other.archives, archives) ||
                other.archives == archives));
  }

  @override
  int get hashCode => Object.hash(runtimeType, archives);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ArchivesUpdatedImplCopyWith<_$ArchivesUpdatedImpl> get copyWith =>
      __$$ArchivesUpdatedImplCopyWithImpl<_$ArchivesUpdatedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() started,
    required TResult Function() getArchived,
    required TResult Function(Status status) statusChanged,
    required TResult Function(ArchivesResponseEntity archives) archivesUpdated,
    required TResult Function(Failure? failure) failureChanged,
    required TResult Function(String value) searchChanged,
  }) {
    return archivesUpdated(archives);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? started,
    TResult? Function()? getArchived,
    TResult? Function(Status status)? statusChanged,
    TResult? Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult? Function(Failure? failure)? failureChanged,
    TResult? Function(String value)? searchChanged,
  }) {
    return archivesUpdated?.call(archives);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? started,
    TResult Function()? getArchived,
    TResult Function(Status status)? statusChanged,
    TResult Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult Function(Failure? failure)? failureChanged,
    TResult Function(String value)? searchChanged,
    required TResult orElse(),
  }) {
    if (archivesUpdated != null) {
      return archivesUpdated(archives);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetArchived value) getArchived,
    required TResult Function(_StatusChanged value) statusChanged,
    required TResult Function(_ArchivesUpdated value) archivesUpdated,
    required TResult Function(_FailureChanged value) failureChanged,
    required TResult Function(_SearchChanged value) searchChanged,
  }) {
    return archivesUpdated(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetArchived value)? getArchived,
    TResult? Function(_StatusChanged value)? statusChanged,
    TResult? Function(_ArchivesUpdated value)? archivesUpdated,
    TResult? Function(_FailureChanged value)? failureChanged,
    TResult? Function(_SearchChanged value)? searchChanged,
  }) {
    return archivesUpdated?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetArchived value)? getArchived,
    TResult Function(_StatusChanged value)? statusChanged,
    TResult Function(_ArchivesUpdated value)? archivesUpdated,
    TResult Function(_FailureChanged value)? failureChanged,
    TResult Function(_SearchChanged value)? searchChanged,
    required TResult orElse(),
  }) {
    if (archivesUpdated != null) {
      return archivesUpdated(this);
    }
    return orElse();
  }
}

abstract class _ArchivesUpdated implements ArchivesEvent {
  const factory _ArchivesUpdated(final ArchivesResponseEntity archives) =
      _$ArchivesUpdatedImpl;

  ArchivesResponseEntity get archives;
  @JsonKey(ignore: true)
  _$$ArchivesUpdatedImplCopyWith<_$ArchivesUpdatedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$FailureChangedImplCopyWith<$Res> {
  factory _$$FailureChangedImplCopyWith(_$FailureChangedImpl value,
          $Res Function(_$FailureChangedImpl) then) =
      __$$FailureChangedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Failure? failure});
}

/// @nodoc
class __$$FailureChangedImplCopyWithImpl<$Res>
    extends _$ArchivesEventCopyWithImpl<$Res, _$FailureChangedImpl>
    implements _$$FailureChangedImplCopyWith<$Res> {
  __$$FailureChangedImplCopyWithImpl(
      _$FailureChangedImpl _value, $Res Function(_$FailureChangedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? failure = freezed,
  }) {
    return _then(_$FailureChangedImpl(
      freezed == failure
          ? _value.failure
          : failure // ignore: cast_nullable_to_non_nullable
              as Failure?,
    ));
  }
}

/// @nodoc

class _$FailureChangedImpl implements _FailureChanged {
  const _$FailureChangedImpl(this.failure);

  @override
  final Failure? failure;

  @override
  String toString() {
    return 'ArchivesEvent.failureChanged(failure: $failure)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FailureChangedImpl &&
            (identical(other.failure, failure) || other.failure == failure));
  }

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FailureChangedImplCopyWith<_$FailureChangedImpl> get copyWith =>
      __$$FailureChangedImplCopyWithImpl<_$FailureChangedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() started,
    required TResult Function() getArchived,
    required TResult Function(Status status) statusChanged,
    required TResult Function(ArchivesResponseEntity archives) archivesUpdated,
    required TResult Function(Failure? failure) failureChanged,
    required TResult Function(String value) searchChanged,
  }) {
    return failureChanged(failure);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? started,
    TResult? Function()? getArchived,
    TResult? Function(Status status)? statusChanged,
    TResult? Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult? Function(Failure? failure)? failureChanged,
    TResult? Function(String value)? searchChanged,
  }) {
    return failureChanged?.call(failure);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? started,
    TResult Function()? getArchived,
    TResult Function(Status status)? statusChanged,
    TResult Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult Function(Failure? failure)? failureChanged,
    TResult Function(String value)? searchChanged,
    required TResult orElse(),
  }) {
    if (failureChanged != null) {
      return failureChanged(failure);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetArchived value) getArchived,
    required TResult Function(_StatusChanged value) statusChanged,
    required TResult Function(_ArchivesUpdated value) archivesUpdated,
    required TResult Function(_FailureChanged value) failureChanged,
    required TResult Function(_SearchChanged value) searchChanged,
  }) {
    return failureChanged(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetArchived value)? getArchived,
    TResult? Function(_StatusChanged value)? statusChanged,
    TResult? Function(_ArchivesUpdated value)? archivesUpdated,
    TResult? Function(_FailureChanged value)? failureChanged,
    TResult? Function(_SearchChanged value)? searchChanged,
  }) {
    return failureChanged?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetArchived value)? getArchived,
    TResult Function(_StatusChanged value)? statusChanged,
    TResult Function(_ArchivesUpdated value)? archivesUpdated,
    TResult Function(_FailureChanged value)? failureChanged,
    TResult Function(_SearchChanged value)? searchChanged,
    required TResult orElse(),
  }) {
    if (failureChanged != null) {
      return failureChanged(this);
    }
    return orElse();
  }
}

abstract class _FailureChanged implements ArchivesEvent {
  const factory _FailureChanged(final Failure? failure) = _$FailureChangedImpl;

  Failure? get failure;
  @JsonKey(ignore: true)
  _$$FailureChangedImplCopyWith<_$FailureChangedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$SearchChangedImplCopyWith<$Res> {
  factory _$$SearchChangedImplCopyWith(
          _$SearchChangedImpl value, $Res Function(_$SearchChangedImpl) then) =
      __$$SearchChangedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String value});
}

/// @nodoc
class __$$SearchChangedImplCopyWithImpl<$Res>
    extends _$ArchivesEventCopyWithImpl<$Res, _$SearchChangedImpl>
    implements _$$SearchChangedImplCopyWith<$Res> {
  __$$SearchChangedImplCopyWithImpl(
      _$SearchChangedImpl _value, $Res Function(_$SearchChangedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? value = null,
  }) {
    return _then(_$SearchChangedImpl(
      null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$SearchChangedImpl implements _SearchChanged {
  const _$SearchChangedImpl(this.value);

  @override
  final String value;

  @override
  String toString() {
    return 'ArchivesEvent.searchChanged(value: $value)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SearchChangedImpl &&
            (identical(other.value, value) || other.value == value));
  }

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SearchChangedImplCopyWith<_$SearchChangedImpl> get copyWith =>
      __$$SearchChangedImplCopyWithImpl<_$SearchChangedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() started,
    required TResult Function() getArchived,
    required TResult Function(Status status) statusChanged,
    required TResult Function(ArchivesResponseEntity archives) archivesUpdated,
    required TResult Function(Failure? failure) failureChanged,
    required TResult Function(String value) searchChanged,
  }) {
    return searchChanged(value);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? started,
    TResult? Function()? getArchived,
    TResult? Function(Status status)? statusChanged,
    TResult? Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult? Function(Failure? failure)? failureChanged,
    TResult? Function(String value)? searchChanged,
  }) {
    return searchChanged?.call(value);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? started,
    TResult Function()? getArchived,
    TResult Function(Status status)? statusChanged,
    TResult Function(ArchivesResponseEntity archives)? archivesUpdated,
    TResult Function(Failure? failure)? failureChanged,
    TResult Function(String value)? searchChanged,
    required TResult orElse(),
  }) {
    if (searchChanged != null) {
      return searchChanged(value);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Started value) started,
    required TResult Function(_GetArchived value) getArchived,
    required TResult Function(_StatusChanged value) statusChanged,
    required TResult Function(_ArchivesUpdated value) archivesUpdated,
    required TResult Function(_FailureChanged value) failureChanged,
    required TResult Function(_SearchChanged value) searchChanged,
  }) {
    return searchChanged(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Started value)? started,
    TResult? Function(_GetArchived value)? getArchived,
    TResult? Function(_StatusChanged value)? statusChanged,
    TResult? Function(_ArchivesUpdated value)? archivesUpdated,
    TResult? Function(_FailureChanged value)? failureChanged,
    TResult? Function(_SearchChanged value)? searchChanged,
  }) {
    return searchChanged?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Started value)? started,
    TResult Function(_GetArchived value)? getArchived,
    TResult Function(_StatusChanged value)? statusChanged,
    TResult Function(_ArchivesUpdated value)? archivesUpdated,
    TResult Function(_FailureChanged value)? failureChanged,
    TResult Function(_SearchChanged value)? searchChanged,
    required TResult orElse(),
  }) {
    if (searchChanged != null) {
      return searchChanged(this);
    }
    return orElse();
  }
}

abstract class _SearchChanged implements ArchivesEvent {
  const factory _SearchChanged(final String value) = _$SearchChangedImpl;

  String get value;
  @JsonKey(ignore: true)
  _$$SearchChangedImplCopyWith<_$SearchChangedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ArchivesState {
  Status get status => throw _privateConstructorUsedError;
  TextEditingController? get textController =>
      throw _privateConstructorUsedError;
  ArchivesResponseEntity? get archives => throw _privateConstructorUsedError;
  Failure? get failure => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $ArchivesStateCopyWith<ArchivesState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ArchivesStateCopyWith<$Res> {
  factory $ArchivesStateCopyWith(
          ArchivesState value, $Res Function(ArchivesState) then) =
      _$ArchivesStateCopyWithImpl<$Res, ArchivesState>;
  @useResult
  $Res call(
      {Status status,
      TextEditingController? textController,
      ArchivesResponseEntity? archives,
      Failure? failure});
}

/// @nodoc
class _$ArchivesStateCopyWithImpl<$Res, $Val extends ArchivesState>
    implements $ArchivesStateCopyWith<$Res> {
  _$ArchivesStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? textController = freezed,
    Object? archives = freezed,
    Object? failure = freezed,
  }) {
    return _then(_value.copyWith(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as Status,
      textController: freezed == textController
          ? _value.textController
          : textController // ignore: cast_nullable_to_non_nullable
              as TextEditingController?,
      archives: freezed == archives
          ? _value.archives
          : archives // ignore: cast_nullable_to_non_nullable
              as ArchivesResponseEntity?,
      failure: freezed == failure
          ? _value.failure
          : failure // ignore: cast_nullable_to_non_nullable
              as Failure?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ArchivesStateImplCopyWith<$Res>
    implements $ArchivesStateCopyWith<$Res> {
  factory _$$ArchivesStateImplCopyWith(
          _$ArchivesStateImpl value, $Res Function(_$ArchivesStateImpl) then) =
      __$$ArchivesStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {Status status,
      TextEditingController? textController,
      ArchivesResponseEntity? archives,
      Failure? failure});
}

/// @nodoc
class __$$ArchivesStateImplCopyWithImpl<$Res>
    extends _$ArchivesStateCopyWithImpl<$Res, _$ArchivesStateImpl>
    implements _$$ArchivesStateImplCopyWith<$Res> {
  __$$ArchivesStateImplCopyWithImpl(
      _$ArchivesStateImpl _value, $Res Function(_$ArchivesStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? textController = freezed,
    Object? archives = freezed,
    Object? failure = freezed,
  }) {
    return _then(_$ArchivesStateImpl(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as Status,
      textController: freezed == textController
          ? _value.textController
          : textController // ignore: cast_nullable_to_non_nullable
              as TextEditingController?,
      archives: freezed == archives
          ? _value.archives
          : archives // ignore: cast_nullable_to_non_nullable
              as ArchivesResponseEntity?,
      failure: freezed == failure
          ? _value.failure
          : failure // ignore: cast_nullable_to_non_nullable
              as Failure?,
    ));
  }
}

/// @nodoc

class _$ArchivesStateImpl implements _ArchivesState {
  const _$ArchivesStateImpl(
      {this.status = Status.UNKNOWN,
      this.textController,
      this.archives,
      this.failure});

  @override
  @JsonKey()
  final Status status;
  @override
  final TextEditingController? textController;
  @override
  final ArchivesResponseEntity? archives;
  @override
  final Failure? failure;

  @override
  String toString() {
    return 'ArchivesState(status: $status, textController: $textController, archives: $archives, failure: $failure)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ArchivesStateImpl &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.textController, textController) ||
                other.textController == textController) &&
            (identical(other.archives, archives) ||
                other.archives == archives) &&
            (identical(other.failure, failure) || other.failure == failure));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, status, textController, archives, failure);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ArchivesStateImplCopyWith<_$ArchivesStateImpl> get copyWith =>
      __$$ArchivesStateImplCopyWithImpl<_$ArchivesStateImpl>(this, _$identity);
}

abstract class _ArchivesState implements ArchivesState {
  const factory _ArchivesState(
      {final Status status,
      final TextEditingController? textController,
      final ArchivesResponseEntity? archives,
      final Failure? failure}) = _$ArchivesStateImpl;

  @override
  Status get status;
  @override
  TextEditingController? get textController;
  @override
  ArchivesResponseEntity? get archives;
  @override
  Failure? get failure;
  @override
  @JsonKey(ignore: true)
  _$$ArchivesStateImplCopyWith<_$ArchivesStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
