import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/models/restaurant_table.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_tables_usecase.dart';

part 'main_cubit.freezed.dart';
part 'main_state.dart';

class MainCubit extends Cubit<MainState> {
  final GetTablesUsecase _getTablesUsecase;
  MainCubit(this._getTablesUsecase) : super(const MainState());

  Future<void> getTables() async {
    emit(state.copyWith(status: Status.LOADING));
    final result = await _getTablesUsecase.call(NoParams());
    result.fold(
      (failure) => emit(state.copyWith(failure: failure, status: Status.ERROR)),
      (tables) => emit(state.copyWith(tables: tables, status: Status.SUCCESS)),
    );
  }
}
