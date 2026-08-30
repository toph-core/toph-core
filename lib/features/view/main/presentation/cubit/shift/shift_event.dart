part of 'shift_bloc.dart';

@freezed
class ShiftEvent with _$ShiftEvent {
  const factory ShiftEvent.started() = _Started;
  const factory ShiftEvent.checkShift() = _CheckShift;

  /// The branch's shift row changed in the replica — a peer opened or closed
  /// it over the LAN, `/sync/pull` delivered it, or the outbox reconciled this
  /// terminal's own row onto the one that won an offline race.
  ///
  /// Raised by the bloc's own watch, never by a screen. It exists so the
  /// re-read happens on the event loop like every other state change rather
  /// than from inside a stream callback.
  const factory ShiftEvent.shiftRowChanged() = _ShiftRowChanged;
  const factory ShiftEvent.updateCashSum({required String value}) = _UpdateCashSum;
  const factory ShiftEvent.updateCardSum({required String value}) = _UpdateCardSum;
  const factory ShiftEvent.updateSumType({required ShiftSumType type}) = _UpdateSumType;
  const factory ShiftEvent.openShift() = _OpenShift;
  const factory ShiftEvent.closeShift() = _CloseShift;
  /// Joriy smena bo‘yicha hisobotni kassir printeriga (naqdsiz).
  const factory ShiftEvent.printShiftReport() = _PrintShiftReport;
}