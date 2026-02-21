import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_archives_usecase.dart';

part 'archives_event.dart';
part 'archives_state.dart';
part 'archives_bloc.freezed.dart';

class ArchivesBloc extends Bloc<ArchivesEvent, ArchivesState> {
  late final GetArchivesUsecase _getArchivesUsecase;
  //
  ArchivesBloc({required GetArchivesUsecase getArchivesUsecase})
    : _getArchivesUsecase = getArchivesUsecase,
      super(ArchivesState.initial()) {
    on<_Started>(_onStarted);
    on<_StatusChanged>(_onStatusChanged);
    on<_ArchivesUpdated>(_onArchivesUpdated);
    on<_FailureChanged>(_onFailureChanged);
    on<_SearchChanged>(_onSearchChanged);
    on<_GetArchived>(_getArchived);
  }

  void _getArchived(_GetArchived event, emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final response = await _getArchivesUsecase.call(
      PaginationRequestModel(
        limit: state.archives?.archives.length ?? 0,
        offset: 20,
      ),
    );

    response.fold((l) => emit(), (r) => emit(state.copyWith(archives: r)));
  }

  void _onStarted(_Started event, Emitter<ArchivesState> emit) {
    emit(
      state.copyWith(textController: TextEditingController(), failure: null),
    );
    add(const _GetArchived());
  }

  void _onStatusChanged(_StatusChanged event, Emitter<ArchivesState> emit) {
    emit(state.copyWith(status: event.status));
  }

  void _onArchivesUpdated(_ArchivesUpdated event, Emitter<ArchivesState> emit) {
    emit(state.copyWith(archives: event.archives, failure: null));
  }

  void _onFailureChanged(_FailureChanged event, Emitter<ArchivesState> emit) {
    emit(state.copyWith(failure: event.failure));
  }

  void _onSearchChanged(_SearchChanged event, Emitter<ArchivesState> emit) {
    final controller = state.textController ?? TextEditingController();
    if (controller.text != event.value) {
      controller.value = controller.value.copyWith(
        text: event.value,
        selection: TextSelection.collapsed(offset: event.value.length),
      );
    }
    emit(state.copyWith(textController: controller));
  }

  @override
  Future<void> close() {
    state.textController?.dispose();
    return super.close();
  }
}
