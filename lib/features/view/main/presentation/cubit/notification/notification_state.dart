part of 'notification_bloc.dart';

@freezed
class NotificationState with _$NotificationState {
  const factory NotificationState({
    @Default(Status.UNKNOWN) Status status,
    ScrollController? scrollController,
    TextEditingController? searchController,
    @Default(ArchivesFilterType.Today) ArchivesFilterType filterType,
    Failure? failure,
  }) = _NotificationState;

  factory NotificationState.initial() {
    return NotificationState(
      scrollController: ScrollController(),
      searchController: TextEditingController(),
    );
  }
}
