import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_entry.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_log_service.dart';

/// Covers the privileged-action audit log added in §11 Phase 6 (final
/// slice) — every `requireManagerPincode` attempt (void, shift open/close;
/// approved or denied; online or offline) now gets recorded here, closing
/// the gap the plan doc flagged from the start: previously there was
/// nothing to audit because privileged actions couldn't happen offline at
/// all, and even the online-only path recorded nothing.
///
/// `AuthDatasourceImpl.verifyPincodeRole`'s own online/offline orchestration
/// (skip the network call when offline, cache the result on success, purge
/// the cache on a definite rejection, fall back to cache on an inconclusive
/// one) is NOT covered here — it needs a real `DioClient` backed by a real
/// `ConnectivityCubit` (itself backed by `connectivity_plus`'s platform
/// channel, unavailable in this test sandbox) to exercise end to end. Same
/// class of gap already disclosed multiple times earlier in this phase for
/// `LoginPinCubit`/`AuthCubit`/`UserBloc`/`SyncEngine.tick`'s direct-to-cloud
/// path — verified by code review instead: the primitives it's built from
/// (`OfflineAuthCache.saveForPin`/`getForPin`/`removeForPin`,
/// `Failure.isDefiniteAuthRejection`) are already fully tested elsewhere,
/// and the new orchestration mirrors `LoginPinCubit.login()`'s
/// already-reviewed shape almost exactly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('audit_log_test').path);
    Hive.registerAdapter(PrivilegedActionAuditEntryAdapter());
  });

  var boxCounter = 0;

  Future<PrivilegedActionAuditLogService> freshService() async {
    boxCounter++;
    final box = await Hive.openBox<PrivilegedActionAuditEntry>('audit_log_test_$boxCounter');
    return PrivilegedActionAuditLogService(box);
  }

  test('an approved entry records the approver and requester', () async {
    final service = await freshService();

    await service.record(
      action: PrivilegedAction.voidOrderItem,
      approved: true,
      verifiedOffline: false,
      approverUserId: 'mgr-1',
      approverName: 'Aziza Manager',
      requestedByUserId: 'waiter-1',
      requestedByName: 'Bekzod Waiter',
    );

    final entry = service.entries.single;
    expect(entry.action, PrivilegedAction.voidOrderItem.name);
    expect(entry.approved, isTrue);
    expect(entry.verifiedOffline, isFalse);
    expect(entry.approverUserId, 'mgr-1');
    expect(entry.approverName, 'Aziza Manager');
    expect(entry.requestedByUserId, 'waiter-1');
    expect(entry.requestedByName, 'Bekzod Waiter');
    expect(entry.reason, isNull);
  });

  test('a denied entry records the reason, with no approver identity', () async {
    final service = await freshService();

    await service.record(
      action: PrivilegedAction.shiftClose,
      approved: false,
      verifiedOffline: true,
      reason: 'offline_unverified',
      requestedByUserId: 'cashier-1',
      requestedByName: 'Nodira Cashier',
    );

    final entry = service.entries.single;
    expect(entry.approved, isFalse);
    expect(entry.verifiedOffline, isTrue);
    expect(entry.reason, 'offline_unverified');
    expect(entry.approverUserId, isNull);
    expect(entry.approverName, isNull);
  });

  test('entries are ordered newest-first', () async {
    final service = await freshService();

    await service.record(
      action: PrivilegedAction.shiftOpen,
      approved: true,
      verifiedOffline: false,
    );
    await Future.delayed(const Duration(milliseconds: 5));
    await service.record(
      action: PrivilegedAction.shiftClose,
      approved: true,
      verifiedOffline: false,
    );

    expect(
      service.entries.map((e) => e.action).toList(),
      [PrivilegedAction.shiftClose.name, PrivilegedAction.shiftOpen.name],
    );
  });

  test('multiple attempts for the same action all persist independently', () async {
    final service = await freshService();

    for (var i = 0; i < 3; i++) {
      await service.record(
        action: PrivilegedAction.voidOrderItem,
        approved: i.isEven,
        verifiedOffline: false,
      );
    }

    expect(service.entries, hasLength(3));
    expect(service.entries.where((e) => e.approved), hasLength(2));
  });

  test('listenable notifies when a new attempt is recorded', () async {
    final service = await freshService();
    var notified = false;
    service.listenable.addListener(() => notified = true);

    await service.record(
      action: PrivilegedAction.shiftOpen,
      approved: true,
      verifiedOffline: false,
    );

    expect(notified, isTrue);
  });
}
