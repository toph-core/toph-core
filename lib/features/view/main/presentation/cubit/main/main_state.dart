part of 'main_cubit.dart';

@freezed
class MainState with _$MainState {
  const factory MainState({
    List<CafeTableModel>? tables,

    /// Every table in the venue, regardless of the selected hall.
    ///
    /// [tables] is the current selection's slice, so the hall pills cannot
    /// count from it — picking a hall would collapse every other pill's
    /// count to zero. This is the second, unfiltered subscription that keeps
    /// those counts steady, and it is what the pill row reads instead of
    /// reaching into a cache from inside `build()`.
    List<CafeTableModel>? allTables,
    List<HallModel>? halls,
    @Default(false) bool isLoading,
    String? selectedHallId,
    @Default(UnknownFailure()) Failure failure,
    @Default(Status.UNKNOWN) Status status,
  }) = _MainState;
}
