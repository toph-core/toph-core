part of 'archives_bloc.dart';

@freezed
class ArchivesEvent with _$ArchivesEvent {
  const factory ArchivesEvent.started() = _Started;
  const factory ArchivesEvent.statusChanged(Status status) = _StatusChanged;
  const factory ArchivesEvent.archivesUpdated(ArchivesResponseEntity archives) =
      _ArchivesUpdated;
  const factory ArchivesEvent.summaryUpdated(ArchivesSummaryEntity summary) =
      _SummaryUpdated;

  /// The list reached its end and there is more in the window. Grows the
  /// query by one [kArchivesPageSize]; a no-op once everything is loaded.
  const factory ArchivesEvent.loadMore() = _LoadMore;

  const factory ArchivesEvent.failureChanged(Failure? failure) =
      _FailureChanged;
  const factory ArchivesEvent.searchChanged(String value) = _SearchChanged;
  const factory ArchivesEvent.searchByArchiveNum(String value) =
      _SearchByArchiveNum;
  const factory ArchivesEvent.selectArchive({required String id}) =
      _SelectArchive;
  const factory ArchivesEvent.getArchiveDetail() = _GetArchiveDetail;

  /// The selected bill's local timer moved — carries the charge it now holds.
  const factory ArchivesEvent.tableChargeUpdated(int amount) =
      _TableChargeUpdated;

  /// The active-period breakdown read back for the selected bill.
  const factory ArchivesEvent.tableSegmentsUpdated(
    List<TableSegment> segments,
  ) = _TableSegmentsUpdated;
  const factory ArchivesEvent.updateFilterType({
    required ArchivesFilterType type,
  }) = _UpdateFilterType;
  const factory ArchivesEvent.updateFilterDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) = _UpdateFilterDateRange;
  const factory ArchivesEvent.updateStatusFilter({String? status}) =
      _UpdateStatusFilter;
}
