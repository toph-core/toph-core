/// The client half of `GET /api/v1/sync/snapshot` — current rows per entity,
/// plus the cursor to resume `/sync/pull` from.
///
/// The change feed alone cannot always bring a replica back into agreement
/// with the server, and this is the endpoint the backend built for the cases
/// where it cannot:
///
/// * The server says so. `POST /sync/pull` returns `snapshot_required` when the
///   requested cursor sits below the oldest surviving `change_log` row —
///   retention has compacted away the changes this terminal missed, and no
///   number of pulls will produce them (`73_change_log_retention.up.sql`).
/// * A row was refused on the way in. `ChangeApplier` skips an incoming row
///   whose local copy has an unsynced local edit, and the cursor advances past
///   it anyway. That is right for the common case — the terminal's own write is
///   about to replace it — and wrong when the refused row was a *delete*: the
///   `change_log` never repeats itself, so the row stays on this terminal
///   forever. That is the "the hall has 9 tables and the POS shows 16" report.
///
/// Both cases need the same thing: what the server currently holds, so the
/// replica can be reconciled against it rather than patched forward.
///
/// Paging is the server's, echoed back verbatim: `snapshot_cursor` from the
/// first page pins the `change_log` position the whole walk is consistent with,
/// and `next` carries the (entity, after_id) keyset coordinate. Nothing here
/// invents a coordinate of its own — a page served against a different cursor
/// is exactly how a change goes missing.
library;

import 'package:mary_ai_pos/core/api/dio_client.dart';

/// Where a snapshot walk resumes.
class SnapshotCoordinate {
  final String entity;
  final String afterId;

  const SnapshotCoordinate({required this.entity, required this.afterId});
}

/// One page of a snapshot.
class SnapshotPage {
  /// The `change_log` id this snapshot is consistent with. Becomes the
  /// terminal's cursor once the walk finishes.
  final int snapshotCursor;

  /// Every replicated entity, in the order the walk visits them. Sent on the
  /// first page only, empty afterwards.
  final List<String> entities;

  /// This page's rows, keyed by entity, shaped exactly like a pull response's
  /// `created` payloads — so they go through the same apply path.
  final Map<String, List<Map<String, dynamic>>> rows;

  /// Rows in this page, across entities.
  final int count;

  /// Where to resume, or null when [done].
  final SnapshotCoordinate? next;

  /// Whether the walk has visited every entity.
  final bool done;

  const SnapshotPage({
    required this.snapshotCursor,
    required this.entities,
    required this.rows,
    required this.count,
    required this.next,
    required this.done,
  });
}

/// The seam the repair loop depends on, so it can be driven without a socket.
abstract class SnapshotApi {
  Future<SnapshotPage> fetch({
    int? cursor,
    String? entity,
    String? afterId,
    int limit,
  });
}

class SnapshotApiClient implements SnapshotApi {
  final DioClient _client;

  const SnapshotApiClient(this._client);

  static const path = '/api/v1/sync/snapshot';

  /// The server clamps to 2000; 500 keeps one page's decode off the frame
  /// budget, which matters because this runs while the terminal is in use.
  static const pageSize = 500;

  @override
  Future<SnapshotPage> fetch({
    int? cursor,
    String? entity,
    String? afterId,
    int limit = pageSize,
  }) async {
    final response = await _client.get(
      path,
      queryParameters: {
        if (cursor != null && cursor > 0) 'cursor': cursor,
        if (entity != null && entity.isNotEmpty) 'entity': entity,
        if (afterId != null && afterId.isNotEmpty) 'after_id': afterId,
        'limit': limit,
      },
    );

    final envelope = response.data;
    final data = envelope is Map ? envelope['data'] : null;
    if (data is! Map) {
      throw StateError('sync/snapshot: unexpected response shape: $envelope');
    }

    final rawRows = data['rows'];
    final rows = <String, List<Map<String, dynamic>>>{};
    if (rawRows is Map) {
      for (final entry in rawRows.entries) {
        final list = entry.value;
        if (list is! List) continue;
        rows[entry.key.toString()] = [
          for (final row in list)
            if (row is Map) Map<String, dynamic>.from(row),
        ];
      }
    }

    final rawNext = data['next'];
    final next = rawNext is Map
        ? SnapshotCoordinate(
            entity: rawNext['entity']?.toString() ?? '',
            afterId: rawNext['after_id']?.toString() ?? '',
          )
        : null;

    final rawEntities = data['entities'];

    return SnapshotPage(
      snapshotCursor: (data['snapshot_cursor'] as num?)?.toInt() ?? 0,
      entities: rawEntities is List
          ? [for (final e in rawEntities) e.toString()]
          : const [],
      rows: rows,
      count: (data['count'] as num?)?.toInt() ?? 0,
      // A page with no `next` is finished whether or not the flag says so;
      // trusting only the flag would loop on a server that omits it.
      next: next != null && next.entity.isNotEmpty ? next : null,
      done: data['done'] == true || next == null || next.entity.isEmpty,
    );
  }
}
