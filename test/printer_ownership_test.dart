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

/// Printers belong to a POS instance.
///
/// The behaviour under test replaces one assumption that was baked into
/// `PrintQueueService`: "a network/TCP printer never needs relay — any terminal
/// can already reach it directly". That is only true of a flat network. A
/// kitchen printer on the kitchen's own switch, or one behind a second access
/// point, answers exactly one machine, and every job raised anywhere else used
/// to burn its socket timeout and fail. With an owner recorded on the printer,
/// such a job is relayed to the owning terminal instead.
///
/// Same construction as `print_queue_service_test.dart`: two service instances
/// stand in for two terminals with their broadcast callbacks wired into each
/// other, and a real `PrinterService` throughout — which makes outcomes
/// deterministic without mocks, because a `usb` print always fails on this
/// non-Windows machine and a `cable` print to a live loopback socket always
/// succeeds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('printer_ownership_test').path);
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PrintJobAdapter());
    }
  });

  var boxCounter = 0;
  Future<Box<PrintJob>> freshBox() async {
    boxCounter++;
    return Hive.openBox<PrintJob>('printer_ownership_test_$boxCounter');
  }

  /// One terminal's device-scoped store, logged in as [cashRegisterId].
  ///
  /// `setMockInitialValues` swaps in a fresh in-memory backing store and each
  /// instance answers from its own snapshot, so two of these are as independent
  /// as two PCs. The auth-context key is seeded directly because that is
  /// exactly what `LoginDataScopeService` writes on every successful login, and
  /// it is where `PrinterConfigStorage` reads this terminal's identity from.
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

  Future<PrinterService> printerFor(PrinterConfigStorage storage) async =>
      PrinterService(storage);

  Future<PrintQueueService> queueFor(
    PrinterConfigStorage storage, {
    required PrinterService printer,
    bool Function() isLanRelayPossible = _alwaysTrue,
    PrintAnnounceBroadcaster broadcastAnnounce = _noopAnnounce,
    PrintClaimBroadcaster broadcastClaim = _noopClaim,
    PrintGrantBroadcaster broadcastGrant = _noopGrant,
    PrintResultBroadcaster broadcastResult = _noopResult,
  }) async {
    return PrintQueueService(
      await freshBox(),
      printer,
      storage,
      await SharedPreferences.getInstance(),
      isLanRelayPossible: isLanRelayPossible,
      broadcastAnnounce: broadcastAnnounce,
      broadcastClaim: broadcastClaim,
      broadcastGrant: broadcastGrant,
      broadcastResult: broadcastResult,
      claimWait: const Duration(milliseconds: 150),
      lease: const Duration(milliseconds: 200),
      // Generous on purpose: these exercise routing and the claim/lease state
      // machine, not caller latency. The production budget is covered in
      // print_relay_deferral_test.dart's ceiling group.
      callerBudget: const Duration(seconds: 5),
    );
  }

  PrinterSettingEntry networkPrinter({
    required String id,
    required String owner,
    required int port,
    String type = 'close_check',
    String name = 'Kassa',
  }) =>
      PrinterSettingEntry(
        id: id,
        ip: InternetAddress.loopbackIPv4.address,
        port: port,
        name: name,
        type: type,
        connectedEntityIds: const [],
        connectionType: 'cable',
        ownerCashRegisterId: owner,
      );

  group('routing by owner', () {
    test(
        'a network printer owned by another terminal is relayed, not dialled '
        'directly', () async {
      // The regression this whole change exists to prevent. Terminal A can open
      // a socket to this address — the test server is on loopback — so under the
      // old rule A would have printed it locally and never told B. The only
      // thing stopping it is that the printer names B as its owner.
      final serverSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => serverSocket.close());
      serverSocket.listen((s) => s.listen((_) {}));

      final printer = networkPrinter(
        id: 'kitchen-1',
        owner: 'till-B',
        port: serverSocket.port,
      );

      final storageA = await terminal('till-A', printers: [printer]);
      final serviceA = await printerFor(storageA);
      final storageB = await terminal('till-B', printers: [printer]);
      final serviceB = await printerFor(storageB);

      late PrintQueueService queueA;
      late PrintQueueService queueB;

      var announced = 0;
      queueA = await queueFor(
        storageA,
        printer: serviceA,
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
        printer: serviceB,
        broadcastClaim: queueA.onRemoteClaim,
        broadcastResult: queueA.onRemoteResult,
      );

      final config = storageA.getCloseCheckPrinter()!;
      expect(config.ownerCashRegisterId, 'till-B');

      final r = await queueA.submitJob(config, [1, 2, 3], jobType: 'cashier');

      expect(announced, 1, reason: 'A must relay rather than dial directly');
      expect(r.ok, isTrue, reason: 'B owns it and can reach it');
      expect(queueA.jobs.single.stateEnum, PrintJobState.printed);
      expect(
        queueA.jobs.single.claimedAt,
        isNotNull,
        reason: 'B claimed the job, so it went over the relay',
      );
    });

    test('a network printer this terminal owns is printed locally', () async {
      final serverSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => serverSocket.close());
      serverSocket.listen((s) => s.listen((_) {}));

      final printer = networkPrinter(
        id: 'till-printer',
        owner: 'till-A',
        port: serverSocket.port,
      );
      final storage = await terminal('till-A', printers: [printer]);

      var announced = false;
      final queue = await queueFor(
        storage,
        printer: await printerFor(storage),
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            announced = true,
      );

      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(r.ok, isTrue);
      expect(announced, isFalse, reason: 'no relay for a printer we own');
      expect(queue.jobs.single.claimedAt, isNull);
    });

    test('an unowned network printer keeps the old direct-print behaviour',
        () async {
      // Every row created before printers had owners is unowned, so this is the
      // path existing installs stay on until someone assigns a printer.
      final serverSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => serverSocket.close());
      serverSocket.listen((s) => s.listen((_) {}));

      final printer = networkPrinter(
        id: 'legacy',
        owner: '',
        port: serverSocket.port,
      );
      final storage = await terminal('till-A', printers: [printer]);

      var announced = false;
      final queue = await queueFor(
        storage,
        printer: await printerFor(storage),
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            announced = true,
      );

      final config = storage.getCloseCheckPrinter()!;
      expect(config.isUnowned, isTrue);

      final r = await queue.submitJob(config, [1, 2, 3], jobType: 'cashier');

      expect(r.ok, isTrue);
      expect(announced, isFalse);
    });

    test(
        'a USB printer registered here with no Windows printer picked fails '
        'fast instead of relaying into silence', () async {
      // Usually a reinstall: the entry syncs down from the backend with this
      // terminal as its owner, but the Windows printer name is device-local and
      // did not survive. Relaying would be pointless — no other terminal owns
      // it — so the operator gets the actionable message immediately rather
      // than after a claim wait and a retry.
      final storage = await terminal('till-A', printers: [
        const PrinterSettingEntry(
          id: 'usb-1',
          ip: '',
          port: 0,
          name: 'Oshxona',
          type: 'close_check',
          connectedEntityIds: [],
          connectionType: 'usb',
          ownerCashRegisterId: 'till-A',
        ),
      ]);

      var announced = false;
      final queue = await queueFor(
        storage,
        printer: await printerFor(storage),
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) =>
            announced = true,
      );

      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(r.ok, isFalse);
      expect(r.error, contains('Windows printeri'));
      expect(announced, isFalse);
      expect(queue.jobs.single.stateEnum, PrintJobState.failed);
    });

    test('a terminal does not claim an announcement for a printer it does not own',
        () async {
      // Ownership is what gates the claim now, not merely holding a USB name.
      final printer = networkPrinter(
        id: 'kitchen-1',
        owner: 'till-C',
        port: 9100,
      );
      final storageB = await terminal('till-B', printers: [printer]);

      var claimed = false;
      final queueB = await queueFor(
        storageB,
        printer: await printerFor(storageB),
        broadcastClaim: (_, __) => claimed = true,
      );

      await queueB.onRemoteAnnounce(
        jobId: 'job-1',
        jobType: 'cashier',
        entryId: 'kitchen-1',
        payloadBase64: base64Encode([1, 2, 3]),
      );

      expect(claimed, isFalse);
    });

    test('LAN off — a job for another terminal\'s printer fails with a reason',
        () async {
      final printer = networkPrinter(
        id: 'kitchen-1',
        owner: 'till-B',
        port: 9100,
      );
      final storage = await terminal('till-A', printers: [printer]);

      final queue = await queueFor(
        storage,
        printer: await printerFor(storage),
        isLanRelayPossible: () => false,
      );

      final r = await queue.submitJob(
        storage.getCloseCheckPrinter()!,
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(r.ok, isFalse);
      expect(r.error, contains('LAN'));
      expect(queue.jobs.single.stateEnum, PrintJobState.failed);
    });
  });

  group('resolving which printer to use', () {
    test('this terminal\'s own printer wins over an equally valid sibling',
        () async {
      // In a hall where every till has its own receipt printer, taking the
      // first matching row would send every check over the LAN to whichever
      // printer happened to be listed first.
      final storage = await terminal('till-B', printers: [
        networkPrinter(id: 'a', owner: 'till-A', port: 9101, name: 'A'),
        networkPrinter(id: 'b', owner: 'till-B', port: 9102, name: 'B'),
        networkPrinter(id: 'c', owner: '', port: 9103, name: 'C'),
      ]);

      expect(storage.getCloseCheckPrinter()!.entryId, 'b');
    });

    test('an unowned printer is preferred over another terminal\'s', () async {
      final storage = await terminal('till-Z', printers: [
        networkPrinter(id: 'a', owner: 'till-A', port: 9101, name: 'A'),
        networkPrinter(id: 'c', owner: '', port: 9103, name: 'C'),
      ]);

      expect(storage.getCloseCheckPrinter()!.entryId, 'c');
    });

    test('a category printer resolves with the same preference', () async {
      final storage = await terminal('till-B', printers: [
        const PrinterSettingEntry(
          id: 'kitchen-a',
          ip: '10.0.0.1',
          port: 9100,
          name: 'Kitchen A',
          type: 'category',
          connectedEntityIds: ['cat-1'],
          connectionType: 'cable',
          ownerCashRegisterId: 'till-A',
        ),
        const PrinterSettingEntry(
          id: 'kitchen-b',
          ip: '10.0.0.2',
          port: 9100,
          name: 'Kitchen B',
          type: 'category',
          connectedEntityIds: ['cat-1'],
          connectionType: 'cable',
          ownerCashRegisterId: 'till-B',
        ),
      ]);

      expect(storage.categoryPrinterForOrNull('cat-1')!.entryId, 'kitchen-b');
    });

    test('a USB printer is usable despite having no ip or port', () async {
      // The old resolvers required `ip.isNotEmpty && port > 0`, which is why
      // USB rows had to carry a placeholder address at all.
      final storage = await terminal('till-A', printers: [
        const PrinterSettingEntry(
          id: 'usb-1',
          ip: '',
          port: 0,
          name: 'Oshxona',
          type: 'close_check',
          connectedEntityIds: [],
          connectionType: 'usb',
          ownerCashRegisterId: 'till-A',
        ),
      ]);

      final config = storage.getCloseCheckPrinter();
      expect(config, isNotNull);
      expect(config!.entryId, 'usb-1');
      expect(config.usesWindowsPrinter, isTrue);
    });
  });

  group('device-local state survives the id change at sync', () {
    test('the USB printer name and paper size follow the entry to its backend id',
        () async {
      // A printer added here gets a `local-…` id because the push to the backend
      // is best-effort and unawaited; the next login replaces the list with the
      // server's, under the server's UUID. Without re-keying, the Windows
      // printer name is orphaned and the printer silently stops working.
      final storage = await terminal('till-A');

      const local = PrinterSettingEntry(
        id: 'local-123',
        ip: '',
        port: 0,
        name: 'Oshxona',
        type: 'close_check',
        connectedEntityIds: [],
        connectionType: 'usb',
        ownerCashRegisterId: 'till-A',
      );
      await storage.applyPrinterSettingsList([local]);
      await storage.saveUsbPrinterName('local-123', 'XP-80C');
      await storage.savePaperSizeCode('local-123', kPaperSizeCode58);

      // Same printer, server-assigned id.
      await storage.applyPrinterSettingsList([
        local.copyWith(id: '9f1c0f4e-0000-0000-0000-000000000001'),
      ]);

      expect(
        storage.getUsbPrinterName('9f1c0f4e-0000-0000-0000-000000000001'),
        'XP-80C',
      );
      expect(
        storage.getPaperSizeCode('9f1c0f4e-0000-0000-0000-000000000001'),
        kPaperSizeCode58,
      );
    });

    test('a genuinely different printer does not inherit anything', () async {
      final storage = await terminal('till-A');

      await storage.applyPrinterSettingsList([
        const PrinterSettingEntry(
          id: 'local-1',
          ip: '',
          port: 0,
          name: 'Oshxona',
          type: 'close_check',
          connectedEntityIds: [],
          connectionType: 'usb',
          ownerCashRegisterId: 'till-A',
        ),
      ]);
      await storage.saveUsbPrinterName('local-1', 'XP-80C');

      // Different name — a second, distinct USB printer, not a re-id.
      await storage.applyPrinterSettingsList([
        const PrinterSettingEntry(
          id: 'server-2',
          ip: '',
          port: 0,
          name: 'Bar',
          type: 'close_check',
          connectedEntityIds: [],
          connectionType: 'usb',
          ownerCashRegisterId: 'till-A',
        ),
      ]);

      expect(storage.getUsbPrinterName('server-2'), isNull);
    });
  });

  group('parsing the API payload', () {
    test('owner, branch and name round-trip', () {
      final entry = PrinterSettingEntry.fromJson({
        'id': 'p1',
        'ip': '192.168.1.50',
        'port': 9100,
        'name': 'Oshxona',
        'type': 'category',
        'connection_type': 'cable',
        'branch_id': 'branch-1',
        'owner_cash_register_id': 'till-B',
        'connected_entity_ids': ['cat-1'],
      });

      expect(entry.name, 'Oshxona');
      expect(entry.branchId, 'branch-1');
      expect(entry.ownerCashRegisterId, 'till-B');
      expect(entry.isUnowned, isFalse);
      expect(entry.isOwnedBy('till-B'), isTrue);
      expect(entry.isOwnedBy('till-A'), isFalse);

      final round = PrinterSettingEntry.fromJson(entry.toJson());
      expect(round.ownerCashRegisterId, 'till-B');
      expect(round.branchId, 'branch-1');
      expect(round.name, 'Oshxona');
    });

    test('a USB row keeps port 0 rather than being "corrected" to 9100', () {
      // The old parser floored any non-positive port to 9100, which combined
      // with the placeholder IP to make every USB printer look identical.
      final entry = PrinterSettingEntry.fromJson({
        'id': 'p2',
        'ip': '',
        'port': 0,
        'type': 'close_check',
        'connection_type': 'usb',
        'connected_entity_ids': <String>[],
      });

      expect(entry.port, 0);
      expect(entry.isAddressless, isTrue);
    });

    test('a network row with a nonsense port still falls back to 9100', () {
      final entry = PrinterSettingEntry.fromJson({
        'id': 'p3',
        'ip': '192.168.1.50',
        'port': 0,
        'type': 'close_check',
        'connection_type': 'cable',
        'connected_entity_ids': <String>[],
      });

      expect(entry.port, 9100);
    });

    test('a row with no owner field at all reads as unowned', () {
      // What every pre-ownership backend row looks like.
      final entry = PrinterSettingEntry.fromJson({
        'id': 'p4',
        'ip': '192.168.1.50',
        'port': 9100,
        'type': 'close_check',
        'connection_type': 'cable',
        'connected_entity_ids': <String>[],
      });

      expect(entry.isUnowned, isTrue);
      expect(entry.isOwnedBy('till-A'), isFalse);
    });
  });

  test('a terminal that is not logged in owns nothing', () async {
    // No auth context yet — every printer reads as someone else's or nobody's,
    // and nothing claims a relayed job by accident.
    SharedPreferences.setMockInitialValues({});
    final storage = PrinterConfigStorage(await SharedPreferences.getInstance());
    await storage.applyPrinterSettingsList([
      networkPrinter(id: 'a', owner: 'till-A', port: 9100),
    ]);

    expect(storage.myCashRegisterId, '');
    expect(storage.ownsEntryId('a'), isFalse);
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
