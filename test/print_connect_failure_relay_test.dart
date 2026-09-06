/// A printer this terminal cannot reach is offered to the LAN before the
/// receipt is written off.
///
/// The venue this comes from has printer rows with no owner at all (the
/// deployed backend predates ownership), so every printer looks reachable to
/// every terminal: a kitchen ticket raised on the client dials the kitchen
/// printer across a network that does not route to it, burns its socket
/// timeout, and dies — while the hub, on the same switch as the printer, could
/// have printed it. A failed *connection* is the only signal available that
/// somebody else should try.
///
/// The safety line runs through the whole file: only a failure where **no
/// socket ever opened** may be relayed. A write that broke half way may have
/// put part of the ticket on paper, and handing those bytes to another
/// terminal is how a customer gets two receipts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/service/printer/print_dispatch_result.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_job.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A transport that fails the way a broken write does: something may have
/// reached the printer. Cannot be produced reliably with a real socket — a
/// server that accepts and hangs up mid-stream is a race — so the one thing
/// under test here, the flag, is stated directly.
class _MidWriteFailurePrinter extends PrinterService {
  _MidWriteFailurePrinter(super.storage);

  @override
  Future<PrintAttempt> printRenderedBytes(
    PrinterConfig config,
    List<int> bytes, {
    bool beep = true,
  }) async =>
      (ok: false, error: 'yozish uzildi', connectFailed: false);
}

/// A transport that fails before connecting, instantly — the real thing takes
/// a socket timeout, which is not what the timing test is measuring.
class _ConnectFailurePrinter extends PrinterService {
  _ConnectFailurePrinter(super.storage);

  @override
  Future<PrintAttempt> printRenderedBytes(
    PrinterConfig config,
    List<int> bytes, {
    bool beep = true,
  }) async =>
      (ok: false, error: 'Connection refused', connectFailed: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('print_connect_failure_test').path,
    );
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PrintJobAdapter());
    }
  });

  var boxCounter = 0;
  Future<Box<PrintJob>> freshBox() async {
    boxCounter++;
    return Hive.openBox<PrintJob>('print_connect_failure_test_$boxCounter');
  }

  Future<PrinterConfigStorage> terminal(
    String cashRegisterId, {
    List<PrinterSettingEntry> printers = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      'pos_last_auth_context': jsonEncode({
        'brand_id': 'brand-1',
        'cash_register_id': cashRegisterId,
      }),
    });
    final storage = PrinterConfigStorage(await SharedPreferences.getInstance());
    if (printers.isNotEmpty) {
      await storage.applyPrinterSettingsList(printers);
    }
    return storage;
  }

  Future<PrintQueueService> queueFor(
    PrinterConfigStorage storage, {
    required PrinterService printer,
    bool Function() isLanRelayPossible = _alwaysTrue,
    PrintAnnounceBroadcaster broadcastAnnounce = _noopAnnounce,
    PrintClaimBroadcaster broadcastClaim = _noopClaim,
    PrintGrantBroadcaster broadcastGrant = _noopGrant,
    PrintResultBroadcaster broadcastResult = _noopResult,
    Duration callerBudget = const Duration(seconds: 5),
    void Function(PrintJob job)? onLateFailure,
  }) async =>
      PrintQueueService(
        await freshBox(),
        printer,
        storage,
        await SharedPreferences.getInstance(),
        isLanRelayPossible: isLanRelayPossible,
        broadcastAnnounce: broadcastAnnounce,
        broadcastClaim: broadcastClaim,
        broadcastGrant: broadcastGrant,
        broadcastResult: broadcastResult,
        claimWait: const Duration(milliseconds: 60),
        lease: const Duration(milliseconds: 200),
        callerBudget: callerBudget,
        onLateFailure: onLateFailure,
      );

  PrinterSettingEntry unownedNetworkPrinter(int port) => PrinterSettingEntry(
        id: 'kitchen-1',
        ip: InternetAddress.loopbackIPv4.address,
        port: port,
        name: 'Oshxona',
        type: 'close_check',
        connectedEntityIds: const [],
        connectionType: 'cable',
        ownerCashRegisterId: '',
      );

  /// A port nothing is listening on — `connect` is refused immediately.
  Future<int> deadPort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  Future<ServerSocket> livePrinter() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    server.listen((s) => s.listen((_) {}));
    return server;
  }

  test('PrinterService says whether anything reached the printer', () async {
    // The distinction everything else here rests on, taken from a real socket.
    final storage = await terminal('till-A');
    final service = PrinterService(storage);

    final refused = await service.printRenderedBytes(
      PrinterConfig(
        ip: InternetAddress.loopbackIPv4.address,
        port: await deadPort(),
        connectionType: 'cable',
      ),
      [1, 2, 3],
      beep: false,
    );
    expect(refused.ok, isFalse);
    expect(refused.connectFailed, isTrue);

    final server = await livePrinter();
    final sent = await service.printRenderedBytes(
      PrinterConfig(
        ip: InternetAddress.loopbackIPv4.address,
        port: server.port,
        connectionType: 'cable',
      ),
      [1, 2, 3],
      beep: false,
    );
    expect(sent.ok, isTrue);
    expect(sent.connectFailed, isFalse);
  });

  test('a printer this terminal cannot reach is relayed and printed once',
      () async {
    // Both terminals hold the same unowned entry, under the same id. They are
    // in one process on one loopback interface, so "A cannot reach it, B can"
    // is expressed as the two copies of the entry naming different ports —
    // which is exactly the asymmetry a segmented venue network produces.
    final server = await livePrinter();
    const entryId = 'kitchen-1';

    final storageA = await terminal(
      'till-A',
      printers: [unownedNetworkPrinter(await deadPort())],
    );
    final storageB = await terminal(
      'till-B',
      printers: [unownedNetworkPrinter(server.port)],
    );

    late PrintQueueService queueA;
    late PrintQueueService queueB;
    var announced = 0;

    queueA = await queueFor(
      storageA,
      printer: PrinterService(storageA),
      broadcastAnnounce: ({
        required jobId,
        required jobType,
        required entryId,
        required payloadBase64,
      }) {
        announced++;
        queueB.onRemoteAnnounce(
          jobId: jobId,
          jobType: jobType,
          entryId: entryId,
          payloadBase64: payloadBase64,
        );
      },
      broadcastGrant: (jobId, t) => queueB.onRemoteGrant(jobId, t),
    );
    queueB = await queueFor(
      storageB,
      printer: PrinterService(storageB),
      broadcastClaim: queueA.onRemoteClaim,
      broadcastResult: queueA.onRemoteResult,
    );

    final r = await queueA.submitJob(
      storageA.getCloseCheckPrinter()!,
      [1, 2, 3],
      jobType: 'cashier',
    );

    expect(announced, 1, reason: 'A could not connect, so it asked the LAN');
    expect(r.ok, isFalse);
    expect(r.deferred, isTrue, reason: 'the till is told queued, not failed');

    await Future.delayed(const Duration(milliseconds: 300));
    expect(queueA.jobs.single.stateEnum, PrintJobState.printed);
    expect(queueA.jobs.single.claimedAt, isNotNull);
    expect(
      queueB.jobs,
      isEmpty,
      reason: 'B prints the relayed job, it does not raise one of its own',
    );
    expect(storageB.entryById(entryId), isNotNull);
  });

  test('a failure mid-write is never relayed', () async {
    // Part of that ticket may already be on paper. A second terminal printing
    // the same bytes is a second receipt, so this fails exactly as before.
    final storage = await terminal(
      'till-A',
      printers: [unownedNetworkPrinter(await deadPort())],
    );
    var announced = 0;
    final queue = await queueFor(
      storage,
      printer: _MidWriteFailurePrinter(storage),
      broadcastAnnounce: ({
        required jobId,
        required jobType,
        required entryId,
        required payloadBase64,
      }) =>
          announced++,
    );

    final r = await queue.submitJob(
      storage.getCloseCheckPrinter()!,
      [1, 2, 3],
      jobType: 'cashier',
    );

    expect(announced, 0);
    expect(r.ok, isFalse);
    expect(r.deferred, isFalse);
    expect(queue.jobs.single.stateEnum, PrintJobState.failed);
  });

  test('the fallback runs behind the released caller, not in front of it',
      () async {
    // The local socket attempt itself is unbounded today and this change does
    // not touch it; what must not be added in front of the till is the relay's
    // own claim/grant/lease stages. So: from the moment the local attempt
    // answers, the caller is released immediately and everything else happens
    // behind it.
    final storage = await terminal(
      'till-A',
      printers: [unownedNetworkPrinter(9100)],
    );
    var announced = 0;
    final queue = await queueFor(
      storage,
      printer: _ConnectFailurePrinter(storage),
      // Nobody answers the announce — the worst case for the caller.
      broadcastAnnounce: ({
        required jobId,
        required jobType,
        required entryId,
        required payloadBase64,
      }) =>
          announced++,
      callerBudget: const Duration(milliseconds: 450),
    );

    final sw = Stopwatch()..start();
    final r = await queue.submitJob(
      storage.getCloseCheckPrinter()!,
      [1, 2, 3],
      jobType: 'cashier',
    );
    sw.stop();

    expect(sw.elapsed, lessThan(const Duration(milliseconds: 500)));
    expect(announced, 1);
    expect(r.deferred, isTrue);
    expect(queue.jobs.single.stateEnum, PrintJobState.queued);
  });

  test('an unclaimed fallback still reports its failure to the operator',
      () async {
    // The till was told "queued". If nothing claims it, that promise has to be
    // taken back — `_onLateFailure` is the only route left once the caller has
    // its answer.
    PrintJob? reported;
    final storage = await terminal(
      'till-A',
      printers: [unownedNetworkPrinter(9100)],
    );
    final queue = await queueFor(
      storage,
      printer: _ConnectFailurePrinter(storage),
      onLateFailure: (job) => reported = job,
    );

    await queue.submitJob(
      storage.getCloseCheckPrinter()!,
      [1, 2, 3],
      jobType: 'cashier',
    );
    // Two claim waits: the announce, then the one retry an unowned job gets.
    await Future.delayed(const Duration(milliseconds: 300));

    expect(reported, isNotNull);
    expect(reported!.stateEnum, PrintJobState.failed);
  });

  test('an announcement for a printer this terminal does not have is ignored',
      () async {
    final storage = await terminal('till-B');
    var claims = 0;
    final queue = await queueFor(
      storage,
      printer: PrinterService(storage),
      broadcastClaim: (jobId, t) => claims++,
    );

    await queue.onRemoteAnnounce(
      jobId: 'j-1',
      jobType: 'cashier',
      entryId: 'nobody-has-this',
      payloadBase64: base64Encode([1, 2, 3]),
    );

    expect(claims, 0);
  });
}

bool _alwaysTrue() => true;
void _noopAnnounce({
  required String jobId,
  required String jobType,
  required String entryId,
  required String payloadBase64,
}) {}
void _noopClaim(String jobId, String terminalId) {}
void _noopGrant(String jobId, String terminalId) {}
void _noopResult(String jobId, String result, String? error) {}
