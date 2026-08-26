/// Occupancy and table timers follow the bills the replica holds.
///
/// The regression these pin: five VIP tables that stayed ЗАНЯТ for two days
/// with their hourly timers still charging — one of them 54 hours and 2.7M
/// so'm in — on bills that had been settled on another terminal. `_table_status`
/// and `_table_timers` are local authority, nothing in the feed corrects them,
/// and the only code that ever cleared them was the payment screen of the
/// terminal that took the payment. Meanwhile `liveOrderForTable` correctly
/// refused to return a paid bill, so the order screen behind those tables was
/// empty with a 0 total and could not ring anything in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/db/table_occupancy_reconciler.dart';

void main() {
  late LocalDatabase db;
  late TableOccupancyReconciler reconciler;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(
      spec,
      data['id'] as String,
      PayloadNormalizer.normalize(spec, data),
    );
  }

  void order(
    String id,
    String tableId,
    String billStatus, {
    String? status,
    int deletedAt = 0,
    String createdAt = '2026-08-23T11:00:00Z',
  }) =>
      put('orders', {
        'id': id,
        'table_id': tableId,
        'bill_status': billStatus,
        'status': ?status,
        'branch_id': 'b1',
        'created_at': createdAt,
        'deleted_at': deletedAt,
      });

  void timer(String orderId, String tableId) => db.saveTableTimer(orderId, {
        'order_id': orderId,
        'table_id': tableId,
        'table_type': 'time_based',
        'state': 'running',
        'price_per_hour': '50000',
      });

  String? statusOf(String tableId) => db.tableStatuses()[tableId];

  setUp(() {
    db = LocalDatabase.open(':memory:');
    reconciler = TableOccupancyReconciler(db);
    put('halls', {'id': 'h1', 'name': 'VIP', 'branch_id': 'b1', 'deleted_at': 0});
    for (var n = 1; n <= 3; n++) {
      put('cafe_tables', {
        'id': 'tb$n',
        'hall_id': 'h1',
        'number': n,
        'table_type': 'time_based',
        'deleted_at': 0,
      });
    }
  });

  tearDown(() => db.dispose());

  group('a bill settled somewhere else', () {
    test('frees the table it was sitting on and drops its timer', () {
      // Exactly the observed state: the table was opened here (so the overlay
      // says busy and a timer record exists), and the paid row then arrived
      // from the pull.
      db.setTableStatus('tb1', 'busy');
      timer('ord-1', 'tb1');
      order('ord-1', 'tb1', 'paid', status: 'paid');

      reconciler.reconcileAll();

      expect(statusOf('tb1'), 'free');
      expect(db.getTableTimer('ord-1'), isNull);
    });

    test('a comped bill counts as settled even though bill_status stays open', () {
      // `/orders/{id}/cancel` sets status = 'cancelled' and leaves bill_status
      // at 'opened' — the server's own shape, and the one a NOT(...) predicate
      // built on bill_status alone would miss.
      db.setTableStatus('tb2', 'busy');
      timer('ord-2', 'tb2');
      order('ord-2', 'tb2', 'opened', status: 'cancelled');

      reconciler.reconcileAll();

      expect(statusOf('tb2'), 'free');
      expect(db.getTableTimer('ord-2'), isNull);
    });

    test('a NULL bill_status is settled, not silently skipped', () {
      // `bill_status IN (...)` is NULL — not false — for a NULL column, so
      // `NOT (live)` evaluates to NULL and drops the row. The predicate spells
      // the negation out for exactly this row.
      db.setTableStatus('tb1', 'busy');
      order('ord-null', 'tb1', '');

      reconciler.reconcileAll();

      expect(statusOf('tb1'), 'free');
    });
  });

  group('what it refuses to do', () {
    test('leaves a table with a live bill busy', () {
      db.setTableStatus('tb1', 'busy');
      timer('ord-live', 'tb1');
      order('ord-live', 'tb1', 'open');

      reconciler.reconcileAll();

      expect(statusOf('tb1'), 'busy');
      expect(db.getTableTimer('ord-live'), isNotNull);
    });

    test('keeps the newest bill when an older paid one shares the table', () {
      db.setTableStatus('tb1', 'busy');
      order('old', 'tb1', 'paid',
          status: 'paid', createdAt: '2026-08-23T08:00:00Z');
      order('new', 'tb1', 'open', createdAt: '2026-08-23T12:00:00Z');
      timer('new', 'tb1');

      reconciler.reconcileAll();

      // The settled bill is evidence, but a live one outranks it — otherwise
      // every table would free itself the moment it had any history.
      expect(statusOf('tb1'), 'busy');
      expect(db.getTableTimer('new'), isNotNull);
    });

    test('will not free a busy table it holds no bill for', () {
      // A table opened on another terminal whose order row has not replicated
      // yet looks exactly like this. Guessing here frees a table under a
      // waiter's hands.
      db.setTableStatus('tb3', 'busy');

      reconciler.reconcileAll();

      expect(statusOf('tb3'), 'busy');
    });
  });

  group('the busy direction', () {
    test('a live bill marks its table busy without a LAN broadcast', () {
      // The only way a remote open used to reach this terminal was a hub
      // message; a terminal with no LAN link never saw it.
      order('remote', 'tb2', 'opened');

      reconciler.reconcileAll();

      expect(statusOf('tb2'), 'busy');
    });
  });

  group('through ChangeApplier', () {
    test('a pull that pays the bill frees the table in the same batch', () {
      final applier = ChangeApplier(db);
      db.setTableStatus('tb1', 'busy');
      timer('ord-1', 'tb1');
      order('ord-1', 'tb1', 'open');

      applier.applyPullResponse({
        'next_sync_cursor': 7,
        'changes': {
          'orders': {
            'updated': [
              {
                'id': 'ord-1',
                'table_id': 'tb1',
                'bill_status': 'paid',
                'status': 'paid',
                'branch_id': 'b1',
                'created_at': '2026-08-23T11:00:00Z',
                'deleted_at': 0,
              },
            ],
          },
        },
      });

      expect(statusOf('tb1'), 'free');
      expect(db.getTableTimer('ord-1'), isNull);
    });

    test('a transfer frees the table the bill left', () {
      final applier = ChangeApplier(db);
      db.setTableStatus('tb1', 'busy');
      order('ord-1', 'tb1', 'open');
      order('ord-old', 'tb1', 'paid', status: 'paid');

      applier.applyOne(
        entity: 'orders',
        action: 'update',
        payload: {
          'id': 'ord-1',
          'table_id': 'tb2',
          'bill_status': 'open',
          'branch_id': 'b1',
          'created_at': '2026-08-23T11:00:00Z',
          'deleted_at': 0,
        },
      );

      // The source is reconsidered because the *stored* row named it, not the
      // incoming one — without that the bill walks away and leaves tb1 busy.
      expect(statusOf('tb1'), 'free');
      expect(statusOf('tb2'), 'busy');
    });

    test('a local write that closes the bill frees the table too', () {
      final applier = ChangeApplier(db);
      db.setTableStatus('tb1', 'busy');
      timer('ord-1', 'tb1');
      order('ord-1', 'tb1', 'open');

      // What PaymentRepositoryImpl.pay writes through LocalWriter.
      applier.applyLocalWrite(
        entity: 'orders',
        id: 'ord-1',
        payload: {
          'id': 'ord-1',
          'table_id': 'tb1',
          'bill_status': 'paid',
          'status': 'paid',
          'branch_id': 'b1',
          'created_at': '2026-08-23T11:00:00Z',
          'deleted_at': 0,
        },
      );

      expect(statusOf('tb1'), 'free');
      expect(db.getTableTimer('ord-1'), isNull);
    });

    test('creating an order locally marks its table busy', () {
      final applier = ChangeApplier(db);

      applier.applyLocalWrite(
        entity: 'orders',
        id: 'fresh',
        payload: {
          'id': 'fresh',
          'table_id': 'tb3',
          'bill_status': 'open',
          'status': 'open',
          'branch_id': 'b1',
          'created_at': '2026-08-23T11:00:00Z',
          'deleted_at': 0,
        },
      );

      expect(statusOf('tb3'), 'busy');
    });
  });
}
