/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §9.3 — booting the real app with the
/// cable pulled.
///
/// §9.3 asks for "the whole app driven with the Dio client replaced by one
/// that throws on any call." The emphasis is on *the whole app*: this harness
/// calls the production `initDi()` and pumps the production `MyApp`, so a
/// screen under test sees exactly the object graph a cashier's terminal sees.
/// The only substitutions are at the four seams where `flutter test` has no
/// platform to offer — the replica file, secure storage, connectivity, and
/// Hive's directory — plus the throwing transport that is the entire point of
/// the exercise.
///
/// Why not a purpose-built widget tree per screen, which would be far less
/// work: §9's opening line. "The previous plans failed on discipline, not
/// knowledge — fixes landed on one path and not its duplicate." A second
/// wiring would be that duplicate, and the failure mode is silent: the suite
/// stays green while the real composition root drifts out from under it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_entry.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/services/offline_queue/quarantined_operation.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_job.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart'
    show navigatorKey;
import 'package:mary_ai_pos/core/services/lan_hub/leader_election_service.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/main.dart' show MyApp;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_connectivity_platform.dart';
import 'in_memory_secure_storage.dart';

/// The transport §9.3 specifies: every request is refused, and every refusal
/// is recorded.
///
/// It fails the way a pulled cable fails — `DioExceptionType.connectionError`,
/// the exact exception `IOHttpClientAdapter` raises when the socket cannot be
/// opened — rather than with some synthetic error the app has never seen. A
/// screen that survives this survives a real outage; a screen that only
/// survives because it caught an unfamiliar error type would be a false pass.
///
/// [requests] exists so a test can say something stronger than "it rendered":
/// it can name exactly which endpoints a screen reached for and assert the
/// user-visible outcome was correct anyway.
class DeadNetworkAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  /// Paths hit since the last [clear], as `/api/v1/...` strings — the readable
  /// form for a test expectation or a failure message.
  List<String> get paths => requests.map((r) => r.uri.path).toList();

  void clear() => requests.clear();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: const SocketException('offline suite: the cable is pulled'),
      message: 'offline suite: the cable is pulled',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Stops `RenderFlex overflowed by N pixels` from failing a test, and nothing
/// else.
///
/// Not a blanket amnesty — it is the one error class here that is an artifact
/// of the test environment rather than a property of the code. Widget tests
/// render text in a fallback font whose glyphs are all square, so every string
/// measures wider than the same string in the app's real typeface, and a few
/// screens overflow by a fixed number of pixels that does not move when the
/// surface is doubled from 1920 to 2560 wide — the signature of text metrics,
/// not of layout. Failing on it would mean this suite reported a font
/// substitution as an offline defect, and the noise would bury the failures it
/// exists to find.
///
/// Filtered at the source rather than swallowed at the assertion, because the
/// binding accumulates errors: three overflows in one test fail it as "multiple
/// exceptions" no matter how many a single `takeException()` consumes.
/// Everything else — a throwing `build`, a null dereference in a bloc, a
/// missing route argument — reaches the binding untouched and still fails.
void _ignoreLayoutOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed by')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Ids the suite and the harness share, so a test can name the row it seeded
/// without repeating a string literal that has to match in two files.
const kBranchId = 'br-1';
const kHallId = 'h-1';
const kFreeTableId = 'tb-free';
const kBusyTableId = 'tb-busy';
const kTimedTableId = 'tb-timed';
const kCategoryId = 'cat-1';
const kGoodId = 'g-osh';
const kCashRegisterId = 'cr-1';

/// The branch shift [OfflineAppHarness.openShift] seeds. Fixed rather than
/// generated so [OfflineAppHarness.clearShift] can address it.
const kSeededShiftId = 'shift-1';
const kOpenOrderId = 'ord-open';
const kPaidOrderId = 'ord-paid';

/// A booted, cable-pulled application: real DI, real `MyApp`, an in-memory
/// replica and a transport that refuses everything.
class OfflineAppHarness {
  OfflineAppHarness._(this.db, this.network, this._hiveDir);

  final LocalDatabase db;
  final DeadNetworkAdapter network;
  final Directory _hiveDir;

  /// Cold-boots the application, inside [WidgetTester.runAsync].
  ///
  /// The `runAsync` is not incidental. Every step of a boot is real
  /// asynchronous work — a temp directory, Hive's typed boxes, SQLite — and a
  /// widget test's `FakeAsync` zone never turns the real event loop, so a boot
  /// started inside it suspends on the first file open and never finishes.
  /// Worse, work *begun* there and left incomplete deadlocks teardown, because
  /// Hive's write lock ends up held by a continuation that zone will never run.
  /// Booting in the real zone also keeps the app's own long-lived timers real,
  /// so the binding's pending-timer check has nothing to report as long as
  /// [dispose] cancels them.
  static Future<OfflineAppHarness> boot(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async => (await tester.runAsync(() => _boot(prefs: prefs)))!;

  /// What `main()` does before `runApp`, minus the parts that are desktop-shell
  /// concerns rather than application wiring.
  ///
  /// `main()` does four things ahead of `initDi()`: a single-instance TCP lock,
  /// Hive adapter registration, screen-orientation setup, and window-manager
  /// sizing. Only the Hive registration is load-bearing for anything below the
  /// UI — `OfflineQueueService`, `PrintQueueService` and the audit log all open
  /// typed boxes during `initDi()` and would throw without their adapters — so
  /// that is reproduced here, pointed at a scratch directory. The other three
  /// are `dart:io` sockets and `window_manager` plugin calls with no headless
  /// implementation and no bearing on what a widget renders.
  static Future<OfflineAppHarness> _boot({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      // Leader election is on by default in production, and since its startup
      // re-arm was fixed it genuinely reaches `start()` here too — a widget
      // test would then bind the real discovery (UDP 8766) and hub (TCP 8765)
      // sockets, elect itself leader of an empty venue, and collide with any
      // other suite doing the same in a parallel shard. The kill switch keeps
      // this harness about what a screen renders. `lan_hub_test.dart` and
      // `leader_election_test.dart` cover the sockets and the election on
      // purpose, over ports they own.
      LeaderElectionService.electionEnabledKey: false,
      ...prefs,
    });
    InMemorySecureStoragePlatform.install();
    // "Cable pulled" starts here, one layer below Dio: the OS itself reports
    // no link, so `ConnectivityCubit` settles offline and `SyncEngine.start()`
    // never fires its startup tick. Without this the boot would begin with a
    // burst of doomed requests and the suite would be timing-dependent.
    FakeConnectivityPlatform.install(initial: const [ConnectivityResult.none]);

    final hiveDir = await Directory.systemTemp.createTemp('mary_pos_offline_');
    Hive.init(hiveDir.path);
    // Mirrors main.dart. Registration is idempotent-by-guard rather than by
    // Hive itself, which throws on a duplicate type id, and the suite boots
    // many times in one process.
    _registerHiveAdaptersOnce();

    final db = LocalDatabase.open(':memory:');
    final network = DeadNetworkAdapter();
    await initDi(
      overrides: DiOverrides(database: db, httpClientAdapter: network),
    );
    // Boot itself is allowed to have tried the network — a login-time printer
    // sync, say. What the suite asserts about is what happens *after* this
    // point, on screens and on user actions.
    network.clear();
    return OfflineAppHarness._(db, network, hiveDir);
  }

  static bool _adaptersRegistered = false;

  static void _registerHiveAdaptersOnce() {
    if (_adaptersRegistered) return;
    _adaptersRegistered = true;
    Hive.registerAdapter(PendingOperationTypeAdapter());
    Hive.registerAdapter(PendingOperationAdapter());
    Hive.registerAdapter(PrintJobAdapter());
    Hive.registerAdapter(QuarantinedOperationAdapter());
    Hive.registerAdapter(PrivilegedActionAuditEntryAdapter());
  }

  /// Writes one replicated row exactly the way a `/sync/pull` batch would —
  /// through the same [PayloadNormalizer] the change applier uses, so a seeded
  /// row is indistinguishable from a replicated one. Same helper, same shape,
  /// as every query test in this suite.
  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(
      spec,
      data['id'] as String,
      PayloadNormalizer.normalize(spec, data),
    );
  }

  /// Points this terminal's receipt printer at a closed local port.
  ///
  /// Not cosmetic, and not a stub: `PrinterConfigStorage.closeCheckConfigOrFallback`
  /// falls back to a hard-coded `192.168.1.222:9100` when no printer is
  /// configured, so *every* payment opens a TCP socket to that address. In a
  /// sandbox that connect neither succeeds nor fails — it sits in the
  /// connect timeout, and because it was started inside the widget test's
  /// `FakeAsync` zone its completion never arrives, which strands the print
  /// queue's Hive write and hangs teardown.
  ///
  /// `127.0.0.1:1` is refused immediately, so the real print path runs start to
  /// finish and fails the way an unplugged printer fails. That is also the
  /// honest configuration: a venue has a printer entry; the hard-coded fallback
  /// is what a *misconfigured* terminal hits.
  void seedLocalPrinter() {
    inject<SharedPreferences>().setString(
      'printer_settings_entries_v2_json',
      jsonEncode([
        {
          'id': 'printer-1',
          'ip': '127.0.0.1',
          'port': 1,
          'type': 'close_check',
          'connection_type': 'cable',
          'connected_entity_ids': <String>[],
        },
      ]),
    );
  }

  /// Seeds a small but complete venue: one branch, one hall, a free dine-in
  /// table, a busy one carrying an open bill, a time-based table, two menu
  /// categories with goods, a cash register, a transaction and a paid bill for
  /// the ledger and archive screens.
  ///
  /// Everything a screen needs has to be *in the replica*, because after Phase
  /// 4 there is nowhere else for a screen to get it — that is the property this
  /// suite exists to prove. So this is not a fixture that stands in for the
  /// network; it is the state a terminal would already hold after its last
  /// successful pull, which is exactly the situation "the cable is pulled"
  /// describes.
  void seedVenue() {
    seedLocalPrinter();
    put('branches', {
      'id': kBranchId,
      'name': 'Markaziy filial',
      'default_service_percent': 10,
      'deleted_at': 0,
    });
    put('halls', {
      'id': kHallId,
      'name': 'Asosiy zal',
      'branch_id': kBranchId,
      'width': 1200,
      'height': 800,
      'deleted_at': 0,
    });
    put('cafe_tables', {
      'id': kFreeTableId,
      'hall_id': kHallId,
      'number': 1,
      'status': 'free',
      'table_type': 'dine_in',
      'pos_x': 40,
      'pos_y': 40,
      'width': 90,
      'height': 90,
      'deleted_at': 0,
    });
    put('cafe_tables', {
      'id': kBusyTableId,
      'hall_id': kHallId,
      'number': 2,
      'status': 'busy',
      'table_type': 'dine_in',
      'pos_x': 200,
      'pos_y': 40,
      'width': 90,
      'height': 90,
      'deleted_at': 0,
    });
    put('cafe_tables', {
      'id': kTimedTableId,
      'hall_id': kHallId,
      'number': 3,
      'status': 'free',
      'table_type': 'time_based',
      'price_per_hour': 40000,
      'pos_x': 360,
      'pos_y': 40,
      'width': 90,
      'height': 90,
      'deleted_at': 0,
    });
    put('departments', {'id': 'dp-1', 'name': 'Oshxona', 'deleted_at': 0});
    put('categories', {
      'id': kCategoryId,
      'name': 'Issiq taomlar',
      'department_id': 'dp-1',
      'branch_id': kBranchId,
      'deleted_at': 0,
    });
    // Every column `GoodsModel` declares `required` has to be here. The menu
    // query drops a row its model cannot parse rather than blanking the whole
    // catalog, so an under-specified fixture does not error — it silently
    // renders an empty menu, which would look exactly like the offline failure
    // this suite is hunting for.
    for (final good in const [
      (id: kGoodId, name: 'Osh', price: 35000, cost: 12000, cook: 10),
      (id: 'g-lagmon', name: 'Lagmon', price: 30000, cost: 10000, cook: 12),
    ]) {
      put('goods', {
        'id': good.id,
        'name': good.name,
        'description': '',
        'category_id': kCategoryId,
        'department_id': 'dp-1',
        'branch_id': kBranchId,
        'price': good.price,
        'cost_price': good.cost,
        'profit': good.price - good.cost,
        'profit_margin': 60,
        'cook_time': good.cook,
        'deleted_at': 0,
      });
    }
    put('users', {
      'id': 'u-1',
      'full_name': 'Kassir Aliyev',
      'username': 'kassir',
      'role': 'manager',
      'is_active': true,
      'branch_id': kBranchId,
      'brand_id': 'brand-1',
      'deleted_at': 0,
    });
    put('cash_registers', {
      'id': kCashRegisterId,
      'name': 'Kassa 1',
      'branch_id': kBranchId,
      'deleted_at': 0,
    });
    put('group_transactions', {
      'id': 'tg-1',
      'name': 'Xaridlar',
      'branch_id': kBranchId,
      'deleted_at': 0,
    });
    put('transactions', {
      'id': 'tx-1',
      'type': 'income',
      'cash_register_id': kCashRegisterId,
      'group_id': 'tg-1',
      'date': '2026-08-22T09:00:00Z',
      'amount': 150000,
      'description': 'Naqd tushum',
      'branch_id': kBranchId,
      'deleted_at': 0,
    });

    // The busy table's open bill, and one line on it.
    put('orders', {
      'id': kOpenOrderId,
      'table_id': kBusyTableId,
      'bill_status': 'open',
      'status': 'pending',
      'order_type': 'dine_in',
      'branch_id': kBranchId,
      'cashier_id': 'u-1',
      'bill_no': 41,
      'guest_count': 2,
      'service_percent': 10,
      'created_at': '2026-08-23T06:00:00Z',
      'deleted_at': 0,
    });
    put('order_items', {
      'id': 'oi-1',
      'order_id': kOpenOrderId,
      'good_id': kGoodId,
      'quantity': 2,
      'price': 35000,
      'status': 'pending',
      'created_at': '2026-08-23T06:01:00Z',
      'deleted_at': 0,
    });

    // A closed, paid bill — the archive and shift-report screens read these.
    put('orders', {
      'id': kPaidOrderId,
      'table_id': kFreeTableId,
      'bill_status': 'closed',
      'status': 'paid',
      'order_type': 'dine_in',
      'branch_id': kBranchId,
      'cashier_id': 'u-1',
      'bill_no': 40,
      'guest_count': 1,
      'service_percent': 10,
      'total_amount': 35000,
      'grand_total': 38500,
      'cash_amount': 38500,
      'created_at': '2026-08-23T05:00:00Z',
      'paid_at': '2026-08-23T05:30:00Z',
      'deleted_at': 0,
    });
    put('order_items', {
      'id': 'oi-2',
      'order_id': kPaidOrderId,
      'good_id': kGoodId,
      'quantity': 1,
      'price': 35000,
      'status': 'done',
      'created_at': '2026-08-23T05:01:00Z',
      'deleted_at': 0,
    });
  }

  /// Puts a signed-in user on the terminal without a single request.
  ///
  /// This is the offline login path the product actually ships: a brand token
  /// in secure storage plus a profile in `OfflineAuthCache`, which is what
  /// `UserBloc`'s `started` handler reads. Nothing here fakes a bloc — the
  /// real bloc runs against real storage and arrives at a real user.
  Future<UserModel> signIn({
    String id = 'u-1',
    String fullName = 'Kassir Aliyev',
    UserRole role = UserRole.manager,
    String branchId = 'br-1',
    String brandId = 'brand-1',
  }) async {
    final user = UserModel(
      id: id,
      fullName: fullName,
      username: 'kassir',
      role: role,
      isActive: true,
      brandId: brandId,
      branchId: branchId,
    );
    final storage = inject<AppTokenStorage>();
    await storage.writeBrandIdToken(
      BrandIdTokenPair(brandId: brandId, password: 'pw'),
    );
    await storage.writeAuthToken(
      const AuthTokenPair(accessToken: 'access', refreshToken: 'refresh'),
    );
    await inject<OfflineAuthCache>().saveUser(
      brandId: brandId,
      password: 'pw',
      user: user,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    return user;
  }

  /// Opens a shift the way `ShiftBloc` does — a local record in
  /// `SharedPreferences` under the bloc's own key.
  ///
  /// A shift is a precondition for most of the app: `WaiterFloorPlanScreen`
  /// replaces the whole floor with an "open a shift" prompt without one, and
  /// `MainScreen` pushes the shift screen on top of wherever you were. Seeding
  /// it directly rather than tapping through the open-shift flow keeps each
  /// render test about the screen it names; the open-shift action itself is
  /// exercised as a user action in its own test.
  Future<void> openShift() async {
    final now = DateTime.now().toUtc();
    // Seeded as a replicated row, because that is what a shift now is: the
    // branch's `branch_shifts` record, which every terminal in the venue reads.
    // Seeding it through [put] rather than through the open-shift flow also
    // makes this indistinguishable from "the terminal beside this one opened
    // the shift and it arrived over the LAN" — which is the state most of these
    // tests are actually describing.
    put('branch_shifts', {
      'id': kSeededShiftId,
      'branch_id': kBranchId,
      'opened_by': 'u-1',
      'closed_by': null,
      'opened_at': now.toIso8601String(),
      'closed_at': null,
      'opening_cash': '0',
      'opening_card': '0',
      'closing_cash': null,
      'closing_card': null,
    });
  }

  /// Clears the branch's shift — the state a venue is in before the first
  /// cashier of the day signs on.
  Future<void> clearShift() async {
    db.deleteRow('branch_shifts', kSeededShiftId);
  }

  /// The app's own order-detail read, resolved out of the live DI — so an
  /// assertion about "the order is there" is answered by the same query the
  /// screen renders from, not by a hand-written SELECT that could agree with
  /// the database while disagreeing with the UI.
  OrdersRepository get orders => inject<OrdersRepository>();

  /// Entity names currently sitting in the outbox, which is where a completed
  /// write is supposed to leave its send. Reading the names rather than the
  /// rows keeps the assertion about *which* write was queued without pinning
  /// the payload shape, which the outbox's own tests already cover.
  Set<String> outboxEntities() =>
      inject<OutboxStore>().pending().map((op) => op.entity).toSet();

  /// Pops the current route and settles — for a test that visits several
  /// screens in one boot.
  Future<void> back(WidgetTester tester) async {
    navigatorKey.currentState!.pop();
    await settle(tester);
  }

  /// Tears down everything `boot` started. Order matters: the two long-lived
  /// timers (`SyncEngine`'s 60s ticker, `ConnectivityCubit`'s 20s probe) have
  /// to be cancelled before the test ends or the next boot inherits them.
  Future<void> dispose(WidgetTester tester) async {
    await _drainHive(tester);
    await tester.runAsync(_dispose);
  }

  /// Lets Hive's write queue finish while the widget-test clock is still being
  /// pumped.
  ///
  /// This is the awkward part of driving a real app from a widget test, and it
  /// is worth being precise about. A user action — taking a payment, say —
  /// starts a Hive write from inside the test's `FakeAsync` zone; the write
  /// itself finishes on the real event loop, but its continuation is scheduled
  /// back into the fake zone, where only `tester.pump` ever runs anything.
  /// `runAsync` gives the real loop a turn but pumps nothing, so awaiting
  /// `flush()` inside a plain `runAsync` waits on a continuation that by
  /// construction cannot run: the process hangs rather than failing, which is
  /// the worst possible failure mode for a test suite.
  ///
  /// So the flush is *started* in the real zone and left in flight while frames
  /// are pumped, which is what actually lets those continuations execute, and
  /// only then awaited.
  Future<void> _drainHive(WidgetTester tester) async {
    late final Future<void> flushing;
    await tester.runAsync(() async {
      flushing = _flushHiveBoxes();
    });
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.runAsync(() => flushing);
  }

  /// Drives every open box's pending write to completion.
  ///
  /// Typed per box because `Hive.box<dynamic>` throws on a box that was opened
  /// with a concrete type — which is all of them. The four names are the ones
  /// `initDi` opens; they are duplicated from their services deliberately,
  /// since importing a private `_boxName` is not possible and a wrong name here
  /// fails loudly (the box simply is not open) rather than silently.
  Future<void> _flushHiveBoxes() async {
    if (Hive.isBoxOpen('offline_queue')) {
      await Hive.box<PendingOperation>('offline_queue').flush();
    }
    if (Hive.isBoxOpen('offline_queue_quarantine')) {
      await Hive.box<QuarantinedOperation>('offline_queue_quarantine').flush();
    }
    if (Hive.isBoxOpen('print_queue')) {
      await Hive.box<PrintJob>('print_queue').flush();
    }
    if (Hive.isBoxOpen('privileged_action_audit_log')) {
      await Hive.box<PrivilegedActionAuditEntry>(
        'privileged_action_audit_log',
      ).flush();
    }
  }

  Future<void> _dispose() async {
    inject<SyncEngine>().stop();
    // Hive first, flushed before it is closed, and all of it before
    // `inject.reset()`.
    //
    // Three constraints that are worth spelling out, because getting any of
    // them wrong hangs the entire test process rather than failing one test.
    // A box write issued from a user action starts inside the widget test's
    // `FakeAsync` zone and completes on the real event loop; `close()` waits on
    // that write's lock. An explicit `flush()` is what actually drives the
    // pending write to completion here — `close()` alone waits on a lock the
    // write still holds. And the whole sequence has to happen while the GetIt
    // container is still standing: reset it first and the wait never returns.
    await Hive.close();
    await Hive.deleteFromDisk();

    await inject<ConnectivityCubit>().close();
    await inject.reset();
    db.dispose();
    if (_hiveDir.existsSync()) _hiveDir.deleteSync(recursive: true);
  }

  /// Pumps `MyApp`'s very first frame and stops there — the splash screen, as
  /// a cold-started terminal actually shows it, before any routing decision.
  Future<void> pumpFirstFrame(WidgetTester tester) async {
    // The POS is a landscape desktop app: `main()` pins the orientation and
    // asks the window manager for a 1000x600 minimum. The widget-test default
    // surface is 800x600, narrower than any layout in this product was ever
    // designed for, and every screen overflows on it — which would show up as
    // a wall of RenderFlex failures that say nothing about offline behaviour.
    // 1920x1080 is the terminal these layouts were drawn for; smaller
    // surfaces overflow in screens that are perfectly healthy on real
    // hardware, and those overflows would drown out the failures this suite
    // is actually looking for.
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _ignoreLayoutOverflow();

    await tester.pumpWidget(const MyApp());
    await tester.pump();
  }

  /// Runs the app from its first frame to wherever splash decides to send it.
  ///
  /// `MyApp` opens on the splash screen, which waits out a 500ms timer and two
  /// storage reads before routing. This waits that out rather than
  /// short-circuiting it, because where splash lands offline is itself part of
  /// what the suite covers.
  Future<void> pumpApp(WidgetTester tester) async {
    await pumpFirstFrame(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
  }

  /// Pushes a named route onto the running app and settles it.
  Future<void> open(
    WidgetTester tester,
    String route, {
    Object? arguments,
  }) async {
    unawaited(
      navigatorKey.currentState!.pushNamed(route, arguments: arguments),
    );
    await settle(tester);
  }

  /// Pushes a widget that has no route of its own — see the suite's notes on
  /// the three screens `RouteGenerate` does not reference. Pushed through the
  /// live navigator so the widget still builds under `MyApp`'s providers,
  /// which is the only environment it could ever run in.
  Future<void> openWidget(WidgetTester tester, Widget screen) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => screen),
      ),
    );
    await settle(tester);
  }

  /// Advances the app until it stops changing, with the real event loop
  /// allowed to turn in between.
  ///
  /// `pumpAndSettle` alone is not enough here, and the reason is specific to
  /// driving a whole application rather than one widget. A widget test runs
  /// inside `FakeAsync`, which only ever flushes microtasks; the app's startup
  /// path awaits things that resolve on the *real* event loop — secure-storage
  /// reads, Hive box I/O — and those futures simply never complete under a
  /// bare `pump`. The visible symptom is subtle and would have been easy to
  /// mistake for a product bug: `UserBloc`'s cached-profile read stays
  /// suspended, so the main screen sits on its "no role yet" spinner and every
  /// screen behind it looks broken.
  ///
  /// So each iteration hands control back to the real loop via `runAsync`,
  /// then pumps a frame for whatever that unblocked. The loop is bounded
  /// because several screens run a permanent animation — the loading
  /// indicator, a pulsing offline badge — under which a settle condition never
  /// arrives; a fixed budget renders them without pretending they are idle.
  Future<void> settle(
    WidgetTester tester, {
    int rounds = 8,
    Duration step = const Duration(milliseconds: 250),
  }) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(step);
    }
  }
}
