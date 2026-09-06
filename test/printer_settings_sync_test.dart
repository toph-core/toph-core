/// Printer sozlamalarining backend bilan sinxronizatsiyasi.
///
/// The bug this covers: a printer added in Settings > Printers was written to
/// the device-local store, pushed to the backend with `unawaited(...)`, and the
/// dialog reported success either way. Three separate losses followed from
/// that one missing `await`:
///
///  1. the other terminal never learned the printer existed (kitchen tickets
///     printed nothing, close checks fell back to `192.168.1.222`);
///  2. logging out deleted it — the login sync replaced the whole local list
///     with the server's, and a local-only entry is not on the server's;
///  3. the entry kept its `local-…` id forever, so a later edit sent
///     `PUT /…/local-1723…`, which the backend rejects in `uuid.Parse` — the
///     failed create could never be retried into existence.
///
/// The four groups below are those four fixes: push failure stays visible,
/// push success re-keys onto the backend id (carrying the USB name), a
/// `local-` id is created rather than updated, and the login sync preserves
/// what has not reached the server yet.
library;

import 'dart:convert';

import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connectivity_platform.dart';
import 'support/fake_http_client_adapter.dart';
import 'support/in_memory_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// One terminal's device-scoped store, logged in as [cashRegisterId] —
  /// same construction as `printer_ownership_test.dart`.
  Future<PrinterConfigStorage> terminal({
    String cashRegisterId = 'kassa-1',
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

  PrinterSettingEntry entry({
    required String id,
    String name = 'Oshxona',
    String type = 'category',
    String connectionType = 'usb',
    String ip = '',
    int port = 0,
    String owner = 'kassa-1',
    List<String> categories = const ['cat-1'],
  }) =>
      PrinterSettingEntry(
        id: id,
        ip: ip,
        port: port,
        name: name,
        type: type,
        connectedEntityIds: categories,
        connectionType: connectionType,
        ownerCashRegisterId: owner,
      );

  // ─── The data source: what actually goes over the wire ──────────────────

  group('pushPrinterSetting', () {
    late DioClient dioClient;
    late MainDataSources dataSource;
    late List<RequestOptions> requests;
    late Future<ResponseBody> Function(RequestOptions) respond;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      InMemorySecureStoragePlatform.install();
      FakeConnectivityPlatform.install();

      dioClient = DioClient(
        AppTokenStorage(prefs, const FlutterSecureStorage()),
        ConnectivityCubit(Connectivity()),
      );
      Alice(
        configuration: AliceConfiguration(
          showNotification: false,
          showInspectorOnShake: false,
        ),
      ).addAdapter(dioClient.aliceDioAdapter);

      requests = [];
      respond = (_) async => okResponse();
      dioClient.dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
        requests.add(options);
        return respond(options);
      });
      dataSource = MainDataSourcesImpl(dioClient);
    });

    ResponseBody created(String id) => ResponseBody.fromString(
          jsonEncode({
            'status': 'success',
            'message': 'Printer setting created successfully',
            'code': 201,
            'data': {
              'id': id,
              'ip': '',
              'port': 0,
              'name': 'Oshxona',
              'type': 'category',
              'connection_type': 'usb',
              'branch_id': 'branch-9',
              'owner_cash_register_id': 'kassa-1',
              'connected_entity_ids': ['cat-1'],
            },
          }),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    test('a local- id is created (POST), never updated (PUT)', () async {
      // `PUT /…/local-1723…` is rejected by the backend's `uuid.Parse`, so an
      // entry whose create failed used to be unfixable: every re-save was a PUT
      // that could not land. It goes out as a create instead.
      respond = (_) async => created('11111111-1111-4111-8111-111111111111');

      final result = await dataSource.pushPrinterSetting(
        const {'name': 'Oshxona'},
        existingId: 'local-1723456789',
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.path, isNot(contains('local-')));
      expect(
        result.getOrElse(() => null)?.id,
        '11111111-1111-4111-8111-111111111111',
      );
    });

    test('a backend id is still updated in place (PUT)', () async {
      respond = (_) async => created('22222222-2222-4222-8222-222222222222');

      await dataSource.pushPrinterSetting(
        const {'name': 'Oshxona'},
        existingId: '22222222-2222-4222-8222-222222222222',
      );

      expect(requests.single.method, 'PUT');
      expect(
        requests.single.path,
        endsWith('/22222222-2222-4222-8222-222222222222'),
      );
    });

    test('a body-less 200 is a success with nothing to adopt', () async {
      respond = (_) async => okResponse();
      final result = await dataSource.pushPrinterSetting(const {});
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => entry(id: 'x')), isNull);
    });

    ResponseBody badRequest(String message) => ResponseBody.fromString(
          jsonEncode({'error': message}),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    test('an addressless printer is retried with a placeholder address',
        () async {
      // The deployed backend predates addressless printers and answers a USB
      // create with 400 "ip talab qilinadi" — the real reason USB printers
      // never persisted. The clean payload goes first; the placeholder is the
      // fallback, so it evaporates when the new backend ships.
      respond = (options) async =>
          requests.length == 1
              ? badRequest('ip talab qilinadi')
              : created('44444444-4444-4444-8444-444444444444');

      final result = await dataSource.pushPrinterSetting(const {
        'ip': '',
        'port': 0,
        'name': 'Oshxona',
        'type': 'category',
        'connection_type': 'usb',
      });

      expect(requests.length, 2);
      expect((requests.first.data as Map)['ip'], '');
      expect((requests.last.data as Map)['ip'], '127.0.0.1');
      expect((requests.last.data as Map)['port'], 9100);
      expect(
        result.getOrElse(() => null)?.id,
        '44444444-4444-4444-8444-444444444444',
      );
    });

    test('a 400 that is not about the address is not retried', () async {
      respond = (_) async => badRequest('printer setting already exists');

      final result = await dataSource.pushPrinterSetting(const {
        'ip': '',
        'connection_type': 'usb',
      });

      expect(requests.length, 1);
      expect(result.isLeft(), isTrue);
    });

    test('a network printer is never given the placeholder', () async {
      respond = (_) async => badRequest('ip talab qilinadi');

      final result = await dataSource.pushPrinterSetting(const {
        'ip': '192.168.1.100',
        'connection_type': 'cable',
      });

      expect(requests.length, 1);
      expect(result.isLeft(), isTrue);
    });

    test('a dropped connection is a failure, not a silent success', () async {
      respond = (options) async => connectionErrorResponse(options);
      final result = await dataSource.pushPrinterSetting(const {});
      expect(result.isLeft(), isTrue);
    });
  });

  // ─── Adopting the id the backend assigned ───────────────────────────────

  group('adoptBackendId', () {
    test('re-keys the entry and carries the USB name and paper size', () async {
      final storage = await terminal();
      await storage.upsertEntry(entry(id: 'local-1'));
      await storage.saveUsbPrinterName('local-1', 'XP-80C');
      await storage.savePaperSizeCode('local-1', 'mm58');

      await storage.adoptBackendId(
        localId: 'local-1',
        backendId: 'be-1',
        branchId: 'branch-9',
      );

      final list = storage.listEntries();
      expect(list.map((e) => e.id), ['be-1']);
      expect(list.single.branchId, 'branch-9');
      // Without this the printer would still be listed but would print
      // nothing: `PrintQueueService` will not even claim a USB job whose
      // entry has no Windows printer name.
      expect(storage.getUsbPrinterName('be-1'), 'XP-80C');
      expect(storage.getPaperSizeCode('be-1'), 'mm58');
      // The old id belongs to no entry any more.
      expect(storage.getUsbPrinterName('local-1'), isNull);
      expect(storage.getPaperSizeCode('local-1'), isNull);
    });

    test('collapses onto an entry the backend id already has', () async {
      final storage = await terminal(
        printers: [entry(id: 'be-1', name: 'Oshxona')],
      );
      await storage.upsertEntry(entry(id: 'local-1', name: 'Oshxona'));
      expect(storage.listEntries().length, 2);

      await storage.adoptBackendId(localId: 'local-1', backendId: 'be-1');

      expect(storage.listEntries().map((e) => e.id), ['be-1']);
    });

    test('does nothing for an id this device does not have', () async {
      final storage = await terminal(printers: [entry(id: 'be-1')]);
      await storage.adoptBackendId(localId: 'local-9', backendId: 'be-9');
      expect(storage.listEntries().map((e) => e.id), ['be-1']);
    });
  });

  // ─── Login sync ─────────────────────────────────────────────────────────

  group('mergeBackendPrinterSettings', () {
    test('does not delete an entry that never reached the backend', () async {
      // The reported production loss: the operator added a printer, the push
      // failed, and logging out took the printer with it.
      final storage = await terminal();
      await storage.upsertEntry(entry(id: 'local-1', name: 'Oshxona'));
      await storage.saveUsbPrinterName('local-1', 'XP-80C');

      await storage.mergeBackendPrinterSettings([
        entry(id: 'be-1', name: 'Bar', type: 'close_check', categories: const []),
      ]);

      expect(storage.listEntries().map((e) => e.id), ['be-1', 'local-1']);
      expect(storage.getUsbPrinterName('local-1'), 'XP-80C');
    });

    test('drops the local copy when the server has the same printer', () async {
      // The push did land (or a sibling terminal added it) — keeping both would
      // list one physical printer twice.
      final storage = await terminal();
      await storage.upsertEntry(entry(id: 'local-1', name: 'Oshxona'));
      await storage.saveUsbPrinterName('local-1', 'XP-80C');

      await storage.mergeBackendPrinterSettings([
        entry(id: 'be-1', name: 'Oshxona'),
      ]);

      expect(storage.listEntries().map((e) => e.id), ['be-1']);
      expect(storage.getUsbPrinterName('be-1'), 'XP-80C');
    });

    test('still removes a backend entry deleted on the server', () async {
      final storage = await terminal(
        printers: [entry(id: 'be-1'), entry(id: 'be-2', name: 'Bar')],
      );

      await storage.mergeBackendPrinterSettings([entry(id: 'be-2', name: 'Bar')]);

      expect(storage.listEntries().map((e) => e.id), ['be-2']);
    });

    test('backend entries keep their precedence over a local-only one', () async {
      final storage = await terminal();
      await storage.upsertEntry(
        entry(
          id: 'local-1',
          name: 'Zaxira',
          type: 'close_check',
          connectionType: 'cable',
          ip: '192.168.1.50',
          port: 9100,
          categories: const [],
        ),
      );

      await storage.mergeBackendPrinterSettings([
        entry(
          id: 'be-1',
          name: 'Chek',
          type: 'close_check',
          connectionType: 'cable',
          ip: '192.168.1.60',
          port: 9100,
          categories: const [],
        ),
      ]);

      expect(storage.getCloseCheckPrinter()?.entryId, 'be-1');
    });
  });

  // ─── The save flow's own outcome ────────────────────────────────────────

  group('save flow', () {
    test(
      'a failed push leaves a local-only entry that survives the next login',
      () async {
        // What the dialog does, minus the widgets: local write first, then the
        // push, then the outcome the operator is shown. The push fails, so the
        // entry stays with its `local-` id — which is what tells the screen to
        // warn, and what `mergeBackendPrinterSettings` then refuses to delete.
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        InMemorySecureStoragePlatform.install();
        FakeConnectivityPlatform.install();
        final dioClient = DioClient(
          AppTokenStorage(prefs, const FlutterSecureStorage()),
          ConnectivityCubit(Connectivity()),
        );
        Alice(
          configuration: AliceConfiguration(
            showNotification: false,
            showInspectorOnShake: false,
          ),
        ).addAdapter(dioClient.aliceDioAdapter);
        dioClient.dio.httpClientAdapter =
            FakeHttpClientAdapter(connectionErrorResponse);

        final storage = PrinterConfigStorage(prefs);
        final localId = storage.generateLocalId();
        await storage.upsertEntry(entry(id: localId));
        await storage.saveUsbPrinterName(localId, 'XP-80C');

        final pushed = await MainDataSourcesImpl(dioClient).pushPrinterSetting(
          const {'name': 'Oshxona'},
          existingId: localId,
        );

        expect(pushed.isLeft(), isTrue, reason: 'the dialog must warn');
        expect(PrinterConfigStorage.isLocalId(localId), isTrue);
        expect(storage.listEntries().map((e) => e.id), [localId]);

        await storage.mergeBackendPrinterSettings(const []);
        expect(storage.listEntries().map((e) => e.id), [localId]);
        expect(storage.getUsbPrinterName(localId), 'XP-80C');
      },
    );
  });
}
