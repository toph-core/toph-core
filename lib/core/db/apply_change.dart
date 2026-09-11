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
import 'table_occupancy_reconciler.dart';

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

  /// Entities that had at least one row refused or fail to apply.
  ///
  /// The cursor moves on regardless, and the feed never repeats a row, so these
  /// are the entities whose local copies may now hold something the server has
  /// removed. `ReplicaRepair` sweeps them; without this set nothing downstream
  /// could tell a refusal from a clean batch.
  ///
  /// Deliberately not [skippedUnknown]'s entities — an entity this client does
  /// not replicate has no local rows to reconcile.
  final Set<String> refusedEntities;

  /// The individual rows refused, as `entity/id`.
  ///
  /// A repair sweep needs these, not just the entity names. A snapshot row this
  /// terminal refuses is a row the server *does* have — the local copy was kept
  /// on purpose — so it must not then be deleted for being "absent from the
  /// snapshot". Without this the monotonic guard on `branch_shifts.closed_at`
  /// turned into the shift row vanishing outright.
  final Set<String> refusedIds;

  const ApplyStats({
    this.applied = 0,
    this.deleted = 0,
    this.skippedPending = 0,
    this.skippedUnknown = 0,
    this.failed = 0,
    this.refusedEntities = const {},
    this.refusedIds = const {},
  });

  int get total => applied + deleted + skippedPending + skippedUnknown + failed;

  ApplyStats _add({
    int applied = 0,
    int deleted = 0,
    int skippedPending = 0,
    int skippedUnknown = 0,
    int failed = 0,
    String? refused,
    String? refusedId,
  }) => ApplyStats(
    applied: this.applied + applied,
    deleted: this.deleted + deleted,
    skippedPending: this.skippedPending + skippedPending,
    skippedUnknown: this.skippedUnknown + skippedUnknown,
    failed: this.failed + failed,
    refusedEntities: refused == null
        ? refusedEntities
        : {...refusedEntities, refused},
    refusedIds: refusedId == null ? refusedIds : {...refusedIds, refusedId},
  );

  @override
  String toString() =>
      'ApplyStats(applied: $applied, deleted: $deleted, '
      'skippedPending: $skippedPending, skippedUnknown: $skippedUnknown, '
      'failed: $failed'
      "${refusedEntities.isEmpty ? '' : ', refused: ${refusedEntities.join(',')}'})";
}

/// One row this terminal changed on its own authority, on its way to the LAN.
///
/// [payload] is the raw row as the writer supplied it, *not* the normalized
/// form stored in SQLite: a peer runs it back through the same
/// [PayloadNormalizer] on the way in, so both replicas derive their columns
/// from identical input by the identical function. Null for a delete.
typedef LocalChangeSink =
    void Function({
      required String entity,
      required String action,
      required String id,
      Map<String, dynamic>? payload,
    });

class ChangeApplier {
  final LocalDatabase _db;

  /// Where locally-originated rows go so other terminals on the LAN can apply
  /// them. Null on a terminal with no hub wiring, and on every applier a test
  /// builds without one — the whole local-first path works unchanged without
  /// it, which is the point: peer propagation is additive.
  final LocalChangeSink? _onLocalChange;

  /// True while [applyFromPeer] is running.
  ///
  /// The hub already fans a message out to every other terminal
  /// (`LanHubServer._broadcastExcept`), so a receiver that re-emitted what it
  /// just applied would put the leader and its followers in a permanent echo.
  /// One flag, checked at the single emission point, is what keeps the feed
  /// one-hop — and it is safe as a plain bool because an apply is synchronous
  /// and Dart is single-threaded.
  bool _fromPeer = false;

  /// Occupancy and table timers are derived from the bills this class applies —
  /// see [TableOccupancyReconciler] for why they cannot be left to the screens
  /// that happen to be open.
  late final TableOccupancyReconciler _occupancy = TableOccupancyReconciler(
    _db,
  );

  /// Tables whose orders the in-flight apply touched, drained by whichever
  /// entry point started it.
  ///
  /// Collected rather than reconciled inline because a pull batch can carry an
  /// order's create and its payment in the same transaction: reconciling per
  /// row would decide occupancy from a half-applied batch. Safe as plain
  /// instance state — an apply is synchronous and Dart is single-threaded.
  final Set<String> _touchedOrderTables = <String>{};

  ChangeApplier(this._db, {LocalChangeSink? onLocalChange})
    : _onLocalChange = onLocalChange;

  /// Records both ends of an `orders` row's occupancy: the table it names, and
  /// the table the stored copy names.
  ///
  /// Both, because a transfer rewrites `table_id` — the source table has to be
  /// reconsidered too, or a moved bill leaves it busy forever. Must be called
  /// *before* the row is written, while the stored copy is still the old one.
  void _noteOrderTables(String entity, String id, [Map<String, dynamic>? row]) {
    if (entity != 'orders') return;
    final incoming = row?['table_id']?.toString() ?? '';
    if (incoming.isNotEmpty) _touchedOrderTables.add(incoming);
    for (final stored in _db.select(
      'SELECT table_id AS table_id FROM orders WHERE id = ?',
      [id],
    )) {
      final tableId = stored['table_id'] as String? ?? '';
      if (tableId.isNotEmpty) _touchedOrderTables.add(tableId);
    }
  }

  /// Re-derives occupancy for everything the batch touched. Call inside the
  /// apply's own transaction, once the last row has landed.
  void _reconcileTouchedTables() {
    if (_touchedOrderTables.isEmpty) return;
    final tables = Set<String>.of(_touchedOrderTables);
    _touchedOrderTables.clear();
    _occupancy.reconcileTables(tables);
  }

  /// Queues [_onLocalChange] for after the current transaction commits.
  ///
  /// Deferred rather than immediate so a rolled-back write is never seen by a
  /// peer — see [LocalDatabase.afterCommit].
  void _emitLocalChange({
    required String entity,
    required String action,
    required String id,
    Map<String, dynamic>? payload,
  }) {
    final sink = _onLocalChange;
    if (sink == null || _fromPeer) return;
    _db.afterCommit(
      () => sink(entity: entity, action: action, id: id, payload: payload),
    );
  }

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
  /// Applies a pull batch.
  ///
  /// [advanceCursor] is false only for a LAN batch the receiver knows it has a
  /// gap before — the rows still apply, but the cursor must keep pointing at
  /// the last position this terminal can vouch for, or the missing rows would
  /// be skipped forever. See `ChangeFeedRelay`.
  ApplyStats applyPullResponse(
    Map<String, dynamic> body, {
    bool advanceCursor = true,
  }) {
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
      // Every bill in the batch has landed, so the floor can be re-derived from
      // them: a bill settled on another terminal frees its table here, and one
      // opened there marks it busy. Inside the batch transaction, so the two
      // never commit apart.
      _reconcileTouchedTables();
      if (cursor is num && advanceCursor) {
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
      final n =
          _lengthOf(changes['created']) +
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
          out = out._add(failed: 1, refused: entity);
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
          out = out._add(failed: 1, refused: entity);
          continue;
        }
        if (_db.isPending(entity, entityId)) {
          // The worst refusal there is: a delete the feed will never repeat.
          // Recorded so a repair pass sweeps this entity later.
          out = out._add(skippedPending: 1, refused: entity);
          continue;
        }
        _noteOrderTables(entity, entityId);
        _db.deleteRow(entity, entityId);
        _db.clearPeerOrigin(entity, entityId);
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
    if (id == null || id.isEmpty) {
      return stats._add(failed: 1, refused: spec.name);
    }

    // An unsynced local edit always wins over the incoming row. Without this,
    // a pull landing between a cashier's write and its replay would silently
    // revert what they just did. The guard clears when the replay is
    // acknowledged (Phase 2), after which the server's version takes over.
    //
    // The one exception is a monotonic set — see [EntitySpec.monotonicSetKey].
    //
    // The complement is checked first and is unconditional: a monotonic key
    // never goes back to unset, whoever sent the row and whatever the pending
    // flag says. Without that, draining a queued open reopened a shift that had
    // already been closed — `OutboxDrainer._succeed` clears the pending guard
    // *before* applying the response, so the guard below could not see it, and
    // the server's still-open row (its close had not drained yet) overwrote the
    // local close and was broadcast to every LAN peer as a reopen.
    if (_wouldUnsetMonotonic(spec, id, raw)) {
      return stats._add(
        skippedPending: 1,
        refused: spec.name,
        refusedId: '${spec.name}/$id',
      );
    }
    if (_db.isPending(spec.name, id) &&
        !_completesMonotonicSet(spec, id, raw)) {
      return stats._add(
        skippedPending: 1,
        refused: spec.name,
        refusedId: '${spec.name}/$id',
      );
    }

    _noteOrderTables(spec.name, id, raw);
    _retireClientTwin(spec, id, raw);

    _db.upsert(spec, id, PayloadNormalizer.normalize(spec, raw));
    // Provenance, for the repair sweep. A row that only ever arrived over the
    // LAN is unsynced work belonging to another till and must not be swept;
    // the same row arriving from the server settles that, because from then on
    // the server's answer about it is authoritative.
    if (_fromPeer) {
      _db.markPeerOrigin(spec.name, id);
    } else {
      _db.clearPeerOrigin(spec.name, id);
    }
    return stats._add(applied: 1);
  }

  /// Whether [raw] would clear this entity's monotonic key on a row where it is
  /// already set — a transition that is never legitimate.
  ///
  /// `branch_shifts.closed_at` is set once and never cleared: the backend has
  /// no reopen, and the column only ever goes null → timestamp. So a row
  /// arriving with it unset is stale by construction, no matter which path
  /// delivered it, and applying it would put a till back to trading under a
  /// shift the venue has closed.
  ///
  /// Counted as `skippedPending` for want of a better bucket — the meaning is
  /// the same one that field already carries, "the local copy was kept" — and a
  /// new stat would ripple through `ReplicationService` and its tests for no
  /// behavioural gain.
  bool _wouldUnsetMonotonic(
    EntitySpec spec,
    String id,
    Map<String, dynamic> raw,
  ) {
    final key = spec.monotonicSetKey;
    if (key == null) return false;
    if (!_isUnset(raw[key])) return false;
    final stored = _db.byId(spec.name, id);
    if (stored == null) return false;
    return !_isUnset(stored[key]);
  }

  /// Whether [raw] sets this entity's monotonic key on a row where it is still
  /// unset — the one case an arriving row is allowed past the pending guard.
  ///
  /// The direction matters and is asserted here rather than assumed: only
  /// unset → set passes. A row arriving with the key *unset*, onto a local row
  /// where it is set, is still skipped, so a pull carrying the pre-close server
  /// copy cannot reopen a shift this terminal has closed and not yet reported.
  bool _completesMonotonicSet(
    EntitySpec spec,
    String id,
    Map<String, dynamic> raw,
  ) {
    final key = spec.monotonicSetKey;
    if (key == null) return false;
    if (_isUnset(raw[key])) return false;
    final stored = _db.byId(spec.name, id);
    if (stored == null) return false;
    return _isUnset(stored[key]);
  }

  static bool _isUnset(Object? value) =>
      value == null || value.toString().isEmpty;

  /// Removes the client-invented row this server row supersedes.
  ///
  /// `order_items` is the one replicated entity whose primary key the backend
  /// does **not** take from the client. `LocalWriter.write`'s contract — "the
  /// id a terminal invents offline is the id the row keeps forever" — is true
  /// of `orders`, whose create honours a client-supplied id, and false here:
  /// both `CreateOrder` and `AddOrderItems` mint `uuid.New()` and ignore
  /// whatever `id` the request carried (`back/internal/service/order.go`).
  ///
  /// So a line rung on this terminal was written locally under a client uuid
  /// and came back on the feed under a different one, and nothing connected
  /// the two. The replica kept both. One physical line, two rows — and every
  /// read that sums `order_items` (the open check, the payment screen, the
  /// kitchen receipt) counted it twice, while the archive read its total off
  /// the server's `food_total` and stayed right. That is the split a cashier
  /// sees as "the table says 1 000 000 and the orders tab says 500 000".
  ///
  /// `client_item_id` (`migrations/tenants/70_order_items_client_id.up.sql`)
  /// is the key the backend does honour, and it rides back on the server row.
  /// So the twin is identified exactly, by the id this terminal chose — never
  /// by matching on good, price or timestamp, which would eventually retire a
  /// line the operator rang twice on purpose.
  ///
  /// Deleted through the same emit as any other change: peers were told about
  /// the local row when it was written and have to be told it is gone.
  void _retireClientTwin(
    EntitySpec spec,
    String serverId,
    Map<String, dynamic> raw,
  ) {
    if (spec.name != 'order_items') return;
    final clientId = raw['client_item_id']?.toString();
    if (clientId == null || clientId.isEmpty || clientId == serverId) return;
    if (_db.byId(spec.name, clientId) == null) return;
    _db.deleteRow(spec.name, clientId);
    // The twin is gone, so its guards have nothing left to guard. Left behind
    // they would shield an id no row has from every future pull.
    _db.clearPending(spec.name, clientId);
    _db.clearProvisional(spec.name, clientId);
    _emitLocalChange(entity: spec.name, action: 'delete', id: clientId);
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
          final stats = _applyUpsert(spec, payload, const ApplyStats());
          // Only a row that actually landed is worth telling peers about — a
          // pending-skip means this terminal kept its own version, so there is
          // nothing new here to hand on.
          if (stats.applied > 0) {
            final id = payload[spec.pk]!.toString();
            _emitLocalChange(
              entity: entity,
              action: action,
              id: id,
              payload: payload,
            );
          }
          _reconcileTouchedTables();
          return stats;
        case 'delete':
          final id = entityId ?? payload?[spec.pk]?.toString();
          if (id == null || id.isEmpty) return const ApplyStats(failed: 1);
          if (_db.isPending(entity, id)) {
            return const ApplyStats(skippedPending: 1);
          }
          _noteOrderTables(entity, id);
          _db.deleteRow(entity, id);
          _db.clearPeerOrigin(entity, id);
          _emitLocalChange(entity: entity, action: 'delete', id: id);
          _reconcileTouchedTables();
          return const ApplyStats(deleted: 1);
        default:
          return const ApplyStats(failed: 1);
      }
    });
  }

  /// Applies a row another terminal on this LAN just wrote.
  ///
  /// Identical to [applyOne] in every respect but one: it does not re-emit.
  /// The row reached this terminal because the hub already fanned it out to
  /// everyone, so passing it on again would be an echo, not replication.
  ///
  /// Note what this deliberately does *not* do — mark the row pending, or
  /// enqueue anything. The terminal that originated the write owns its trip to
  /// the server; a peer holds the row only so its operator can see it, and
  /// lets the next cloud pull replace it with the canonical version. Two
  /// terminals queuing the same create is exactly the duplicate this avoids.
  ApplyStats applyFromPeer({
    required String entity,
    required String action,
    String? entityId,
    Map<String, dynamic>? payload,
  }) {
    _fromPeer = true;
    try {
      return applyOne(
        entity: entity,
        action: action,
        entityId: entityId,
        payload: payload,
      );
    } finally {
      _fromPeer = false;
    }
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
      _noteOrderTables(entity, id, payload);
      _db.upsert(spec, id, PayloadNormalizer.normalize(spec, payload));
      _db.markPending(entity, id);
      // Peers get the row itself, never the pending guard: the guard says
      // "this terminal owes the server a write", which is true here and false
      // everywhere else.
      _emitLocalChange(
        entity: entity,
        action: 'update',
        id: id,
        payload: payload,
      );
      // The local half of the same rule the pull path applies: taking a payment
      // here closes the bill on the row above, so the table frees itself and
      // its timer is dropped without the payment screen having to remember —
      // and, crucially, without depending on that screen being the one that
      // took it.
      _reconcileTouchedTables();
    });
  }

  /// Removes a locally-deleted row and guards it against replication until the
  /// outbox confirms the delete — the delete-shaped twin of [applyLocalWrite],
  /// and `LocalWriter.delete`'s way of reaching peers.
  ///
  /// Separate from [applyOne]'s `delete` branch because the two mean different
  /// things: this one asserts local authority over the row, where `applyOne`
  /// yields to it.
  void applyLocalDelete({required String entity, required String id}) {
    final spec = kEntitiesByName[entity];
    if (spec == null) {
      throw ArgumentError.value(entity, 'entity', 'not a replicated entity');
    }
    _db.transaction(() {
      _noteOrderTables(entity, id);
      _db.deleteRow(entity, id);
      _db.clearPeerOrigin(entity, id);
      _db.markPending(entity, id);
      _emitLocalChange(entity: entity, action: 'delete', id: id);
      _reconcileTouchedTables();
    });
  }

  static int _lengthOf(Object? value) => value is List ? value.length : 0;
}
