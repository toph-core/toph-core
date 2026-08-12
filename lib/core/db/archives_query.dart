import 'dart:convert';

import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — archives as a local query.
///
/// The archives screen used to be the clearest case of the pattern this phase
/// exists to delete: an online-first fetch with a cache fallback, where only
/// the *default* view ("today", unfiltered, page 1) was mirrored locally.
/// Everything else — a date range, a bill-number search, page 2 — had no local
/// answer and went to the network, which is why `ArchivesBloc` carries an
/// `_isDefaultView` guard and the repository carries a separate
/// `getHydratedArchives` snapshot. Once the rows are in a table, filtering and
/// paging are just SQL and none of that machinery has anything left to do.
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

  /// One page of archives, in `ArchivesResponseModel.fromJson`'s shape.
  Map<String, dynamic> page(ArchivesFilterRequestEntity filter) {
    // Reuse the request builder rather than re-deriving the filter semantics:
    // "Today" means the last 24 hours, "Week" the last 7 days, and so on. That
    // mapping already exists, was already what the server was asked for, and
    // must not fork into a second local copy that drifts.
    final req = filter.request();

    final where = <String>['o.deleted_at IS NULL'];
    final params = <Object?>[];

    final billNo = req['bill_no'];
    if (billNo != null) {
      where.add('o.bill_no = ?');
      params.add(billNo is int ? billNo : int.tryParse('$billNo'));
    }

    final billStatus = req['bill_status'];
    if (billStatus is String && billStatus.isNotEmpty) {
      where.add('o.bill_status = ?');
      params.add(billStatus);
    }

    // Compared on the first 19 characters — `YYYY-MM-DDTHH:MM:SS`, the prefix
    // both sides always share. The stored value comes from `to_jsonb` and ends
    // in `+00:00`; the filter is built with `toIso8601String()` and ends in
    // `.000Z`. Both are UTC, but they are not lexicographically comparable in
    // full, so a naive `>=` would be wrong by a fraction of a second at each
    // boundary. Truncating to seconds makes the comparison exact.
    final start = req['start'];
    if (start is String && start.isNotEmpty) {
      where.add('substr($_closedAt, 1, 19) >= substr(?, 1, 19)');
      params.add(start);
    }
    final end = req['end'];
    if (end is String && end.isNotEmpty) {
      where.add('substr($_closedAt, 1, 19) <= substr(?, 1, 19)');
      params.add(end);
    }

    final whereSql = where.join(' AND ');

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
       ORDER BY $_closedAt DESC, o.bill_no DESC
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
