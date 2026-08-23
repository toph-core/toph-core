/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — closing a bill without a
/// network, and proving every replica read agrees it is closed.
///
/// The bug these pin: paying used to queue the payment and change nothing
/// else. The `orders` row kept `bill_status = 'open'`, so
/// `OrderDetailQuery.liveOrderForTable` — the read behind the floor plan, the
/// order screen and the waiter open-order list — still reported a live bill on
/// a table the cashier had just settled. Online the next pull papered over it.
/// Offline, which is the case this architecture exists for, nothing ever did.
///
/// Everything below runs against a real in-memory replica and the real outbox
/// table, with no HTTP and no app: the local commit is the whole subject, and
/// the send is somebody else's test (`orders_outbox_test.dart`).
///
/// Deliberately built without `OrdersRepositoryImpl`: rows are seeded straight
/// into the replica, in the shape a `/sync/pull` delivers them, so what is
/// asserted is the state of the database rather than the cooperation of two
/// repositories.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/archives_query.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_operation.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/core/pricing/order_totals.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_filter_request/archives_filter_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/payment_repository_impl.dart';

void main() {
  late LocalDatabase db;
  late ChangeApplier applier;
  late OutboxStore outbox;
  late OrderDetailQuery detail;
  late ArchivesQuery archives;
  late PaymentRepositoryImpl repo;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  /// An open bill on table `tb1`, in the shape the change feed delivers one.
  void openBill({
    String id = 'o1',
    String? tableId = 'tb1',
    String billStatus = 'open',
    String createdAt = '2026-08-20T18:00:00+00:00',
  }) {
    put('orders', {
      'id': id,
      'table_id': tableId ?? '',
      'branch_id': 'b1',
      'bill_no': 41,
      'bill_status': billStatus,
      'status': 'open',
      'order_type': 'dine_in',
      'guest_count': 4,
      'service_percent': 20,
      'created_at': createdAt,
    });
    put('order_items', {
      'id': '$id-l1',
      'order_id': id,
      'good_id': 'g1',
      'quantity': 2,
      'price': 25000,
      'status': 'pending',
      'created_at': createdAt,
    });
  }

  /// The totals the payment screen would have shown for [openBill]: two
  /// portions at 25 000, 20% service, no table charge, no discount.
  OrderTotals settledTotals({
    double tableCharge = 0,
    double discountPercent = 0,
    double discountAmount = 0,
    bool includeService = true,
  }) =>
      OrderTotals.compute(
        itemsAmount: 50000,
        tableCharge: tableCharge,
        servicePercent: 20,
        discountPercent: discountPercent,
        discountAmount: discountAmount,
        includeService: includeService,
      );

  ArchivesFilterRequestModel filter({String? billStatus}) =>
      ArchivesFilterRequestModel(
        filterType: ArchivesFilterType.All,
        billStatus: billStatus,
        pagination: const PaginationRequestModel(limit: 20, offset: 0),
      );

  Map<String, dynamic> orderRow(String id) => db.byId('orders', id)!;

  List<OutboxOperation> ops() => outbox.pending();

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
    outbox = OutboxStore(db);
    detail = OrderDetailQuery(db);
    archives = ArchivesQuery(db);
    repo = PaymentRepositoryImpl(
      writer: LocalWriter(db: db, applier: applier, outbox: outbox),
    );

    put('halls', {'id': 'h1', 'name': 'Main', 'branch_id': 'b1', 'deleted_at': 0});
    put('cafe_tables', {'id': 'tb1', 'hall_id': 'h1', 'number': 5, 'deleted_at': 0});
    put('goods', {
      'id': 'g1',
      'name': 'Osh',
      'branch_id': 'b1',
      'price': 25000,
      'deleted_at': 0,
    });
  });

  tearDown(() => db.dispose());

  // ───────────────────────────────────────────────────────────────────────
  // The bug itself
  // ───────────────────────────────────────────────────────────────────────

  group('pay — the bill closes locally', () {
    test('the table stops reporting a live bill the moment the cashier pays',
        () async {
      openBill();
      expect(detail.liveOrderForTable('tb1'), isNotNull);

      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      // This is the assertion the old implementation failed: it queued the
      // payment and left `bill_status = 'open'` behind.
      expect(detail.liveOrderForTable('tb1'), isNull);
      expect(detail.openOrders(), isEmpty);
      expect(orderRow('o1')['bill_status'], 'paid');
      expect(orderRow('o1')['status'], 'paid');
    });

    test('a takeaway bill leaves the open-order list too', () async {
      openBill(id: 't1', tableId: null);
      expect(detail.openOrders().map((o) => o['id']), ['t1']);

      await repo.pay(
        orderId: 't1',
        tableId: '',
        paidAmount: 60000,
        paymentType: 'card',
        applyService: true,
        settled: settledTotals(),
      );

      expect(detail.openOrders(), isEmpty);
    });

    test('the settled bill still reads by order id, items and all', () async {
      openBill();

      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      // `liveOrderById` deliberately ignores bill_status — the payment screen
      // must keep rendering the check it just settled, and the archive detail
      // reads the same way.
      final bill = detail.liveOrderById('o1')!;
      expect(bill['bill_status'], 'paid');
      expect(bill['table_number'], 5);
      expect(bill['hall_name'], 'Main');
      expect((bill['items'] as List), hasLength(1));
      expect((bill['items'] as List).single['good_name'], 'Osh');
    });

    test('nothing but the closure changes: the rest of the row survives',
        () async {
      openBill();

      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      final row = orderRow('o1');
      // A replicated row is one JSON blob and the write replaces it, so a
      // patch that forgot to merge would silently drop the bill number, the
      // guest count and the opening time — everything the receipt and the
      // archive are keyed on.
      expect(row['bill_no'], 41);
      expect(row['guest_count'], 4);
      expect(row['created_at'], '2026-08-20T18:00:00+00:00');
      expect(row['order_type'], 'dine_in');
      expect(row['table_id'], 'tb1');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The pending guard
  // ───────────────────────────────────────────────────────────────────────

  group('pay — the pending guard', () {
    test('a pull carrying the still-open server row cannot reopen the bill',
        () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );
      expect(db.isPending('orders', 'o1'), isTrue);

      // The server has not heard about the payment yet, so its version of this
      // order is still open — and its `bill_status` is the backend's own
      // spelling, `opened`.
      final stats = applier.applyPullResponse({
        'next_sync_cursor': 7,
        'changes': {
          'orders': {
            'updated': [
              {
                'id': 'o1',
                'table_id': 'tb1',
                'branch_id': 'b1',
                'bill_no': 41,
                'bill_status': 'opened',
                'status': 'open',
                'order_type': 'dine_in',
                'guest_count': 4,
                'created_at': '2026-08-20T18:00:00+00:00',
              },
            ],
          },
        },
      });

      expect(stats.skippedPending, 1);
      expect(orderRow('o1')['bill_status'], 'paid');
      expect(detail.liveOrderForTable('tb1'), isNull);
    });

    test('once the pay is acknowledged the server row takes over', () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      // What OutboxDrainer._succeed does on an ack.
      db.clearPending('orders', 'o1');

      applier.applyPullResponse({
        'next_sync_cursor': 8,
        'changes': {
          'orders': {
            'updated': [
              {
                'id': 'o1',
                'table_id': 'tb1',
                'bill_no': 41,
                'bill_status': 'paid',
                'status': 'paid',
                'paid_at': '2026-08-20T19:30:00+00:00',
                'grand_total': 60000,
                'created_at': '2026-08-20T18:00:00+00:00',
              },
            ],
          },
        },
      });

      // Server is authoritative from here on, and it agrees the bill is closed
      // — which is the point of writing the same shape it writes.
      expect(orderRow('o1')['bill_status'], 'paid');
      expect(orderRow('o1')['grand_total'], '60000');
      expect(detail.liveOrderForTable('tb1'), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The queued operation
  // ───────────────────────────────────────────────────────────────────────

  group('pay — the queued operation', () {
    test('is one orders/pay op on the outbox, keyed to the order', () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      expect(ops(), hasLength(1));
      final op = ops().single;
      expect(op.entity, 'orders');
      expect(op.action, 'pay');
      // The entity id is the order's, so `orders_outbox`'s pay handler finds
      // it, the op chains behind that order's own create, and the ack clears
      // the guard on this exact row.
      expect(op.entityId, 'o1');
      expect(op.payload['order_id'], 'o1');
      expect(op.payload['customer_paid_amount'], '60000');
      expect(op.payload['payment_type'], 'cash');
      expect(op.payload['apply_service'], isTrue);
    });

    test('carries the same client_payment_id on every replay', () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      final first = ops().single;
      final key = first.payload['client_payment_id'] as String;
      expect(key, isNotEmpty);

      // Two failed sends, i.e. two more attempts of the same charge. The key
      // is persisted in the payload, not minted per attempt, so the backend
      // sees one payment however many times the terminal retries.
      outbox.markFailed(first.id, 'timeout');
      outbox.markFailed(first.id, 'timeout again');

      final replayed = ops().single;
      expect(replayed.id, first.id);
      expect(replayed.attempts, 2);
      expect(replayed.payload['client_payment_id'], key);
    });

    test('two separate payments never share an idempotency key', () async {
      openBill(id: 'o1');
      openBill(id: 'o2', tableId: null);

      for (final id in ['o1', 'o2']) {
        await repo.pay(
          orderId: id,
          tableId: '',
          paidAmount: 60000,
          paymentType: 'cash',
          applyService: true,
          settled: settledTotals(),
        );
      }

      final keys =
          ops().map((o) => o.payload['client_payment_id']).toSet();
      expect(keys, hasLength(2));
    });

    test('freezes the table charge and the closing clock into the payload',
        () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 200000,
        paymentType: 'cash',
        applyService: true,
        tableCharge: 120000,
        settled: settledTotals(tableCharge: 120000),
      );

      final op = ops().single;
      // Both are frozen for the same reason: the queued pay may replay hours
      // later, on a clock that has moved and a timer the server would price
      // differently.
      // A string on the wire, not a number: MarkOrderPaidRequest declares
      // table_charge/discount_* as *string, and encoding/json refuses a
      // number into a string field — which 400s the whole pay, quarantines
      // the op, and reopens the settled bill when the guard releases.
      expect(op.payload['table_charge'], '120000');
      expect(op.payload['paid_at'], orderRow('o1')['paid_at']);
      expect(DateTime.tryParse(op.payload['paid_at'] as String), isNotNull);
    });

    test('discount stays money-or-percent, never both', () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 54000,
        paymentType: 'cash',
        applyService: true,
        discountPercent: 10,
        discountAmount: 0,
        settled: settledTotals(discountPercent: 10),
      );

      final op = ops().single;
      expect(op.payload['discount_percent'], '10');
      expect(op.payload.containsKey('discount_amount'), isFalse);
      // The row records the percent that was applied and the money it came to,
      // exactly as PayOrderBill writes both columns.
      expect(orderRow('o1')['discount_percent'], '10');
      expect(orderRow('o1')['discount_amount'], '6000');
    });

    test('a flat discount sends no percent and clears the stored one',
        () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 55000,
        paymentType: 'cash',
        applyService: true,
        discountAmount: 5000,
        discountPercent: 0,
        settled: settledTotals(discountAmount: 5000),
      );

      final op = ops().single;
      expect(op.payload['discount_amount'], '5000');
      expect(op.payload.containsKey('discount_percent'), isFalse);
      expect(orderRow('o1')['discount_percent'], isNull);
      expect(orderRow('o1')['discount_amount'], '5000');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The money on the closed row
  // ───────────────────────────────────────────────────────────────────────

  group('pay — the settled figures', () {
    test('records the numbers the cashier was looking at', () async {
      openBill();
      final due = settledTotals();

      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 70000,
        paymentType: 'cash',
        applyService: true,
        settled: due,
      );

      final row = orderRow('o1');
      // Money columns are `numeric` on the server and arrive from the feed as
      // strings, so PayloadNormalizer stores them that way here too — the same
      // shape a pulled row has.
      expect(row['food_total'], '50000');
      expect(row['service_amount'], '10000');
      expect(row['grand_total'], '60000');
      expect(row['total_amount'], '60000');
      expect(row['customer_paid_amount'], '70000');
      expect(row['change_amount'], '10000');
      expect(row['cash_amount'], '70000');
      expect(row.containsKey('card_amount'), isFalse);
      expect(row['payment_type'], 'cash');
      expect(row['service_applied'], isTrue);
      expect(due.grandTotal, 60000);
    });

    test('the service toggle settles the charge at zero, as the server does',
        () async {
      openBill();

      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 50000,
        paymentType: 'card',
        applyService: false,
        settled: settledTotals(includeService: false),
      );

      final row = orderRow('o1');
      expect(row['service_applied'], isFalse);
      expect(row['service_amount'], '0');
      expect(row['grand_total'], '50000');
      expect(row['card_amount'], '50000');
      expect(row.containsKey('cash_amount'), isFalse);
    });

    test('closes correctly with no totals supplied, leaving money to the pull',
        () async {
      // The waiter close-order path does not assemble totals.
      openBill();

      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
      );

      final row = orderRow('o1');
      expect(row['bill_status'], 'paid');
      expect(row['customer_paid_amount'], '60000');
      expect(row.containsKey('grand_total'), isFalse);
      expect(detail.liveOrderForTable('tb1'), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Archives
  // ───────────────────────────────────────────────────────────────────────

  group('pay — the archive', () {
    test('a locally-paid bill is in the archives list immediately, offline',
        () async {
      openBill();
      expect(
        (archives.page(filter(billStatus: 'paid'))['items'] as List),
        isEmpty,
      );

      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 70000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      final items = archives.page(filter(billStatus: 'paid'))['items'] as List;
      expect(items, hasLength(1));
      final bill = items.single as Map<String, dynamic>;
      expect(bill['id'], 'o1');
      expect(bill['bill_no'], 41);
      expect(bill['grand_total'], '60000');
      // The list model reads the close time under `closed_at`, projected from
      // `paid_at` — so a bill with no `paid_at` would sort as if still open.
      expect(bill['closed_at'], isNotNull);
      expect(bill['closed_at'], orderRow('o1')['paid_at']);
      expect(bill['quantity'], 2);
    });

    test('and is no longer in the "opened" filter', () async {
      openBill();
      await repo.pay(
        orderId: 'o1',
        tableId: 'tb1',
        paidAmount: 60000,
        paymentType: 'cash',
        applyService: true,
        settled: settledTotals(),
      );

      expect(
        (archives.page(filter(billStatus: 'open'))['items'] as List),
        isEmpty,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The comped check
  // ───────────────────────────────────────────────────────────────────────

  group('cancelZeroTotalOrder', () {
    test('takes the comped bill off the table without inventing a bill_status',
        () async {
      openBill();

      await repo.cancelZeroTotalOrder(orderId: 'o1', tableId: 'tb1');

      final row = orderRow('o1');
      // `CancelOrder` sets `status = 'cancelled'` and touches nothing else, so
      // neither does this — a local `bill_status` the server will never write
      // would be reverted by the first pull after the cancel acks.
      expect(row['status'], 'cancelled');
      expect(row['bill_status'], 'open');
      // It still leaves every live read, which is what the table needs.
      expect(detail.liveOrderForTable('tb1'), isNull);
      expect(detail.openOrders(), isEmpty);
      // And it is still readable by id, so the receipt/archive detail works.
      expect(detail.liveOrderById('o1'), isNotNull);
    });

    test('queues one orders/cancel op and guards the row', () async {
      openBill();

      await repo.cancelZeroTotalOrder(orderId: 'o1', tableId: 'tb1');

      final op = ops().single;
      expect(op.entity, 'orders');
      expect(op.action, 'cancel');
      expect(op.entityId, 'o1');
      expect(op.payload['order_id'], 'o1');
      expect(db.isPending('orders', 'o1'), isTrue);
    });

    test('a pull cannot resurrect the comped bill before the cancel syncs',
        () async {
      openBill();
      await repo.cancelZeroTotalOrder(orderId: 'o1', tableId: 'tb1');

      applier.applyPullResponse({
        'next_sync_cursor': 3,
        'changes': {
          'orders': {
            'updated': [
              {
                'id': 'o1',
                'table_id': 'tb1',
                'bill_status': 'opened',
                'status': 'open',
                'created_at': '2026-08-20T18:00:00+00:00',
              },
            ],
          },
        },
      });

      expect(orderRow('o1')['status'], 'cancelled');
      expect(detail.liveOrderForTable('tb1'), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The live-bill predicate the above depends on
  // ───────────────────────────────────────────────────────────────────────

  group('OrderDetailQuery — what counts as a live bill', () {
    test('a bill the feed delivered ("opened") is live, same as a local "open"',
        () {
      // The backend's enum is ('opened', 'closed', 'paid', 'debt', 'deleted')
      // and `to_jsonb` sends that label verbatim; the client writes 'open' for
      // an order it created itself. Matching only one spelling hides every
      // bill that came off the feed — including this terminal's own, once its
      // create acks and the pull re-delivers it.
      openBill(billStatus: 'opened');

      expect(detail.liveOrderForTable('tb1')!['id'], 'o1');
      expect(detail.openOrders().map((o) => o['id']), ['o1']);
    });

    test('a paid or cancelled bill is not', () {
      openBill(id: 'paid-bill', billStatus: 'paid');
      openBill(id: 'comped', billStatus: 'opened');
      put('orders', {
        ...db.byId('orders', 'comped')!,
        'status': 'cancelled',
      });

      expect(detail.openOrders(), isEmpty);
      // Both remain reachable by id.
      expect(detail.liveOrderById('paid-bill'), isNotNull);
      expect(detail.liveOrderById('comped'), isNotNull);
    });
  });
}
