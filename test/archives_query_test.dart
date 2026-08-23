/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the archives list as a local
/// query.
///
/// These fix the projection contract: `ArchivesQuery.page` has to produce
/// exactly the map `ArchivesResponseModel.fromJson` used to receive from
/// `GET /api/v1/bills`, assembled from replicated rows instead. Money fixtures
/// are integral on purpose — `PayloadNormalizer.numToCanonicalString` renders
/// `295200.00` as `"295200"`, which is what the models' `parseInt` can read.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/archives_query.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_filter_request/archives_filter_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_response/archives_response_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';

void main() {
  late LocalDatabase db;
  late ArchivesQuery query;

  void put(String entity, Map<String, dynamic> data) =>
      db.upsert(kEntitiesByName[entity]!, data['id'] as String, data);

  Map<String, dynamic> order({
    required String id,
    int billNo = 1,
    String billStatus = 'closed',
    String? tableId = 't-1',
    String createdAt = '2026-08-10T09:00:00+00:00',
    String? paidAt = '2026-08-10T10:00:00+00:00',
    String grandTotal = '295200',
    String tableCharge = '0',
    int? deletedAt,
  }) => {
    'id': id,
    'bill_no': billNo,
    'bill_status': billStatus,
    'table_id': tableId,
    'branch_id': 'b-1',
    'created_at': createdAt,
    'paid_at': paidAt,
    'grand_total': grandTotal,
    'food_total': '246000',
    'service_amount': '49200',
    'discount_amount': '0',
    'customer_paid_amount': '300000',
    'table_charge': tableCharge,
    'deleted_at': deletedAt,
  };

  Map<String, dynamic> item({
    required String id,
    String orderId = 'o-1',
    int quantity = 1,
    String status = 'served',
  }) => {
    'id': id,
    'order_id': orderId,
    'good_id': 'g-1',
    'quantity': quantity,
    'price': '123000',
    'status': status,
  };

  ArchivesFilterRequestModel filter({
    ArchivesFilterType type = ArchivesFilterType.All,
    int? billNo,
    String? billStatus,
    DateTime? start,
    DateTime? end,
    int limit = 20,
    int offset = 0,
  }) => ArchivesFilterRequestModel(
    archiveNum: billNo,
    filterType: type,
    startDate: start,
    endDate: end,
    billStatus: billStatus,
    pagination: PaginationRequestModel(limit: limit, offset: offset),
  );

  setUp(() {
    db = LocalDatabase.open(':memory:');
    query = ArchivesQuery(db);
    put('halls', {'id': 'h-1', 'name': 'Asosiy zal', 'branch_id': 'b-1'});
    put('cafe_tables', {
      'id': 't-1',
      'hall_id': 'h-1',
      'number': 5,
      'status': 'free',
      'table_type': 'simple',
      'price_per_hour': '0',
    });
  });

  tearDown(() => db.dispose());

  group('ArchivesQuery — projection', () {
    test('joins table number and hall name onto the bill', () {
      put('orders', order(id: 'o-1', billNo: 101));

      final items = query.page(filter())['items'] as List;
      expect(items, hasLength(1));
      expect(items.first['table_number'], 5);
      expect(items.first['hall_name'], 'Asosiy zal');
      expect(items.first['bill_no'], 101);
    });

    test('renames order columns to the names the list model reads', () {
      put('orders', order(id: 'o-1', tableCharge: '150000'));

      final row =
          (query.page(filter())['items'] as List).first as Map<String, dynamic>;
      expect(row['opened_at'], '2026-08-10T09:00:00+00:00');
      expect(row['closed_at'], '2026-08-10T10:00:00+00:00');
      expect(row['table_amount'], '150000');
    });

    test('sums non-cancelled item quantities', () {
      put('orders', order(id: 'o-1'));
      put('order_items', item(id: 'i-1', quantity: 2));
      put('order_items', item(id: 'i-2', quantity: 3));
      put('order_items', item(id: 'i-3', quantity: 9, status: 'cancelled'));

      final row = (query.page(filter())['items'] as List).first;
      expect(row['quantity'], 5);
    });

    test('a bill with no items reports zero, not null', () {
      put('orders', order(id: 'o-1'));
      expect((query.page(filter())['items'] as List).first['quantity'], 0);
    });

    test('a takeaway bill with no table survives the join', () {
      put('orders', order(id: 'o-1', tableId: null));

      final row = (query.page(filter())['items'] as List).first;
      expect(row['table_number'], isNull);
      expect(row['hall_name'], isNull);
    });

    test('parses into ArchivesResponseModel unchanged', () {
      put('orders', order(id: 'o-1', billNo: 77));
      put('order_items', item(id: 'i-1', quantity: 4));

      final parsed = ArchivesResponseModel.fromJson(query.page(filter()));
      expect(parsed.archives, hasLength(1));
      final archive = parsed.archives.first;
      expect(archive.id, 'o-1');
      expect(archive.bilNumber, 77);
      expect(archive.tableNumber, 5);
      expect(archive.hallName, 'Asosiy zal');
      expect(archive.totalPrice, 295200);
      expect(archive.goodsQuantity, 4);
      expect(parsed.pagination.total, 1);
    });
  });

  group('ArchivesQuery — filtering', () {
    test('excludes soft-deleted bills', () {
      put('orders', order(id: 'o-1'));
      put('orders', order(id: 'o-2', deletedAt: 1760000000));

      final items = query.page(filter())['items'] as List;
      expect(items.map((e) => e['id']), ['o-1']);
    });

    test('filters by bill status', () {
      put('orders', order(id: 'o-1', billStatus: 'closed'));
      put('orders', order(id: 'o-2', billStatus: 'debt'));

      final page = query.page(filter(billStatus: 'debt'));
      expect((page['items'] as List).map((e) => e['id']), ['o-2']);
      expect((page['pagination'] as Map)['total'], 1);
    });

    test('finds one bill by number', () {
      put('orders', order(id: 'o-1', billNo: 11));
      put('orders', order(id: 'o-2', billNo: 12));

      final items = query.page(filter(billNo: 12))['items'] as List;
      expect(items.map((e) => e['id']), ['o-2']);
    });

    test('an explicit date range bounds on the closing time', () {
      put('orders', order(id: 'old', paidAt: '2026-08-01T10:00:00+00:00'));
      put('orders', order(id: 'mid', paidAt: '2026-08-10T10:00:00+00:00'));
      put('orders', order(id: 'new', paidAt: '2026-08-20T10:00:00+00:00'));

      final items =
          query.page(
                filter(
                  type: ArchivesFilterType.date,
                  start: DateTime.utc(2026, 8, 5),
                  end: DateTime.utc(2026, 8, 15),
                ),
              )['items']
              as List;
      expect(items.map((e) => e['id']), ['mid']);
    });

    test('"today" keeps the last 24 hours and drops what precedes it', () {
      final now = DateTime.now().toUtc();
      final recent = now.subtract(const Duration(hours: 2));
      final stale = now.subtract(const Duration(days: 3));
      put('orders', order(id: 'recent', paidAt: recent.toIso8601String()));
      put('orders', order(id: 'stale', paidAt: stale.toIso8601String()));

      final items =
          query.page(filter(type: ArchivesFilterType.Today))['items'] as List;
      expect(items.map((e) => e['id']), ['recent']);
    });

    test('an open bill falls back to its opening time for range and order', () {
      put(
        'orders',
        order(
          id: 'open-bill',
          billStatus: 'open',
          paidAt: null,
          createdAt: '2026-08-10T08:00:00+00:00',
        ),
      );

      final items =
          query.page(
                filter(
                  type: ArchivesFilterType.date,
                  start: DateTime.utc(2026, 8, 9),
                  end: DateTime.utc(2026, 8, 11),
                ),
              )['items']
              as List;
      expect(items.map((e) => e['id']), ['open-bill']);
    });
  });

  group('ArchivesQuery — timestamps are instants, not strings', () {
    // `to_jsonb` renders a `timestamptz` in the database session's timezone.
    // A backend not running in UTC therefore feeds the replica offsets like
    // `+05:00`, and the window has to read those as the instants they are.
    String atOffset(DateTime utc, int offsetHours) {
      final shifted = utc.add(Duration(hours: offsetHours));
      final sign = offsetHours < 0 ? '-' : '+';
      final hh = offsetHours.abs().toString().padLeft(2, '0');
      return '${shifted.toIso8601String().split('.').first}$sign$hh:00';
    }

    test('a bill just paid stays in Today when the server renders +05:00', () {
      final paidAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      put(
        'orders',
        order(
          id: 'o-1',
          billNo: 1,
          createdAt: atOffset(paidAt.subtract(const Duration(hours: 1)), 5),
          paidAt: atOffset(paidAt, 5),
        ),
      );

      // The regression: compared as text prefixes, "…T14:15:00" reads as later
      // than the UTC upper bound "…T09:20:00" and the bill is excluded — five
      // hours of a venue's own orders gone from the tab that lists them.
      final items =
          query.page(filter(type: ArchivesFilterType.Today))['items'] as List;
      expect(items.map((e) => e['id']), ['o-1']);
      expect(query.summary(filter(type: ArchivesFilterType.Today))['count'], 1);
    });

    test('the same bill in Z form and in +05:00 form are one instant', () {
      final paidAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      // What a terminal writes for itself, and what the feed later replaces it
      // with. Both must survive the window identically — the swap between them
      // is what a sync performs, and used to be what made the bill disappear.
      put(
        'orders',
        order(
          id: 'local',
          billNo: 1,
          createdAt: paidAt.toIso8601String(),
          paidAt: paidAt.toIso8601String(),
        ),
      );
      put(
        'orders',
        order(
          id: 'feed',
          billNo: 2,
          createdAt: atOffset(paidAt, 5),
          paidAt: atOffset(paidAt, 5),
        ),
      );

      final items =
          query.page(filter(type: ArchivesFilterType.Today))['items'] as List;
      expect(items.map((e) => e['id']).toSet(), {'local', 'feed'});
    });

    test('a bill genuinely outside the window is still excluded', () {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 3));
      put(
        'orders',
        order(
          id: 'o-old',
          billNo: 1,
          createdAt: atOffset(old, 5),
          paidAt: atOffset(old, 5),
        ),
      );

      expect(
        (query.page(filter(type: ArchivesFilterType.Today))['items'] as List),
        isEmpty,
      );
      // ...and reachable without a date filter, which is what "All" is for.
      expect((query.page(filter())['items'] as List).map((e) => e['id']), [
        'o-old',
      ]);
    });

    test('bills from both sources sort chronologically, not lexically', () {
      final now = DateTime.now().toUtc();
      final newer = now.subtract(const Duration(minutes: 5));
      final older = now.subtract(const Duration(minutes: 30));
      // The older bill carries the offset form, whose text sorts *above* the
      // newer bill's Z form. Ordered as text the list comes out backwards.
      put(
        'orders',
        order(
          id: 'older-offset',
          billNo: 1,
          createdAt: atOffset(older, 5),
          paidAt: atOffset(older, 5),
        ),
      );
      put(
        'orders',
        order(
          id: 'newer-utc',
          billNo: 2,
          createdAt: newer.toIso8601String(),
          paidAt: newer.toIso8601String(),
        ),
      );

      final items = query.page(filter())['items'] as List;
      expect(items.map((e) => e['id']), ['newer-utc', 'older-offset']);
    });
  });

  group('ArchivesQuery — window summary', () {
    test('counts and sums the whole window, not one page', () {
      for (var i = 0; i < 25; i++) {
        put('orders', order(id: 'o-$i', billNo: 100 + i, grandTotal: '400000'));
      }

      // The page is capped, deliberately — the summary is not.
      expect((query.page(filter(limit: 20))['items'] as List), hasLength(20));

      final summary = query.summary(filter(limit: 20));
      expect(summary['count'], 25);
      expect(summary['revenue'], 25 * 400000);
      expect(summary['avg_check'], 400000);
      expect(summary['open_count'], 0);
    });

    test('an open bill contributes its running table charge', () {
      put(
        'orders',
        order(
          id: 'o-open',
          billNo: 1,
          billStatus: 'opened',
          paidAt: null,
          grandTotal: '100000',
          tableCharge: '25000',
        ),
      );
      put('orders', order(id: 'o-paid', billNo: 2, grandTotal: '100000'));

      final summary = query.summary(filter());
      expect(summary['open_count'], 1);
      // The open bill bills 125 000 on screen, the closed one 100 000 — the
      // header has to agree with the rows it sits above.
      expect(summary['revenue'], 225000);
    });

    test('respects the same filters the page does', () {
      put('orders', order(id: 'o-1', billNo: 1, grandTotal: '100000'));
      put('orders', order(id: 'o-2', billNo: 2, grandTotal: '300000'));

      final summary = query.summary(filter(billNo: 2));
      expect(summary['count'], 1);
      expect(summary['revenue'], 300000);
    });

    test('an empty window is zero, not a division by zero', () {
      final summary = query.summary(filter(billNo: 999));
      expect(summary['count'], 0);
      expect(summary['revenue'], 0);
      expect(summary['avg_check'], 0);
    });
  });

  group('ArchivesQuery — bill-number search', () {
    test('finds a bill by the first digits of its number', () {
      put('orders', order(id: 'o-1', billNo: 1247));
      put('orders', order(id: 'o-2', billNo: 990));

      final items = query.page(filter(billNo: 12))['items'] as List;
      expect(items.map((e) => e['id']), ['o-1']);
    });

    test('an exact number still matches exactly one bill', () {
      put('orders', order(id: 'o-1', billNo: 124));
      put('orders', order(id: 'o-2', billNo: 125));

      final items = query.page(filter(billNo: 124))['items'] as List;
      expect(items.map((e) => e['id']), ['o-1']);
    });

    test('a number nothing starts with finds nothing', () {
      put('orders', order(id: 'o-1', billNo: 124));

      expect((query.page(filter(billNo: 7))['items'] as List), isEmpty);
    });
  });

  group('ArchivesQuery — ordering and paging', () {
    setUp(() {
      for (var i = 1; i <= 5; i++) {
        put(
          'orders',
          order(id: 'o-$i', billNo: i, paidAt: '2026-08-0${i}T10:00:00+00:00'),
        );
      }
    });

    test('newest closed bill first', () {
      final items = query.page(filter())['items'] as List;
      expect(items.map((e) => e['id']), ['o-5', 'o-4', 'o-3', 'o-2', 'o-1']);
    });

    test('limit and offset page through, total counts the whole match', () {
      final page = query.page(filter(limit: 2, offset: 2));
      expect((page['items'] as List).map((e) => e['id']), ['o-3', 'o-2']);
      final pagination = page['pagination'] as Map;
      expect(pagination['total'], 5);
      expect(pagination['limit'], 2);
      expect(pagination['offset'], 2);
    });

    test('an offset past the end is empty, not an error', () {
      final page = query.page(filter(limit: 20, offset: 99));
      expect(page['items'], isEmpty);
      expect((page['pagination'] as Map)['total'], 5);
    });

    test('total reflects the filter, not the table', () {
      put('orders', order(id: 'debt-1', billNo: 9, billStatus: 'debt'));
      expect(
        (query.page(filter(billStatus: 'debt'))['pagination'] as Map)['total'],
        1,
      );
    });
  });

  group('ArchivesQuery — reactivity', () {
    test('re-emits when a replicated order lands', () async {
      final seen = <int>[];
      final sub = query
          .watch(filter())
          .listen((page) => seen.add((page['items'] as List).length));

      await Future<void>.delayed(Duration.zero);
      put('orders', order(id: 'o-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();
      expect(seen.first, 0, reason: 'first frame renders immediately');
      expect(seen.last, 1, reason: 'and again once the row arrives');
    });

    test(
      're-emits when an item changes the count on a rendered bill',
      () async {
        put('orders', order(id: 'o-1'));
        final seen = <Object?>[];
        final sub = query
            .watch(filter())
            .listen(
              (page) => seen.add((page['items'] as List).first['quantity']),
            );

        await Future<void>.delayed(Duration.zero);
        put('order_items', item(id: 'i-1', quantity: 7));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await sub.cancel();
        expect(seen.first, 0);
        expect(seen.last, 7);
      },
    );
  });
}
