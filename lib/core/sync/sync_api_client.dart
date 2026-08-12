/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — the replication protocol client.
///
/// The only code in the app that speaks to `/api/v1/sync/*`. Everything that
/// enters the local replica from the cloud comes through [pull]; Phase 2's
/// outbox drain will use [push] for the three entities the backend accepts.
///
/// This class does no storage and no decision-making: it performs one HTTP
/// round trip and hands back a decoded page. [ReplicationService] owns the loop
/// and [ChangeApplier] owns the writes, so a network failure here can never
/// leave the database half-updated.
library;

import 'package:mary_ai_pos/core/api/dio_client.dart';

/// One page of the change feed.
class SyncPullPage {
  /// The cursor to send on the next request. Equal to the requested cursor when
  /// the server had nothing new.
  final int nextCursor;

  /// The `data` object of the response, in exactly the shape
  /// [ChangeApplier.applyPullResponse] expects — `{next_sync_cursor, changes}`.
  /// Passed through undecomposed so there is one parser, not two.
  final Map<String, dynamic> body;

  /// Total rows across every entity and action in this page. A page smaller
  /// than the requested limit means the client has caught up.
  final int rowCount;

  const SyncPullPage({
    required this.nextCursor,
    required this.body,
    required this.rowCount,
  });

  static const empty = SyncPullPage(
    nextCursor: 0,
    body: {'next_sync_cursor': 0, 'changes': <String, dynamic>{}},
    rowCount: 0,
  );
}

/// The seam between "where changes come from" and "what we do with them".
///
/// [ReplicationService] depends on this, not on [SyncApiClient], for two
/// reasons. It makes the loop testable without a socket — and in Phase 5 a
/// follower's source becomes the leader's LAN relay rather than the cloud,
/// which is then a new implementation of this interface and *no change at all*
/// to the replication loop or the apply path.
abstract class SyncApi {
  Future<SyncPullPage> pull({required int cursor, int limit});
}

class SyncApiClient implements SyncApi {
  final DioClient _client;

  const SyncApiClient(this._client);

  /// Server-side maximum (`maxSyncBatchSize` in `service/sync.go`). Asking for
  /// more is silently clamped, so this is both our page size and the ceiling.
  static const batchSize = 500;

  static const pullPath = '/api/v1/sync/pull';
  static const pushPath = '/api/v1/sync/push';

  /// Fetches changes after [cursor].
  ///
  /// Throws on transport or protocol failure — the caller decides whether that
  /// means "retry later" (it always does) or "surface to the user" (it never
  /// does, except during first-login bootstrap).
  @override
  Future<SyncPullPage> pull({
    required int cursor,
    int limit = batchSize,
  }) async {
    final response = await _client.post(
      pullPath,
      data: {'last_sync_cursor': cursor, 'limit': limit},
    );

    // Handlers wrap every payload as {status, message, data, code}
    // (`model.NewSuccessResponse`), so the page we want is one level in.
    final envelope = response.data;
    final data = envelope is Map ? envelope['data'] : null;
    if (data is! Map) {
      throw StateError('sync/pull: unexpected response shape: $envelope');
    }

    final body = Map<String, dynamic>.from(data);
    final next = body['next_sync_cursor'];
    return SyncPullPage(
      // A missing cursor is treated as "no advance" rather than zero, which
      // would rewind the client to the start of history.
      nextCursor: next is num ? next.toInt() : cursor,
      body: body,
      rowCount: countRows(body['changes']),
    );
  }

  /// Counts rows across the `changes` map, for the caught-up check.
  ///
  /// Public and static so [ReplicationService] and its tests can reason about
  /// page fullness without reaching into a response.
  static int countRows(Object? changes) {
    if (changes is! Map) return 0;
    var total = 0;
    for (final entry in changes.values) {
      if (entry is! Map) continue;
      for (final key in const ['created', 'updated', 'deleted']) {
        final list = entry[key];
        if (list is List) total += list.length;
      }
    }
    return total;
  }
}
