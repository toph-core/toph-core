// BACKEND_SYNC_PLAN.md §6 — first-ever test coverage for LeaseManager:
// solo-mode arbitration, the durable check against LocalDatabase, ephemeral
// claim racing + TTL expiry, release (same-process and leader-side), and the
// client-mode round trip / unreachable branches against a fake LanHub.
//
// Hand-written `implements + noSuchMethod` fakes, matching this test suite's
// existing convention (test/support/*) rather than a mocking package.

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';

CafeTableModel table(String id, {TableStatus status = TableStatus.free}) =>
    CafeTableModel(
      id: id,
      hallId: 'hall-1',
      number: 1,
      posX: 0,
      posY: 0,
      width: 1,
      height: 1,
      rotation: 0,
      capacity: 4,
      status: status,
    );

class FakeLocalDatabase implements LocalDatabase {
  List<CafeTableModel> tables = [];

  @override
  List<CafeTableModel> getTables() => tables;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class FakeLanHub implements LanHubService {
  LanMode fakeMode = LanMode.disabled;
  bool connected = true;

  /// Reply the fake "leader" sends back; `null` simulates a timeout.
  LanHubMessage? Function({required String tableId, required String terminalId})?
      onRequestLease;

  final List<({String tableId, String terminalId})> released = [];

  @override
  LanMode get mode => fakeMode;

  @override
  bool get isClientConnected => connected;

  @override
  Future<LanHubMessage?> requestLease({
    required String tableId,
    required String terminalId,
  }) async =>
      onRequestLease?.call(tableId: tableId, terminalId: terminalId);

  @override
  void releaseLease({required String tableId, required String terminalId}) {
    released.add((tableId: tableId, terminalId: terminalId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class FakePrintQueueService implements PrintQueueService {
  final String fakeTerminalId;
  FakePrintQueueService(this.fakeTerminalId);

  @override
  String get terminalId => fakeTerminalId;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  late FakeLocalDatabase db;
  late FakeLanHub lanHub;
  late LeaseManager lease;

  setUp(() {
    db = FakeLocalDatabase();
    lanHub = FakeLanHub();
    lease = LeaseManager(lanHub: lanHub, localDb: db);
    GetIt.I.registerSingleton<PrintQueueService>(
      FakePrintQueueService('terminal-me'),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('solo / leader arbitration (durable check)', () {
    test('free table in disabled (solo) mode is granted', () async {
      db.tables = [table('t1')];
      final result = await lease.acquireTableLease('t1');
      expect(result.isGranted, isTrue);
    });

    test('durably busy table is rejected', () async {
      db.tables = [table('t1', status: TableStatus.busy)];
      final result = await lease.acquireTableLease('t1');
      expect(result.isGranted, isFalse);
      expect(result.isUnreachable, isFalse);
    });

    test('unknown table id falls through the durable check and is granted',
        () async {
      db.tables = [table('other')];
      final result = await lease.acquireTableLease('t1');
      expect(result.isGranted, isTrue);
    });

    test('server mode arbitrates locally, same as solo', () async {
      lanHub.fakeMode = LanMode.server;
      db.tables = [table('t1')];
      expect((await lease.acquireTableLease('t1')).isGranted, isTrue);
      db.tables = [table('t1', status: TableStatus.busy)];
      expect((await lease.acquireTableLease('t1')).isGranted, isFalse);
    });
  });

  group('ephemeral claims (leader side)', () {
    test('a second terminal racing within the TTL is rejected with heldBy',
        () async {
      db.tables = [table('t1')];
      final first = await lease.handleLeaseRequestAsLeader(
        LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-a'),
      );
      expect(first.type, LanHubMessageType.leaseGranted);

      final second = await lease.handleLeaseRequestAsLeader(
        LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-b'),
      );
      expect(second.type, LanHubMessageType.leaseRejected);
      expect(second.leaseHeldBy, 'terminal-a');
    });

    test('the same claimant re-requesting its own live claim is granted',
        () async {
      db.tables = [table('t1')];
      final first = await lease.handleLeaseRequestAsLeader(
        LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-a'),
      );
      expect(first.type, LanHubMessageType.leaseGranted);
      final again = await lease.handleLeaseRequestAsLeader(
        LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-a'),
      );
      expect(again.type, LanHubMessageType.leaseGranted);
    });

    test('an expired ephemeral claim no longer blocks a new claimant',
        () async {
      db.tables = [table('t1')];
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      await withClock(Clock.fixed(t0), () async {
        final first = await lease.handleLeaseRequestAsLeader(
          LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-a'),
        );
        expect(first.type, LanHubMessageType.leaseGranted);
      });

      // 6s later — past the 5s ephemeral TTL backstop.
      await withClock(Clock.fixed(t0.add(const Duration(seconds: 6))),
          () async {
        final second = await lease.handleLeaseRequestAsLeader(
          LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-b'),
        );
        expect(second.type, LanHubMessageType.leaseGranted);
      });
    });

    test('releaseTableLease evicts the claim immediately (no TTL wait)',
        () async {
      db.tables = [table('t1')];
      expect((await lease.acquireTableLease('t1')).isGranted, isTrue);
      lease.releaseTableLease('t1');
      final next = await lease.handleLeaseRequestAsLeader(
        LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-b'),
      );
      expect(next.type, LanHubMessageType.leaseGranted);
    });

    test("leader-side release from the wrong terminal doesn't evict", () async {
      db.tables = [table('t1')];
      final granted = await lease.handleLeaseRequestAsLeader(
        LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-a'),
      );
      expect(granted.type, LanHubMessageType.leaseGranted);

      lease.handleLeaseReleaseAsLeader(
        LanHubMessage.leaseRelease(tableId: 't1', terminalId: 'terminal-b'),
      );
      final stillHeld = await lease.handleLeaseRequestAsLeader(
        LanHubMessage.leaseRequest(tableId: 't1', terminalId: 'terminal-c'),
      );
      expect(stillHeld.type, LanHubMessageType.leaseRejected);
      expect(stillHeld.leaseHeldBy, 'terminal-a');
    });
  });

  group('client mode (follower → leader round trip)', () {
    setUp(() {
      lanHub.fakeMode = LanMode.client;
    });

    test('disconnected follower gets unreachable, not rejected', () async {
      lanHub.connected = false;
      final result = await lease.acquireTableLease('t1');
      expect(result.isGranted, isFalse);
      expect(result.isUnreachable, isTrue);
    });

    test('granted reply from the leader is granted', () async {
      lanHub.onRequestLease = ({required tableId, required terminalId}) =>
          LanHubMessage.leaseGranted(tableId: tableId);
      final result = await lease.acquireTableLease('t1');
      expect(result.isGranted, isTrue);
    });

    test('rejected reply carries the holding terminal through', () async {
      lanHub.onRequestLease = ({required tableId, required terminalId}) =>
          LanHubMessage.leaseRejected(tableId: tableId, heldBy: 'terminal-x');
      final result = await lease.acquireTableLease('t1');
      expect(result.isGranted, isFalse);
      expect(result.heldBy, 'terminal-x');
      expect(result.isUnreachable, isFalse);
    });

    test('a null (timed-out) reply is unreachable', () async {
      lanHub.onRequestLease = ({required tableId, required terminalId}) => null;
      final result = await lease.acquireTableLease('t1');
      expect(result.isGranted, isFalse);
      expect(result.isUnreachable, isTrue);
    });

    test('release in client mode sends the LAN release message', () async {
      lanHub.onRequestLease = ({required tableId, required terminalId}) =>
          LanHubMessage.leaseGranted(tableId: tableId);
      await lease.acquireTableLease('t1');
      lease.releaseTableLease('t1');
      expect(lanHub.released, hasLength(1));
      expect(lanHub.released.single.tableId, 't1');
      expect(lanHub.released.single.terminalId, 'terminal-me');
    });
  });
}
