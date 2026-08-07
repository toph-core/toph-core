import 'dart:async';
import 'dart:typed_data';

import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:clock/clock.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/services/offline_queue/quarantined_operation.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_job.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connectivity_platform.dart';
import 'support/fake_http_client_adapter.dart';
import 'support/in_memory_secure_storage.dart';

/// The full-shift soak test flagged as the one remaining Phase 6 item —
/// see offline-first-architecture-plan.md §11 Phase 6. Previously judged
/// impossible without either real hardware or a fake-clock refactor "this
/// codebase never needed for anything else." It still doesn't need one:
/// `fake_async` fakes `Timer`/`Timer.periodic` transparently via zone
/// overrides with zero production changes, and `package:clock` covers the
/// single spot where raw wall-clock time (not a Timer) drives real logic —
/// `OfflineQueueService`'s retry backoff (see the comment on its
/// `_lastAttemptAt` field). Everything else in this codebase that looks
/// time-sensitive (print-job claim/lease, LAN reconnect backoff, the sync
/// engine's periodic tick) is Timer-driven already, not wall-clock-polled,
/// so it falls out of `fake_async` for free.
///
/// Every Hive box opened here uses the in-memory storage backend
/// (`bytes: Uint8List(0)`) instead of the disk backend other tests use.
/// Disk-backed writes go through `RandomAccessFile`, real `dart:io` async
/// I/O that `fake_async`'s `elapse()` cannot advance (it only fakes Timers
/// and zone-scheduled microtasks) — a disk box's `put`/`delete` would just
/// never resolve inside a fake-time elapse. The in-memory backend's writes
/// resolve via a plain `Future.value()` (a microtask), which `elapse()`
/// handles correctly, and — confirmed by reading `Keystore.beginTransaction`
/// — the key/value map is updated synchronously on `put`/`delete` before
/// that Future even resolves, same "value visible immediately, Future
/// completion is separate" behavior already documented for the disk backend
/// in `print_queue_service_test.dart`.
///
/// This slice also newly unblocks something disclosed as a gap repeatedly
/// across Phase 6: a real `DioClient`/`ConnectivityCubit` pair, previously
/// "unavailable in this sandbox" because `connectivity_plus` needs a
/// platform channel. `connectivity_plus_platform_interface` exposes a
/// settable `ConnectivityPlatform.instance` for exactly this purpose (the
/// same pattern `flutter_secure_storage_platform_interface` already used
/// for `InMemorySecureStoragePlatform`) — see
/// `support/fake_connectivity_platform.dart`. Paired with
/// `support/fake_http_client_adapter.dart` (swapped onto `DioClient.dio`'s
/// public `httpClientAdapter` setter, no real socket ever opens), this test
/// exercises a genuine `OfflineQueueService.syncAll` round trip end to end
/// — something every earlier Phase 6 test explicitly deferred to "verified
/// by code review instead."
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.registerAdapter(PendingOperationTypeAdapter());
    Hive.registerAdapter(PendingOperationAdapter());
    Hive.registerAdapter(QuarantinedOperationAdapter());
    Hive.registerAdapter(PrintJobAdapter());
  });

  group('Offline queue over a simulated shift', () {
    test(
      'drains despite repeated LAN partitions, no operation lost, duplicated, or left stuck',
      () async {
        final outbox = await Hive.openBox<PendingOperation>(
          'soak_relay_outbox',
          bytes: Uint8List(0),
        );
        final quarantineBox = await Hive.openBox<QuarantinedOperation>(
          'soak_relay_quarantine',
          bytes: Uint8List(0),
        );
        final service = OfflineQueueService(outbox, quarantineBox);

        fakeAsync((async) {
          // Three partition windows spread across an 8h shift — leader
          // reachable outside of them.
          final downWindows = [
            (const Duration(hours: 1), const Duration(hours: 1, minutes: 20)),
            (const Duration(hours: 3, minutes: 30), const Duration(hours: 3, minutes: 45)),
            (const Duration(hours: 6), const Duration(hours: 6, minutes: 40)),
          ];
          bool isUp(Duration elapsed) =>
              !downWindows.any((w) => elapsed >= w.$1 && elapsed < w.$2);

          final enqueuedIds = <String>[];
          final syncedIds = <String>[];
          final quarantinedIds = <String>[];
          var opCounter = 0;

          // A mixed-type op roughly every 90s — ~320 over the shift.
          Timer.periodic(const Duration(seconds: 90), (t) {
            final elapsed = Duration(seconds: t.tick * 90);
            if (elapsed >= const Duration(hours: 8)) {
              t.cancel();
              return;
            }
            opCounter++;
            final id = 'op-$opCounter';
            // Every 37th op is one the leader always terminally rejects —
            // exercises the quarantine path amid otherwise-successful traffic.
            final badOp = opCounter % 37 == 0;
            enqueuedIds.add(id);
            unawaited(
              service.enqueue(
                PendingOperation(
                  id: id,
                  type: PendingOperationType.createOrder,
                  payload: badOp ? '{"bad":true}' : '{}',
                  tableId: 'table-${opCounter % 12}',
                  createdAt: DateTime(2026, 8, 5, 9).add(elapsed),
                ),
              ),
            );
          });

          // Drive relayViaLan every 30s — the cadence a reconnect-edge
          // listener plus the periodic sync tick would produce together.
          Timer.periodic(const Duration(seconds: 30), (t) {
            final up = isUp(Duration(seconds: t.tick * 30));
            unawaited(
              service.relayViaLan(
                isLeaderConnected: () => up,
                relayOne: (op) async {
                  if (op.payload.contains('"bad":true')) {
                    quarantinedIds.add(op.id);
                    return RelayOpResult.terminalFailure;
                  }
                  syncedIds.add(op.id);
                  return RelayOpResult.synced;
                },
              ),
            );
          });

          async.elapse(const Duration(hours: 8, minutes: 5));

          expect(
            service.pending,
            isEmpty,
            reason: 'every op should have drained by the end of the shift',
          );
          expect(
            syncedIds.toSet().length,
            syncedIds.length,
            reason: 'no op should have been synced twice',
          );
          expect(
            quarantinedIds.toSet().length,
            quarantinedIds.length,
            reason: 'no op should have been quarantined twice',
          );
          expect(syncedIds.toSet().intersection(quarantinedIds.toSet()), isEmpty);
          expect(syncedIds.length + quarantinedIds.length, enqueuedIds.length);
          expect(service.quarantined.map((q) => q.id).toSet(), quarantinedIds.toSet());
        });
      },
    );
  });

  group('Offline queue retry backoff over a simulated shift', () {
    test(
      'grows on repeated cloud failures, stays bounded, and resets once a pass succeeds',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        InMemorySecureStoragePlatform.install();
        FakeConnectivityPlatform.install();

        final tokenStorage = AppTokenStorage(prefs, const FlutterSecureStorage());
        final connectivity = ConnectivityCubit(Connectivity());
        final dioClient = DioClient(tokenStorage, connectivity);
        // Mirrors di.dart's real wiring — DioClient's constructor
        // unconditionally adds `aliceDioAdapter` as an interceptor, which
        // throws `LateInitializationError` on every request until an
        // `Alice` instance actually registers it.
        Alice(
          configuration: AliceConfiguration(
            showNotification: false,
            showInspectorOnShake: false,
          ),
        ).addAdapter(dioClient.aliceDioAdapter);

        var attemptCount = 0;
        var shouldFail = true;
        dioClient.dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
          attemptCount++;
          if (shouldFail) return connectionErrorResponse(options);
          return okResponse();
        });

        final outbox = await Hive.openBox<PendingOperation>(
          'soak_backoff_outbox',
          bytes: Uint8List(0),
        );
        final quarantineBox = await Hive.openBox<QuarantinedOperation>(
          'soak_backoff_quarantine',
          bytes: Uint8List(0),
        );
        final service = OfflineQueueService(outbox, quarantineBox);
        await service.enqueue(
          PendingOperation(
            id: 'backoff-op-1',
            type: PendingOperationType.createOrder,
            payload: '{}',
            tableId: 'table-1',
            createdAt: DateTime(2026, 8, 5, 9),
          ),
        );

        fakeAsync((async) {
          withClock(async.getClock(DateTime(2026, 8, 5, 9)), () {
            // Drive syncAll far more often than any real backoff would allow
            // through — if backoff weren't working, attemptCount would track
            // the tick count almost 1:1.
            Timer.periodic(const Duration(seconds: 5), (_) {
              unawaited(service.syncAll(dioClient));
            });

            async.elapse(const Duration(minutes: 20));

            expect(
              service.pending,
              hasLength(1),
              reason: 'a connection error is retryable, never a terminal drop',
            );
            expect(
              attemptCount,
              inInclusiveRange(4, 20),
              reason: 'backoff should sharply cut attempts below the '
                  '240 a naive 5s-interval retry would make in 20 minutes, '
                  'while still making forward progress',
            );

            // Network recovers. The op should drain within one backoff
            // window (capped at 2 minutes + jitter) of the flip.
            shouldFail = false;
            async.elapse(const Duration(minutes: 3));

            expect(service.pending, isEmpty);

            // A fresh failure right after a success should back off from
            // the base interval again, not still be near the 2-minute cap —
            // proves consecutiveFailures actually reset on success.
            shouldFail = true;
            unawaited(
              service.enqueue(
                PendingOperation(
                  id: 'backoff-op-2',
                  type: PendingOperationType.createOrder,
                  payload: '{}',
                  tableId: 'table-1',
                  createdAt: clock.now(),
                ),
              ),
            );
            final attemptsBeforeSecondOp = attemptCount;
            async.elapse(const Duration(seconds: 30));
            expect(
              attemptCount - attemptsBeforeSecondOp,
              greaterThanOrEqualTo(2),
              reason: 'post-reset backoff should allow at least two attempts '
                  'within 30s — a still-capped backoff would allow at most one',
            );
          });
        });
      },
    );
  });

  group('Print queue over a simulated shift', () {
    test(
      'every announced job resolves to printed or a terminal failure — none left queued/claimed',
      () async {
        final box = await Hive.openBox<PrintJob>('soak_print_queue', bytes: Uint8List(0));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final printerService = PrinterService(PrinterConfigStorage(prefs));
        final cacheService = CacheService(await Hive.openBox('soak_print_cache', bytes: Uint8List(0)));

        fakeAsync((async) {
          late PrintQueueService service;
          final jobVariant = <String, int>{};
          final announceCount = <String, int>{};
          var firstSeenCounter = 0;

          void onAnnounce({
            required String jobId,
            required String jobType,
            required String entryId,
            required String payloadBase64,
          }) {
            final variant = jobVariant.putIfAbsent(jobId, () => firstSeenCounter++ % 4);
            final n = (announceCount[jobId] ?? 0) + 1;
            announceCount[jobId] = n;
            switch (variant) {
              case 0: // claimed and printed promptly, first attempt.
                if (n == 1) {
                  Timer(const Duration(milliseconds: 500), () => service.onRemoteClaim(jobId));
                  Timer(
                    const Duration(seconds: 2),
                    () => service.onRemoteResult(jobId, 'printed', null),
                  );
                }
              case 1: // never claimed by anyone, either attempt — ends failed.
                break;
              case 2: // claimed but the claimer vanishes (lease expires); resolves on retry.
                Timer(const Duration(milliseconds: 500), () => service.onRemoteClaim(jobId));
                if (n == 2) {
                  Timer(
                    const Duration(seconds: 2),
                    () => service.onRemoteResult(jobId, 'printed', null),
                  );
                }
              case 3: // claimed, then an explicit — terminal, non-retried — failure.
                if (n == 1) {
                  Timer(const Duration(milliseconds: 500), () => service.onRemoteClaim(jobId));
                  Timer(
                    const Duration(seconds: 2),
                    () => service.onRemoteResult(jobId, 'failed', 'printer out of paper'),
                  );
                }
            }
          }

          service = PrintQueueService(
            box,
            printerService,
            cacheService,
            prefs,
            isLanRelayPossible: () => true,
            broadcastAnnounce: onAnnounce,
            broadcastClaim: (_) {},
            broadcastResult: (_, _, _) {},
          );

          var jobCounter = 0;
          Timer.periodic(const Duration(minutes: 2), (t) {
            final elapsed = Duration(minutes: t.tick * 2);
            if (elapsed >= const Duration(hours: 8)) {
              t.cancel();
              return;
            }
            jobCounter++;
            unawaited(
              service.submitJob(
                const PrinterConfig(ip: '', connectionType: 'usb', entryId: 'entry-usb-1'),
                const [1, 2, 3],
                jobType: 'kitchen',
                beep: false,
              ),
            );
          });

          async.elapse(const Duration(hours: 8, seconds: 30));

          expect(box.length, jobCounter, reason: 'no job should have vanished from the box');

          final finalStates = {for (final job in box.values) job.id: job.stateEnum};
          expect(
            finalStates.values.every(
              (s) => s == PrintJobState.printed || s == PrintJobState.failed,
            ),
            isTrue,
            reason: 'every job should have finalized — none stuck queued/claimed',
          );

          int countInState(int variant, PrintJobState state) => jobVariant.entries
              .where((e) => e.value == variant)
              .where((e) => finalStates[e.key] == state)
              .length;
          int countOfVariant(int variant) =>
              jobVariant.values.where((v) => v == variant).length;

          expect(countInState(0, PrintJobState.printed), countOfVariant(0));
          expect(countInState(1, PrintJobState.failed), countOfVariant(1));
          expect(countInState(2, PrintJobState.printed), countOfVariant(2));
          expect(countInState(3, PrintJobState.failed), countOfVariant(3));
        });
      },
    );
  });
}
