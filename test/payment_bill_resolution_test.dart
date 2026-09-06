/// `PaymentBloc` must always resolve the bill to a state the cashier can act
/// on — never to a spinner that cannot end.
///
/// The defect these pin: the payment screen's only render gate is
/// `state.detail != null`, and the bloc watched the bill by **table id
/// alone**. That key resolves through `OrderDetailQuery.liveOrderForTable`,
/// which matches only a bill still inside the open-bill predicate — so a check
/// that had already left it (settled on this terminal, settled on another and
/// pulled in, or comped) resolved to null on every emission. `Status.ERROR`
/// was never emitted either, so the screen's "payment info not found" branch
/// was dead code: the null rendered a spinner with no message and no way back,
/// on the highest-stakes screen in the app.
///
/// Driven at the bloc + real-replica level rather than through the app: the
/// subject is which rows the two keys resolve to and what the bloc emits for
/// each, and that is exactly what a `LocalDatabase` and a real
/// `OrdersRepositoryImpl` can answer without a widget tree.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/orders_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/payment_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/service_charge_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/tables_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';

class _FakeLanHub implements LanHubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTables implements TablesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePrinter implements PrinterService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late LocalDatabase db;
  late OrdersRepositoryImpl orders;
  late PaymentBloc bloc;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(
      spec,
      data['id'] as String,
      PayloadNormalizer.normalize(spec, data),
    );
  }

  /// One bill on `tb1`, at whatever [billStatus]/[status] the caller wants.
  void bill({
    String id = 'o1',
    String tableId = 'tb1',
    String billStatus = 'open',
    String status = 'open',
  }) {
    put('orders', {
      'id': id,
      'table_id': tableId,
      'branch_id': 'b1',
      'bill_status': billStatus,
      'status': status,
      'order_type': 'dine_in',
      'guest_count': 2,
      'bill_no': 7,
      'created_at': '2026-08-23T06:00:00Z',
      'deleted_at': 0,
    });
    put('order_items', {
      'id': 'oi-$id',
      'order_id': id,
      'good_id': 'g1',
      'quantity': 2,
      'price': 35000,
      'status': 'pending',
      'created_at': '2026-08-23T06:01:00Z',
      'deleted_at': 0,
    });
  }

  setUp(() {
    db = LocalDatabase.open(':memory:');
    final applier = ChangeApplier(db);
    final outbox = OutboxStore(db);
    final writer = LocalWriter(db: db, applier: applier, outbox: outbox);
    orders = OrdersRepositoryImpl(
      db: db,
      applier: applier,
      writer: writer,
      detail: OrderDetailQuery(db),
      lanHub: _FakeLanHub(),
      tables: _FakeTables(),
    );
    bloc = PaymentBloc(
      ordersRepository: orders,
      paymentRepository: PaymentRepositoryImpl(writer: writer),
      printerService: _FakePrinter(),
      // The real implementation over the same replica, not a fake: it reads
      // `branches.default_service_percent`, which these fixtures control
      // anyway, so the bloc's service-percent resolution is exercised rather
      // than stubbed out.
      serviceChargeRepository: ServiceChargeRepositoryImpl(db, writer),
    );

    put('halls', {'id': 'h1', 'name': 'Main', 'branch_id': 'b1', 'deleted_at': 0});
    put('cafe_tables', {'id': 'tb1', 'hall_id': 'h1', 'number': 5, 'deleted_at': 0});
    put('goods', {
      'id': 'g1',
      'name': 'Osh',
      'branch_id': 'b1',
      'price': 35000,
      'deleted_at': 0,
    });
  });

  tearDown(() async {
    await bloc.close();
    db.dispose();
  });

  /// Starts the screen's bloc and lets the detail subscription's first
  /// emission land.
  Future<void> start({String? tableId, String? orderId}) async {
    bloc.add(PaymentEvent.started(tableId: tableId, orderId: orderId));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('an open bill resolves from the table key alone', () async {
    bill();
    await start(tableId: 'tb1');

    expect(bloc.state.detail?.id, 'o1');
    expect(bloc.state.detailStatus, Status.SUCCESS);
  });

  test('a settled bill still resolves through the order key', () async {
    // What a check settled a moment ago looks like: `PaymentRepositoryImpl.pay`
    // writes `bill_status = 'paid'` onto the row, which takes it straight out
    // of `liveOrderForTable`. The table key alone is null from here on.
    bill(billStatus: 'paid', status: 'paid');
    expect(
      orders.getOrderDetail('tb1'),
      isNull,
      reason: 'precondition: the table key no longer resolves a settled bill',
    );

    await start(tableId: 'tb1', orderId: 'o1');

    expect(
      bloc.state.detail?.id,
      'o1',
      reason: 'the order key resolves the row whatever its bill_status',
    );
    expect(bloc.state.detailStatus, Status.SUCCESS);
  });

  test('a comped bill still resolves through the order key', () async {
    // `cancelZeroTotalOrder` sets `status = 'cancelled'` and leaves
    // `bill_status` alone — the other way a bill leaves the live read.
    bill(status: 'cancelled');
    expect(orders.getOrderDetail('tb1'), isNull);

    await start(tableId: 'tb1', orderId: 'o1');

    expect(bloc.state.detail?.id, 'o1');
  });

  test('a key that resolves to no bill ends in ERROR, not LOADING', () async {
    await start(tableId: 'tb-no-such-table');

    expect(
      bloc.state.detailStatus,
      Status.ERROR,
      reason:
          'the replica read is synchronous and authoritative — a null on the '
          'first emission is an answer, and rendering it as LOADING is what '
          'left the cashier on a spinner that could never finish',
    );
    expect(bloc.state.detail, isNull);
  });

  test('no keys at all ends in ERROR rather than never subscribing', () async {
    await start();

    expect(bloc.state.detailStatus, Status.ERROR);
  });

  test('a bill that appears after the ERROR still lands on screen', () async {
    await start(tableId: 'tb1');
    expect(bloc.state.detailStatus, Status.ERROR);

    // The subscription is still open — the error state is an answer to "is
    // there a bill right now", not a torn-down screen.
    bill();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.detail?.id, 'o1');
    expect(bloc.state.detailStatus, Status.SUCCESS);
  });
}
