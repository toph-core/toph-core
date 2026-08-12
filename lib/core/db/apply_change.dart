/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 0 — the one inbound write path.
///
/// Everything that enters the local replica from outside this terminal goes
/// through [ChangeApplier]: the cloud pull today, and in Phase 5 the leader's
/// LAN relay, which carries the *same* `{entity, action, payload}` rows and so
/// reuses this class rather than growing a second apply path. That reuse is the
/// point — a follower and a leader must converge on identical state, which they
/// cannot do if they parse the feed differently.
library;

import 'entity_registry.dart';
import 'local_database.dart';
import 'payload_normalizer.dart';

/// Outcome of applying a batch. Surfaced on the sync-status screen and asserted
/// in tests; nothing branches on it at runtime.
class ApplyStats {
  final int applied;
  final int deleted;

  /// Rows skipped because the local copy has an unsynced local edit.
  final int skippedPending;

  /// Rows for entities this client does not replicate — expected whenever the
  /// backend logs an entity the POS has no use for.
  final int skippedUnknown;

  /// Rows that could not be applied (missing primary key, malformed payload).
  final int failed;

  const ApplyStats({
    this.applied = 0,
    this.deleted = 0,
    this.skippedPending = 0,
    this.skippedUnknown = 0,
    this.failed = 0,
  });

  int get total => applied + deleted + skippedPending + skippedUnknown + failed;

  ApplyStats _add({
    int applied = 0,
    int deleted = 0,
    int skippedPending = 0,
    int skippedUnknown = 0,
    int failed = 0,
  }) =>
      ApplyStats(
        applied: this.applied + applied,
        deleted: this.deleted + deleted,
        skippedPending: this.skippedPending + skippedPending,
        skippedUnknown: this.skippedUnknown + skippedUnknown,
        failed: this.failed + failed,
      );

  @override
  String toString() => 'ApplyStats(applied: $applied, deleted: $deleted, '
      'skippedPending: $skippedPending, skippedUnknown: $skippedUnknown, '
      'failed: $failed)';
}

class ChangeApplier {
  final LocalDatabase _db;

  const ChangeApplier(this._db);

  /// Applies a decoded `POST /api/v1/sync/pull` response body.
  ///
  /// Expects the server's shape:
  /// ```json
  /// { "next_sync_cursor": 42,
  ///   "changes": { "goods": { "created": [{…}], "updated": [{…}], "deleted": ["id"] } } }
  /// ```
  ///
  /// The whole batch commits as one transaction, so subscribers see one
  /// consistent state change per pull rather than a row-by-row flicker, and a
  /// mid-batch failure leaves the cursor and the data consistent with each
  /// other. The cursor is advanced **inside** the same transaction: persisting
  /// it separately could skip a batch permanently if the process died between
  /// the two writes.
  ApplyStats applyPullResponse(Map<String, dynamic> body) {
    final changes = body['changes'];
    final cursor = body['next_sync_cursor'];

    return _db.transaction(() {
      var stats = const ApplyStats();
      var sawTables = false;
      if (changes is Map) {
        for (final entry in changes.entries) {
          final entity = entry.key.toString();
          final value = entry.value;
          if (value is Map) {
            stats = _applyEntityChanges(entity, value, stats);
            if (entity == 'cafe_tables') sawTables = true;
          }
        }
      }
      // Local occupancy is keyed by table id and is not replicated, so a table
      // deleted upstream would otherwise leave its status row behind forever.
      // Cheap, and only when tables actually changed.
      if (sawTables) _db.pruneTableStatuses();
      if (cursor is num) {
        final next = cursor.toInt();
        // Never move the cursor backwards: a retried or out-of-order batch must
        // not cause changes already applied to be requested again forever.
        if (next > _db.syncCursor) _db.syncCursor = next;
      }
      return stats;
    });
  }

  ApplyStats _applyEntityChanges(
    String entity,
    Map<dynamic, dynamic> changes,
    ApplyStats stats,
  ) {
    final spec = kEntitiesByName[entity];
    if (spec == null) {
      // Count every row so the skip is visible rather than silent.
      final n = _lengthOf(changes['created']) +
          _lengthOf(changes['updated']) +
          _lengthOf(changes['deleted']);
      return stats._add(skippedUnknown: n);
    }

    var out = stats;

    // Creates and updates are applied identically — the payload is the whole
    // row either way, and `INSERT OR REPLACE` makes the distinction moot. This
    // also makes the apply idempotent, which matters because a retried pull can
    // legitimately redeliver rows.
    for (final list in [changes['created'], changes['updated']]) {
      if (list is! List) continue;
      for (final row in list) {
        if (row is! Map) {
          out = out._add(failed: 1);
          continue;
        }
        out = _applyUpsert(spec, Map<String, dynamic>.from(row), out);
      }
    }

    // Deletes last, deliberately. The pull response groups by action, which
    // discards the change_log's original ordering, so a row created and then
    // deleted inside one batch appears in both lists. Applying deletes last
    // converges on the correct end state. The inverse case — delete then
    // re-create the same primary key — cannot occur here: keys are server-side
    // UUIDs and are never reused.
    final deleted = changes['deleted'];
    if (deleted is List) {
      for (final id in deleted) {
        final entityId = id?.toString();
        if (entityId == null || entityId.isEmpty) {
          out = out._add(failed: 1);
          continue;
        }
        if (_db.isPending(entity, entityId)) {
          out = out._add(skippedPending: 1);
          continue;
        }
        _db.deleteRow(entity, entityId);
        out = out._add(deleted: 1);
      }
    }

    return out;
  }

  ApplyStats _applyUpsert(
    EntitySpec spec,
    Map<String, dynamic> raw,
    ApplyStats stats,
  ) {
    final id = raw[spec.pk]?.toString();
    if (id == null || id.isEmpty) return stats._add(failed: 1);

    // An unsynced local edit always wins over the incoming row. Without this,
    // a pull landing between a cashier's write and its replay would silently
    // revert what they just did. The guard clears when the replay is
    // acknowledged (Phase 2), after which the server's version takes over.
    if (_db.isPending(spec.name, id)) return stats._add(skippedPending: 1);

    _db.upsert(spec, id, PayloadNormalizer.normalize(spec, raw));
    return stats._add(applied: 1);
  }

  /// Applies a single change. The entry point for the Phase 5 LAN relay and for
  /// anything that has one row rather than a pull batch.
  ApplyStats applyOne({
    required String entity,
    required String action,
    String? entityId,
    Map<String, dynamic>? payload,
  }) {
    final spec = kEntitiesByName[entity];
    if (spec == null) return const ApplyStats(skippedUnknown: 1);

    return _db.transaction(() {
      switch (action) {
        case 'create':
        case 'update':
          if (payload == null) return const ApplyStats(failed: 1);
          return _applyUpsert(spec, payload, const ApplyStats());
        case 'delete':
          final id = entityId ?? payload?[spec.pk]?.toString();
          if (id == null || id.isEmpty) return const ApplyStats(failed: 1);
          if (_db.isPending(entity, id)) {
            return const ApplyStats(skippedPending: 1);
          }
          _db.deleteRow(entity, id);
          return const ApplyStats(deleted: 1);
        default:
          return const ApplyStats(failed: 1);
      }
    });
  }

  /// Writes a locally-originated row and guards it against replication until
  /// the outbox confirms it. This is how every local write reaches the database
  /// in Phase 2 — the UI observes the result immediately, and the row survives
  /// pulls that would otherwise overwrite it.
  void applyLocalWrite({
    required String entity,
    required String id,
    required Map<String, dynamic> payload,
  }) {
    final spec = kEntitiesByName[entity];
    if (spec == null) {
      throw ArgumentError.value(entity, 'entity', 'not a replicated entity');
    }
    _db.transaction(() {
      _db.upsert(spec, id, PayloadNormalizer.normalize(spec, payload));
      _db.markPending(entity, id);
    });
  }

  static int _lengthOf(Object? value) => value is List ? value.length : 0;
}
