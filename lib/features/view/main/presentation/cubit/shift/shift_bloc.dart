import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/db/branch_shift_query.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/outbox/branch_shift_outbox.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/branch_shift/branch_shift_model.dart';

part 'shift_event.dart';
part 'shift_state.dart';
part 'shift_bloc.freezed.dart';

/// The venue's shift — one per branch, shared by every terminal in it.
///
/// **What changed and why.** This bloc used to keep the active shift in
/// `SharedPreferences`, privately, on each terminal. Nothing was shared, so
/// nothing could agree: a two-till cafe had two "current" shifts with two
/// opening floats, the second till showed no shift until its own cashier
/// opened one, and closing on one till left the other still trading. There was
/// no query, anywhere, that could say what the branch's shift was.
///
/// The shift is now a replicated row (`branch_shifts`), which makes the
/// terminals agree by construction rather than by convention:
///
/// * **Reads** come from the replica through [BranchShiftQuery], and this bloc
///   *watches* it. A peer's open or close lands in the local database — over
///   the LAN in the same instant, or from `/sync/pull` later — and the screen
///   updates without anyone reloading anything.
/// * **Writes** go through [LocalWriter], which commits the row and queues the
///   operation in one transaction and broadcasts the row to every LAN peer as
///   it does. So the till beside this one sees the shift open before the server
///   has heard of it, which is the case the venue actually cares about: the
///   internet is down and there are customers.
/// * **Arbitration** — two terminals opening offline at the same moment — is
///   settled by the server when the queue drains, and the loser converges onto
///   the winner's row automatically (see `branch_shift_outbox.dart`). No shift
///   is lost and no cashier is shown an error, because neither of them did
///   anything wrong.
///
/// Still local-first, exactly as before: nothing here awaits the network, and
/// a genuine server-side rejection surfaces through the outbox's quarantine
/// list rather than synchronously on screen.
class ShiftBloc extends Bloc<ShiftEvent, ShiftState> {
  final PrinterService _printerService;
  final BranchShiftQuery _shifts;
  final LocalWriter _writer;

  /// Live subscription to the branch's shift row.
  ///
  /// This is what makes one terminal's open visible on all the others. Without
  /// it the row would still arrive — replication does not need a listener — but
  /// this bloc would not notice until something else happened to rebuild it,
  /// which is the "the other till still shows no shift" complaint in a
  /// different costume.
  StreamSubscription<Map<String, dynamic>?>? _watch;

  ShiftBloc({
    required PrinterService printerService,
    required BranchShiftQuery shifts,
    required LocalWriter writer,
  })  : _printerService = printerService,
        _shifts = shifts,
        _writer = writer,
        super(const ShiftState()) {
    on<_Started>(_started);
    on<_CheckShift>(_checkShift);
    on<_UpdateCashSum>(_updateCashSum);
    on<_UpdateCardSum>(_updateCardSum);
    on<_UpdateSumType>(_updateSumType);
    on<_OpenShift>(_openShift);
    on<_CloseShift>(_closeShift);
    on<_PrintShiftReport>(_printShiftReport);
    on<_ShiftRowChanged>(_shiftRowChanged);
  }

  @override
  Future<void> close() async {
    await _watch?.cancel();
    return super.close();
  }

  /// The branch this terminal trades in.
  ///
  /// The same source the LAN hub authenticates peers against
  /// (`LanHubService._validateIncomingAuth`), so a terminal cannot be watching
  /// one branch's shift while exchanging rows with another's.
  String get _branchId =>
      navigatorKey.currentContext?.read<UserBloc>().state.userMOdel?.branchId ??
      '';

  String get _userId =>
      navigatorKey.currentContext?.read<UserBloc>().state.userMOdel?.id ?? '';

  BranchShiftModel? _readActive() {
    final row = _shifts.activeShift(_branchId);
    if (row == null) return null;
    try {
      return BranchShiftModel.fromJson(row);
    } catch (_) {
      // A row we cannot parse is not a shift we can trade under. Treating it as
      // "no shift" sends the cashier to the open screen, which is recoverable;
      // treating it as a shift would put the till in a state no screen can
      // describe.
      return null;
    }
  }

  void _listen() {
    _watch?.cancel();
    final branchId = _branchId;
    if (branchId.isEmpty) return;
    _watch = _shifts.watchActiveShift(branchId).listen(
      (_) {
        if (!isClosed) add(const ShiftEvent.shiftRowChanged());
      },
      onError: (_) {},
    );
  }

  /// Re-reads the shift after the row changed underneath us — a peer opened or
  /// closed it, or the outbox reconciled this terminal's own row onto the one
  /// that won.
  void _shiftRowChanged(_ShiftRowChanged event, Emitter<ShiftState> emit) {
    final active = _readActive();
    if (active?.id == state.shift?.id) return;
    emit(state.copyWith(shift: active));
  }

  /// Prints the close receipt for [shift], with the counts held in [s].
  ///
  /// [shift] is passed rather than read back off `s.shift` because the two can
  /// differ: `_closeShift` falls back to the replica when the bloc's own state
  /// has no shift (a peer opened it and this bloc had not caught up). Reading
  /// the state here meant that fallback closed the shift with no receipt
  /// printed at all — the one artefact the cashier is actually accountable for.
  Future<void> _printShiftClose(BranchShiftModel shift, ShiftState s) async {
    final ctx = navigatorKey.currentContext;
    final name = ctx?.read<UserBloc>().state.userMOdel?.fullName ?? '';
    await _printerService.printShiftCloseReceipt(
      shiftId: shift.id,
      openedAt: shift.openedAt,
      // What the cashier actually counted on the numpad (`_updateCardSum`),
      // not a literal zero. The receipt is the paper record of the drawer at
      // close; printing 0 on every shift made it worthless as one.
      closingCard: int.tryParse(s.cardSum) ?? 0,
      cashierLabel: name.isEmpty ? (shift.openedBy ?? shift.id) : name,
    );
  }

  Future<void> _printShiftReport(
    _PrintShiftReport event,
    Emitter<ShiftState> emit,
  ) async {
    final shift = state.shift ?? _readActive();
    if (shift == null) return;
    await _printShiftClose(shift, state);
  }

  /// Opens the branch's shift.
  ///
  /// The id is invented here and kept: the receipt printed a second later names
  /// it, so it cannot be a placeholder the server later replaces. `create`
  /// rather than `write` because the row is provisional until the server
  /// confirms it — that is what lets the drainer swap this terminal's row for
  /// the winning one, in the rare case two terminals opened at once offline,
  /// without the cashier seeing anything happen.
  ///
  /// Guarded against a second open: if the branch already has a shift — this
  /// terminal's or a peer's, arrived over the LAN a moment ago — the existing
  /// one is adopted instead of a second row being written. The server enforces
  /// this too; doing it here as well is what stops the UI from ever showing a
  /// shift that is about to be reconciled away.
  Future<void> _openShift(_OpenShift event, Emitter<ShiftState> emit) async {
    emit(state.copyWith(status: Status.LOADING));

    final existing = _readActive();
    if (existing != null) {
      _goToMain();
      showSuccessMessage(
        navigatorKey.currentContext!,
        "Smena allaqachon ochilgan",
      );
      emit(state.copyWith(status: Status.SUCCESS, shift: existing));
      return;
    }

    final branchId = _branchId;
    if (branchId.isEmpty) {
      // Without a branch there is nothing to open a shift *for*, and a row
      // written under an empty branch id would be invisible to every read.
      emit(
        state.copyWith(
          status: Status.ERROR,
          failure: const ServerFailure(),
        ),
      );
      return;
    }

    final id = generateUuidV4();
    final now = DateTime.now();
    final openCash = int.tryParse(state.cashSum) ?? 0;
    final openCard = int.tryParse(state.cardSum) ?? 0;
    final openedBy = _userId;

    final row = <String, dynamic>{
      'id': id,
      'branch_id': branchId,
      'opened_by': openedBy.isEmpty ? null : openedBy,
      'closed_by': null,
      'opened_at': now.toUtc().toIso8601String(),
      // Explicitly null rather than absent: `closed_at` is a promoted column
      // and the active-shift query is `closed_at IS NULL`, so it has to be
      // written, not merely left out.
      'closed_at': null,
      'opening_cash': openCash.toString(),
      'opening_card': openCard.toString(),
      'closing_cash': null,
      'closing_card': null,
    };

    _writer.create(
      entity: kBranchShiftEntity,
      id: id,
      row: row,
      // `opened_by` is deliberately absent from the request: the backend takes
      // it from the JWT, so a queued open is attributed to whoever's session
      // drains it — the same rule the per-register open followed.
      request: {
        'id': id,
        'opening_cash': openCash.toString(),
        'opening_card': openCard.toString(),
      },
    );

    _goToMain();
    if (emit.isDone) return;
    showSuccessMessage(navigatorKey.currentContext!, "Smena ochildi");
    emit(
      state.copyWith(
        status: Status.SUCCESS,
        shift: _readActive(),
        cardSum: '0',
        cashSum: '0',
      ),
    );
  }

  /// Closes the branch's shift — for the whole branch, not this terminal.
  ///
  /// A merge write, not a whole-row one: the stored row keeps `opened_at`, the
  /// opening float and the id it was created with, and only the four closing
  /// fields are laid over it. Writing the whole row instead would mean this
  /// terminal's idea of the opening float overwrites the one the terminal that
  /// actually opened the shift recorded.
  ///
  /// The local commit takes effect immediately — `closed_at` is set, so
  /// [BranchShiftQuery.activeShift] stops returning it — and broadcasts to
  /// every LAN peer, so the other tills stop trading under it at the same
  /// moment rather than whenever they next reach the server.
  Future<void> _closeShift(_CloseShift event, Emitter<ShiftState> emit) async {
    final shift = state.shift ?? _readActive();
    if (shift == null) return;

    emit(state.copyWith(status: Status.LOADING));

    final closingCash = state.cashSum;
    final closingCard = state.cardSum;
    final closedBy = _userId;

    // Snapshot before the SUCCESS emit below zeroes the counted sums, since
    // the receipt is built after that point.
    final counted = state;

    _writer.write(
      entity: kBranchShiftEntity,
      id: shift.id,
      action: kBranchShiftClose,
      merge: true,
      row: {
        'id': shift.id,
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'closed_by': closedBy.isEmpty ? null : closedBy,
        'closing_cash': closingCash,
        'closing_card': closingCard,
      },
      request: {
        'closing_cash': closingCash,
        'closing_card': closingCard,
      },
    );

    // Printing is deliberately NOT awaited, and runs after the close is
    // durable rather than before it.
    //
    // It used to gate the whole thing: `await _printShiftClose(...)` ran first,
    // and a close-check printer that is switched off or on a stale IP does not
    // refuse the connection — it simply never answers, so `Socket.connect`
    // waits out its full timeout. `PrinterConfig.timeoutMs` defaults to 10s and
    // `_connectAndPrint` retries twice with a 1s backoff, so the cashier stood
    // in front of a spinner for up to ~32s before the shift was even recorded
    // as closed. The print queue's 450ms caller budget does not help here: it
    // is armed only on the relay path, and a printer that is unowned — which
    // every row is until owners are assigned — takes the local path instead.
    //
    // Nothing is lost by not waiting. `PrintQueueService.submitJob` persists
    // the job to its Hive box before dispatching, so the receipt survives a
    // crash and stays retryable, and `printShiftCloseReceipt` already catches
    // its own failures and raises the printer toast itself.
    unawaited(_printShiftClose(shift, counted));

    if (emit.isDone) return;
    showSuccessMessage(
      navigatorKey.currentContext!,
      'Smena yopildi — internet kelganda yakunlanadi.',
    );
    emit(
      state.copyWith(
        status: Status.SUCCESS,
        shift: null,
        cardSum: '0',
        cashSum: '0',
      ),
    );
  }

  void _updateCardSum(_UpdateCardSum event, emit) {
    if (int.tryParse(event.value) != null) {
      String value = state.cardSum == '0'
          ? event.value
          : state.cardSum + event.value;
      emit(state.copyWith(cardSum: value));
    } else if (event.value == "delete") {
      String value = state.cardSum.length == 1
          ? '0'
          : state.cardSum.substring(0, state.cardSum.length - 1);
      emit(state.copyWith(cardSum: value));
    }
  }

  void _updateCashSum(_UpdateCashSum event, emit) {
    if (int.tryParse(event.value) != null) {
      String value = state.cashSum == '0'
          ? event.value
          : state.cashSum + event.value;
      emit(state.copyWith(cashSum: value));
    } else if (event.value == "delete") {
      String value = state.cashSum.length == 1
          ? '0'
          : state.cashSum.substring(0, state.cashSum.length - 1);
      emit(state.copyWith(cashSum: value));
    }
  }

  void _updateSumType(_UpdateSumType event, emit) {
    if (state.sum != event.type) {
      emit(state.copyWith(sum: event.type));
    }
  }

  /// Local-only, as before — but "local" now means the branch's row rather than
  /// this terminal's private note, so a cashier arriving at a till that has
  /// never opened a shift finds the venue's shift already open on it.
  Future<void> _checkShift(_CheckShift event, Emitter<ShiftState> emit) async {
    emit(state.copyWith(status: Status.LOADING));
    _listen();
    final active = _readActive();
    if (active == null) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Navigator.pushNamed(ctx, AppRoutes.closeShiftScreen);
      }
    }
    if (emit.isDone) return;
    emit(state.copyWith(status: Status.SUCCESS, shift: active));
  }

  void _started(_Started event, Emitter<ShiftState> emit) {
    _listen();
    emit(ShiftState(shift: _readActive()));
  }

  void _goToMain() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      ctx,
      AppRoutes.mainScreen,
      (router) => true,
    );
  }
}
