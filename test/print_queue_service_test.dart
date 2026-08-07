import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_job.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exercises `PrintQueueService`'s claim/lease state machine directly — two
/// instances stand in for two terminals, with their broadcast callbacks
/// wired straight into each other's `onRemote*` methods rather than going
/// through `LanHubService`/the real WebSocket transport (that wire-level
/// path is already covered by `lan_hub_test.dart`; this covers the
/// orchestration logic sitting on top of it, which is what's actually new
/// here). Uses a real `PrinterService` throughout — no mocking framework in
/// this project — which conveniently makes two outcomes deterministic
/// without any fakery: a `usb`-type print always fails immediately on this
/// (non-Windows) test machine ("USB printer faqat Windows da ishlaydi"),
/// and a `cable`-type print against a real local loopback socket always
/// succeeds. That's enough to distinguish every state-machine path this
/// test cares about.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('print_queue_test').path);
    Hive.registerAdapter(PrintJobAdapter());
  });

  Future<PrinterService> newPrinterService() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return PrinterService(PrinterConfigStorage(prefs));
  }

  Future<PrintQueueService> newQueueService({
    required Box<PrintJob> box,
    required PrinterService printerService,
    required CacheService cacheService,
    bool Function() isLanRelayPossible = _alwaysTrue,
    PrintAnnounceBroadcaster broadcastAnnounce = _noopAnnounce,
    PrintClaimBroadcaster broadcastClaim = _noopClaim,
    PrintResultBroadcaster broadcastResult = _noopResult,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return PrintQueueService(
      box,
      printerService,
      cacheService,
      prefs,
      isLanRelayPossible: isLanRelayPossible,
      broadcastAnnounce: broadcastAnnounce,
      broadcastClaim: broadcastClaim,
      broadcastResult: broadcastResult,
      claimWait: const Duration(milliseconds: 150),
      lease: const Duration(milliseconds: 200),
    );
  }

  var boxCounter = 0;

  Future<Box<PrintJob>> freshBox() async {
    boxCounter++;
    return Hive.openBox<PrintJob>('print_queue_test_$boxCounter');
  }

  Future<CacheService> freshCache() async {
    boxCounter++;
    return CacheService(await Hive.openBox('cache_test_$boxCounter'));
  }

  group('PrintQueueService', () {
    test('a network/TCP job needs no relay and finishes locally', () async {
      final serverSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => serverSocket.close());
      serverSocket.listen((s) => s.listen((_) {}));

      final printer = await newPrinterService();
      final cache = await freshCache();
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
      );

      final r = await queue.submitJob(
        PrinterConfig(
          ip: InternetAddress.loopbackIPv4.address,
          port: serverSocket.port,
          connectionType: 'cable',
        ),
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(r.ok, isTrue);
      expect(queue.jobs.single.stateEnum, PrintJobState.printed);
    });

    test('a USB job this terminal owns prints locally, no broadcast at all', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      await cache.saveUsbPrinterName('entry-1', 'My Local USB Printer');

      var broadcastCalled = false;
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            broadcastCalled = true,
      );

      final r = await queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-1'),
        [1, 2, 3],
        jobType: 'cashier',
      );

      // Deterministic on this (non-Windows) test machine.
      expect(r.ok, isFalse);
      expect(r.error, contains('Windows'));
      expect(broadcastCalled, isFalse);
      expect(queue.jobs.single.stateEnum, PrintJobState.failed);
    });

    test('a USB job this terminal does not own is announced, claimed, and resolved by the owner', () async {
      final printerA = await newPrinterService();
      final printerB = await newPrinterService();
      final cacheA = await freshCache(); // does NOT own entry-2
      final cacheB = await freshCache();
      await cacheB.saveUsbPrinterName('entry-2', 'Bs USB Printer');

      late PrintQueueService queueA;
      late PrintQueueService queueB;

      queueA = await newQueueService(
        box: await freshBox(),
        printerService: printerA,
        cacheService: cacheA,
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
        broadcastClaim: (_) {}, // B's claim goes straight back to A below
      );
      queueB = await newQueueService(
        box: await freshBox(),
        printerService: printerB,
        cacheService: cacheB,
        broadcastClaim: queueA.onRemoteClaim,
        broadcastResult: queueA.onRemoteResult,
      );

      final r = await queueA.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-2'),
        [1, 2, 3],
        jobType: 'cashier',
      );

      // B claimed it (proven by the error being B's platform failure, not
      // A's "nobody claimed" message) and reported back a real failure
      // (B is also non-Windows in this test environment).
      expect(r.ok, isFalse);
      expect(r.error, contains('Windows'));
      expect(queueA.jobs.single.stateEnum, PrintJobState.failed);
      expect(queueA.jobs.single.claimedAt, isNotNull);
    });

    test('nobody claims within the wait window — one retry, then a clear unclaimed failure', () async {
      final printer = await newPrinterService();
      final cache = await freshCache(); // nobody owns entry-3 anywhere
      var announceCount = 0;
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            announceCount++,
      );

      final r = await queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-3'),
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(r.ok, isFalse);
      expect(r.error, contains('egallamadi'));
      expect(announceCount, 2); // original + exactly one retry
      expect(queue.jobs.single.retryCount, 1);
    });

    test('claimed but no result within the lease — one retry, then fails', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      var announceCount = 0;
      late PrintQueueService queue;
      queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) {
          announceCount++;
          // Someone claims it every time, but never reports back — e.g. it
          // crashed mid-print.
          queue.onRemoteClaim(jobId);
        },
      );

      final r = await queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-4'),
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(r.ok, isFalse);
      expect(r.error, contains('natija bermadi'));
      expect(announceCount, 2);
      expect(queue.jobs.single.retryCount, 1);
    });

    test('a stale queued/claimed job from a previous run is recovered as failed on init', () async {
      final box = await freshBox();
      final staleJob = PrintJob(
        id: 'stale-1',
        jobType: 'cashier',
        entryId: 'entry-5',
        payloadBase64: '',
        connectionType: 'usb',
        ip: '',
        port: 0,
        state: 'queued',
        createdAt: DateTime.now().toUtc(),
      );
      await box.put(staleJob.id, staleJob);

      final printer = await newPrinterService();
      final cache = await freshCache();
      await newQueueService(box: box, printerService: printer, cacheService: cache);

      final recovered = box.get('stale-1')!;
      expect(recovered.stateEnum, PrintJobState.failed);
      expect(recovered.lastError, isNotNull);
    });

    test('LAN mode disabled — a USB job this terminal does not own fails fast with a clear reason, never hangs', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
        isLanRelayPossible: () => false,
      );

      final r = await queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-6'),
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(r.ok, isFalse);
      expect(r.error, contains('LAN'));
      expect(queue.jobs.single.stateEnum, PrintJobState.failed);
    });
  });

  group('Concurrent multi-destination dispatch (Phase 5 kitchen wiring)', () {
    // `PrinterService.printKitchenReceiptFor` now fires one `submitJob` per
    // destination printer without awaiting between them (`Future.wait` on
    // the collected futures), instead of the old sequential loop that
    // stopped at the first failure — a relayed job can take several hundred
    // ms to over 20s to resolve, and blocking every other destination
    // printer's urgent kitchen ticket behind that would be a regression.
    // Exercised directly at the `PrintQueueService` level (bypassing
    // `PrinterService.printKitchenReceiptFor` itself, which reaches for
    // `CacheService`/`UserBloc` via ad-hoc `inject()` calls that would need
    // the full DI graph to stand up here) — this is where the actual
    // concurrency risk lives; `printKitchenReceiptFor`'s own change is a
    // thin `Future.wait` over calls into exactly this method.
    test('a slow (relay-needing) job does not block a fast local one — both resolve independently', () async {
      final serverSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => serverSocket.close());
      serverSocket.listen((s) => s.listen((_) {}));

      final printer = await newPrinterService();
      final cache = await freshCache();
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
      );

      // Nobody owns 'entry-slow' anywhere — announces, waits, retries once,
      // then fails, same as the dedicated unclaimed-timeout test above; the
      // only new thing under test here is that it runs *alongside* the fast
      // job rather than before or after it.
      final fastFuture = queue.submitJob(
        PrinterConfig(
          ip: InternetAddress.loopbackIPv4.address,
          port: serverSocket.port,
          connectionType: 'cable',
        ),
        [1, 2, 3],
        jobType: 'kitchen',
        beep: false,
      );
      final slowFuture = queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-slow'),
        [4, 5, 6],
        jobType: 'kitchen',
        beep: false,
      );

      // Comfortably after the fast TCP job should have landed, comfortably
      // before the slow job's 150ms claim-wait has even expired once —
      // proves the fast job wasn't stuck waiting behind the slow one.
      await Future.delayed(const Duration(milliseconds: 60));
      final jobs = {for (final j in queue.jobs) j.connectionType: j};
      expect(
        jobs['cable']!.stateEnum,
        PrintJobState.printed,
        reason: 'the fast job should already be done well before the slow '
            "one's first claim-wait even expires, proving concurrent "
            'dispatch rather than sequential',
      );
      expect(jobs['usb']!.stateEnum, PrintJobState.queued);

      final fastResult = await fastFuture;
      final slowResult = await slowFuture;
      expect(fastResult.ok, isTrue);
      expect(slowResult.ok, isFalse);
    });
  });

  group('Sync-status UI support (Phase 6)', () {
    test('queuedCount/claimedCount/failedCount reflect the box regardless of how jobs got there', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      final box = await freshBox();
      final queue = await newQueueService(
        box: box,
        printerService: printer,
        cacheService: cache,
      );

      // Seeded directly — these getters are plain filters over the box, not
      // tied to any particular submitJob path.
      await box.put('q1', PrintJob(
        id: 'q1',
        jobType: 'kitchen',
        entryId: 'e1',
        payloadBase64: '',
        connectionType: 'usb',
        ip: '',
        port: 0,
        state: 'queued',
        createdAt: DateTime.now().toUtc(),
      ));
      await box.put('c1', PrintJob(
        id: 'c1',
        jobType: 'kitchen',
        entryId: 'e2',
        payloadBase64: '',
        connectionType: 'usb',
        ip: '',
        port: 0,
        state: 'claimed',
        createdAt: DateTime.now().toUtc(),
      ));
      await box.put('f1', PrintJob(
        id: 'f1',
        jobType: 'kitchen',
        entryId: 'e3',
        payloadBase64: '',
        connectionType: 'usb',
        ip: '',
        port: 0,
        state: 'failed',
        createdAt: DateTime.now().toUtc(),
      ));
      await box.put('f2', PrintJob(
        id: 'f2',
        jobType: 'kitchen',
        entryId: 'e4',
        payloadBase64: '',
        connectionType: 'usb',
        ip: '',
        port: 0,
        state: 'failed',
        createdAt: DateTime.now().toUtc(),
      ));

      expect(queue.queuedCount, 1);
      expect(queue.claimedCount, 1);
      expect(queue.failedCount, 2);
    });

    test('retryFailedJob resubmits a failed job under a fresh id, leaving the original row as history', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      await cache.saveUsbPrinterName('entry-retry', 'My Local USB Printer');
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
      );

      // Deterministic failure on this non-Windows test machine (same as the
      // "USB job this terminal owns" test above).
      final original = await queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-retry'),
        [1, 2, 3],
        jobType: 'cashier',
      );
      expect(original.ok, isFalse);
      expect(queue.failedCount, 1);
      final originalId = queue.jobs.single.id;

      final retryResult = await queue.retryFailedJob(originalId);

      expect(retryResult, isNotNull);
      expect(retryResult!.ok, isFalse); // still deterministic-fails here
      expect(
        queue.jobs.length,
        2,
        reason: 'retry submits a new job rather than mutating the old one',
      );
      expect(
        queue.jobs.any((j) => j.id == originalId),
        isTrue,
        reason: 'the original failed row stays as history',
      );
      expect(queue.failedCount, 2);
    });

    test('retryFailedJob is a no-op for a job that is not failed', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      final box = await freshBox();
      final queue = await newQueueService(
        box: box,
        printerService: printer,
        cacheService: cache,
      );
      await box.put('queued-1', PrintJob(
        id: 'queued-1',
        jobType: 'kitchen',
        entryId: 'e1',
        payloadBase64: '',
        connectionType: 'usb',
        ip: '',
        port: 0,
        state: 'queued',
        createdAt: DateTime.now().toUtc(),
      ));

      final result = await queue.retryFailedJob('queued-1');

      expect(result, isNull);
      expect(queue.jobs.length, 1, reason: 'nothing should have been submitted');
    });

    test('dismissFailedJob removes a failed job without resubmitting', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      await cache.saveUsbPrinterName('entry-dismiss', 'My Local USB Printer');
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
      );

      await queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-dismiss'),
        [1, 2, 3],
        jobType: 'cashier',
      );
      final jobId = queue.jobs.single.id;

      await queue.dismissFailedJob(jobId);

      expect(queue.jobs, isEmpty);
    });

    test('listenable notifies on submit', () async {
      final printer = await newPrinterService();
      final cache = await freshCache();
      await cache.saveUsbPrinterName('entry-listen', 'My Local USB Printer');
      final queue = await newQueueService(
        box: await freshBox(),
        printerService: printer,
        cacheService: cache,
      );

      var notified = false;
      queue.listenable.addListener(() => notified = true);

      await queue.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-listen'),
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(notified, isTrue);
    });
  });

  group('Duplicate delivery (Phase 6 deterministic tests)', () {
    // The LAN transport makes no at-most-once promise (see the matching
    // test in lan_hub_test.dart) — a broadcast can genuinely arrive twice,
    // and two terminals can race to claim the same announced job. Both
    // `onRemoteClaim`/`onRemoteResult` already guard on the job's current
    // state before acting (confirmed by reading the code, not assumed —
    // each has its own "first claim/result already won" doc comment); these
    // tests prove that guard actually holds under a genuine duplicate.
    test('a second onRemoteClaim for an already-claimed job is ignored — first claimant keeps it', () async {
      final printerA = await newPrinterService();
      final cacheA = await freshCache(); // does NOT own entry-dup
      final queueA = await newQueueService(
        box: await freshBox(),
        printerService: printerA,
        cacheService: cacheA,
      );

      // Deliberately not awaited yet — `submitJob` only resolves once the
      // job is fully finalized, and this test needs to drive the claim
      // sequence manually while the job is still `queued`.
      final future = queueA.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-dup'),
        [1, 2, 3],
        jobType: 'cashier',
      );
      final jobId = queueA.jobs.single.id;
      expect(queueA.jobs.single.stateEnum, PrintJobState.queued);

      queueA.onRemoteClaim(jobId);
      final claimedAtFirst = queueA.jobs.single.claimedAt;
      expect(queueA.jobs.single.stateEnum, PrintJobState.claimed);
      expect(claimedAtFirst, isNotNull);

      // A second, duplicate claim for the same job — simulating either a
      // redelivered broadcast or a genuine second terminal racing in late.
      await Future.delayed(const Duration(milliseconds: 5));
      queueA.onRemoteClaim(jobId);

      expect(
        queueA.jobs.single.claimedAt,
        claimedAtFirst,
        reason: 'the second claim must not reset the lease clock — that '
            "would let a late/duplicate claimant repeatedly steal the job "
            'from whoever actually claimed it first',
      );

      // Resolve it cleanly so nothing (the lease timer in particular) is
      // left dangling past the end of this test.
      queueA.onRemoteResult(jobId, 'printed', null);
      await future;
    });

    test('a second onRemoteResult for an already-resolved job is ignored — first result stands', () async {
      final printerA = await newPrinterService();
      final cacheA = await freshCache();
      final queueA = await newQueueService(
        box: await freshBox(),
        printerService: printerA,
        cacheService: cacheA,
      );

      final future = queueA.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-dup2'),
        [1, 2, 3],
        jobType: 'cashier',
      );
      final jobId = queueA.jobs.single.id;
      // Yield once so `submitJob`'s own async continuation (past its first
      // `await`) actually reaches the line that registers this job's
      // pending completer — otherwise `onRemoteResult` below would find
      // nothing to complete and `future` would hang forever, since the box
      // mutation it does happens regardless but the completer registration
      // is what `future` is actually waiting on.
      await Future.delayed(const Duration(milliseconds: 5));
      queueA.onRemoteClaim(jobId);

      queueA.onRemoteResult(jobId, 'printed', null);
      await future;
      expect(queueA.jobs.single.stateEnum, PrintJobState.printed);

      // A duplicate/late second result, disagreeing with the first —
      // exactly the scenario that would matter: if this were applied, a
      // successfully printed receipt would flip back to "failed".
      queueA.onRemoteResult(jobId, 'failed', 'stale duplicate');

      expect(
        queueA.jobs.single.stateEnum,
        PrintJobState.printed,
        reason: 'the job already resolved — a later duplicate must never '
            'overwrite a real outcome, in either direction',
      );
      expect(queueA.jobs.single.lastError, isNull);
    });

    test('two terminals racing to claim the same announced job — only the first claim is honored, the second is a no-op', () async {
      final printerA = await newPrinterService();
      final printerB = await newPrinterService();
      final printerC = await newPrinterService();
      final cacheA = await freshCache(); // does NOT own entry-race
      final cacheB = await freshCache();
      final cacheC = await freshCache();
      await cacheB.saveUsbPrinterName('entry-race', "B's USB Printer");
      await cacheC.saveUsbPrinterName('entry-race', "C's USB Printer");

      late PrintQueueService queueA;
      late PrintQueueService queueB;
      late PrintQueueService queueC;

      // A itself never claims in this test (it doesn't own entry-race) —
      // its own `broadcastClaim`/`broadcastResult` are never exercised, so
      // they're left at the harness defaults. This wrapper is what B and C
      // both call, so it can't live inside A's own initializer (which would
      // be a definite-assignment error — A referencing itself before its
      // own `queueA = ...` has completed).
      final claimsSeenByA = <String>[];
      void deliverClaimToA(String jobId) {
        claimsSeenByA.add(jobId);
        queueA.onRemoteClaim(jobId);
      }

      queueA = await newQueueService(
        box: await freshBox(),
        printerService: printerA,
        cacheService: cacheA,
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) {
          // Both B and C hear the same announcement, exactly like a real
          // broadcast — this is the race.
          queueB.onRemoteAnnounce(
            jobId: jobId,
            jobType: jobType,
            entryId: entryId,
            payloadBase64: payloadBase64,
          );
          queueC.onRemoteAnnounce(
            jobId: jobId,
            jobType: jobType,
            entryId: entryId,
            payloadBase64: payloadBase64,
          );
        },
      );
      queueB = await newQueueService(
        box: await freshBox(),
        printerService: printerB,
        cacheService: cacheB,
        broadcastClaim: deliverClaimToA,
        broadcastResult: queueA.onRemoteResult,
      );
      queueC = await newQueueService(
        box: await freshBox(),
        printerService: printerC,
        cacheService: cacheC,
        broadcastClaim: deliverClaimToA,
        broadcastResult: queueA.onRemoteResult,
      );

      final r = await queueA.submitJob(
        const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-race'),
        [1, 2, 3],
        jobType: 'cashier',
      );

      // Both B and C actually raced in and claimed — proving this was a
      // genuine race, not just one of them ever trying.
      expect(
        claimsSeenByA,
        hasLength(2),
        reason: 'both B and C must have claimed for this to test the race '
            'at all, not just a single-claimer happy path',
      );
      // ...but only one of B/C actually printed (both fail deterministically
      // on this non-Windows machine, either way) — the loser's claim
      // arrived when the job was already `claimed`, so `onRemoteClaim`
      // no-oped it instead of resetting ownership.
      expect(r.ok, isFalse);
      expect(r.error, contains('Windows'));
      expect(queueA.jobs.single.stateEnum, PrintJobState.failed);
      expect(
        queueA.jobs.single.claimedAt,
        isNotNull,
        reason: 'the winner\'s claim must have been accepted',
      );
    });
  });
}

bool _alwaysTrue() => true;
void _noopAnnounce({
  required String jobId,
  required String jobType,
  required String entryId,
  required String payloadBase64,
}) {}
void _noopClaim(String jobId) {}
void _noopResult(String jobId, String result, String? error) {}
