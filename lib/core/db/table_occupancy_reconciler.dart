import 'entity_registry.dart';
import 'local_database.dart';
import 'order_detail_query.dart';

/// Keeps the two local-authority overlays honest about the bills the replica
/// actually holds: occupancy (`_table_status`) and the per-order table timer
/// (`_table_timers`).
///
/// ## The failure this exists to make impossible
///
/// Both overlays are local authority on purpose — a cashier opening a table
/// must see it busy with the uplink down, and the server's `cafe_tables.status`
/// lags or, offline, never moves at all. Neither is replicated, so nothing in
/// the feed can correct them. What nobody wired up is the other half of that
/// deal: they were only ever *cleared* by the terminal that took the payment
/// (`PaymentBloc._onPaymentSuccess`, `WaiterLocalRepositoryImpl.closeOrder`).
///
/// Settle the same bill anywhere else — another terminal, the back office, a
/// night this terminal was switched off — and the paid `orders` row arrives on
/// the feed while these two overlays go on saying "busy, timer running". The
/// operator gets a table card that is occupied and still charging by the hour,
/// forever, on top of an order screen that is empty: `liveOrderForTable`
/// correctly refuses to hand back a settled bill, so there are no items, the
/// total is 0, and ringing anything in fails with "Buyurtma ID topilmadi".
/// Observed on five VIP tables at once, one of them 54 hours and 2.7M so'm into
/// a bill that had been paid two days earlier.
///
/// ## The rule
///
/// Occupancy follows the bills, both directions, and only ever on evidence the
/// replica actually holds:
///
///  * a table with a **live** bill is busy. This is also how a bill opened on
///    another terminal reaches a floor with no LAN link to it — until now only
///    a hub broadcast could do that, so a lone terminal never saw remote opens.
///  * a table with **no live bill but at least one settled or voided one** is
///    free. The settled bill is the evidence: a table whose remote order simply
///    has not replicated yet has no settled bill either, so it is left exactly
///    as the operator last set it rather than freed under a waiter's hands.
///  * a timer whose order is no longer live is dropped, whatever its table went
///    on to do — including one left behind by a transfer.
///
/// Never on a guess. A table the replica holds no orders for at all keeps
/// whatever this terminal last said about it.
///
/// ## Where it runs
///
/// After every apply — pull batch, LAN peer row, and this terminal's own local
/// writes ([ChangeApplier]) — and once over the whole floor at startup, which
/// is what heals a terminal that was off while the venue closed its bills.
/// Deriving it in one place is the point: the payment screen still broadcasts
/// `free` over the LAN for immediacy, but correctness no longer depends on any
/// screen remembering to.
class TableOccupancyReconciler {
  static const _busy = 'busy';
  static const _free = 'free';

  final LocalDatabase _db;
  late final OrderDetailQuery _orders = OrderDetailQuery(_db);

  TableOccupancyReconciler(this._db);

  /// The negation of [OrderDetailQuery.liveBill], spelled out rather than
  /// wrapped in `NOT (...)`.
  ///
  /// `bill_status IN ('open', 'opened')` is NULL — not false — for a row whose
  /// `bill_status` is NULL, and `NOT NULL` is NULL, so the wrapped form would
  /// silently skip exactly the malformed rows this most needs to catch.
  static String _notLive(String o) => '($o.deleted_at IS NOT NULL '
      "OR COALESCE($o.bill_status, '') NOT IN ('open', 'opened') "
      "OR $o.status = 'cancelled')";

  /// Reconciles [tableIds] — the tables whose orders an apply just touched.
  ///
  /// Returns how many occupancy rows changed, for the callers that log it.
  int reconcileTables(Iterable<String> tableIds) {
    final ids = {
      for (final id in tableIds)
        if (id.isNotEmpty) id,
    };
    if (ids.isEmpty) return 0;

    return _db.transaction(() {
      final status = _db.tableStatuses();
      var changed = 0;
      for (final tableId in ids) {
        final current = status[tableId];
        if (_orders.liveOrderForTable(tableId) != null) {
          if (current == _busy) continue;
          _db.setTableStatus(tableId, _busy);
          changed++;
          continue;
        }
        if (current == _free) continue;
        // No live bill *and* nothing settled here: this replica knows nothing
        // about the table, so it has no standing to overrule the operator.
        if (!_hasSettledOrder(tableId)) continue;
        _db.setTableStatus(tableId, _free);
        changed++;
      }
      changed += evictSettledTimers();
      return changed;
    });
  }

  /// One pass over the whole floor: every table this terminal has an opinion
  /// about, plus every table the replica holds an order for.
  ///
  /// The second half is what makes a cold start correct. A terminal that
  /// bootstraps into a venue mid-service has no occupancy rows at all, and the
  /// replicated `status` column is whatever the server last logged; the open
  /// bills it just pulled are the better answer, and this is where they are
  /// applied.
  int reconcileAll() => _db.transaction(
        () => reconcileTables({
          ..._db.tableStatuses().keys,
          ..._tablesWithOrders(),
        }),
      );

  /// Drops every timer record whose order the replica says is settled.
  ///
  /// Deliberately global rather than per-table, and deliberately a select
  /// before the deletes: a timer left behind by a transfer belongs to a table
  /// nobody is reconciling, and issuing a DELETE per settled order would wake
  /// every timer watcher on every pull for rows that are not there.
  ///
  /// An unsent local start/pause for such an order is dropped with it. That is
  /// the right trade: the bill it belonged to is closed, so the transition has
  /// nothing left to bill.
  int evictSettledTimers() {
    final rows = _db.select(
      'SELECT t.order_id AS order_id FROM ${LocalTables.tableTimers} t '
      'JOIN orders o ON o.id = t.order_id '
      'WHERE ${_notLive('o')}',
    );
    var evicted = 0;
    for (final row in rows) {
      final orderId = row['order_id'] as String?;
      if (orderId == null || orderId.isEmpty) continue;
      _db.evictTableTimer(orderId);
      evicted++;
    }
    return evicted;
  }

  bool _hasSettledOrder(String tableId) => _db
      .select(
        'SELECT o.id AS id FROM orders o '
        'WHERE o.table_id = ? AND ${_notLive('o')} LIMIT 1',
        [tableId],
      )
      .isNotEmpty;

  Iterable<String> _tablesWithOrders() => _db
      .select(
        "SELECT DISTINCT table_id AS table_id FROM orders "
        "WHERE table_id IS NOT NULL AND table_id <> ''",
      )
      .map((row) => row['table_id'] as String? ?? '');
}
