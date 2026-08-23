import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/timer_shift_outbox.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/shift/shift_response_model.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'shift_event.dart';
part 'shift_state.dart';
part 'shift_bloc.freezed.dart';

/// offline-first-target-architecture.md §4/§8 Phase 2. `_openShift`/
/// `_closeShift` are local-first, always — a single local commit (write the
/// local shift record + enqueue the outbox op) that returns without
/// awaiting the network, same shape every other write in this app now has.
/// Previously both awaited the real `OpenShiftUsecase`/`CloseShiftUsecase`
/// call first and only fell back to the queue on a connectivity-classified
/// failure; a genuine validation rejection (e.g. "already has an open
/// shift") was therefore visible synchronously. That synchronous rejection
/// is gone now — a real conflict surfaces later via the outbox's quarantine
/// list (§12 rule 5's "deliberate fallback for genuinely ambiguous cases"),
/// not as an immediate on-screen error. Flagged in
/// EXECUTION_CONCERNS.md as a real, visible behavior change worth a second
/// look, not something decided silently.
///
/// `_checkShift` is local-only now (CLIENT_FACING_OFFLINE_PLAN.md §1): the
/// local shift record is primary and no network call is initiated from this
/// bloc at all. If shift state can drift from the server, reconciling it is
/// the sync engine's job in the background, not this bloc's — flagged in
/// EXECUTION_CONCERNS.md as a cross-side dependency, since no such
/// reconciliation pass exists on that side yet.
class ShiftBloc extends Bloc<ShiftEvent, ShiftState> {
  final SharedPreferences _prefs;
  final AppTokenStorage _tokenStorage;
  final PrinterService _printerService;
  //
  ShiftBloc({
    required SharedPreferences prefs,
    required AppTokenStorage tokenStorage,
    required PrinterService printerService,
  }) : _prefs = prefs,
       _tokenStorage = tokenStorage,
       _printerService = printerService,
       super(const ShiftState()) {
    on<_Started>(_started);
    on<_CheckShift>(_checkShift);
    on<_UpdateCashSum>(_updateCashSum);
    on<_UpdateCardSum>(_updateCardSum);
    on<_UpdateSumType>(_updateSumType);
    on<_OpenShift>(_openShift);
    on<_CloseShift>(_closeShift);
    on<_PrintShiftReport>(_printShiftReport);
  }

  /// Public because the brand-switch wipe (`LoginDataScopeService`) must
  /// clear this record too — with `_checkShift` local-only, a stale shift
  /// from the previous brand would otherwise be presented as active.
  static const String localShiftPrefsKey = 'pos_local_active_shift';

  ShiftResponseModel? _readLocalShift() {
    try {
      final raw = _prefs.getString(localShiftPrefsKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return ShiftResponseModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLocalShift(ShiftResponseModel shift) async {
    try {
      await _prefs.setString(localShiftPrefsKey, jsonEncode(shift.toJson()));
    } catch (_) {}
  }

  Future<void> _clearLocalShift() async {
    try {
      await _prefs.remove(localShiftPrefsKey);
    } catch (_) {}
  }

  static String? _jwtClaim(String jwt, String key) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final obj = jsonDecode(decoded);
      if (obj is! Map) return null;
      final v = obj[key];
      if (v == null) return null;
      return v.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String> _resolveCashRegisterId() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) return '';
    return _jwtClaim(token, 'cash_register_id') ?? '';
  }

  String _resolveCashierId() {
    final ctx = navigatorKey.currentContext;
    final id = ctx?.read<UserBloc>().state.userMOdel?.id ?? '';
    return id;
  }

  Future<void> _printShiftCloseFromState(ShiftState s) async {
    final shift = s.shift;
    if (shift == null) return;
    final ctx = navigatorKey.currentContext;
    final name = ctx?.read<UserBloc>().state.userMOdel?.fullName ?? '';
    await _printerService.printShiftCloseReceipt(
      shiftId: shift.id,
      openedAt: shift.openedAt,
      closingCard: 0,
      cashierLabel: name.isEmpty ? shift.cashierId : name,
    );
  }

  Future<void> _printShiftReport(
    _PrintShiftReport event,
    Emitter<ShiftState> emit,
  ) async {
    await _printShiftCloseFromState(state);
  }

  /// Cash-register id is both the operation's `entityId` and, through it, its
  /// chain key — the shift's own id isn't known/valid yet for an
  /// offline-opened (`local_...`) shift, and even for a real shift we don't
  /// want the replay depending on an id that might be stale by the time
  /// connectivity returns. The close handler resolves the register's currently
  /// active shift instead (`timer_shift_outbox.dart`).
  ///
  /// Sharing that key with the open is what keeps a close from overtaking the
  /// open it belongs to: `OutboxDrainer` holds a whole chain back for the pass
  /// once one of its operations fails, and within a pass the queue replays in
  /// enqueue order.
  ///
  /// `enqueueOnly` rather than `write`: the active shift lives in
  /// `SharedPreferences`, not the replica (the plan's one deliberate
  /// non-database exception), so there is no local row for the writer to
  /// commit alongside the operation.
  void _enqueueCloseShift(String cashRegisterId) {
    inject<LocalWriter>().enqueueOnly(
      entity: kShiftEntity,
      action: kShiftClose,
      entityId: cashRegisterId,
      request: {
        'cash_register_id': cashRegisterId,
        'closing_cash': '0',
        'closing_card': '0',
      },
    );
  }

  /// §4/§9: local-first, always. `local_...` id stands in until sync
  /// replaces it — the close handler resolves the real shift by
  /// `cash_register_id` at replay time, not by this id.
  /// No `AuthCubit.logout()` call here, unlike the old synchronous-success
  /// path — that immediate-logout behavior only ever fired when the online
  /// call had already been confirmed by the server; since every close is
  /// now deferred to replay, this mirrors what the old *offline* branches
  /// already did (no logout), not the old online branch. Flagged in
  /// EXECUTION_CONCERNS.md — a real, visible UX change worth a second look.
  Future<void> _closeShift(_CloseShift event, Emitter<ShiftState> emit) async {
    final shift = state.shift;
    if (shift == null) return;

    emit(state.copyWith(status: Status.LOADING));
    await _printShiftCloseFromState(state);
    _enqueueCloseShift(shift.cashRegisterId);
    await _clearLocalShift();
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

  /// §4/§9: local-first, always — a synthetic `local_...` shift is written
  /// and the open queued unconditionally, no network await first. A real
  /// validation rejection (e.g. "already has an open shift" on this
  /// register) is no longer visible synchronously — see the class doc.
  Future<void> _openShift(_OpenShift evente, Emitter<ShiftState> emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final cashRegisterId = await _resolveCashRegisterId();
    final cashierId = _resolveCashierId();
    final openCash = int.tryParse(state.cashSum) ?? 0;
    final openCard = int.tryParse(state.cardSum) ?? 0;
    final now = DateTime.now();

    final local = ShiftResponseModel(
      id: 'local_${now.millisecondsSinceEpoch}',
      cashRegisterId: cashRegisterId,
      cashierId: cashierId,
      openedAt: now,
      openingCash: openCash,
      openinCard: openCard,
      createdAt: now,
      updatedAt: now,
    );
    await _writeLocalShift(local);
    // Same entityId/chain key as the close — see `_enqueueCloseShift`.
    // `cashier_id` is deliberately absent: the backend takes it from the JWT,
    // so it is resolved by whoever's session drains the queue.
    inject<LocalWriter>().enqueueOnly(
      entity: kShiftEntity,
      action: kShiftOpen,
      entityId: cashRegisterId,
      request: {
        'cash_register_id': cashRegisterId,
        'opening_cash': openCash.toString(),
        'opening_card': openCard.toString(),
      },
    );
    if (emit.isDone) return;
    Navigator.pushNamedAndRemoveUntil(
      navigatorKey.currentContext!,
      AppRoutes.mainScreen,
      (router) => true,
    );
    showSuccessMessage(
      navigatorKey.currentContext!,
      "Smena ochildi",
    );
    emit(
      state.copyWith(
        status: Status.SUCCESS,
        shift: local,
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

  /// CLIENT_FACING_OFFLINE_PLAN.md §1: the local shift record is primary —
  /// no network call is initiated from here at all. The previous
  /// server-first check (with local fallback) is gone; "no local shift" now
  /// routes to the open-shift flow exactly like the server's "no active
  /// shift" answer used to.
  Future<void> _checkShift(_CheckShift event, Emitter<ShiftState> emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final local = _readLocalShift();
    if (local == null) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Navigator.pushNamed(ctx, AppRoutes.closeShiftScreen);
      }
    }
    if (emit.isDone) return;
    emit(state.copyWith(status: Status.SUCCESS, shift: local));
  }

  void _started(_Started event, Emitter<ShiftState> emit) {
    final local = _readLocalShift();
    emit(ShiftState(shift: local));
  }
}
