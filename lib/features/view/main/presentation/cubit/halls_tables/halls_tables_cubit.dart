import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/halls_tables_local_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — one cubit for the halls list and the
/// selected hall's floor plan, so neither the section nor the detail view
/// resolves a repository of its own.
///
/// No `loading` flag, on either list: both reads are synchronous queries
/// against the replica, so the first emission already carries rows.
class HallsTablesState {
  final List<HallModel> halls;
  final HallModel? selectedHall;

  /// Tables of [selectedHall]. Empty when no hall is selected.
  final List<CafeTableModel> tables;

  /// A local write that failed — never a connection error.
  final String? error;

  /// One-shot message for a write whose effect is not yet visible (a queued
  /// create). Cleared by [acknowledge].
  final String? notice;

  const HallsTablesState({
    this.halls = const [],
    this.selectedHall,
    this.tables = const [],
    this.error,
    this.notice,
  });

  HallsTablesState copyWith({
    List<HallModel>? halls,
    Object? selectedHall = _sentinel,
    List<CafeTableModel>? tables,
    Object? error = _sentinel,
    Object? notice = _sentinel,
  }) {
    return HallsTablesState(
      halls: halls ?? this.halls,
      selectedHall: identical(selectedHall, _sentinel)
          ? this.selectedHall
          : selectedHall as HallModel?,
      tables: tables ?? this.tables,
      error: identical(error, _sentinel) ? this.error : error as String?,
      notice: identical(notice, _sentinel) ? this.notice : notice as String?,
    );
  }

  static const _sentinel = Object();
}

class HallsTablesCubit extends Cubit<HallsTablesState> {
  final HallsTablesLocalRepository _repository;
  StreamSubscription<List<HallModel>>? _hallsSub;
  StreamSubscription<List<CafeTableModel>>? _tablesSub;

  HallsTablesCubit(this._repository) : super(const HallsTablesState()) {
    _hallsSub = _repository.watchHalls().listen((halls) {
      if (isClosed) return;
      // Re-resolve the selection against the new list: a hall renamed elsewhere
      // should show its new name, and one deleted elsewhere should drop the
      // detail view rather than leave it showing a hall that no longer exists.
      final current = state.selectedHall;
      HallModel? selected;
      if (current != null) {
        for (final h in halls) {
          if (h.id == current.id) {
            selected = h;
            break;
          }
        }
      }
      emit(state.copyWith(halls: halls, selectedHall: selected));
      if (current != null && selected == null) _subscribeTables(null);
    });
  }

  void selectHall(HallModel? hall) {
    emit(state.copyWith(selectedHall: hall, tables: const []));
    _subscribeTables(hall?.id);
  }

  void _subscribeTables(String? hallId) {
    _tablesSub?.cancel();
    _tablesSub = null;
    if (hallId == null) return;
    _tablesSub = _repository.watchTablesForHall(hallId).listen((tables) {
      if (!isClosed) emit(state.copyWith(tables: tables));
    });
  }

  // ── Writes ───────────────────────────────────────────────────────────

  bool createHall(Map<String, dynamic> body) =>
      _apply(() => _repository.createHall(body));

  bool updateHall(String id, Map<String, dynamic> changes) =>
      _apply(() => _repository.updateHall(id, changes));

  bool deleteHall(String id) => _apply(() => _repository.deleteHall(id));

  bool createTable(Map<String, dynamic> body) =>
      _apply(() => _repository.createTable(body));

  bool updateTable(String id, Map<String, dynamic> changes) =>
      _apply(() => _repository.updateTable(id, changes));

  bool deleteTable(String id) => _apply(() => _repository.deleteTable(id));

  /// Runs a write and reports whether it was accepted locally. Synchronous
  /// throughout — a floor-plan drag never waits on anything.
  bool _apply(Either<Failure, Unit> Function() write) {
    return write().fold(
      (failure) {
        emit(state.copyWith(error: failure.toString(), notice: null));
        return false;
      },
      (_) {
        emit(state.copyWith(error: null));
        return true;
      },
    );
  }

  void acknowledge() {
    if (state.notice != null || state.error != null) {
      emit(state.copyWith(notice: null, error: null));
    }
  }

  @override
  Future<void> close() {
    _hallsSub?.cancel();
    _tablesSub?.cancel();
    return super.close();
  }
}
