/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §B2/§B3 — the order aggregate's replica
/// write/read round trip, proven end to end without a socket or a running app.
///
/// The data-layer safety net for the money-path flip: a write through
/// [OrdersRepositoryImpl] lands the rows the screen reads AND the outbox op that
/// carries them, and a later pull delivering the server's same-id rows converges
/// instead of duplicating. What this cannot exercise is the bloc-level overlay
/// (grouping, existing-item +/- sync, kitchen printing) — that is the on-device
/// gate. Everything below is the part that CAN be pinned.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/database/local_database.dart' as hive;
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart'
    show TableStatus;
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/orders_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

class _FakeLanHub implements LanHubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The write-only Hive snapshot mirror is never exercised by these replica
/// round trips (createOrder/addItems/cancel/transfer/getOrderDetail never touch
/// it), so a stub that would throw if it ever were is exactly right.
class _FakeHive implements hive.LocalDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTables implements TablesRepository {
  final List<({String id, TableStatus status})> statusWrites = [];

  @override
  Future<void> updateTableStatus(String tableId, TableStatus status) async {
    statusWrites.add((id: tableId, status: status));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LocalDatabase db;
  late OutboxStore outbox;
  late OrdersRepositoryImpl repo;
  late _FakeTables tables;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  OrderItem line(String goodId, String name, String price, {int qty = 1, String comment = ''}) =>
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
        comment: comment,
      );

  setUp(() {
    db = LocalDatabase.open(':memory:');
    final applier = ChangeApplier(db);
    outbox = OutboxStore(db);
    tables = _FakeTables();
    repo = OrdersRepositoryImpl(
      db: db,
      applier: applier,
      writer: LocalWriter(db: db, applier: applier, outbox: outbox),
      detail: OrderDetailQuery(db),
      hiveStore: _FakeHive(),
      lanHub: _FakeLanHub(),
      tables: tables,
    );

    put('halls', {'id': 'h1', 'name': 'Main', 'branch_id': 'b1', 'deleted_at': 0});
    put('cafe_tables', {'id': 'tb1', 'hall_id': 'h1', 'number': 5, 'deleted_at': 0});
    put('cafe_tables', {'id': 'tb2', 'hall_id': 'h1', 'number': 6, 'deleted_at': 0});
    put('goods', {'id': 'g1', 'name': 'Osh', 'branch_id': 'b1', 'price': 25000, 'deleted_at': 0});
    put('goods', {'id': 'g2', 'name': 'Lagmon', 'branch_id': 'b1', 'price': 30000, 'deleted_at': 0});
  });

  tearDown(() => db.dispose());

  List<OutboxOperation> readyOps() => outbox.ready(limit: 100);

  group('createOrder', () {
    test('shows the order and its items on the replica read immediately', () async {
      await repo.createOrder(
        tableId: 'tb1',
        clientOrderId: 'o1',
        guestCount: 3,
        items: [line('g1', 'Osh', '25000'), line('g2', 'Lagmon', '30000', qty: 2)],
        tableStatus: TableStatus.busy,
      );

      final detail = repo.getOrderDetail('tb1')!;
      expect(detail.id, 'o1');
      expect(detail.tableNumber, 5);
      expect(detail.hallName, 'Main');
      expect(detail.guestCount, 3);
      // good_name comes from the join; quantity/price from the stored line rows.
      expect(detail.goods.map((g) => g.name), ['Osh', 'Lagmon']);
      expect(detail.goods.map((g) => g.quantity), [1, 2]);
    });

    test('enqueues one orders/create op carrying the items with client ids', () async {
      await repo.createOrder(
        tableId: 'tb1',
        clientOrderId: 'o1',
        guestCount: 1,
        items: [line('g1', 'Osh', '25000')],
        tableStatus: TableStatus.busy,
      );

      final ops = readyOps();
      expect(ops, hasLength(1));
      final op = ops.single;
      expect(op.entity, 'orders');
      expect(op.action, 'create');
      expect(op.entityId, 'o1');
      final bodyItems = (op.payload['items'] as List).cast<Map<String, dynamic>>();
      expect(bodyItems, hasLength(1));
      // The line id the server will honour is in the body, and it is the same id
      // the local row was written under (no reconciliation needed).
      final sentId = bodyItems.single['id'] as String;
      expect(sentId, isNotEmpty);
      final storedId = (repo.getOrderDetail('tb1')!.goods.single).id;
      expect(sentId, storedId);
    });

    test('a pull re-delivering the same-id server rows converges, no duplicate', () async {
      await repo.createOrder(
        tableId: 'tb1',
        clientOrderId: 'o1',
        guestCount: 1,
        items: [line('g1', 'Osh', '25000')],
        tableStatus: TableStatus.busy,
      );
      final itemId = repo.getOrderDetail('tb1')!.goods.single.id;

      // The server's version of the same line, under the same id but a higher
      // price (e.g. a modifier applied server-side).
      ChangeApplier(db).applyPullResponse({
        'next_sync_cursor': 1,
        'changes': {
          'order_items': {
            'created': [
              {
                'id': itemId,
                'order_id': 'o1',
                'good_id': 'g1',
                'quantity': 1,
                'price': 40000,
                'status': 'pending',
                'created_at': '2026-08-12T10:00:00Z',
              },
            ],
          },
        },
      });

      final goods = repo.getOrderDetail('tb1')!.goods;
      expect(goods, hasLength(1)); // converged onto the same row, not duplicated
      expect(goods.single.price, 40000); // and picked up the server's value
    });
  });

  group('addItems', () {
    test('adds a line to an open order and enqueues a per-item op', () async {
      await repo.createOrder(
        tableId: 'tb1',
        clientOrderId: 'o1',
        guestCount: 1,
        items: [line('g1', 'Osh', '25000')],
        tableStatus: TableStatus.busy,
      );

      await repo.addItems(
        tableId: 'tb1',
        orderId: 'o1',
        items: [line('g2', 'Lagmon', '30000')],
      );

      expect(repo.getOrderDetail('tb1')!.goods.map((g) => g.name), ['Osh', 'Lagmon']);

      final addOps = readyOps().where((o) => o.entity == 'order_items' && o.action == 'create');
      expect(addOps, hasLength(1));
      expect(addOps.single.payload['order_id'], 'o1');
    });
  });

  group('cancelLineItems', () {
    test('removes the line and guards it so a pull cannot resurrect it', () async {
      await repo.createOrder(
        tableId: 'tb1',
        clientOrderId: 'o1',
        guestCount: 1,
        items: [line('g1', 'Osh', '25000'), line('g2', 'Lagmon', '30000')],
        tableStatus: TableStatus.busy,
      );
      final oshId = repo.getOrderDetail('tb1')!.goods
          .firstWhere((g) => g.name == 'Osh').id;

      await repo.cancelLineItems(lineIds: [oshId], comment: 'wrong table');

      expect(repo.getOrderDetail('tb1')!.goods.map((g) => g.name), ['Lagmon']);
      expect(db.isPending('order_items', oshId), isTrue);

      // A pull still carrying the (not-yet-cancelled) server line must not bring
      // it back while the cancel is unsynced.
      ChangeApplier(db).applyPullResponse({
        'next_sync_cursor': 2,
        'changes': {
          'order_items': {
            'created': [
              {
                'id': oshId,
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
      expect(repo.getOrderDetail('tb1')!.goods.map((g) => g.name), ['Lagmon']);

      final cancelOps = readyOps().where((o) => o.action == 'delete');
      expect(cancelOps.single.entityId, oshId);
      expect(cancelOps.single.payload['order_id'], 'o1');
    });
  });

  group('transferTable', () {
    test('re-keys the bill onto the target table and patches occupancy', () async {
      await repo.createOrder(
        tableId: 'tb1',
        clientOrderId: 'o1',
        guestCount: 1,
        items: [line('g1', 'Osh', '25000')],
        tableStatus: TableStatus.busy,
      );

      await repo.transferTable(orderId: 'o1', sourceTableId: 'tb1', targetTableId: 'tb2');

      expect(repo.getOrderDetail('tb1'), isNull);
      expect(repo.getOrderDetail('tb2')!.id, 'o1');
      expect(tables.statusWrites, [
        (id: 'tb1', status: TableStatus.free),
        (id: 'tb2', status: TableStatus.busy),
      ]);
      expect(readyOps().any((o) => o.action == 'transfer'), isTrue);
    });
  });

  group('takeaway', () {
    test('is readable by its order id (no table)', () async {
      await repo.createTakeawayOrder(
        clientOrderId: 't1',
        guestCount: 1,
        items: [line('g1', 'Osh', '25000')],
      );

      final detail = repo.getOrderDetail('t1')!;
      expect(detail.id, 't1');
      expect(detail.goods.single.name, 'Osh');
    });
  });
}
