/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §9.3 — the order flow, offline end to end.
///
/// The unit tests pin the pieces: `orders_replica_write_test` the repository →
/// replica read, `orders_outbox_test` the handlers against a fake adapter. This
/// ties them together through the real drainer: a write goes in the front door
/// (OrdersRepositoryImpl), the outbox drains through the registered handlers to
/// a genuine DioClient with no socket, and the local row's pending guard
/// behaves — held while the send is failing, released once the server has it.
/// It is the "no user action awaits a Dio future, and the queue reaches the
/// server on its own" property as a test.
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
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/orders_outbox.dart';
import 'package:mary_ai_pos/core/outbox/outbox_drainer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_executor.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart'
    show TableStatus;
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/orders_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connectivity_platform.dart';
import 'support/fake_http_client_adapter.dart';
import 'support/in_memory_secure_storage.dart';

class _FakeLanHub implements LanHubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTables implements TablesRepository {
  @override
  Future<void> updateTableStatus(String tableId, TableStatus status) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late ChangeApplier applier;
  late OutboxStore outbox;
  late OrdersRepositoryImpl repo;
  late OutboxDrainer drainer;
  late DioClient dioClient;
  late List<RequestOptions> requests;
  late bool offline; // when true the fake server drops the connection

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  OrderItem line(String goodId, String name, String price, {int qty = 1}) =>
      OrderItem(
        goods: GoodsModel(
          id: goodId,
          name: name,
          price: price,
          categoryId: '',
          cookTime: 0,
          costPrice: '0',
          description: '',
          profit: '0',
          profitMargin: '0',
        ),
        quantity: qty,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    InMemorySecureStoragePlatform.install();
    FakeConnectivityPlatform.install();

    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
    outbox = OutboxStore(db);
    repo = OrdersRepositoryImpl(
      db: db,
      applier: applier,
      writer: LocalWriter(db: db, applier: applier, outbox: outbox),
      detail: OrderDetailQuery(db),
      lanHub: _FakeLanHub(),
      tables: _FakeTables(),
    );

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
    offline = false;
    dioClient.dio.httpClientAdapter = FakeHttpClientAdapter((options) async {
      requests.add(options);
      if (offline) return connectionErrorResponse(options);
      return okResponse();
    });

    final executors = OutboxExecutors();
    registerOrdersOutboxHandlers(executors, dioClient);
    drainer = OutboxDrainer(
      store: outbox,
      executors: executors,
      db: db,
      applier: applier,
    );

    put('halls', {'id': 'h1', 'name': 'Main', 'branch_id': 'b1', 'deleted_at': 0});
    put('cafe_tables', {'id': 'tb1', 'hall_id': 'h1', 'number': 5, 'deleted_at': 0});
    put('goods', {'id': 'g1', 'name': 'Osh', 'branch_id': 'b1', 'price': 25000, 'deleted_at': 0});
    put('goods', {'id': 'g2', 'name': 'Lagmon', 'branch_id': 'b1', 'price': 30000, 'deleted_at': 0});
  });

  tearDown(() => db.dispose());

  Map<String, dynamic> bodyOf(RequestOptions o) {
    final d = o.data;
    if (d is Map) return d.cast<String, dynamic>();
    if (d is String && d.isNotEmpty) {
      return jsonDecode(d) as Map<String, dynamic>;
    }
    return {};
  }

  test('an order written offline shows locally and drains once the server is reachable',
      () async {
    await repo.createOrder(
      tableId: 'tb1',
      clientOrderId: 'o1',
      guestCount: 2,
      items: [line('g1', 'Osh', '25000')],
      tableStatus: TableStatus.busy,
    );

    // The UI has its order immediately, and the row is guarded so a pull can't
    // revert it before the create is acknowledged.
    expect(repo.getOrderDetail('tb1')!.id, 'o1');
    expect(db.isPending('orders', 'o1'), isTrue);

    final result = await drainer.drain();

    expect(result.sent, 1);
    // The create reached POST /orders carrying its line.
    final createReq = requests.singleWhere((r) => r.uri.path == '/api/v1/orders');
    expect((bodyOf(createReq)['items'] as List).single['good_id'], 'g1');
    // Acknowledged — the guard releases so replication may correct the row.
    expect(db.isPending('orders', 'o1'), isFalse);
  });

  test('a send that never reaches the server keeps the local row guarded',
      () async {
    offline = true;
    await repo.createOrder(
      tableId: 'tb1',
      clientOrderId: 'o1',
      guestCount: 1,
      items: [line('g1', 'Osh', '25000')],
      tableStatus: TableStatus.busy,
    );

    final result = await drainer.drain();

    // The request was attempted but dropped — retryable, not a verdict.
    expect(requests, isNotEmpty);
    expect(result.sent, 0);
    expect(result.retrying, 1);
    // The order still shows and stays guarded for the next attempt.
    expect(repo.getOrderDetail('tb1')!.id, 'o1');
    expect(db.isPending('orders', 'o1'), isTrue);
  });

  test('an added line never overtakes the order that created it', () async {
    await repo.createOrder(
      tableId: 'tb1',
      clientOrderId: 'o1',
      guestCount: 1,
      items: [line('g1', 'Osh', '25000')],
      tableStatus: TableStatus.busy,
    );
    await repo.addItems(tableId: 'tb1', orderId: 'o1', items: [line('g2', 'Lagmon', '30000')]);

    await drainer.drain();

    final createIdx = requests.indexWhere((r) => r.uri.path == '/api/v1/orders');
    final addIdx =
        requests.indexWhere((r) => r.uri.path == '/api/v1/orders/o1/items');
    expect(createIdx, isNonNegative);
    expect(addIdx, isNonNegative);
    // Chain key = order id, so the create is on the wire before the add-items.
    expect(createIdx, lessThan(addIdx));
  });

  test('after the create acks, a pull of the server row converges without a duplicate',
      () async {
    await repo.createOrder(
      tableId: 'tb1',
      clientOrderId: 'o1',
      guestCount: 1,
      items: [line('g1', 'Osh', '25000')],
      tableStatus: TableStatus.busy,
    );
    final itemId = repo.getOrderDetail('tb1')!.goods.single.id;
    await drainer.drain();

    // The next pull delivers the server's order + line under the same ids.
    applier.applyPullResponse({
      'next_sync_cursor': 1,
      'changes': {
        'orders': {
          'created': [
            {
              'id': 'o1',
              'table_id': 'tb1',
              'bill_status': 'open',
              'branch_id': 'b1',
              'bill_no': 42,
              'created_at': '2026-08-12T10:00:00Z',
            },
          ],
        },
        'order_items': {
          'created': [
            {
              'id': itemId,
              'order_id': 'o1',
              'good_id': 'g1',
              'quantity': 1,
              'price': 25000,
              'status': 'pending',
              'created_at': '2026-08-12T10:00:00Z',
            },
          ],
        },
      },
    });

    final detail = repo.getOrderDetail('tb1')!;
    expect(detail.goods, hasLength(1)); // converged, not duplicated
    expect(detail.bilNumber, 42); // and picked up the server bill number
  });
}
