import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';

part 'main_cubit.freezed.dart';
part 'main_state.dart';

/// offline-first-target-architecture.md §9 (V4). Halls/tables are a pure
/// `TablesRepository.watchX()` subscription — no throttle fields, no
/// `ConnectivityCubit` dependency, no awaited fetch usecase. `SyncEngine`
/// keeps `LocalDatabase` current independently of whether this Cubit (or
/// any screen) is even alive; this class only ever projects whatever's
/// already there.
class MainCubit extends Cubit<MainState> {
  final TablesRepository _tablesRepository;
  final LanHubService _lanHub;

  StreamSubscription<({String tableId, String status})>? _lanSub;
  StreamSubscription<List<HallModel>>? _hallsSub;
  StreamSubscription<List<CafeTableModel>>? _tablesSub;

  MainCubit(this._tablesRepository, this._lanHub) : super(const MainState()) {
    _lanSub = _lanHub.onRemoteTableUpdate.listen(_applyRemoteTableUpdate);
    _hallsSub = _tablesRepository.watchHalls().listen((halls) {
      emit(state.copyWith(halls: halls, status: Status.SUCCESS));
    });
    _watchTablesForSelection();
  }

  void _watchTablesForSelection() {
    _tablesSub?.cancel();
    final hallId = state.selectedHallId;
    final stream = hallId == null
        ? _tablesRepository.watchAllTables()
        : _tablesRepository.watchTablesForHall(hallId);
    _tablesSub = stream.listen((tables) {
      emit(state.copyWith(tables: tables, status: Status.SUCCESS));
    });
  }

  void _applyRemoteTableUpdate(({String tableId, String status}) event) {
    // Noma'lum status string kelsa — stolni "free" deb taxmin qilmaymiz
    // (bu band stolni bekorga bo'shatib qo'yishi mumkin edi). Shunchaki
    // e'tiborsiz qoldiramiz; keyingi to'g'ri broadcast yoki forced refresh
    // holatni tuzatadi.
    final newStatus = TableStatus.values
        .where((s) => s.name == event.status)
        .firstOrNull;
    if (newStatus == null) return;
    updateTableStatus(event.tableId, newStatus);
  }

  /// Local, immediate, durable — writes through `TablesRepository` into
  /// `LocalDatabase`, which is what makes this visible to every subscriber
  /// (including this same Cubit's own `watchAllTables`/`watchTablesForHall`
  /// stream) without a round trip through the cloud. Fire-and-forget per §5
  /// — the caller doesn't wait on it, same as any other local write in this
  /// app.
  void updateTableStatus(String id, TableStatus status) {
    unawaited(_tablesRepository.updateTableStatus(id, status));
  }

  /// Stol holati o'zgarganda LAN hub ga broadcast qilish.
  void broadcastTableStatus(String tableId, TableStatus status) {
    updateTableStatus(tableId, status);
    _lanHub.tableStatusChanged(tableId, status.name);
  }

  /// Kept for call-site compatibility (many screens still call
  /// `getHalls()`/`refreshTables()`/`loadAllHallsTables()` expecting an
  /// awaitable "make sure this is fresh" signal). Halls/tables state itself
  /// is already live via the constructor's stream subscriptions — this only
  /// ever asks `SyncEngine` for an extra pass; [force] bypasses its backoff
  /// for an explicit manual refresh (e.g. right after a settings-screen
  /// CRUD action), matching §5's "Manual retry" trigger category rather than
  /// the write-commit path §5 explicitly forbids awaiting on.
  Future<void> getHalls({bool force = false}) async {
    if (force) {
      await inject<SyncEngine>().tick(force: true);
    } else {
      unawaited(inject<SyncEngine>().tick());
    }
  }

  Future<void> loadAllHallsTables({bool force = false}) => getHalls(force: force);

  Future<void> refreshTables({bool force = false}) => getHalls(force: force);

  void setSelectedHallId(String id) {
    if (state.selectedHallId == id) return;
    emit(state.copyWith(selectedHallId: id));
    _watchTablesForSelection();
  }

  @override
  Future<void> close() {
    _lanSub?.cancel();
    _hallsSub?.cancel();
    _tablesSub?.cancel();
    return super.close();
  }
}
