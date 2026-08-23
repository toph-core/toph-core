import 'dart:convert';

import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — archives as a local query.
///
/// The archives screen used to be the clearest case of the pattern this phase
/// exists to delete: an online-first fetch with a cache fallback, where only
/// the *default* view ("today", unfiltered, page 1) was mirrored locally.
/// Everything else — a date range, a bill-number search, page 2 — had no local
/// answer and went to the network, which is why `ArchivesBloc` carried an
/// `_isDefaultView` guard. Once the rows are in a table, filtering and paging
/// are just SQL, and none of that machinery has anything left to do: the guard
/// is gone and every view the screen offers is the same live query.
///
/// Three reads share one `WHERE` here, and they must: [page] is the rows,
/// its `total` is what tells the list whether to keep loading, and [summary]
/// is the header. A window that counts one set of bills and lists another is
/// how a paid check comes to be missing from a screen that claims to hold it.
///
/// The archives list is a projection, not a stored shape: `orders` holds the
/// bill, the table number and hall name come from joins, and the item count is
/// an aggregate over `order_items`. The REST endpoint assembled the same
/// projection server-side; this assembles it here, in the same key shape, so
/// `ArchivesResponseModel.fromJson` parses it unchanged.
class ArchivesQuery {
  final LocalDatabase _db;

  const ArchivesQuery(this._db);

  /// Tables whose changes invalidate a rendered page — the watch set.
  static const watchedTables = {
    'orders',
    'order_items',
    'cafe_tables',
    'halls',
  };

  /// The `WHERE` every read here shares, so the page, its total and the
  /// window's summary can never describe different sets of bills.
  ({String sql, List<Object?> params}) _where(
    ArchivesFilterRequestEntity filter,
  ) {
    // Reuse the request builder rather than re-deriving the filter semantics:
    // "Today" means the last 24 hours, "Week" the last 7 days, and so on. That
    // mapping already exists, was already what the server was asked for, and
    // must not fork into a second local copy that drifts.
    final req = filter.request();

    final where = <String>['o.deleted_at IS NULL'];
    final params = <Object?>[];

    // Prefix, not equality. The search box is a bill *number* field a cashier
    // types into while looking for a check, and typing the first digits of a
    // four-digit number matched nothing at all — indistinguishable, from
    // behind the counter, from the check having been deleted. `bill_no` is an
    // INTEGER column, so the cast is what lets `LIKE` see it as digits.
    final billNo = req['bill_no'];
    if (billNo != null) {
      where.add('CAST(o.bill_no AS TEXT) LIKE ?');
      params.add('$billNo%');
    }

    final billStatus = req['bill_status'];
    if (billStatus is String && billStatus.isNotEmpty) {
      where.add('o.bill_status = ?');
      params.add(billStatus);
    }

    // Compared as instants. Both sides are parsed by SQLite, which understands
    // every form this replica holds — `.000Z` from a local write, `+00:00` or
    // `+05:00` from `to_jsonb`, and a bare `YYYY-MM-DDTHH:MM:SS` — and reduces
    // each to the same epoch second.
    //
    // This used to compare the first 19 characters of the two strings, and
    // that is the bug that made a venue's own orders vanish from the Orders
    // tab. `to_jsonb` renders a `timestamptz` in the database session's
    // timezone, so on a server that is not running in UTC a bill paid at
    // 14:15 local arrives as `2026-08-23T14:15:00+05:00` while the window's
    // upper bound is built as UTC `2026-08-23T09:20:00.000Z`. Truncated to 19
    // characters those read as 14:15 and 09:20, so `paid_at <= end` is false
    // and the bill is excluded — every bill of the last five hours, dropped
    // from Today, Week, Month and Year alike.
    //
    // What made it look like deletion: the row a terminal writes itself
    // carries its own UTC `.000Z` stamp and displays correctly, and is only
    // replaced by the server's rendering when a pull delivers it. So the check
    // was on screen, and then a sync — a periodic tick, or the one a table
    // timer's pause/resume nudges 750 ms after it queues — swapped in a
    // timestamp the filter could no longer read, and it was gone. Nothing was
    // deleted anywhere; the same bill would reappear on its own once the clock
    // moved past the offset.
    final start = req['start'];
    if (start is String && start.isNotEmpty) {
      where.add('$_closedAtEpoch >= $_paramEpoch');
      params.add(start);
    }
    final end = req['end'];
    if (end is String && end.isNotEmpty) {
      where.add('$_closedAtEpoch <= $_paramEpoch');
      params.add(end);
    }

    return (sql: where.join(' AND '), params: params);
  }

  /// One page of archives, in `ArchivesResponseModel.fromJson`'s shape.
  Map<String, dynamic> page(ArchivesFilterRequestEntity filter) {
    final req = filter.request();
    final built = _where(filter);
    final whereSql = built.sql;
    final params = built.params;

    final countRows = _db.select(
      'SELECT COUNT(*) AS c FROM orders o WHERE $whereSql',
      params,
    );
    final total = (countRows.first['c'] as num?)?.toInt() ?? 0;

    final limit = _asInt(req['limit']) ?? 20;
    final offset = _asInt(req['offset']) ?? 0;

    final rows = _db.select(
      '''
      SELECT o.id          AS id,
             o.data        AS data,
             t.number      AS table_number,
             h.name        AS hall_name
        FROM orders o
        LEFT JOIN cafe_tables t ON t.id = o.table_id AND t.deleted_at IS NULL
        LEFT JOIN halls      h ON h.id = t.hall_id   AND h.deleted_at IS NULL
       WHERE $whereSql
       ORDER BY $_closedAtEpoch DESC, o.bill_no DESC
       LIMIT ? OFFSET ?
      ''',
      [...params, limit, offset],
    );

    final items = <Map<String, dynamic>>[];
    final ids = <String>[];
    for (final row in rows) {
      final decoded = _decode(row['data']);
      if (decoded == null) continue;
      final id = row['id'] as String? ?? decoded['id']?.toString() ?? '';
      ids.add(id);
      items.add({
        ...decoded,
        'id': id,
        // Joined, not stored: the server synthesised these too.
        'table_number': row['table_number'],
        'hall_name': row['hall_name'],
        // The list model reads the bill's open/close times under the names the
        // REST projection used, not the column names on `orders`.
        'opened_at': decoded['created_at'],
        'closed_at': decoded['paid_at'],
        'table_amount': decoded['table_charge'],
      });
    }

    final quantities = _quantitiesFor(ids);
    for (final item in items) {
      item['quantity'] = quantities[item['id']] ?? 0;
    }

    return {
      'items': items,
      'pagination': {'offset': offset, 'limit': limit, 'total': total},
    };
  }

  /// The same page, re-emitted whenever anything it reads from changes.
  Stream<Map<String, dynamic>> watch(ArchivesFilterRequestEntity filter) =>
      _db.watch(watchedTables, () => page(filter));

  /// Totals over the **whole** filtered window, not the loaded page.
  ///
  /// The header used to fold over whatever rows the list happened to be
  /// holding, which meant it agreed with the screen and disagreed with the
  /// database the moment the window held more bills than one page: a shift
  /// with 25 checks reported 20, and reported the revenue of 20. A count a
  /// cashier reconciles a till against cannot be a count of what fits on
  /// screen.
  ///
  /// `grand_total` and `table_charge` are not promoted columns, so they are
  /// read out of the row with `json_extract` — the access the registry
  /// prescribes for exactly this, and already how `transactions_query.dart`
  /// and `order_detail_query.dart` reach unpromoted fields. They are stored as
  /// canonical numeric strings (`PayloadNormalizer.numToCanonicalString`), so
  /// the CAST is what makes them summable.
  ///
  /// An open bill's persisted `grand_total` does not yet include the running
  /// table charge — that is only folded in at payment — so it is added back
  /// here, exactly as the row rendering does.
  Map<String, dynamic> summary(ArchivesFilterRequestEntity filter) {
    final built = _where(filter);
    final rows = _db.select('''
      SELECT COUNT(*) AS c,
             SUM(CASE WHEN $_isOpenBill THEN 1 ELSE 0 END) AS open_count,
             SUM(
               CAST(COALESCE(json_extract(o.data, '\$.grand_total'), 0) AS REAL)
               + CASE WHEN $_isOpenBill
                      THEN CAST(COALESCE(json_extract(o.data, '\$.table_charge'), 0) AS REAL)
                      ELSE 0 END
             ) AS revenue
        FROM orders o
       WHERE ${built.sql}
      ''', built.params);
    final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
    final count = (row['c'] as num?)?.toInt() ?? 0;
    final revenue = (row['revenue'] as num?)?.round() ?? 0;
    return {
      'count': count,
      'open_count': (row['open_count'] as num?)?.toInt() ?? 0,
      'revenue': revenue,
      'avg_check': count == 0 ? 0 : revenue ~/ count,
    };
  }

  /// The same summary, re-emitted whenever anything it reads from changes.
  Stream<Map<String, dynamic>> watchSummary(
    ArchivesFilterRequestEntity filter,
  ) => _db.watch(watchedTables, () => summary(filter));

  /// A bill that has not been settled yet. Both spellings, for the reason
  /// `OrderDetailQuery` accepts both: the backend enum is `opened` and the
  /// client has historically written `open`.
  static const _isOpenBill = "o.bill_status IN ('open', 'opened', 'pending')";

  /// Non-cancelled item count per order, for the page's orders only.
  ///
  /// Done as one extra query rather than a correlated subquery so the read
  /// needs nothing from SQLite's JSON1 extension — `quantity` is not a
  /// promoted column, so summing it in SQL would mean `json_extract`.
  Map<String, int> _quantitiesFor(List<String> orderIds) {
    if (orderIds.isEmpty) return const {};
    final placeholders = List.filled(orderIds.length, '?').join(',');
    final rows = _db.select(
      'SELECT order_id, data FROM order_items '
      'WHERE order_id IN ($placeholders) AND deleted_at IS NULL',
      orderIds,
    );
    final out = <String, int>{};
    for (final row in rows) {
      final orderId = row['order_id'] as String?;
      if (orderId == null) continue;
      final decoded = _decode(row['data']);
      if (decoded == null) continue;
      if (decoded['status'] == 'cancelled') continue;
      out[orderId] = (out[orderId] ?? 0) + (_asInt(decoded['quantity']) ?? 0);
    }
    return out;
  }

  /// A closed bill is ordered and filtered by when it closed; one that is
  /// still open falls back to when it opened, so it does not sort to the
  /// bottom of every list.
  static const _closedAt = 'COALESCE(o.paid_at, o.created_at)';

  /// [_closedAt] as an epoch second.
  ///
  /// Ordering needs this as much as filtering does: sorted as text, a row
  /// stamped `...T14:15:00+05:00` sorts above one stamped `...T09:20:00.000Z`
  /// even though it is the older of the two, so a list of bills from two
  /// sources comes out in an order that is neither chronological nor stable.
  static const _closedAtEpoch = "CAST(strftime('%s', $_closedAt) AS INTEGER)";

  /// The bound side of the same comparison.
  static const _paramEpoch = "CAST(strftime('%s', ?) AS INTEGER)";

  static Map<String, dynamic>? _decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
    return null;
  }
}
