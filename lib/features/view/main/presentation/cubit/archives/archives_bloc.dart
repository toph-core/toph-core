import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/features/view/main/data/models/archives_filter_request/archives_filter_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_summary_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/archives_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';
import 'package:rxdart/rxdart.dart';

part 'archives_event.dart';
part 'archives_state.dart';
part 'archives_bloc.freezed.dart';

/// The Orders screen, as one live query over the local replica.
///
/// **What this used to be, and why it lost checks.** The screen had two ways
/// to get rows: a subscription to a single hard-coded view (unfiltered,
/// "today", 20 rows) and a one-shot fetch for everything else. Because the
/// two could disagree, the subscription had to be suppressed whenever a
/// filter, a search or a second page was active — the `_isDefaultView` guard.
/// And because nothing ever asked for a second page, the 20 rows the
/// subscription carried were the only bills the terminal could show: a venue's
/// 21st bill of the day was unreachable in every filter while sitting in both
/// the replica and the backend, which reads from behind the counter as a paid
/// check having been deleted.
///
/// **What it is now.** One subscription, over whatever the operator is
/// actually looking at. A filter change, a search, or reaching the bottom of
/// the list rebuilds that subscription; nothing else does anything. The window
/// grows by [kArchivesPageSize] per load and re-reads from offset 0 rather
/// than appending, so a bill that arrives from the feed mid-scroll lands in
/// its right place instead of shifting everything below it.
///
/// **Nothing here awaits the network — there is no network here.** Every read
/// is `LocalDatabase`, and the screen renders whatever the replica holds,
/// online or off. The one call that touches `SyncEngine` is a fire-and-forget
/// nudge; no frame, no list and no error state depends on it returning, or on
/// it existing at all.
class ArchivesBloc extends Bloc<ArchivesEvent, ArchivesState> {
  final ArchivesLocalRepository _archivesRepository;

  /// Optional so every existing construction of this bloc keeps working; a
  /// bloc built without it simply never reports a running table charge, and
  /// the panel falls back to the server's `table_amount`.
  final TableTimerLocalRepository? _tableTimers;

  StreamSubscription<ArchivesResponseEntity?>? _archivesSub;
  StreamSubscription<ArchivesSummaryEntity>? _summarySub;

  /// Follows the *selected* bill only, and is torn down and rebuilt on every
  /// selection — one row's timer, not the venue's.
  StreamSubscription<TableTimerResponse?>? _tableChargeSub;

  /// Set the instant [close] begins, and checked before every dispatch below.
  ///
  /// `isClosed` is not enough on its own: `Bloc.close` shuts the event sink
  /// first and only flips `isClosed` at the end, so there is a window in which
  /// the bloc reports itself open and yet throws on `add`. A query result
  /// landing in that window — the replica is written constantly, and this
  /// screen is closed by an ordinary back press — would take the throw.
  bool _closing = false;

  ArchivesBloc({
    required ArchivesLocalRepository archivesRepository,
    TableTimerLocalRepository? tableTimers,
  }) : _archivesRepository = archivesRepository,
       _tableTimers = tableTimers,
       super(ArchivesState.initial()) {
    on<_Started>(_onStarted);
    on<_StatusChanged>(_onStatusChanged);
    on<_ArchivesUpdated>(_onArchivesUpdated);
    on<_SummaryUpdated>(_onSummaryUpdated);
    on<_LoadMore>(_onLoadMore);
    on<_FailureChanged>(_onFailureChanged);
    on<_SearchChanged>(_onSearchChanged);
    on<_SelectArchive>(_selectArchive);
    on<_GetArchiveDetail>(_getArchiveDetail);
    on<_TableChargeUpdated>(_onTableChargeUpdated);
    on<_TableSegmentsUpdated>(_onTableSegmentsUpdated);
    on<_UpdateFilterType>(_updateFilterType);
    on<_UpdateFilterDateRange>(_updateFilterDateRange);
    on<_UpdateStatusFilter>(_updateStatusFilter);
    on<_SearchByArchiveNum>(
      _onSearchByArchiveNum,
      transformer: (events, mapper) => events
          .debounceTime(const Duration(milliseconds: 300))
          .switchMap(mapper),
    );
  }

  /// The query behind everything on screen: the operator's filters, plus a
  /// window sized to how far they have scrolled.
  ///
  /// Always `offset: 0` with a growing `limit`. Paging by offset would be one
  /// fewer row to read, and would also mean each page is a snapshot of a
  /// different instant — with bills arriving from the feed while the operator
  /// scrolls, a row can cross a page boundary and be shown twice or skipped.
  /// Re-reading the window keeps the list one consistent answer.
  ArchivesFilterRequestEntity get _filter => _filterWith(state.loadedLimit);

  ArchivesFilterRequestEntity _filterWith(int limit) =>
      ArchivesFilterRequestModel(
        archiveNum: int.tryParse(state.textController?.text.trim() ?? ''),
        filterType: state.filterType,
        startDate: state.startFilterDate,
        endDate: state.endFilterDate,
        billStatus: state.statusFilter,
        pagination: PaginationRequestModel(limit: limit),
      );

  /// Every bill in the current window, however far the list has scrolled.
  ///
  /// For the CSV export, which used to serialise `state.archives` — so it
  /// exported the page rather than the window, and silently produced a
  /// different file depending on how far the operator had scrolled before
  /// pressing it. One local query, no network.
  Future<List<ArchiveEntity>> archivesInWindow() async {
    final total = state.totalCount;
    if (total <= 0) return const [];
    final result = await _archivesRepository.getArchives(_filterWith(total));
    return result.fold(
      // A failure here is a malformed replica row, not an empty window: fall
      // back to what is on screen rather than exporting nothing.
      (_) => state.archives?.archives ?? const [],
      (r) => r.archives,
    );
  }

  /// Points both subscriptions at the current [_filter].
  ///
  /// Called on every change to what is being looked at. The old code path this
  /// replaces — cancel the stream, fetch once, hope the two agree — is what
  /// the `_isDefaultView` guard existed to paper over.
  void _resubscribe() {
    _archivesSub?.cancel();
    _summarySub?.cancel();
    // `_tableChargeSub` is deliberately NOT cancelled here. It tracks the
    // *selected bill's* timer, which has nothing to do with which archives are
    // listed — and nothing in this bloc clears `selectArchive` on a filter
    // change, so the bill stays on screen. Cancelling it here (without ever
    // re-arming it, since only `_watchTableCharge` does that) froze the running
    // table charge on a still-selected bill after any load-more, filter,
    // search or date-range change. Its lifetime belongs to the selection:
    // `_watchTableCharge` cancels the previous one, and `close()` cancels the
    // last.
    final filter = _filter;

    _archivesSub = _archivesRepository
        .watchArchives(filter)
        .listen(
          (archives) {
            if (isClosed || archives == null) return;
            add(ArchivesEvent.archivesUpdated(archives));
          },
          // A query that throws is a malformed replica row, not a connection
          // problem. Surfacing it beats the previous behaviour, where the error
          // reached the zone unhandled and the list simply stopped updating.
          onError: (Object e) {
            if (isClosed) return;
            add(ArchivesEvent.failureChanged(MessageFailure('$e')));
          },
        );

    _summarySub = _archivesRepository.watchSummary(filter).listen((summary) {
      if (isClosed) return;
      add(ArchivesEvent.summaryUpdated(summary));
    }, onError: (Object _) {});
  }

  void _onStarted(_Started event, Emitter<ArchivesState> emit) {
    emit(
      state.copyWith(
        textController: state.textController ?? TextEditingController(),
        status: Status.LOADING,
        failure: null,
      ),
    );

    // Synchronous first paint, so opening the screen never shows a spinner
    // over data the terminal already has. The subscription below re-emits the
    // same window a microtask later and every time it changes after that.
    final hydrated = _archivesRepository.getHydratedArchives();
    if (hydrated != null && !_closing && !isClosed) {
      add(ArchivesEvent.archivesUpdated(hydrated));
    }
    _resubscribe();

    // Fire-and-forget: ask the sync engine to catch up sooner than its next
    // tick. Deliberately not awaited and deliberately tolerant of a missing
    // registration — the screen has already rendered from the replica, and
    // nothing below this line depends on the pass, its result or its timing.
    try {
      unawaited(inject<SyncEngine>().tick());
    } catch (e) {
      if (kDebugMode) debugPrint('[ArchivesBloc] no SyncEngine to nudge: $e');
    }
  }

  Future<void> _onArchivesUpdated(
    _ArchivesUpdated event,
    Emitter<ArchivesState> emit,
  ) async {
    final archives = event.archives.archives;
    emit(
      state.copyWith(
        archives: event.archives,
        status: Status.SUCCESS,
        isLoadingMore: false,
        failure: null,
      ),
    );

    // Keep a selection on screen: the first row when there is none, and again
    // when the row that was selected has left the window (a filter changed
    // under it, or its bill was voided).
    if (archives.isEmpty) return;
    final selectedId = state.selectArchive?.id;
    final stillListed =
        selectedId != null && archives.any((a) => a.id == selectedId);
    if (!stillListed) await _select(archives.first, emit);
  }

  void _onSummaryUpdated(_SummaryUpdated event, Emitter<ArchivesState> emit) {
    emit(state.copyWith(summary: event.summary));
  }

  /// Grows the window by one page. Dispatched by the list on reaching its end.
  void _onLoadMore(_LoadMore event, Emitter<ArchivesState> emit) {
    if (state.isLoadingMore) return;
    final loaded = state.archives?.archives.length ?? 0;
    // Nothing left to ask for: the window is entirely on screen. `total` comes
    // from the same `WHERE` as the rows, so the two cannot disagree.
    if (loaded >= (state.archives?.pagination.total ?? 0)) return;
    // The last read came back short of what was asked for, so a bigger limit
    // would return the same rows. Guards against a scroll storm at the bottom.
    if (loaded < state.loadedLimit) return;

    emit(
      state.copyWith(
        loadedLimit: state.loadedLimit + kArchivesPageSize,
        isLoadingMore: true,
      ),
    );
    _resubscribe();
  }

  void _updateFilterType(_UpdateFilterType event, Emitter<ArchivesState> emit) {
    if (state.filterType == event.type) return;
    emit(
      state.copyWith(
        filterType: event.type,
        startFilterDate: null,
        endFilterDate: null,
        loadedLimit: kArchivesPageSize,
        isLoadingMore: false,
      ),
    );
    _resubscribe();
  }

  void _updateFilterDateRange(
    _UpdateFilterDateRange event,
    Emitter<ArchivesState> emit,
  ) {
    emit(
      state.copyWith(
        filterType: ArchivesFilterType.date,
        startFilterDate: _startOfDay(event.startDate),
        endFilterDate: _endOfDay(event.endDate),
        loadedLimit: kArchivesPageSize,
        isLoadingMore: false,
      ),
    );
    _resubscribe();
  }

  /// A picked range is two calendar *days*, and both are inclusive.
  ///
  /// `showDateRangePicker` returns midnight for each end, so passing its
  /// `end` through unchanged asked for "up to 00:00 on the last day" — the
  /// whole of the day the operator selected was excluded, which reads as the
  /// range simply not working for anything recent. Widening to the last
  /// instant of that day is what "to the 23rd" means to the person picking it.
  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  void _updateStatusFilter(
    _UpdateStatusFilter event,
    Emitter<ArchivesState> emit,
  ) {
    if (state.statusFilter == event.status) return;
    emit(
      state.copyWith(
        statusFilter: event.status,
        loadedLimit: kArchivesPageSize,
        isLoadingMore: false,
      ),
    );
    _resubscribe();
  }

  Future<void> _getArchiveDetail(
    _GetArchiveDetail event,
    Emitter<ArchivesState> emit,
  ) async {
    final selected = state.selectArchive;
    if (selected != null) await _loadDetail(selected.id, emit);
  }

  Future<void> _selectArchive(
    _SelectArchive event,
    Emitter<ArchivesState> emit,
  ) async {
    final archives = state.archives?.archives ?? const <ArchiveEntity>[];
    final index = archives.indexWhere((v) => v.id == event.id);
    if (index == -1) return;
    await _select(archives[index], emit);
  }

  /// Selects a bill and loads its detail, both inside the handler that decided
  /// to.
  ///
  /// Deliberately not `add(getArchiveDetail())`. Chaining one event onto
  /// another means the second is dispatched from inside the first, and a bloc
  /// closing at that moment — the screen popped while a row lands — has
  /// already shut its event sink while still reporting itself open, so the
  /// chained dispatch throws instead of being ignored. Awaiting the work here
  /// keeps it inside a handler that is provably still running.
  Future<void> _select(
    ArchiveEntity archive,
    Emitter<ArchivesState> emit,
  ) async {
    emit(state.copyWith(selectArchive: archive));
    await _loadDetail(archive.id, emit);
  }

  Future<void> _loadDetail(String id, Emitter<ArchivesState> emit) async {
    emit(
      state.copyWith(
        archiveStatus: Status.LOADING,
        selectArchiveDetail: null,
        selectedTableCharge: 0,
        selectedTableSegments: const [],
      ),
    );
    _watchTableCharge(id);
    final response = await _archivesRepository.getArchiveWithId(id);
    if (_closing || isClosed || emit.isDone) return;
    response.fold(
      (l) => emit(state.copyWith(archiveStatus: Status.ERROR, failure: l)),
      (r) => emit(
        state.copyWith(archiveStatus: Status.SUCCESS, selectArchiveDetail: r),
      ),
    );
  }

  /// Subscribes to the selected bill's local timer record.
  ///
  /// Stored amounts only — `final_amount` once the timer is frozen, otherwise
  /// `current_amount` — which is exactly what
  /// `PaymentBloc._hydrateTableChargeFromLocalTimer` reads, so the number the
  /// details panel shows is the number payment will charge. The per-second
  /// accrual the table badge renders is a display refinement and is
  /// deliberately not reproduced here.
  void _watchTableCharge(String orderId) {
    _tableChargeSub?.cancel();
    _tableChargeSub = null;

    final timers = _tableTimers;
    if (timers == null || orderId.isEmpty) return;

    _tableChargeSub = timers.watchTimer(orderId).listen(
      (timer) {
        if (_closing || isClosed || timer == null) return;
        final frozen = parseAmountToInt(timer.finalAmount);
        final amount = frozen > 0
            ? frozen
            : parseAmountToInt(timer.currentAmount);
        add(ArchivesEvent.tableChargeUpdated(amount));
        unawaited(_readTableSegments(orderId));
      },
      // A local timer that cannot be read must never take the panel down
      // with it — the bill's own totals are already on screen.
      onError: (_) {},
    );
  }

  void _onTableChargeUpdated(
    _TableChargeUpdated event,
    Emitter<ArchivesState> emit,
  ) {
    if (event.amount == state.selectedTableCharge) return;
    emit(state.copyWith(selectedTableCharge: event.amount));
  }

  /// Reads the active-period breakdown the local timer can account for.
  ///
  /// The details panel renders the server's `table_sessions` when it has
  /// them, but a bill that is still open usually has none on this terminal —
  /// which left the breakdown accordion with nothing to show for exactly the
  /// bills that were accruing a charge. `getBillDetails` synthesizes the same
  /// [TableSegment] shape from the local record, so the accordion renders the
  /// running periods offline, and the moment a server snapshot arrives it is
  /// simply preferred over this.
  Future<void> _readTableSegments(String orderId) async {
    final timers = _tableTimers;
    if (timers == null) return;

    final result = await timers.getBillDetails(orderId);
    if (_closing || isClosed) return;
    // Still the same selection? A fast click through the list can land this
    // after the operator has moved on.
    if (state.selectArchive?.id != orderId) return;

    final segments = result.fold(
      (_) => const <TableSegment>[],
      (details) => details.segments,
    );
    if (segments.isEmpty) return;
    add(ArchivesEvent.tableSegmentsUpdated(segments));
  }

  void _onTableSegmentsUpdated(
    _TableSegmentsUpdated event,
    Emitter<ArchivesState> emit,
  ) {
    emit(state.copyWith(selectedTableSegments: event.segments));
  }

  void _onStatusChanged(_StatusChanged event, Emitter<ArchivesState> emit) {
    emit(state.copyWith(status: event.status));
  }

  void _onFailureChanged(_FailureChanged event, Emitter<ArchivesState> emit) {
    emit(state.copyWith(failure: event.failure, status: Status.ERROR));
  }

  void _onSearchChanged(_SearchChanged event, Emitter<ArchivesState> emit) {
    emit(state.copyWith(textController: _applySearchText(event.value)));
  }

  TextEditingController _applySearchText(String value) {
    final controller = state.textController ?? TextEditingController();
    if (controller.text != value) {
      controller.value = controller.value.copyWith(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    return controller;
  }

  /// A bill-number search is just another filter, and resets the window.
  ///
  /// It used to re-request the list *without* resetting anything, so the
  /// pagination arithmetic of the moment was applied to the search: with a
  /// full page on screen the single matching bill was skipped by the offset
  /// and the screen reported nothing found for a check that was in the
  /// database. See `PaginationRequestModel.calculate`.
  void _onSearchByArchiveNum(
    _SearchByArchiveNum event,
    Emitter<ArchivesState> emit,
  ) {
    // Written straight onto the controller rather than dispatched as a
    // `searchChanged`. That event would only be handled *after* this one
    // returns, so the resubscription below would have queried with the
    // previous text — the search box would consistently be one keystroke
    // behind, and clearing it would not restore the list.
    final controller = _applySearchText(event.value);
    emit(
      state.copyWith(
        textController: controller,
        loadedLimit: kArchivesPageSize,
        isLoadingMore: false,
      ),
    );
    _resubscribe();
  }

  @override
  Future<void> close() {
    _closing = true;
    _archivesSub?.cancel();
    _summarySub?.cancel();
    // Cancelled here too, or one live timer subscription leaks per visit to the
    // archive screen — this bloc is a factory, so a new one is built each time.
    _tableChargeSub?.cancel();
    state.textController?.dispose();
    return super.close();
  }
}
