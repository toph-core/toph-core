part of 'main_cubit.dart';

@freezed
class MainState with _$MainState {
  const factory MainState({
    List<RestaurantTable>? tables,
    @Default(UnknownFailure()) Failure failure,
    @Default(Status.UNKNOWN) Status status,
  }) = _MainState;
}
