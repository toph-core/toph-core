/// Terminals tell each other which printers are plugged into them.
///
/// Why this exists at all: the deployed backend predates printer ownership and
/// the POS token carries no `cash_register_id`, so `myCashRegisterId` is `''`
/// on every terminal and every printer row reads as unowned. Both reported
/// symptoms follow from that one gap —
///
///  * a close check raised on the hub had no `close_check` entry to find,
///    because the till's USB printer only ever existed on the till, and fell
///    back to the hardcoded `192.168.1.222`;
///  * a kitchen ticket raised on the client dialled the kitchen printer
///    directly across a network that does not route to it.
///
/// `LanHubMessage.printerSettings` closes it without any backend change: each
/// terminal announces its own entries, under its own entry ids, and the
/// receiver records who they belong to in a device-local map — never in
/// `ownerCashRegisterId`, which is the backend's field and rejects anything
/// that is not a UUID.
///
/// Two `PrintQueueService` instances with their broadcast callbacks wired into
/// each other stand in for two terminals, the same construction
/// `printer_ownership_test.dart` uses.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_message.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_job.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('printer_lan_share_test').path,
    );
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PrintJobAdapter());
    }
  });

  var boxCounter = 0;
  Future<Box<PrintJob>> freshBox() async {
    boxCounter++;
    return Hive.openBox<PrintJob>('printer_lan_share_test_$boxCounter');
  }

  /// One terminal's store. `cashRegisterId` is `''` by default — the state the
  /// live backend actually leaves both machines in.
  Future<PrinterConfigStorage> terminal({
    String cashRegisterId = '',
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
    PrintAnnounceBroadcaster broadcastAnnounce = _noopAnnounce,
    PrintClaimBroadcaster broadcastClaim = _noopClaim,
    PrintGrantBroadcaster broadcastGrant = _noopGrant,
    PrintResultBroadcaster broadcastResult = _noopResult,
  }) async =>
      PrintQueueService(
        await freshBox(),
        printer,
        storage,
        await SharedPreferences.getInstance(),
        isLanRelayPossible: () => true,
        broadcastAnnounce: broadcastAnnounce,
        broadcastClaim: broadcastClaim,
        broadcastGrant: broadcastGrant,
        broadcastResult: broadcastResult,
        claimWait: const Duration(milliseconds: 60),
        lease: const Duration(milliseconds: 200),
        callerBudget: const Duration(seconds: 5),
      );

  /// The till's USB close-check printer: created on the till, addressless, and
  /// invisible to every other machine until it is announced.
  PrinterSettingEntry tillUsbCloseCheck({String id = 'local-1'}) =>
      PrinterSettingEntry(
        id: id,
        ip: '',
        port: 0,
        name: 'Kassa',
        type: 'close_check',
        connectedEntityIds: const [],
        connectionType: 'usb',
        ownerCashRegisterId: '',
      );

  PrinterSettingEntry kitchenNetworkPrinter({
    required int port,
    String id = 'kitchen-1',
  }) =>
      PrinterSettingEntry(
        id: id,
        ip: InternetAddress.loopbackIPv4.address,
        port: port,
        name: 'Oshxona',
        type: 'category',
        connectedEntityIds: const ['cat-1'],
        connectionType: 'cable',
        ownerCashRegisterId: '',
      );

  /// Hands [from]'s announcement to [to], exactly as `LanHubService` does on
  /// receipt: the wire format is a real `LanHubMessage`, parsed back.
  Future<void> announce({
    required PrinterConfigStorage from,
    required String fromTerminalId,
    required PrinterConfigStorage to,
  }) async {
    final wire = LanHubMessage.printerSettings(
      terminalId: fromTerminalId,
      cashRegisterId: from.myCashRegisterId,
      entriesJson:
          PrinterSettingEntry.encodeList(from.entriesOwnedByThisTerminal()),
    ).toJson();

    final msg = LanHubMessage.tryParse(wire)!;
    expect(msg.type, LanHubMessageType.printerSettings);
    await to.applyPeerPrinterSettings(
      peerTerminalId: msg.printTerminalId!,
      entries: PrinterSettingEntry.listFromJsonList(
        jsonDecode(msg.printerEntries!) as List,
      ),
    );
  }

  group('learning a peer\'s printers', () {
    test('the hub learns the till\'s close-check printer and stops falling '
        'back to 192.168.1.222', () async {
      final till = await terminal(printers: [tillUsbCloseCheck()]);
      await till.saveUsbPrinterName('local-1', 'XP-80C');
      final hub = await terminal();

      expect(
        hub.closeCheckConfigOrFallback().ip,
        PrinterConfigStorage.fallbackCloseCheckIp,
        reason: 'the symptom, before the announcement',
      );

      await announce(from: till, fromTerminalId: 'term-till', to: hub);

      final config = hub.closeCheckConfigOrFallback();
      expect(config.entryId, 'local-1', reason: 'the till\'s own entry id');
      expect(config.connectionType, 'usb');
      expect(hub.lanOwnerOf('local-1'), 'term-till');
    });

    test('a peer entry is not echoed back as this terminal\'s own', () async {
      // Otherwise ownership would drift: the hub would announce the till's
      // printer as the hub's, and the till would relay to it.
      final till = await terminal(printers: [tillUsbCloseCheck()]);
      final hub = await terminal(printers: [kitchenNetworkPrinter(port: 9100)]);

      await announce(from: till, fromTerminalId: 'term-till', to: hub);

      expect(
        hub.entriesOwnedByThisTerminal().map((e) => e.id),
        ['kitchen-1'],
      );
    });

    test('a printer this terminal already has is left alone', () async {
      // Both machines synced the same row from the backend. Neither may take
      // it from the other: if both marked it as the peer's, neither would ever
      // claim a job for it.
      final shared = kitchenNetworkPrinter(port: 9100, id: 'be-1');
      final hub = await terminal(printers: [shared]);
      final client = await terminal(printers: [shared]);

      await announce(from: hub, fromTerminalId: 'term-hub', to: client);

      expect(client.listEntries().length, 1);
      expect(client.lanOwnerOf('be-1'), isNull);
      expect(client.entriesOwnedByThisTerminal().length, 1);
    });

    test('the same printer under a different id does not become a duplicate',
        () async {
      // Identity, not id: the operator added the same printer on both machines
      // before either reached the backend.
      final hub = await terminal(
        printers: [kitchenNetworkPrinter(port: 9100, id: 'local-hub')],
      );
      final client = await terminal(
        printers: [kitchenNetworkPrinter(port: 9100, id: 'local-client')],
      );

      await announce(from: hub, fromTerminalId: 'term-hub', to: client);

      expect(client.listEntries().map((e) => e.id), ['local-client']);
      expect(client.lanOwnerOf('local-hub'), isNull);
    });

    test('a printer deleted on the peer disappears here too', () async {
      final till = await terminal(printers: [tillUsbCloseCheck()]);
      final hub = await terminal();
      await announce(from: till, fromTerminalId: 'term-till', to: hub);
      expect(hub.listEntries().length, 1);

      await till.deleteEntry('local-1');
      await announce(from: till, fromTerminalId: 'term-till', to: hub);

      expect(hub.listEntries(), isEmpty);
      expect(hub.lanOwnerOf('local-1'), isNull);
    });
  });

  group('routing on what the LAN said', () {
    test('a job for a peer\'s printer is relayed, and the owner prints it once',
        () async {
      // The close check raised on the hub for the till's USB printer: the whole
      // point of the exercise.
      final till = await terminal(printers: [tillUsbCloseCheck()]);
      // The till holds the Windows printer name, which is what makes it — and
      // only it — claimable for this entry.
      await till.saveUsbPrinterName('local-1', 'XP-80C');
      final hub = await terminal();

      late PrintQueueService hubQueue;
      late PrintQueueService tillQueue;
      var announced = 0;
      var printed = 0;

      hubQueue = await queueFor(
        hub,
        printer: PrinterService(hub),
        broadcastAnnounce: ({
          required jobId,
          required jobType,
          required entryId,
          required payloadBase64,
        }) {
          announced++;
          tillQueue.onRemoteAnnounce(
            jobId: jobId,
            jobType: jobType,
            entryId: entryId,
            payloadBase64: payloadBase64,
          );
        },
        broadcastGrant: (jobId, t) => tillQueue.onRemoteGrant(jobId, t),
      );
      tillQueue = await queueFor(
        till,
        // A `usb` print always fails on this non-Windows machine, so what is
        // asserted is that the till *claimed and attempted* it — that the job
        // reached the one terminal the printer is plugged into.
        printer: PrinterService(till),
        broadcastClaim: hubQueue.onRemoteClaim,
        broadcastResult: (jobId, result, error) {
          printed++;
          hubQueue.onRemoteResult(jobId, result, error);
        },
      );

      await announce(from: till, fromTerminalId: tillQueue.terminalId, to: hub);

      final r = await hubQueue.submitJob(
        hub.closeCheckConfigOrFallback(),
        [1, 2, 3],
        jobType: 'cashier',
      );

      expect(announced, 1, reason: 'relayed, not dialled from the hub');
      expect(printed, 1, reason: 'exactly one terminal answered');
      expect(r.ok, isFalse, reason: 'no Windows spooler on this machine');
      expect(hubQueue.jobs.single.claimedAt, isNotNull);
    });

    test('a job announced under the peer\'s entry id is claimable on the owner',
        () async {
      // The id-agreement half. The announcement carries nothing but an entry
      // id, so the two terminals have to call the printer by the same name.
      final till = await terminal(printers: [tillUsbCloseCheck(id: 'be-42')]);
      await till.saveUsbPrinterName('be-42', 'XP-80C');
      final hub = await terminal();
      await announce(from: till, fromTerminalId: 'term-till', to: hub);

      var claims = 0;
      final tillQueue = await queueFor(
        till,
        printer: PrinterService(till),
        broadcastClaim: (jobId, t) => claims++,
      );

      await tillQueue.onRemoteAnnounce(
        jobId: 'j-1',
        jobType: 'cashier',
        entryId: hub.listEntries().single.id,
        payloadBase64: base64Encode([1, 2, 3]),
      );

      expect(claims, 1);
    });

    test('the terminal that learned a printer never claims a job for it',
        () async {
      // Both would otherwise put a hand up for a network printer, and the one
      // that cannot reach it might win the grant.
      final hub = await terminal(printers: [kitchenNetworkPrinter(port: 9100)]);
      final client = await terminal();
      await announce(from: hub, fromTerminalId: 'term-hub', to: client);

      var claims = 0;
      final clientQueue = await queueFor(
        client,
        printer: PrinterService(client),
        broadcastClaim: (jobId, t) => claims++,
      );

      await clientQueue.onRemoteAnnounce(
        jobId: 'j-1',
        jobType: 'kitchen',
        entryId: 'kitchen-1',
        payloadBase64: base64Encode([1, 2, 3]),
      );

      expect(claims, 0);
    });

    test('backend ownership still wins where it is populated', () async {
      // Nothing here may regress once the backend starts issuing cash register
      // ids: an entry that names this terminal is printed here, whatever a
      // stale LAN announcement says.
      final storage = await terminal(cashRegisterId: 'kassa-1');
      await storage.applyPrinterSettingsList([
        PrinterSettingEntry(
          id: 'be-1',
          ip: InternetAddress.loopbackIPv4.address,
          port: 9100,
          name: 'Kassa',
          type: 'close_check',
          connectedEntityIds: const [],
          connectionType: 'cable',
          ownerCashRegisterId: 'kassa-1',
        ),
      ]);

      final config = storage.getCloseCheckPrinter()!;
      expect(storage.isOwnedByThisTerminal(storage.entryById('be-1')!), isTrue);
      expect(config.isUnowned, isFalse);
    });
  });

  group('the login sync', () {
    test('keeps a peer\'s printer that the backend has never heard of',
        () async {
      final till = await terminal(printers: [tillUsbCloseCheck()]);
      final hub = await terminal();
      await announce(from: till, fromTerminalId: 'term-till', to: hub);

      await hub.mergeBackendPrinterSettings(const []);

      expect(hub.listEntries().map((e) => e.id), ['local-1']);
      expect(
        hub.lanOwnerOf('local-1'),
        'term-till',
        reason: 'still routed to the till',
      );
    });

    test('moves the ownership marker onto the backend row for the same printer',
        () async {
      // The peer eventually pushed its printer and the server assigned a UUID.
      // The server's row is the real one — but if the marker did not move with
      // it, the hub would start dialling a USB printer plugged into the till.
      final till = await terminal(printers: [tillUsbCloseCheck()]);
      final hub = await terminal();
      await announce(from: till, fromTerminalId: 'term-till', to: hub);

      await hub.mergeBackendPrinterSettings([tillUsbCloseCheck(id: 'be-9')]);

      expect(hub.listEntries().map((e) => e.id), ['be-9']);
      expect(hub.lanOwnerOf('be-9'), 'term-till');
      expect(hub.lanOwnerOf('local-1'), isNull);
    });

    test('a peer\'s printer is never offered to the backend', () async {
      // `entriesOwnedByThisTerminal` is what the announcement sends and what a
      // push would ever be built from; a peer's row is in neither.
      final till = await terminal(printers: [tillUsbCloseCheck()]);
      final hub = await terminal(printers: [kitchenNetworkPrinter(port: 9100)]);
      await announce(from: till, fromTerminalId: 'term-till', to: hub);

      expect(hub.listEntries().length, 2);
      expect(hub.entriesOwnedByThisTerminal().map((e) => e.id), ['kitchen-1']);
      expect(hub.isLanLearned('local-1'), isTrue);
      expect(hub.isLanLearned('kitchen-1'), isFalse);
    });
  });
}

void _noopAnnounce({
  required String jobId,
  required String jobType,
  required String entryId,
  required String payloadBase64,
}) {}
void _noopClaim(String jobId, String terminalId) {}
void _noopGrant(String jobId, String terminalId) {}
void _noopResult(String jobId, String result, String? error) {}
