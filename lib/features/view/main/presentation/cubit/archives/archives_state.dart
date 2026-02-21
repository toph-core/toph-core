part of 'archives_bloc.dart';

@freezed
class ArchivesState with _$ArchivesState {
  const factory ArchivesState({
    @Default(Status.UNKNOWN) Status status,
    TextEditingController? textController,
    ArchivesResponseEntity? archives,
    Failure? failure,
  }) = _ArchivesState;

  factory ArchivesState.initial() {
    return ArchivesState(textController: TextEditingController());
  }
}
