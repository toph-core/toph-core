/// The bug that made paid checks vanish from the Orders tab.
///
/// `saveOrderDetailSnapshot` is handed an `ArchiveDetailModel` — the REST bill
/// *projection*, with `opened_at`/`closed_at`/`table_amount` and no
/// `created_at`, `paid_at`, `status` or `branch_id`. It wrote that map as the
/// whole `orders` row, and a replicated row is one JSON blob replaced
/// wholesale, so both timestamp columns were blanked. `ArchivesQuery` filters
/// and orders on `COALESCE(paid_at, created_at)`, so the bill then matched no
/// date window at all — invisible in Today, Week, Month, Year and any picked
/// range, visible only under "All", and untouched on the server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/archives_query.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_filter_request/archives_filter_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';

void main() {
  late LocalDatabase db;
  late ChangeApplier applier;
  late ArchivesQuery archives;

  String pgTs(DateTime t) =>
      '${t.toUtc().toIso8601String().split('.').first}+00:00';

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(
      spec,
      data['id'] as String,
      PayloadNormalizer.normalize(spec, data),
    );
  }

  /// The projection shape the snapshot callers hand in, as observed on a real
  /// terminal: local time, no offset, and none of the row's own columns.
  Map<String, dynamic> projection({
    required String id,
    required DateTime openedLocal,
    String billStatus = 'opened',
  }) => {
    'id': id,
    'bill_no': 1,
    'bill_status': billStatus,
    'table_id': 'tb1',
    'guest_count': 2,
    'opened_at': openedLocal.toIso8601String(),
    'closed_at': null,
    'table_amount': 277.78,
    'table_number': 5,
    'hall_name': 'Asosiy zal',
    'cashier_name': 'Javohir',
    'grand_total': 400000,
  };

  List<int> billsInToday() =>
      ((archives.page(
                    const ArchivesFilterRequestModel(
                      filterType: ArchivesFilterType.Today,
                      pagination: PaginationRequestModel(limit: 50),
                    ),
                  )['items']
                  as List)
              .map((e) => e['bill_no'] as int))
          .toList();

  setUp(() {
    db = LocalDatabase.open(':memory:');
    applier = ChangeApplier(db);
    archives = ArchivesQuery(db);
    put('halls', {'id': 'h1', 'name': 'Asosiy zal', 'deleted_at': 0});
    put('cafe_tables', {
      'id': 'tb1',
      'hall_id': 'h1',
      'number': 5,
      'deleted_at': 0,
    });
  });

  tearDown(() => db.dispose());

  test('a snapshot must not blank the timestamps the feed delivered', () {
    final createdAt = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    // The authoritative row, as a pull delivers it.
    put('orders', {
      'id': 'o1',
      'table_id': 'tb1',
      'branch_id': 'b1',
      'bill_no': 1,
      'bill_status': 'paid',
      'status': 'paid',
      'created_at': pgTs(createdAt),
      'paid_at': pgTs(createdAt.add(const Duration(hours: 1))),
      'grand_total': 400000,
      'deleted_at': 0,
    });
    expect(billsInToday(), [1]);

    // Re-entering the order screen writes the projection over it.
    final row = db.byId('orders', 'o1')!;
    final merged = <String, dynamic>{
      ...row,
      ...projection(id: 'o1', openedLocal: DateTime.now(), billStatus: 'paid'),
    };
    merged['created_at'] = row['created_at'];
    merged['paid_at'] = row['paid_at'];
    applier.applyOne(entity: 'orders', action: 'update', payload: merged);

    expect(billsInToday(), [1], reason: 'the bill must not leave the window');
    expect(db.byId('orders', 'o1')!['paid_at'], isNotNull);
    expect(
      db.byId('orders', 'o1')!['branch_id'],
      'b1',
      reason: 'the projection must not erase columns it does not carry',
    );
  });

  test('a projection-only bill lands with a usable UTC timestamp', () {
    // No feed row yet — a timed order created on this terminal. The projection
    // stamps device-local time with no offset; stored verbatim SQLite reads it
    // as UTC, which in a UTC+5 venue puts the bill hours into the future and
    // straight back out of the window.
    final openedLocal = DateTime.now();
    final p = projection(id: 'o2', openedLocal: openedLocal);
    applier.applyOne(
      entity: 'orders',
      action: 'update',
      payload: {
        ...p,
        'created_at': DateTime.parse(
          p['opened_at'] as String,
        ).toUtc().toIso8601String(),
      }..removeWhere((k, _) => k == 'opened_at'),
    );

    expect(billsInToday(), [1], reason: 'a bill opened now is in Today');
  });

  test('schema v5 repairs rows an older build already blanked', () {
    // Exactly what a terminal that ran the old build holds: projection shape,
    // no created_at, local-time opened_at left behind in `data`.
    final openedLocal = DateTime.now();
    db.upsert(
      kEntitiesByName['orders']!,
      'o3',
      projection(id: 'o3', openedLocal: openedLocal, billStatus: 'paid'),
    );
    expect(
      db.select('SELECT created_at FROM orders').first['created_at'],
      isNull,
    );
    expect(billsInToday(), isEmpty, reason: 'this is the reported symptom');

    // What reopening the database on the new build does.
    db.repairBlankedOrderTimestamps();

    expect(billsInToday(), [1], reason: 'the bill is back in its window');
  });
}
