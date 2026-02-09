import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_halls_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_tables_by_hall_id_usecase.dart';

part 'main_cubit.freezed.dart';
part 'main_state.dart';

class MainCubit extends Cubit<MainState> {
  final GetTablesByHallIdUsecase _getTablesUsecase;
  final GetHallsUsecase _getHallsUsecase;
  MainCubit(this._getTablesUsecase, this._getHallsUsecase)
    : super(const MainState());

  Future<void> _getTablesByHallId(String hallId) async {
    emit(state.copyWith(status: Status.LOADING));
    final result = await _getTablesUsecase.call(hallId);
    result.fold(
      (failure) => emit(state.copyWith(failure: failure, status: Status.ERROR)),
      (tables) => emit(state.copyWith(tables: tables, status: Status.SUCCESS)),
    );
  }

  Future<void> getHalls() async {
    emit(state.copyWith(status: Status.OTHER_LOADING));
    final result = await _getHallsUsecase.call(NoParams());
    result.fold(
      (failure) => emit(state.copyWith(failure: failure, status: Status.ERROR)),
      (halls) {
        emit(state.copyWith(halls: halls, status: Status.SUCCESS));
        if (halls.isNotEmpty) {
          setSelectedHallId(halls.first.id);
        }
      },
    );
  }

  void setSelectedHallId(String id) {
    if (state.selectedHallId == id) return;

    emit(state.copyWith(selectedHallId: id));
    _getTablesByHallId(id);
  }
}
