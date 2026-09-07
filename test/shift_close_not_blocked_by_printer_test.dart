/// Closing a shift must not wait on a printer.
///
/// `ShiftBloc._closeShift` used to `await _printShiftClose(...)` before writing
/// the close, which put a network printer on the critical path of a cash
/// operation. A close-check printer that is switched off, or on an address it
/// no longer holds, does not refuse the connection — it never answers, so
/// `Socket.connect` waits out its full timeout. `PrinterConfig.timeoutMs`
/// defaults to 10s and `PrinterService._connectAndPrint` retries twice with a
/// 1s backoff between attempts, so the worst case is roughly
///
///     3 × 10s (connect timeouts) + 2 × 1s (backoff) ≈ 32s
///
/// of spinner before the shift was even recorded as closed locally. The print
/// queue's 450ms caller budget is no help: `_armCallerBudget` is armed only on
/// the relay path, and a printer that is unowned — which every row is until
/// owners are assigned — takes the local path instead.
///
/// Waiting also buys nothing. `PrintQueueService.submitJob` persists the job
/// before dispatching, so an un-awaited receipt still survives a crash and stays
/// retryable, and `printShiftCloseReceipt` catches its own failures and raises
/// the printer toast itself.
///
/// This is a source guard rather than a behavioural one because driving
/// `_closeShift` needs a `BuildContext`, a `UserBloc` and a printer — the same
/// reason `branch_shift_test.dart` builds its rows by hand. What is being
/// protected is an ordering, and the ordering is legible in the source.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String closeShiftBody;

  setUpAll(() {
    final source = File(
      'lib/features/view/main/presentation/cubit/shift/shift_bloc.dart',
    ).readAsStringSync();

    const start = 'Future<void> _closeShift(';
    final from = source.indexOf(start);
    expect(from, isNot(-1),
        reason: 'ShiftBloc._closeShift has been renamed — update this guard');

    // Up to the next method at the same indentation, which is enough to bound
    // the handler without parsing Dart.
    final rest = source.substring(from);
    final end = rest.indexOf('\n  void _updateCardSum(');
    expect(end, isNot(-1),
        reason: 'the method after _closeShift changed — update this guard');

    // Comments are stripped first: this handler's own doc quotes the old
    // `await _printShiftClose(...)` line to explain why it went away, and a
    // guard that reads prose would fire on the explanation.
    closeShiftBody = rest
        .substring(0, end)
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  });

  test('the receipt is not awaited', () {
    expect(
      closeShiftBody.contains('await _printShiftClose('),
      isFalse,
      reason: 'awaiting the close receipt puts an unreachable printer\'s '
          'socket timeout (~32s) in front of the cashier before the shift is '
          'recorded as closed',
    );
  });

  test('the receipt is still requested', () {
    expect(
      closeShiftBody.contains('unawaited(_printShiftClose('),
      isTrue,
      reason: 'the close receipt is the paper record of the drawer — it must '
          'still be raised, just not waited on',
    );
  });

  test('the close is durable before the receipt is raised', () {
    final write = closeShiftBody.indexOf('_writer.write(');
    final print = closeShiftBody.indexOf('_printShiftClose(');

    expect(write, isNot(-1), reason: 'the close write disappeared');
    expect(print, isNot(-1), reason: 'the close receipt disappeared');
    expect(
      write < print,
      isTrue,
      reason: 'the shift close must reach the outbox before the receipt is '
          'raised, so a crash mid-print cannot lose the close itself',
    );
  });
}
