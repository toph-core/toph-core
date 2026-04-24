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

  // ── Throttle: bir xil tables chaqiriqni 30s ichida takrorlamaymiz ──
  DateTime? _lastAllTablesFetchAt;
  final Map<String, DateTime> _lastHallFetchAt = {};
  DateTime? _lastHallsFetchAt;
  static const _tablesThrottle = Duration(seconds: 30);
  static const _hallsThrottle = Duration(minutes: 5);

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

  Future<void> _getTablesByHallId(String hallId, {bool force = false}) async {
    // Cache-first: cache dan ushbu zal stollarini ko'rsat
    final allCachedRaw = _cache.getTables();
    final allCached = allCachedRaw
        .map((e) => CafeTableModel.fromJson(e))
        .toList();
    final cachedForHall = allCached.where((t) => t.hallId == hallId).toList();
    if (cachedForHall.isNotEmpty) {
      emit(state.copyWith(tables: cachedForHall, status: Status.SUCCESS));
    } else {
      emit(state.copyWith(status: Status.LOADING));
    }

    if (!_connectivity.isOnline) return;

    // Throttle: 30s ichida VA cache da shu zal stollari bor bo'lsa — takrorlamaymiz
    final lastAt = _lastHallFetchAt[hallId];
    if (!force &&
        cachedForHall.isNotEmpty &&
        lastAt != null &&
        DateTime.now().difference(lastAt) < _tablesThrottle) {
      return;
    }
    _lastHallFetchAt[hallId] = DateTime.now();

    // Orqa fonda network dan yangilanadi
    final result = await _getTablesUsecase.call(hallId);
    if (isClosed) return;
    result.fold(
      (failure) {
        if (cachedForHall.isEmpty) {
          emit(state.copyWith(failure: failure, status: Status.ERROR));
        }
      },
      (tables) {
        // Merge: boshqa zallarning cache yozuvlarini saqlab, faqat shu zalni yangilaymiz
        final otherHalls = allCached.where((t) => t.hallId != hallId).toList();
        final merged = [...otherHalls, ...tables];
        _cache.saveTables(merged.map((t) => t.toJson()).toList());
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

  Future<void> getHalls({bool force = false}) async {
    // Cache-first: darhol cache dan ko'rsat
    final cached = _cache.getHalls();
    List<HallModel> hallsForTables = const [];
    if (cached.isNotEmpty) {
      hallsForTables = cached.map((e) => HallModel.fromJson(e)).toList();
      emit(
        state.copyWith(
          halls: hallsForTables,
          // "Barchasi" har safar default — avvalgi tanlangan zalni tozalaymiz
          selectedHallId: null,
          status: Status.SUCCESS,
        ),
      );
    } else {
      emit(state.copyWith(selectedHallId: null, status: Status.OTHER_LOADING));
    }

    // Throttle: halls kam o'zgaradi — 5 daqiqa ichida takrorlamaymiz
    final shouldSkipNetwork = !force &&
        _lastHallsFetchAt != null &&
        DateTime.now().difference(_lastHallsFetchAt!) < _hallsThrottle;

    // Orqa fonda network dan yangilanadi
    if (_connectivity.isOnline && !shouldSkipNetwork) {
      _lastHallsFetchAt = DateTime.now();
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
          hallsForTables = halls;
          emit(state.copyWith(halls: halls, status: Status.SUCCESS));
        },
      );
    }

    // Zallar mavjud bo'lsa — "Barchasi" rejimida barcha stollarni yuklaymiz.
    // `state.halls` o'rniga bevosita lokal nusxadan foydalanamiz — hech qanday
    // sinxron/ketma-ketlik muammosi bo'lmasin.
    if (hallsForTables.isNotEmpty) {
      await loadAllHallsTables(force: force, hallsOverride: hallsForTables);
    }
  }

  void setSelectedHallId(String id) {
    if (state.selectedHallId == id) return;
    emit(state.copyWith(selectedHallId: id));
    _getTablesByHallId(id);
  }

  /// "Barchasi" rejimi: barcha zallar stollarini yig'ib ko'rsatadi.
  /// `selectedHallId` null ga o'rnatiladi.
  Future<void> loadAllHallsTables({
    bool force = false,
    List<HallModel>? hallsOverride,
  }) async {
    final halls = hallsOverride ?? state.halls ?? const <HallModel>[];
    if (halls.isEmpty) return;

    // Cache-first: darhol keshdagi barcha stollarni ko'rsat (boshqa zal
    // tanlovidan qolgan state.tables ni "Barchasi" ostida ko'rsatish muammosini
    // oldini olamiz)
    final allCached = _cache
        .getTables()
        .map((e) => CafeTableModel.fromJson(e))
        .toList();
    if (allCached.isNotEmpty) {
      emit(state.copyWith(
        selectedHallId: null,
        tables: allCached,
        status: Status.SUCCESS,
      ));
    } else {
      emit(state.copyWith(selectedHallId: null, status: Status.LOADING));
    }

    // Throttle: so'nggi "barchasi" fetch 30s ichida bo'lsa — network chaqirmaymiz
    if (!force &&
        _lastAllTablesFetchAt != null &&
        DateTime.now().difference(_lastAllTablesFetchAt!) < _tablesThrottle &&
        allCached.isNotEmpty) {
      return;
    }

    if (!_connectivity.isOnline) {
      return;
    }

    _lastAllTablesFetchAt = DateTime.now();
    // Ketma-ket yuklaymiz — parallel Future.wait backendni cho'ktiradi (500 xato).
    final all = <CafeTableModel>[];
    for (final h in halls) {
      if (isClosed) return;
      final r = await _getTablesUsecase.call(h.id);
      if (isClosed) return;
      r.fold((_) => null, all.addAll);
      _lastHallFetchAt[h.id] = DateTime.now();
    }
    _cache.saveTables(all.map((t) => t.toJson()).toList());
    emit(state.copyWith(tables: all, status: Status.SUCCESS));
  }

  Future<void> refreshTables({bool force = false}) async {
    final hallId = state.selectedHallId;
    if (hallId == null) {
      await loadAllHallsTables(force: force);
      return;
    }
    await _getTablesByHallId(hallId, force: force);
  }

  @override
  Future<void> close() {
    _lanSub?.cancel();
    return super.close();
  }
}
