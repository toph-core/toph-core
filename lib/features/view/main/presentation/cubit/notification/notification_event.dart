part of 'notification_bloc.dart';

@freezed
class NotificationEvent with _$NotificationEvent {
  const factory NotificationEvent.started() = _Started;
  const factory NotificationEvent.updateFilterType({
    required ArchivesFilterType filterType,
  }) = _UpdateFilterType;
  const factory NotificationEvent.getNotifications() = _GetNotifications;
  const factory NotificationEvent.againNotifications() = _AgainNotifications;
}
