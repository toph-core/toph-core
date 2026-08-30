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

    /// The selected bill's table (time) charge as the local timer currently
    /// holds it, in whole so'm.
    ///
    /// The server reports `table_amount: 0` until a bill is paid — it only
    /// computes the charge at settlement — so for an open bill this is the
    /// only place the running amount exists, and without it the details panel
    /// showed no charge for exactly the bills that were accruing one. 0 when
    /// there is no local timer for the selection, in which case the panel
    /// falls back to the detail's own `tableAmount`.
    @Default(0) int selectedTableCharge,

    /// The selected bill's active-period breakdown, synthesized from the
    /// local timer record — the fallback for a bill whose server-side
    /// `table_sessions` have not been hydrated onto this terminal yet, which
    /// is the normal case for a bill that is still open. Empty when there is
    /// nothing local to read; the panel prefers the detail's own
    /// `activePeriods` whenever those exist.
    @Default(<TableSegment>[]) List<TableSegment> selectedTableSegments,
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
