/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §2/§7 — table timers and shift open/close
/// on the outbox instead of the retiring Hive queue.
///
/// Three layers, in the order a write travels:
///
///  1. **The repository.** A real in-memory `LocalDatabase` with a real
///     `LocalWriter`/`OutboxStore` behind it, so "the record lands *and* the
///     operation lands" is observed in the real `_outbox` table rather than
///     against a fake writer that cannot fail to record anything.
///  2. **Ordering.** The chain key, driven through a real `OutboxDrainer`: a
///     timer action must never reach a server that has not yet been told the
///     order exists.
///  3. **The handlers.** Timer verbs against a fake HTTP adapter (the shape
///     `orders_outbox_test.dart` uses), shift verbs against a fake
///     `MainRepository` (the shape `outbox_handlers_test.dart` uses), because
///     that is how each is actually wired.
///
/// The hydration shield (`pendingLocalTimerOrderIds`) gets its own group. It is
/// the one property here whose failure is silent and expensive: a server
/// snapshot overwriting a live local timer re-prices the largest line on a
/// billiard/PS bill, and nothing on screen says it happened.
library;

import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/outbox/timer_shift_outbox.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lease/lease_manager.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/close_shift/close_shift_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_shift/open_shift_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/shift/shift_response_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/table_timer_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart'
    show OrderItem;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connectivity_platform.dart';
import 'support/fake_http_client_adapter.dart';
import 'support/in_memory_secure_storage.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fakes — hand-written `implements + noSuchMethod`, this suite's convention.
// ─────────────────────────────────────────────────────────────────────────────

/// Records the delegated order create. `createTimedOrder` must route the order
/// half here (which enqueues on its own) and never build a second one itself.
class _FakeOrders implements OrdersRepository {
  final List<String> calls = [];

  @override
  Future<void> createOrder({
    required String tableId,
    required String clientOrderId,
    required int guestCount,
    required List<OrderItem> items,
    TableStatus? tableStatus,
    String? waiterId,
  }) async {
    calls.add('createOrder:$tableId:$clientOrderId');
  }

  @override
  Future<void> saveOrderDetailSnapshot(
    String key,
    Map<String, dynamic> json,
  ) async {
    calls.add('snapshot:$key');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakeLanHub implements LanHubService {
  @override
  LanMode get mode => LanMode.disabled;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakePrintQueue implements PrintQueueService {
  @override
  String get terminalId => 'terminal-under-test';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// Only the three shift methods the handlers touch are real; anything else
/// throws, which is itself part of what the shift tests assert.
class _FakeShiftRepository implements MainRepository {
  final List<String> calls = [];

  Either<Failure, ShiftResponseModel> openResult = const Right(
    ShiftResponseModel(id: 'shift-server'),
  );
  Either<Failure, ShiftResponseModel?> activeResult = const Right(
    ShiftResponseModel(id: 'shift-1'),
  );
  Either<Failure, bool> closeResult = const Right(true);

  @override
  Future<Either<Failure, ShiftResponseModel>> openShift({
    required OpenShiftModel request,
  }) async {
    calls.add(
      'open:${request.cashRegisterId}:'
      '${request.openCashSum}:${request.openCardSum}',
    );
    return openResult;
  }

  @override
  Future<Either<Failure, ShiftResponseModel?>> checkShift({
    required String id,
  }) async {
    calls.add('check:$id');
    return activeResult;
  }

  @override
  Future<Either<Failure, bool>> closeShift({
    required CloseShiftRequestModel request,
  }) async {
    calls.add(
      'close:${request.shiftId}:'
      '${request.closingCash}:${request.closingCard}',
    );
    return closeResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────────────────
  // 1. The repository: a record and an operation, together
  // ───────────────────────────────────────────────────────────────────────
  group('timer writes land a replica record and an outbox operation', () {
    late LocalDatabase db;
    late OutboxStore outbox;
    late _FakeOrders orders;
    late TableTimerLocalRepositoryImpl repo;

    setUp(() {
      db = LocalDatabase.open(':memory:');
      final applier = ChangeApplier(db);
      outbox = OutboxStore(db);
      orders = _FakeOrders();
      GetIt.I.registerSingleton<PrintQueueService>(_FakePrintQueue());
      repo = TableTimerLocalRepositoryImpl(
        db,
        LocalWriter(db: db, applier: applier, outbox: outbox),
        orders,
        LeaseManager(lanHub: _FakeLanHub(), localDb: db),
      );
      final spec = kEntitiesByName['cafe_tables']!;
      db.upsert(spec, 't1', {
        'id': 't1',
        'name': 'Bilyard 1',
        'table_type': 'time_based',
        'price_per_hour': '60000',
        'status': TableStatus.free.name,
      });
    });

    tearDown(() async {
      db.dispose();
      await GetIt.I.reset();
    });

    List<OutboxOperation> timerOps() => outbox
        .pending()
        .where((op) => op.entity == kTimerSessionEntity)
        .toList();

    test('start writes the record and queues exactly one start', () async {
      await repo.startTimer('o-1', tableId: 't1');

      final record = db.getTableTimer('o-1');
      expect(record, isNotNull);
      expect(record!['state'], 'running');
      expect(record['active_started_at'], isNotNull);
      // The proven billing engine is untouched by the queue swap: the record
      // still carries the table's price, which is what every amount is derived
      // from.
      expect(record['price_per_hour'], '60000');

      final ops = timerOps();
      expect(ops, hasLength(1));
      expect(ops.single.action, kTimerStart);
      expect(ops.single.entityId, 'o-1');
      expect(ops.single.payload['order_id'], 'o-1');
    });

    test('start, pause and resume queue three ops in that order', () async {
      await repo.startTimer('o-1', tableId: 't1');
      await repo.pauseTimer('o-1');
      await repo.resumeTimer('o-1');

      // No coalescing, deliberately: these are transitions, not a
      // last-writer-wins value. Collapsing them would ask the server to resume
      // a session it was never told to start.
      expect(
        timerOps().map((op) => op.action),
        [kTimerStart, kTimerPause, kTimerResume],
      );
      expect(db.getTableTimer('o-1')!['state'], 'running');
      expect((db.getTableTimer('o-1')!['pauses'] as List), hasLength(1));
    });

    test('a repeated press on an unchanged state queues nothing', () async {
      await repo.startTimer('o-1', tableId: 't1');
      await repo.startTimer('o-1', tableId: 't1'); // already running
      await repo.resumeTimer('o-1'); // already running
      await repo.pauseTimer('o-1');
      await repo.pauseTimer('o-1'); // already paused

      // The state guards in the repository are what make queue-side coalescing
      // unnecessary: a double-tap never becomes a second operation.
      expect(timerOps().map((op) => op.action), [kTimerStart, kTimerPause]);
    });

    test('pause and resume on an unknown order queue nothing', () async {
      await repo.pauseTimer('nope');
      await repo.resumeTimer('nope');
      expect(timerOps(), isEmpty);
    });

    test('the record and its operation commit together', () async {
      await repo.startTimer('o-1', tableId: 't1');
      // Both halves are visible, which is the property `LocalDatabase
      // .transaction` is there to give: never a record the queue will not
      // carry, never an operation with no record behind it.
      expect(db.getTableTimer('o-1'), isNotNull);
      expect(timerOps(), hasLength(1));
    });

    test(
      'createTimedOrder delegates the create and adds no order op of its own',
      () async {
        final result = await repo.createTimedOrder(tableId: 't1', guestCount: 2);
        final orderId = result.fold((_) => '', (r) => r.orderId);
        expect(orderId, isNotEmpty);

        // The order create is the delegate's job (and it enqueues there); the
        // timer half writes only the local-authority record, in state `none`,
        // because the cashier has not pressed start yet.
        expect(orders.calls, ['createOrder:t1:$orderId', 'snapshot:t1']);
        expect(db.getTableTimer(orderId)!['state'], 'none');
        expect(timerOps(), isEmpty);
      },
    );

    test('a second createTimedOrder on a busy table reuses the order', () async {
      final first = await repo.createTimedOrder(tableId: 't1', guestCount: 2);
      orders.calls.clear();
      final second = await repo.createTimedOrder(tableId: 't1', guestCount: 4);

      expect(
        second.fold((_) => '', (r) => r.orderId),
        first.fold((_) => '', (r) => r.orderId),
      );
      expect(second.fold((_) => false, (r) => r.wasExisting), isTrue);
      expect(orders.calls, isEmpty);
    });

    test('evictTimer still writes only the local record', () async {
      await repo.startTimer('o-1', tableId: 't1');
      final before = outbox.pending().length;
      await repo.evictTimer('o-1');

      expect(db.getTableTimer('o-1'), isNull);
      // Nothing queued: the server closes its own session when the payment
      // lands, so an operation here would be a second request for something
      // already done.
      expect(outbox.pending(), hasLength(before));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 2. Ordering: a timer action never overtakes its order
  // ───────────────────────────────────────────────────────────────────────
  group('causality', () {
    late LocalDatabase db;
    late OutboxStore store;
    late OutboxExecutors executors;
    late OutboxDrainer drainer;

    setUp(() {
      db = LocalDatabase.open(':memory:');
      store = OutboxStore(db);
      executors = OutboxExecutors();
      drainer = OutboxDrainer(
        store: store,
        executors: executors,
        db: db,
        applier: ChangeApplier(db),
      );
    });

    tearDown(() => db.dispose());

    OutboxOperation timerOp({String action = kTimerStart, String? id}) =>
        OutboxOperation(
          id: id ?? 'op-timer',
          entity: kTimerSessionEntity,
          action: action,
          entityId: 'order-1',
          payload: const {'order_id': 'order-1'},
          createdAt: DateTime.utc(2026),
          nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
        );

    test('a timer op shares its chain with the order that owns it', () async {
      registerTimerShiftOutboxHandlers(
        executors,
        await _unusedDio(),
        _FakeShiftRepository(),
      );
      final order = OutboxOperation(
        id: 'op-order',
        entity: 'orders',
        action: 'create',
        entityId: 'order-1',
        payload: const {'id': 'order-1'},
        createdAt: DateTime.utc(2026),
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      // Chain keys are deliberately not namespaced by entity, so "same order"
      // means "same chain" across `orders` and `table_time_sessions`.
      expect(executors.chainKeyOf(timerOp()), 'order-1');
      expect(executors.chainKeyOf(order), 'order-1');
    });

    test('a failing order create holds its timer action back', () async {
      var timerSent = false;
      executors.register(
        'orders',
        'create',
        OutboxHandler(
          send: (_) async => const OutboxExecutionResult.retry('offline'),
        ),
      );
      executors.register(
        kTimerSessionEntity,
        kTimerStart,
        OutboxHandler(
          chainKey: timerOrderIdOf,
          send: (_) async {
            timerSent = true;
            return const OutboxExecutionResult.succeeded();
          },
        ),
      );

      store.enqueue(
        id: 'op-order',
        entity: 'orders',
        action: 'create',
        entityId: 'order-1',
        payload: const {'id': 'order-1'},
      );
      store.enqueue(
        id: 'op-timer',
        entity: kTimerSessionEntity,
        action: kTimerStart,
        entityId: 'order-1',
        payload: const {'order_id': 'order-1'},
      );

      final result = await drainer.drain();

      // Without the chain the start would post to a server that has never
      // heard of the order — a 400, which this outbox treats as a verdict, so
      // the cashier's start would be quarantined rather than retried.
      expect(timerSent, isFalse);
      expect(result.blocked, 1);
      expect(result.retrying, 1);
    });

    test('an unrelated order keeps draining', () async {
      final sent = <String>[];
      executors.register(
        'orders',
        'create',
        OutboxHandler(
          send: (op) async => op.entityId == 'order-1'
              ? const OutboxExecutionResult.retry('offline')
              : const OutboxExecutionResult.succeeded(),
        ),
      );
      executors.register(
        kTimerSessionEntity,
        kTimerStart,
        OutboxHandler(
          chainKey: timerOrderIdOf,
          send: (op) async {
            sent.add(op.entityId!);
            return const OutboxExecutionResult.succeeded();
          },
        ),
      );

      store.enqueue(
        id: 'op-order-1',
        entity: 'orders',
        action: 'create',
        entityId: 'order-1',
        payload: const {'id': 'order-1'},
      );
      store.enqueue(
        id: 'op-timer-1',
        entity: kTimerSessionEntity,
        action: kTimerStart,
        entityId: 'order-1',
        payload: const {'order_id': 'order-1'},
      );
      store.enqueue(
        id: 'op-timer-2',
        entity: kTimerSessionEntity,
        action: kTimerStart,
        entityId: 'order-2',
        payload: const {'order_id': 'order-2'},
      );

      await drainer.drain();
      expect(sent, ['order-2']);
    });

    test('open and close of one register share a chain', () async {
      registerTimerShiftOutboxHandlers(
        executors,
        await _unusedDio(),
        _FakeShiftRepository(),
      );
      OutboxOperation shiftOp(String action) => OutboxOperation(
            id: 'op-$action',
            entity: kShiftEntity,
            action: action,
            entityId: 'register-1',
            payload: const {'cash_register_id': 'register-1'},
            createdAt: DateTime.utc(2026),
            nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
          );
      expect(executors.chainKeyOf(shiftOp(kShiftOpen)), 'register-1');
      expect(executors.chainKeyOf(shiftOp(kShiftClose)), 'register-1');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 3. The hydration shield
  // ───────────────────────────────────────────────────────────────────────
  group('a live local timer is shielded from server hydration', () {
    late LocalDatabase db;
    late OutboxStore store;

    setUp(() {
      db = LocalDatabase.open(':memory:');
      store = OutboxStore(db);
    });

    tearDown(() => db.dispose());

    void enqueueTimer(String orderId) => store.enqueue(
          id: 'op-timer-$orderId',
          entity: kTimerSessionEntity,
          action: kTimerPause,
          entityId: orderId,
          payload: {'order_id': orderId},
        );

    test('a queued timer action shields its order', () {
      enqueueTimer('order-1');
      expect(
        TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(store, 'order-1'),
        isTrue,
      );
      expect(
        TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(store, 'order-2'),
        isFalse,
      );
    });

    test('a queued order create shields its order too', () {
      // The server has never heard of this order, so a timer fetch for it can
      // only answer about nothing — or about someone else's session.
      store.enqueue(
        id: 'op-order',
        entity: 'orders',
        action: 'create',
        entityId: 'order-1',
        payload: const {'id': 'order-1'},
      );
      expect(
        TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(store, 'order-1'),
        isTrue,
      );
    });

    test('other operations on the same order do not shield it', () {
      // Narrow on purpose: an order with a queued payment has no unsent timer
      // state, so a server snapshot is welcome there.
      store.enqueue(
        id: 'op-pay',
        entity: 'orders',
        action: 'pay',
        entityId: 'order-1',
        payload: const {'order_id': 'order-1'},
      );
      expect(
        TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(store, 'order-1'),
        isFalse,
      );
    });

    test('the shield lifts once the action is sent', () {
      enqueueTimer('order-1');
      store.markSucceeded('op-timer-order-1');
      expect(
        TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(store, 'order-1'),
        isFalse,
      );
    });

    test('a quarantined action does not shield', () {
      enqueueTimer('order-1');
      store.markPermanentlyFailed('op-timer-order-1', 'rejected');
      // Same reasoning as `OutboxDrainer._fail` releasing the `_pending`
      // guard: an operation the server refused should stop holding the local
      // record away from the server's version. A visible correction beats a
      // private truth no other terminal can see.
      expect(
        TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(store, 'order-1'),
        isFalse,
      );
    });

    test('the scan is not truncated by the default page size', () {
      // `OutboxStore.pending` caps at 500 rows by default. A terminal offline
      // through a busy service holds more than that, and a timer operation
      // past the cap would be invisible here — which is exactly the silent
      // stomp this guard exists to prevent.
      for (var i = 0; i < 600; i++) {
        store.enqueue(
          id: 'op-noise-$i',
          entity: 'orders',
          action: 'create',
          entityId: 'noise-$i',
          payload: {'id': 'noise-$i'},
        );
      }
      enqueueTimer('order-late');
      expect(
        TableTimerLocalRepositoryImpl.hasPendingLocalTimerOps(
          store,
          'order-late',
        ),
        isTrue,
      );
    });

    test('the set form answers for every order in one scan', () {
      enqueueTimer('order-1');
      enqueueTimer('order-2');
      expect(
        TableTimerLocalRepositoryImpl.pendingLocalTimerOrderIds(store),
        {'order-1', 'order-2'},
      );
    });

    test('hydration overwrites an order that holds no local operation', () {
      // The other half of the property: the shield is narrow, so an order with
      // nothing queued still converges on the server's snapshot. Modelled the
      // way `SyncEngine._hydrateTableTimers` does it — ask the set, then write.
      db.saveTableTimer('order-1', {
        'order_id': 'order-1',
        'state': 'running',
        'accumulated_active_sec': 10,
      });
      final shielded =
          TableTimerLocalRepositoryImpl.pendingLocalTimerOrderIds(store);
      expect(shielded.contains('order-1'), isFalse);

      db.saveTableTimer(
        'order-1',
        TableTimerLocalRepositoryImpl.normalizeServerSnapshot(const {
          'order_id': 'order-1',
          'state': 'paused',
          'total_active_sec': 900,
        }),
      );
      expect(db.getTableTimer('order-1')!['accumulated_active_sec'], 900);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 4. The timer handlers, over a fake socket
  // ───────────────────────────────────────────────────────────────────────
  group('timer handlers', () {
    late DioClient dioClient;
    late OutboxExecutors executors;
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

      executors = OutboxExecutors();
      registerTimerShiftOutboxHandlers(
        executors,
        dioClient,
        _FakeShiftRepository(),
      );
    });

    OutboxOperation op(String action, {String? entityId = 'order-1'}) =>
        OutboxOperation(
          id: 'op-$action',
          entity: kTimerSessionEntity,
          action: action,
          entityId: entityId,
          payload: {'order_id': entityId ?? '', 'action': action},
          createdAt: DateTime.utc(2026),
          nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
        );

    Future<OutboxExecutionResult> run(OutboxOperation o) =>
        executors.resolve(o)!.send(o);

    test('each verb posts its own endpoint', () async {
      for (final action in [kTimerStart, kTimerPause, kTimerResume]) {
        final result = await run(op(action));
        expect(result.outcome, OutboxOutcome.succeeded);
      }
      expect(requests.map((r) => r.path), [
        '/api/v1/orders/order-1/table-timer/start',
        '/api/v1/orders/order-1/table-timer/pause',
        '/api/v1/orders/order-1/table-timer/resume',
      ]);
      expect(requests.map((r) => r.method), ['POST', 'POST', 'POST']);
    });

    test('a replay is safe: the server no-ops an already-applied verb', () async {
      // The backend returns the existing session for a repeated start and
      // documents pause-on-paused / resume-on-running as no-op successes, so a
      // replay after a lost response is an ordinary 200 here.
      await run(op(kTimerStart));
      final again = await run(op(kTimerStart));
      expect(again.outcome, OutboxOutcome.succeeded);
      expect(requests, hasLength(2));
    });

    test('a 4xx is a verdict and stops retrying', () async {
      // Every timer endpoint answers a service error with 400 — including
      // "cannot manage timer for paid order" — so retrying it eight times
      // would only delay everything queued behind it.
      respond = (_) async => ResponseBody.fromString('{}', 400);
      final result = await run(op(kTimerPause));
      expect(result.outcome, OutboxOutcome.permanent);
    });

    test('a 5xx never reached a verdict and is retried', () async {
      respond = (_) async => ResponseBody.fromString('{}', 503);
      final result = await run(op(kTimerResume));
      expect(result.outcome, OutboxOutcome.retry);
    });

    test('an op with no order id is permanent, not a retry', () async {
      final result = await run(op(kTimerStart, entityId: null));
      expect(result.outcome, OutboxOutcome.permanent);
      expect(requests, isEmpty);
    });

    test('the order id falls back to the payload', () async {
      final result = await executors.resolve(op(kTimerStart))!.send(
            OutboxOperation(
              id: 'op-x',
              entity: kTimerSessionEntity,
              action: kTimerStart,
              payload: const {'order_id': 'order-9'},
              createdAt: DateTime.utc(2026),
              nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(requests.single.path, '/api/v1/orders/order-9/table-timer/start');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 5. The shift handlers
  // ───────────────────────────────────────────────────────────────────────
  group('shift handlers', () {
    late _FakeShiftRepository remote;
    late OutboxExecutors executors;

    setUp(() async {
      remote = _FakeShiftRepository();
      executors = OutboxExecutors();
      registerTimerShiftOutboxHandlers(executors, await _unusedDio(), remote);
    });

    OutboxOperation op(
      String action, {
      String? entityId = 'register-1',
      Map<String, dynamic>? payload,
    }) =>
        OutboxOperation(
          id: 'op-$action',
          entity: kShiftEntity,
          action: action,
          entityId: entityId,
          payload: payload ??
              const {
                'cash_register_id': 'register-1',
                'opening_cash': '50000',
                'opening_card': '0',
                'closing_cash': '0',
                'closing_card': '0',
              },
          createdAt: DateTime.utc(2026),
          nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
        );

    Future<OutboxExecutionResult> run(OutboxOperation o) =>
        executors.resolve(o)!.send(o);

    test('open sends the register and its parsed sums', () async {
      final result = await run(op(kShiftOpen));
      expect(result.outcome, OutboxOutcome.succeeded);
      // Sums cross the queue as strings (the wire shape); the request model
      // takes ints. `cashier_id` is absent on purpose — the backend reads it
      // from the JWT.
      expect(remote.calls, ['open:register-1:50000:0']);
    });

    test('open with no register is permanent, not a retry', () async {
      final result = await run(op(kShiftOpen, entityId: null, payload: const {}));
      expect(result.outcome, OutboxOutcome.permanent);
      expect(remote.calls, isEmpty);
    });

    test('an open that never reached a verdict is retried', () async {
      remote.openResult = const Left(ConnectionFailure());
      expect((await run(op(kShiftOpen))).outcome, OutboxOutcome.retry);
    });

    test('an open the server refused on the merits is quarantined', () async {
      remote.openResult = const Left(ValidationFailure());
      expect((await run(op(kShiftOpen))).outcome, OutboxOutcome.permanent);
    });

    test('close resolves the active shift and closes that one', () async {
      final result = await run(op(kShiftClose));
      expect(result.outcome, OutboxOutcome.succeeded);
      // Never the shift's own id: an offline-opened shift carries a
      // `local_...` placeholder, and even a real id may be stale by replay
      // time.
      expect(remote.calls, ['check:register-1', 'close:shift-1:0:0']);
    });

    test('a replayed close finds nothing open and succeeds without closing '
        'again', () async {
      remote.activeResult = const Right(null);
      final result = await run(op(kShiftClose));

      // The one case that must never double-count. No active shift, and the
      // open that would have created one has already drained or been
      // quarantined, so the desired state already holds — succeeding here is
      // what stops a money-critical operation from reaching a human for a till
      // that is already reconciled.
      expect(result.outcome, OutboxOutcome.succeeded);
      expect(remote.calls, ['check:register-1']);
    });

    test('a lookup that failed is not read as "nothing to close"', () async {
      remote.activeResult = const Left(ConnectionFailure());
      final result = await run(op(kShiftClose));
      expect(result.outcome, OutboxOutcome.retry);
      expect(remote.calls, ['check:register-1']);
    });

    test('a close the server refused is quarantined, not silently dropped',
        () async {
      remote.closeResult = const Left(ValidationFailure());
      expect((await run(op(kShiftClose))).outcome, OutboxOutcome.permanent);
    });

    test('close with no register is permanent', () async {
      final result =
          await run(op(kShiftClose, entityId: null, payload: const {}));
      expect(result.outcome, OutboxOutcome.permanent);
      expect(remote.calls, isEmpty);
    });

    test('a close drained twice closes at most once', () async {
      // First pass closes the shift; the register then has no active shift, so
      // the replay is a no-op success rather than a second close.
      await run(op(kShiftClose));
      remote.activeResult = const Right(null);
      final replay = await run(op(kShiftClose));

      expect(replay.outcome, OutboxOutcome.succeeded);
      expect(
        remote.calls.where((c) => c.startsWith('close:')),
        hasLength(1),
      );
    });
  });
}

/// A `DioClient` these groups never reach through. Real rather than faked
/// because `registerTimerShiftOutboxHandlers` takes one for the timer half;
/// its adapter throws, so an accidental request fails loudly instead of
/// quietly passing.
Future<DioClient> _unusedDio() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  InMemorySecureStoragePlatform.install();
  FakeConnectivityPlatform.install();
  final client = DioClient(
    AppTokenStorage(prefs, const FlutterSecureStorage()),
    ConnectivityCubit(Connectivity()),
  );
  Alice(
    configuration: AliceConfiguration(
      showNotification: false,
      showInspectorOnShake: false,
    ),
  ).addAdapter(client.aliceDioAdapter);
  client.dio.httpClientAdapter = FakeHttpClientAdapter(
    (_) async => throw StateError('these handlers must not speak HTTP'),
  );
  return client;
}
