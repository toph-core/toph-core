import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_job.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A receipt raised on one terminal for a printer that belongs to another must
/// survive that other terminal being briefly away.
///
/// The scenario throughout: the close-check printer hangs off till B, and an
/// order is closed on the hub (or on till C). Relaying it is already covered by
/// `printer_ownership_test.dart`; what is covered here is what happens when B
/// is not answering at the moment the check is raised — mid-reboot, on a
/// flapping access point, or simply not switched on yet. Before this, the job
/// was announced twice three seconds apart and then declared failed, so a
/// closing check was gone in six seconds and had to be hand-retried from the
/// sync-status screen.
///
/// Same two-instance construction as the other print tests: real
/// `PrinterService` throughout, broadcast callbacks wired into each other, and
/// a live loopback socket standing in for a reachable network printer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('print_deferral_test').path);
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PrintJobAdapter());
    }
  });

  var boxCounter = 0;
  Future<Box<PrintJob>> freshBox() async {
    boxCounter++;
    return Hive.openBox<PrintJob>('print_deferral_test_$boxCounter');
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
    Box<PrintJob>? box,
    bool Function() isLanRelayPossible = _alwaysTrue,
    PrintAnnounceBroadcaster broadcastAnnounce = _noopAnnounce,
    PrintClaimBroadcaster broadcastClaim = _noopClaim,
    PrintGrantBroadcaster broadcastGrant = _noopGrant,
    PrintResultBroadcaster broadcastResult = _noopResult,
    Duration ownerWait = const Duration(seconds: 30),
    Duration deferredRetryInterval = const Duration(milliseconds: 120),
  }) async =>
      PrintQueueService(
        box ?? await freshBox(),
        printer,
        storage,
        await SharedPreferences.getInstance(),
        isLanRelayPossible: isLanRelayPossible,
        broadcastAnnounce: broadcastAnnounce,
        broadcastClaim: broadcastClaim,
        broadcastGrant: broadcastGrant,
        broadcastResult: broadcastResult,
        claimWait: const Duration(milliseconds: 60),
        lease: const Duration(milliseconds: 100),
        // Generous on purpose: these exercise the claim/lease state machine,
        // whose stages here add up to longer than the production caller budget.
        // The budget's own behaviour is covered separately, in
        // print_relay_deferral_test.dart's ceiling group.
        callerBudget: const Duration(seconds: 5),
        ownerWait: ownerWait,
        deferredRetryInterval: deferredRetryInterval,
      );

  PrinterSettingEntry closeCheckOwnedBy(String owner, int port) =>
      PrinterSettingEntry(
        id: 'close-check-1',
        ip: InternetAddress.loopbackIPv4.address,
        port: port,
        name: 'Kassa',
        type: 'close_check',
        connectedEntityIds: const [],
        connectionType: 'cable',
        ownerCashRegisterId: owner,
      );

  /// A socket that accepts and drains — a printer that is switched on.
  Future<ServerSocket> livePrinter() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close());
    server.listen((s) => s.listen((_) {}));
    return server;
  }

  group('the owner is away when the check is raised', () {
    test('the caller is released immediately, and the job is kept, not failed',
        () async {
      // The close-order flow awaits this call. Blocking it until till B comes
      // back would freeze the till on a screen the cashier cannot leave, so the
      // answer has to come back now — as `deferred`, which is neither a success
      // to be ignored nor a failure to be reprinted.
      final printerEntry = closeCheckOwnedBy('till-B', 9100);
      final storage = await terminal('till-A', printers: [printerEntry]);

      final queue = await queueFor(
        storage,
        printer: PrinterService(storage),
        // Nothing is listening: till B is not on the network.
        broadcastAnnounce: _noopAnnounce,
      );

      final r = await queue
          .submitJob(
            storage.getCloseCheckPrinter()!,
            [1, 2, 3],
            jobType: 'cashier',
          )
          .timeout(const Duration(seconds: 5));

      expect(r.deferred, isTrue);
      expect(r.ok, isFalse);
      expect(r.error, contains('navbatga'));

      final job = queue.jobs.single;
      expect(
        job.stateEnum,
        PrintJobState.queued,
        reason: 'the receipt is still pending, not written off',
      );
      expect(queue.deferredCount, 1);
    });

    test('an owned printer defers after one claim wait, not two', () async {
      // The wait before the caller is told is visible — `_closeShift` holds a
      // loading state across it — so it is one `claimWait`, not two. An owner
      // that is actually on the network claims the first announce in
      // milliseconds; a second synchronous round only re-confirms an absence
      // already established. Re-announcing still happens, on the deferred loop.
      final printerEntry = closeCheckOwnedBy('till-B', 9100);
      final storage = await terminal('till-A', printers: [printerEntry]);

      var announces = 0;
      final queue = await queueFor(
        storage,
        printer: PrinterService(storage),
        // Long enough that the deferred loop cannot muddy the count.
        deferredRetryInterval: const Duration(seconds: 30),
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            announces++,
      );

      final sw = Stopwatch()..start();
      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );
      sw.stop();

      expect(r.deferred, isTrue);
      expect(announces, 1, reason: 'one announce before deferring, not two');
      expect(
        sw.elapsedMilliseconds,
        lessThan(150),
        reason: 'one claimWait (60ms here), not two',
      );
    });

    test('it prints as soon as the owning terminal comes back', () async {
      final server = await livePrinter();
      final printerEntry = closeCheckOwnedBy('till-B', server.port);

      final storageA = await terminal('till-A', printers: [printerEntry]);
      final storageB = await terminal('till-B', printers: [printerEntry]);

      late PrintQueueService queueA;
      late PrintQueueService queueB;

      // Till B is off the network until this flips.
      var bOnline = false;

      queueA = await queueFor(
        storageA,
        printer: PrinterService(storageA),
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) {
          if (!bOnline) return;
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
      expect(r.deferred, isTrue);
      expect(queueA.jobs.single.stateEnum, PrintJobState.queued);

      // Till B finishes booting and joins the hub. `di.dart` wires exactly this
      // call to the LAN peer set changing.
      bOnline = true;
      queueA.retryPendingRelays();

      await _until(() => queueA.jobs.single.stateEnum == PrintJobState.printed);
      expect(queueA.jobs.single.stateEnum, PrintJobState.printed);
      expect(queueA.deferredCount, 0);
    });

    test('the backstop timer prints it even with no peer-change signal',
        () async {
      // Not every reappearance produces a peer event, so the interval retry has
      // to be able to carry the job on its own.
      final server = await livePrinter();
      final printerEntry = closeCheckOwnedBy('till-B', server.port);

      final storageA = await terminal('till-A', printers: [printerEntry]);
      final storageB = await terminal('till-B', printers: [printerEntry]);

      late PrintQueueService queueA;
      late PrintQueueService queueB;
      var bOnline = false;

      queueA = await queueFor(
        storageA,
        printer: PrinterService(storageA),
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) {
          if (!bOnline) return;
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

      await queueA.submitJob(
        storageA.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );

      bOnline = true; // no retryPendingRelays() call — the timer must do it
      await _until(() => queueA.jobs.single.stateEnum == PrintJobState.printed);
      expect(queueA.jobs.single.stateEnum, PrintJobState.printed);
    });

    test('it is given up on once ownerWait runs out', () async {
      // Bounded on purpose: a receipt that surfaces long after the customer has
      // left is its own kind of wrong.
      final printerEntry = closeCheckOwnedBy('till-B', 9100);
      final storage = await terminal('till-A', printers: [printerEntry]);

      final queue = await queueFor(
        storage,
        printer: PrinterService(storage),
        ownerWait: const Duration(milliseconds: 150),
        deferredRetryInterval: const Duration(milliseconds: 50),
      );

      await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );

      await _until(() => queue.jobs.single.stateEnum == PrintJobState.failed);
      expect(queue.jobs.single.lastError, contains('qaytmadi'));
      expect(queue.deferredCount, 0);
    });

    test('reassigning the printer to this terminal prints it here', () async {
      // The operator gives up waiting and plugs the printer into this till
      // instead. The job should follow the printer rather than go on announcing
      // into an empty room.
      final server = await livePrinter();
      final storage = await terminal(
        'till-A',
        printers: [closeCheckOwnedBy('till-B', server.port)],
      );

      final queue = await queueFor(
        storage,
        printer: PrinterService(storage),
      );

      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );
      expect(r.deferred, isTrue);

      await storage.applyPrinterSettingsList([
        closeCheckOwnedBy('till-A', server.port),
      ]);
      queue.retryPendingRelays();

      await _until(() => queue.jobs.single.stateEnum == PrintJobState.printed);
      expect(queue.jobs.single.stateEnum, PrintJobState.printed);
    });
  });

  group('the 500ms ceiling on what the till waits', () {
    // These use the real production durations, not the shortened ones the rest
    // of the file runs with — the point is the shipped numbers.
    Future<PrintQueueService> productionQueue(
      PrinterConfigStorage storage, {
      PrintAnnounceBroadcaster broadcastAnnounce = _noopAnnounce,
    }) async =>
        PrintQueueService(
          await freshBox(),
          PrinterService(storage),
          storage,
          await SharedPreferences.getInstance(),
          isLanRelayPossible: () => true,
          broadcastAnnounce: broadcastAnnounce,
          broadcastClaim: _noopClaim,
          broadcastGrant: _noopGrant,
          broadcastResult: _noopResult,
        );

    /// Nothing the till waits on may exceed this, whatever the network is
    /// doing. The relay protocol has five stages and any of them can stall; the
    /// caller's answer is deliberately decoupled from all of it.
    const ceiling = Duration(milliseconds: 500);

    test('an absent owner does not hold the till past the ceiling', () async {
      final storage = await terminal(
        'till-A',
        printers: [closeCheckOwnedBy('till-B', 9100)],
      );
      final queue = await productionQueue(storage);

      final sw = Stopwatch()..start();
      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );
      sw.stop();

      expect(sw.elapsed, lessThan(ceiling));
      expect(r.deferred, isTrue);
      expect(queue.jobs.single.stateEnum, PrintJobState.queued,
          reason: 'released early, but still pending — not abandoned');
    });

    test('a claimant that goes silent does not hold the till either', () async {
      // The worst case for the protocol: someone claims, so the originator
      // stops its claim wait and starts a ten-second lease. The till must not
      // be waiting on that lease.
      final storage = await terminal(
        'till-A',
        printers: [closeCheckOwnedBy('till-B', 9100)],
      );
      late PrintQueueService queue;
      queue = await productionQueue(
        storage,
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            queue.onRemoteClaim(jobId, 'ghost-terminal'),
      );

      final sw = Stopwatch()..start();
      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );
      sw.stop();

      expect(sw.elapsed, lessThan(ceiling));
      expect(r.deferred, isTrue);
    });

    test('an unowned printer nobody answers is capped too', () async {
      final storage = await terminal('till-A');
      final queue = await productionQueue(storage);

      final sw = Stopwatch()..start();
      await queue.submitJob(
        const PrinterConfig(
          ip: '',
          connectionType: 'usb',
          entryId: 'nobody-has-this',
        ),
        [1, 2, 3],
        jobType: 'cashier',
      );
      sw.stop();

      expect(sw.elapsed, lessThan(ceiling));
    });

    test('a job that fails after the till was released is still reported',
        () async {
      // The obligation the budget creates. The till was told "queued" and
      // walked away, so the eventual failure has nobody to return to — without
      // this hook the receipt would simply never appear and nothing would say
      // so.
      PrintJob? reported;
      final storage = await terminal(
        'till-A',
        printers: [closeCheckOwnedBy('till-B', 9100)],
      );
      final queue = PrintQueueService(
        await freshBox(),
        PrinterService(storage),
        storage,
        await SharedPreferences.getInstance(),
        isLanRelayPossible: () => true,
        broadcastAnnounce: _noopAnnounce,
        broadcastClaim: _noopClaim,
        broadcastGrant: _noopGrant,
        broadcastResult: _noopResult,
        claimWait: const Duration(milliseconds: 40),
        lease: const Duration(milliseconds: 40),
        callerBudget: const Duration(milliseconds: 30),
        ownerWait: const Duration(milliseconds: 80),
        deferredRetryInterval: const Duration(milliseconds: 30),
        onLateFailure: (job) => reported = job,
      );

      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );
      expect(r.deferred, isTrue);

      await _until(() => reported != null);
      expect(reported!.lastError, isNotNull);
    });
  });

  group('across a restart of the terminal holding the job', () {
    test('a job still inside its window is picked back up, not discarded',
        () async {
      // The till was shut down for the night with a check still waiting on the
      // kitchen terminal. It should still come out when both are back.
      final server = await livePrinter();
      final printerEntry = closeCheckOwnedBy('till-B', server.port);
      final storageA = await terminal('till-A', printers: [printerEntry]);
      final box = await freshBox();

      final first = await queueFor(
        storageA,
        printer: PrinterService(storageA),
        box: box,
      );
      await first.submitJob(
        storageA.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );
      expect(first.jobs.single.stateEnum, PrintJobState.queued);

      // Same box, new service — the app restarting.
      final storageB = await terminal('till-B', printers: [printerEntry]);
      late PrintQueueService revived;
      final queueB = await queueFor(
        storageB,
        printer: PrinterService(storageB),
        broadcastClaim: (jobId, t) => revived.onRemoteClaim(jobId, t),
        broadcastResult: (jobId, result, error) =>
            revived.onRemoteResult(jobId, result, error),
      );
      revived = await queueFor(
        storageA,
        printer: PrinterService(storageA),
        box: box,
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            queueB.onRemoteAnnounce(
          jobId: jobId,
          jobType: jobType,
          entryId: entryId,
          payloadBase64: payloadBase64,
        ),
        broadcastGrant: (jobId, t) => queueB.onRemoteGrant(jobId, t),
      );

      expect(
        revived.jobs.single.stateEnum,
        isNot(PrintJobState.failed),
        reason: 'a restart must not discard a check that is still viable',
      );
      await _until(
          () => revived.jobs.single.stateEnum == PrintJobState.printed);
    });

    test('an unowned job is still failed on restart, as before', () async {
      // No terminal to wait for, so there is nothing the retry loop could do —
      // the pre-existing behaviour has to stay.
      final storage = await terminal('till-A');
      final box = await freshBox();

      final first = await queueFor(
        storage,
        printer: PrinterService(storage),
        box: box,
      );
      await first.submitJob(
        // A printer no entry describes: the legacy / no-owner shape.
        const PrinterConfig(
          ip: '',
          connectionType: 'usb',
          entryId: 'unknown-entry',
        ),
        [1, 2, 3],
        jobType: 'cashier',
      );

      final revived = await queueFor(
        storage,
        printer: PrinterService(storage),
        box: box,
      );
      expect(revived.jobs.single.stateEnum, PrintJobState.failed);
    });
  });

  test('two grants landing together produce exactly one printout', () async {
    // A deferred job is re-announced on a timer *and* whenever the LAN peer set
    // changes, so the same job can be granted to this terminal twice inside the
    // second or two a receipt takes to render and spool. The persisted
    // printed-job memory only closes the window *after* a print finishes; the
    // in-flight set closes the one during it.
    final server = await livePrinter();
    final printerEntry = closeCheckOwnedBy('till-B', server.port);
    final storageB = await terminal('till-B', printers: [printerEntry]);

    final results = <String>[];
    final claims = <String>[];
    final queueB = await queueFor(
      storageB,
      printer: PrinterService(storageB),
      broadcastClaim: (jobId, _) => claims.add(jobId),
      broadcastResult: (jobId, result, error) => results.add(result),
    );

    const jobId = 'job-race';
    await queueB.onRemoteAnnounce(
      jobId: jobId,
      jobType: 'cashier',
      entryId: printerEntry.id,
      payloadBase64: base64Encode([1, 2, 3]),
    );
    expect(claims, [jobId], reason: 'it puts its hand up, but does not print');
    expect(results, isEmpty, reason: 'nothing prints before a grant');

    // Two grants for the same job, in flight at once.
    await Future.wait([
      queueB.onRemoteGrant(jobId, queueB.terminalId),
      queueB.onRemoteGrant(jobId, queueB.terminalId),
    ]);

    expect(
      results,
      ['printed'],
      reason: 'only one of the two grants may reach the printer',
    );
  });

  test('a grant addressed to another terminal is ignored', () async {
    final server = await livePrinter();
    final printerEntry = closeCheckOwnedBy('till-B', server.port);
    final storageB = await terminal('till-B', printers: [printerEntry]);

    final results = <String>[];
    final queueB = await queueFor(
      storageB,
      printer: PrinterService(storageB),
      broadcastResult: (jobId, result, error) => results.add(result),
    );

    await queueB.onRemoteAnnounce(
      jobId: 'job-x',
      jobType: 'cashier',
      entryId: printerEntry.id,
      payloadBase64: base64Encode([1, 2, 3]),
    );
    await queueB.onRemoteGrant('job-x', 'some-other-terminal');

    expect(results, isEmpty, reason: 'it lost the race and must not print');
  });

  test('an owner that already printed a job does not print it twice after its '
      'own restart', () async {
    // The reason the printed-job memory had to be written to disk. With
    // ownerWait stretching re-announcements over minutes rather than seconds,
    // the window now easily spans a restart of the owning terminal — which
    // would otherwise print the ticket, forget, hear the same job announced
    // again, and produce a second copy.
    final server = await livePrinter();
    final printerEntry = closeCheckOwnedBy('till-B', server.port);
    final storageB = await terminal('till-B', printers: [printerEntry]);

    final results = <String>[];
    final firstB = await queueFor(
      storageB,
      printer: PrinterService(storageB),
      broadcastResult: (jobId, result, error) => results.add(result),
    );

    const jobId = 'job-42';
    await firstB.onRemoteAnnounce(
      jobId: jobId,
      jobType: 'cashier',
      entryId: printerEntry.id,
      payloadBase64: base64Encode([1, 2, 3]),
    );
    await firstB.onRemoteGrant(jobId, firstB.terminalId);
    expect(results, ['printed']);

    // Till B restarts — new service, same SharedPreferences.
    final secondB = await queueFor(
      storageB,
      printer: PrinterService(storageB),
      broadcastResult: (jobId2, result, error) => results.add(result),
    );

    await secondB.onRemoteAnnounce(
      jobId: jobId,
      jobType: 'cashier',
      entryId: printerEntry.id,
      payloadBase64: base64Encode([1, 2, 3]),
    );

    // It answers the originator so the job resolves, but nothing new comes out
    // of the printer.
    expect(results, ['printed', 'printed']);
    expect(
      secondB.jobs.where((j) => j.id == jobId),
      isEmpty,
      reason: 'the claimant never owns a row for a job it did not originate',
    );
  });
}

/// Polls until [predicate] holds or the budget runs out. The deferral paths are
/// driven by real timers, so there is no scheduler to pump.
Future<void> _until(
  bool Function() predicate, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('condition not reached within $budget');
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
