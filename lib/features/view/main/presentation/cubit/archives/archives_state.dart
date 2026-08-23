part of 'archives_bloc.dart';

@freezed
class ArchivesState with _$ArchivesState {
  const ArchivesState._();

  const factory ArchivesState({
    @Default(Status.UNKNOWN) Status status,
    @Default(Status.UNKNOWN) Status archiveStatus,
    @Default(ArchivesFilterType.Today) ArchivesFilterType filterType,
    @Default([
      ArchivesFilterType.All,
      ArchivesFilterType.Today,
      ArchivesFilterType.Week,
      ArchivesFilterType.month,
    ])
    List<ArchivesFilterType> filters,
    DateTime? startFilterDate,
    DateTime? endFilterDate,
    String? statusFilter,
    TextEditingController? textController,
    ArchivesResponseEntity? archives,

    /// Totals for the whole filtered window — not a fold over [archives],
    /// which only ever holds what has been scrolled to.
    @Default(ArchivesSummaryEntity()) ArchivesSummaryEntity summary,

    /// How many rows the current query asks for. Grows by
    /// [kArchivesPageSize] each time the operator reaches the end of the list.
    @Default(kArchivesPageSize) int loadedLimit,

    /// A window growth is in flight — the list shows a footer spinner and
    /// ignores further load-more requests until it lands.
    @Default(false) bool isLoadingMore,
    ArchiveDetailEntity? selectArchiveDetail,
    ArchiveEntity? selectArchive,
    Failure? failure,
  }) = _ArchivesState;

  factory ArchivesState.initial() =>
      ArchivesState(textController: TextEditingController());

  /// Rows on screen out of rows in the window.
  int get loadedCount => archives?.archives.length ?? 0;

  int get totalCount => archives?.pagination.total ?? 0;

  /// Whether the window holds bills the list has not asked for yet.
  bool get hasMore => loadedCount < totalCount;
}
