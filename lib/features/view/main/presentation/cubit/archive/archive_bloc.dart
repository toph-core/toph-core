import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/archives_local_repository.dart';

part 'archive_event.dart';
part 'archive_state.dart';
part 'archive_bloc.freezed.dart';

class ArchiveBloc extends Bloc<ArchiveEvent, ArchiveState> {
  final ArchivesLocalRepository _archivesRepository;

  ArchiveBloc({required ArchivesLocalRepository archivesRepository})
    : _archivesRepository = archivesRepository,
      super(const ArchiveState()) {
    on<_Started>(_onStarted);
    on<_GetArchive>(_getArchive);
  }

  void _getArchive(_GetArchive event, emit) async {
    if (event.id != null) {
      emit(state.copyWith(status: Status.LOADING, archiveDetail: null));
      final response = await _archivesRepository.getArchiveWithId(event.id!);
      response.fold((l) {
        showErrorMessage(
          navigatorKey.currentContext!,
          l.getLocalizedMessage(navigatorKey.currentContext!),
        );
        emit(state.copyWith(status: Status.ERROR, failure: l));
      }, (r) => emit(state.copyWith(status: Status.SUCCESS, archiveDetail: r)));
    }
  }

  Future<void> _onStarted(_Started event, Emitter<ArchiveState> emit) async {
    emit(const ArchiveState());
  }
}
