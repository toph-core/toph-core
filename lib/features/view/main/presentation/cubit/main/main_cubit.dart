import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
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
  final CacheService _cache;
  final ConnectivityCubit _connectivity;
  final LanHubService _lanHub;

  StreamSubscription<({String tableId, String status})>? _lanSub;

  MainCubit(
    this._getTablesUsecase,
    this._getHallsUsecase,
    this._cache,
    this._connectivity,
    this._lanHub,
  ) : super(const MainState()) {
    _lanSub = _lanHub.onRemoteTableUpdate.listen(_applyRemoteTableUpdate);
  }

  void _applyRemoteTableUpdate(({String tableId, String status}) event) {
    final newStatus = TableStatus.values.firstWhere(
      (s) => s.name == event.status,
      orElse: () => TableStatus.free,
    );
    updateTableStatus(event.tableId, newStatus);
  }

  Future<void> _getTablesByHallId(String hallId) async {
    // Cache-first: darhol cache dan ko'rsat
    final cached = _cache.getTables();
    if (cached.isNotEmpty) {
      final cachedTables = cached
          .map((e) => CafeTableModel.fromJson(e))
          .where((t) => t.hallId == hallId)
          .toList();
      emit(state.copyWith(tables: cachedTables, status: Status.SUCCESS));
    } else {
      emit(state.copyWith(status: Status.LOADING));
    }

    if (!_connectivity.isOnline) return;

    // Orqa fonda network dan yangilanadi
    final result = await _getTablesUsecase.call(hallId);
    if (isClosed) return;
    result.fold(
      (failure) {
        if (cached.isEmpty) {
          emit(state.copyWith(failure: failure, status: Status.ERROR));
        }
      },
      (tables) {
        _cache.saveTables(tables.map((t) => t.toJson()).toList());
        emit(state.copyWith(tables: tables, status: Status.SUCCESS));
      },
    );
  }

  void updateTableStatus(String id, TableStatus status) {
    if (state.tables != null) {
      final index = state.tables!.indexWhere((v) => v.id == id);
      if (index != -1) {
        final newTables = List<CafeTableModel>.from(state.tables!);
        newTables[index] = newTables[index].copyWith(status: status);
        emit(state.copyWith(tables: newTables));
      }
    }
  }

  /// Stol holati o'zgarganda LAN hub ga broadcast qilish.
  void broadcastTableStatus(String tableId, TableStatus status) {
    updateTableStatus(tableId, status);
    _lanHub.tableStatusChanged(tableId, status.name);
  }

  Future<void> getHalls() async {
    // Cache-first: darhol cache dan ko'rsat
    final cached = _cache.getHalls();
    if (cached.isNotEmpty) {
      final halls = cached.map((e) => HallModel.fromJson(e)).toList();
      emit(state.copyWith(halls: halls, status: Status.SUCCESS));
      if (halls.isNotEmpty) setSelectedHallId(halls.first.id);
    } else {
      emit(state.copyWith(status: Status.OTHER_LOADING));
    }

    if (!_connectivity.isOnline) return;

    // Orqa fonda network dan yangilanadi
    final result = await _getHallsUsecase.call(NoParams());
    if (isClosed) return;
    result.fold(
      (failure) {
        if (cached.isEmpty) {
          emit(state.copyWith(failure: failure, status: Status.ERROR));
        }
      },
      (halls) {
        _cache.saveHalls(halls.map((h) => h.toJson()).toList());
        emit(state.copyWith(halls: halls, status: Status.SUCCESS));
        // Agar hali zal tanlanmagan bo'lsa birinchisini tanlash
        if (state.selectedHallId == null && halls.isNotEmpty) {
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

  Future<void> refreshTables() async {
    final hallId = state.selectedHallId;
    if (hallId == null) return;
    await _getTablesByHallId(hallId);
  }

  @override
  Future<void> close() {
    _lanSub?.cancel();
    return super.close();
  }
}
