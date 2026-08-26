/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — replaying queued writes.
library;

import 'package:flutter/foundation.dart';

import '../db/apply_change.dart';
import '../db/local_database.dart';
import 'outbox_executor.dart';
import 'outbox_operation.dart';
import 'outbox_store.dart';

@immutable
class OutboxDrainResult {
  final int sent;
  final int retrying;
  final int quarantined;

  /// Held back this pass: either an earlier operation on the same aggregate
  /// failed, or the body still quotes a provisional id whose own create has
  /// not been acknowledged. Not an error — they are waiting their turn.
  final int blocked;

  const OutboxDrainResult({
    this.sent = 0,
    this.retrying = 0,
    this.quarantined = 0,
    this.blocked = 0,
  });

  int get total => sent + retrying + quarantined + blocked;
  bool get madeProgress => sent > 0;

  @override
  String toString() => 'OutboxDrainResult(sent: $sent, retrying: $retrying, '
      'quarantined: $quarantined, blocked: $blocked)';
}

class OutboxDrainer {
  final OutboxStore _store;
  final OutboxExecutors _executors;
  final LocalDatabase _db;
  final ChangeApplier _applier;

  bool _running = false;

  OutboxDrainer({
    required OutboxStore store,
    required OutboxExecutors executors,
    required LocalDatabase db,
    required ChangeApplier applier,
  })  : _store = store,
        _executors = executors,
        _db = db,
        _applier = applier;

  bool get isRunning => _running;

  /// Sends every ready operation, oldest first.
  ///
  /// Operations are processed in the order the cashier produced them, which is
  /// what preserves causality. When one fails, its whole causal chain is held
  /// back for this pass — but unrelated chains keep going, so a single bad
  /// write cannot stall the queue behind it. That is the difference between
  /// per-operation and global backoff, and the reason a poisoned payment on
  /// table 4 does not stop table 9's order from reaching the server.
  Future<OutboxDrainResult> drain({int limit = 100}) async {
    if (_running) return const OutboxDrainResult();

    // Phase 2 ships the machinery with no handlers registered; Phase 4 adds
    // them as each repository moves onto the outbox. Draining against an empty
    // registry would quarantine any operation it found for want of a handler,
    // so an empty registry means "not yet in service", not "reject everything".
    if (_executors.isEmpty) return const OutboxDrainResult();

    _running = true;

    var sent = 0;
    var retrying = 0;
    var quarantined = 0;
    var blocked = 0;
    final blockedChains = <String>{};

    try {
      // Ids the server has not named yet. An operation whose body quotes one
      // of them cannot be sent: the server would be handed a reference to a
      // row it has never heard of. See [_unresolvedProvisionalIds].
      final unresolved = _unresolvedProvisionalIds();

      // Set once any reconciliation has rewritten queued payloads. The loop
      // below is iterating operations decoded at the top of the pass, so from
      // that point on each one has to be re-read before it is sent — see
      // `_succeed`'s return value.
      var rewrote = false;

      // Ordering hazard the chain keys were meant to close, but could not.
      // An operation in backoff is not returned by [OutboxStore.ready], so
      // nothing below ever sees it — and a chain nobody sees is a chain
      // nobody blocks. A later operation on the same chain therefore drained
      // straight past the one it belongs behind: a pay ahead of its own
      // create, a shift close ahead of a payment that was still retrying.
      // Seed those chains before the pass, so the hold-back below covers a
      // retrying predecessor as well as a queued one.
      for (final held in _store.backingOff(limit: limit)) {
        blockedChains.add(_executors.chainKeyOf(held));
      }

      for (var op in _store.ready(limit: limit)) {
        // A translation that landed a moment ago repointed the good queued
        // behind it. Sending the copy this loop is holding would send the
        // provisional id anyway, which is the exact failure the rewrite exists
        // to prevent.
        if (rewrote) {
          final fresh = _store.find(op.id);
          if (fresh == null) continue;
          op = fresh;
        }

        final chain = _executors.chainKeyOf(op);
        if (blockedChains.contains(chain)) {
          blocked++;
          continue;
        }

        if (_awaitsProvisionalId(op, unresolved)) {
          // Held, not failed. The create it is waiting on is still queued, and
          // `rewriteReferences` will repoint this body the moment that create
          // comes back with a real id.
          blocked++;
          blockedChains.add(chain);
          continue;
        }

        final handler = _executors.resolve(op);
        if (handler == null) {
          // Nothing can ever send this. Quarantining beats retrying it eight
          // times to reach the same conclusion, and it surfaces the gap —
          // an operation enqueued for an entity nobody registered a handler
          // for is a programming error, not a network condition.
          _fail(op, 'no executor registered for ${op.entity}/${op.action}',
              permanent: true);
          quarantined++;
          blockedChains.add(chain);
          continue;
        }

        OutboxExecutionResult result;
        try {
          result = await handler.send(op);
        } catch (e) {
          // An executor that throws is treated as retryable: an unexpected
          // exception is far more likely to be a transport fault than a
          // considered rejection by the server.
          result = OutboxExecutionResult.retry('$e');
        }

        switch (result.outcome) {
          case OutboxOutcome.succeeded:
            rewrote |= _succeed(op, result.serverRow) > 0;
            // Either the id was resolved and every queued reference to it has
            // just been rewritten, or the endpoint did not name one and no
            // amount of waiting will produce it. Both end the wait.
            unresolved.remove(op.entityId);
            sent++;
          case OutboxOutcome.retry:
            _store.markFailed(op.id, result.error ?? 'unknown error');
            retrying++;
            blockedChains.add(chain);
          case OutboxOutcome.permanent:
            _fail(op, result.error ?? 'rejected', permanent: true);
            // The create is out of the queue for good. Dependents stop waiting
            // on it and are sent — where the reference really was load-bearing
            // the server rejects them too, which puts both halves of the
            // problem in the quarantine list where an operator can see them.
            unresolved.remove(op.entityId);
            quarantined++;
            blockedChains.add(chain);
        }
      }
    } finally {
      _running = false;
    }

    return OutboxDrainResult(
      sent: sent,
      retrying: retrying,
      quarantined: quarantined,
      blocked: blocked,
    );
  }

  /// Provisional ids that a queued `create` still owes the server a real id
  /// for.
  ///
  /// A row created offline under an endpoint that assigns its own id lives
  /// under a client-invented key until that create is acknowledged
  /// (`LocalWriter.create`). Anything written *afterwards* that points at it —
  /// a meal quoting the translation row that holds its name, a cash movement
  /// filed under a transaction group that was added in the same offline
  /// stretch — carries that invented key in its body.
  ///
  /// Sending such a body before the create lands hands the server a foreign key
  /// it cannot resolve, and the write is rejected on its merits, quarantined,
  /// and lost to the operator. Holding it costs one drain pass:
  /// [OutboxStore.rewriteReferences] repoints every queued body the instant the
  /// create returns the real id, so the next pass sends a request the server can
  /// satisfy.
  ///
  /// Reads `pending()` rather than `ready()` on purpose — a create backing off
  /// after a timeout is still going to happen, and its dependents must wait for
  /// it, not overtake it.
  Set<String> _unresolvedProvisionalIds() {
    final out = <String>{};
    for (final op in _store.pending()) {
      if (op.action != 'create') continue;
      final id = op.entityId;
      if (id == null || id.isEmpty) continue;
      if (_db.isProvisional(op.entity, id)) out.add(id);
    }
    return out;
  }

  /// Whether [op]'s body quotes a provisional id belonging to some *other* row.
  ///
  /// Its own [OutboxOperation.entityId] is excluded: a create's payload may
  /// legitimately carry the key it was written under, and it is precisely the
  /// operation that resolves it.
  static bool _awaitsProvisionalId(OutboxOperation op, Set<String> unresolved) {
    if (unresolved.isEmpty) return false;
    final ownId = op.entityId;
    for (final id in unresolved) {
      if (id == ownId) continue;
      if (_quotes(op.payload, id)) return true;
    }
    return false;
  }

  /// Whole-value match, never a substring: ids are UUIDs, and a description
  /// that merely quoted one is not a reference. Same rule as
  /// [OutboxStore.rewriteReferences], which is what will rewrite whatever this
  /// finds.
  static bool _quotes(Object? node, String id) {
    if (node is String) return node == id;
    if (node is List) {
      for (final item in node) {
        if (_quotes(item, id)) return true;
      }
      return false;
    }
    if (node is Map) {
      for (final value in node.values) {
        if (_quotes(value, id)) return true;
      }
      return false;
    }
    return false;
  }

  /// Records the success and returns how many queued operations were
  /// repointed onto the server's id — zero for everything except a
  /// reconciliation that actually renamed a row.
  int _succeed(OutboxOperation op, Map<String, dynamic>? serverRow) {
    return _db.transaction(() {
      _store.markSucceeded(op.id);
      final entityId = op.entityId;
      if (entityId != null && entityId.isNotEmpty) {
        // The write is confirmed, so the local row stops being protected and
        // replication may correct it from here on.
        _db.clearPending(op.entity, entityId);
      }
      if (entityId != null &&
          entityId.isNotEmpty &&
          _db.isProvisional(op.entity, entityId)) {
        return _reconcile(op, entityId, serverRow);
      }
      if (serverRow != null) {
        _applier.applyOne(
          entity: op.entity,
          action: 'update',
          entityId: entityId,
          payload: serverRow,
        );
      }
      return 0;
    });
  }

  /// Replaces a provisional row with the server's, and repoints anything still
  /// queued that referred to it.
  ///
  /// Runs inside `_succeed`'s transaction: the old row's removal, the new row's
  /// arrival and the reference rewrite are one atomic step, so there is no
  /// instant where a queued operation points at a row that no longer exists.
  /// Returns the number of queued operations whose bodies were repointed.
  int _reconcile(
    OutboxOperation op,
    String provisionalId,
    Map<String, dynamic>? serverRow,
  ) {
    // Unwrap before anything else: the id and the row have to come from the
    // same place, or the envelope gets stored as the row.
    final row = _rowOf(serverRow);
    final serverId = row?['id'] as String?;

    if (serverId == null || serverId.isEmpty) {
      // The endpoint did not tell us the id it assigned. The local row is a
      // fabrication we can no longer justify keeping: replication will deliver
      // the server's version under its own id, and leaving this one would put
      // two rows on screen for one thing. Dropping it costs the operator a
      // brief disappearance and costs the data nothing — the write succeeded.
      //
      // Through the applier, not `_db.deleteRow`: LAN peers were told about
      // this provisional row when it was written, so they have to be told it
      // is gone. `_succeed` has already cleared the pending guard, so the
      // delete is not skipped as someone else's unsynced edit.
      _applier.applyOne(
        entity: op.entity,
        action: 'delete',
        entityId: provisionalId,
      );
      _db.clearProvisional(op.entity, provisionalId);
      return 0;
    }

    var rewritten = 0;
    if (serverId != provisionalId) {
      // Same reason as above — a peer that kept the provisional row while
      // receiving the server's would show the same hall, user or table twice.
      _applier.applyOne(
        entity: op.entity,
        action: 'delete',
        entityId: provisionalId,
      );
      rewritten = _store.rewriteReferences(oldId: provisionalId, newId: serverId);
    }
    _db.clearProvisional(op.entity, provisionalId);
    _applier.applyOne(
      entity: op.entity,
      action: 'update',
      entityId: serverId,
      payload: row!,
    );
    return rewritten;
  }

  /// The created row out of a create response, which is either the row itself
  /// or the row under a `data` envelope.
  static Map<String, dynamic>? _rowOf(Map<String, dynamic>? response) {
    if (response == null) return null;
    final direct = response['id'];
    if (direct is String && direct.isNotEmpty) return response;
    final data = response['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  void _fail(OutboxOperation op, String error, {required bool permanent}) {
    _db.transaction(() {
      if (permanent) {
        _store.markPermanentlyFailed(op.id, error);
        final entityId = op.entityId;
        if (entityId != null && entityId.isNotEmpty) {
          // Deliberate: a quarantined write releases its local row.
          //
          // The alternative — keeping the guard — would shield a row the
          // server never accepted from every future replication pass, leaving
          // the terminal displaying something no other terminal can see, with
          // no path back to agreement. Releasing it lets the server's version
          // win; the operator sees the change revert and finds the reason in
          // the quarantine list. A visible revert beats a silent private
          // truth.
          _db.clearPending(op.entity, entityId);
        }
      } else {
        _store.markFailed(op.id, error);
      }
    });
  }
}
