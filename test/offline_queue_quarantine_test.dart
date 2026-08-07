import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/services/offline_queue/quarantined_operation.dart';

/// Covers the quarantine mechanism added in §11 Phase 6 (sync-status UI
/// slice) — before this, a terminal 4xx or LAN-relay `terminalFailure` just
/// deleted the op from `OfflineQueueService`'s box with no trace. Exercised
/// through [OfflineQueueService.relayViaLan], which takes its network call
/// as a plain injected callback — no real `DioClient`/`ConnectivityCubit`
/// needed, the same reason `PrintQueueService`'s LAN-relay tests don't need
/// a real `LanHubService`. `syncAll`'s own direct-to-cloud drop path (the
/// six `_exec*` methods' `_dropped(e.toString())` calls) is NOT covered
/// here — that needs a real `DioClient` backed by a real `ConnectivityCubit`
/// (itself backed by `connectivity_plus`'s platform channel, unavailable in
/// this test sandbox) to exercise end to end, the same class of gap already
/// disclosed for `LoginPinCubit`/`AuthCubit`/`UserBloc` in Phase 6's first
/// slice — verified by code review instead: every `_exec*` catch block and
/// early-return drop site was changed identically, funneling through the
/// shared `_dropped()` helper that `relayViaLan`'s own quarantine call sites
/// (tested below) also feed from.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('offline_queue_quarantine_test').path);
    Hive.registerAdapter(PendingOperationTypeAdapter());
    Hive.registerAdapter(PendingOperationAdapter());
    Hive.registerAdapter(QuarantinedOperationAdapter());
  });

  var boxCounter = 0;

  Future<OfflineQueueService> freshService() async {
    boxCounter++;
    final box = await Hive.openBox<PendingOperation>('outbox_test_$boxCounter');
    final quarantineBox =
        await Hive.openBox<QuarantinedOperation>('quarantine_test_$boxCounter');
    return OfflineQueueService(box, quarantineBox);
  }

  PendingOperation op(String id, {String tableId = 'table-1'}) => PendingOperation(
        id: id,
        type: PendingOperationType.createOrder,
        payload: '{}',
        tableId: tableId,
        createdAt: DateTime.now().toUtc(),
      );

  group('relayViaLan quarantining', () {
    test('a terminalFailure result quarantines the op and removes it from pending', () async {
      final service = await freshService();
      await service.enqueue(op('op-1'));

      await service.relayViaLan(
        isLeaderConnected: () => true,
        relayOne: (_) async => RelayOpResult.terminalFailure,
      );

      expect(service.pending, isEmpty);
      expect(service.quarantined, hasLength(1));
      expect(service.quarantined.single.id, 'op-1');
      expect(service.quarantined.single.reason, isNotEmpty);
    });

    test('a synced result deletes the op without quarantining it', () async {
      final service = await freshService();
      await service.enqueue(op('op-2'));

      await service.relayViaLan(
        isLeaderConnected: () => true,
        relayOne: (_) async => RelayOpResult.synced,
      );

      expect(service.pending, isEmpty);
      expect(
        service.quarantined,
        isEmpty,
        reason: 'a real success must never show up as a rejection to investigate',
      );
    });

    test('a retryLater result leaves the op queued, not quarantined', () async {
      final service = await freshService();
      await service.enqueue(op('op-3'));

      await service.relayViaLan(
        isLeaderConnected: () => true,
        relayOne: (_) async => RelayOpResult.retryLater,
      );

      expect(service.pending.map((o) => o.id), ['op-3']);
      expect(service.quarantined, isEmpty);
    });
  });

  group('manual resolution', () {
    Future<OfflineQueueService> serviceWithOneQuarantined(String id) async {
      final service = await freshService();
      await service.enqueue(op(id));
      await service.relayViaLan(
        isLeaderConnected: () => true,
        relayOne: (_) async => RelayOpResult.terminalFailure,
      );
      return service;
    }

    test('retryQuarantined moves the op back to pending under the same id', () async {
      final service = await serviceWithOneQuarantined('op-4');

      await service.retryQuarantined('op-4');

      expect(service.quarantined, isEmpty);
      expect(service.pending.map((o) => o.id), ['op-4']);
    });

    test('retryQuarantined on an unknown id is a safe no-op', () async {
      final service = await freshService();
      await service.retryQuarantined('never-existed');
      expect(service.pending, isEmpty);
      expect(service.quarantined, isEmpty);
    });

    test('dismissQuarantined discards the op for good, without re-enqueueing it', () async {
      final service = await serviceWithOneQuarantined('op-5');

      await service.dismissQuarantined('op-5');

      expect(service.quarantined, isEmpty);
      expect(service.pending, isEmpty);
    });

    test('quarantined lists newest-first', () async {
      final service = await freshService();
      await service.enqueue(op('older'));
      await service.relayViaLan(
        isLeaderConnected: () => true,
        relayOne: (_) async => RelayOpResult.terminalFailure,
      );
      await Future.delayed(const Duration(milliseconds: 5));
      await service.enqueue(op('newer'));
      await service.relayViaLan(
        isLeaderConnected: () => true,
        relayOne: (_) async => RelayOpResult.terminalFailure,
      );

      expect(service.quarantined.map((o) => o.id).toList(), ['newer', 'older']);
    });
  });

  group('reactivity', () {
    test('listenable notifies when an op is enqueued', () async {
      final service = await freshService();
      var notified = false;
      service.listenable.addListener(() => notified = true);

      await service.enqueue(op('op-6'));

      expect(notified, isTrue);
    });

    test('quarantineListenable notifies when an op is quarantined', () async {
      final service = await freshService();
      await service.enqueue(op('op-7'));
      var notified = false;
      service.quarantineListenable.addListener(() => notified = true);

      await service.relayViaLan(
        isLeaderConnected: () => true,
        relayOne: (_) async => RelayOpResult.terminalFailure,
      );

      expect(notified, isTrue);
    });
  });
}
