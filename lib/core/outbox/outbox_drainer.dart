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

  /// Held back because an earlier operation on the same aggregate failed.
  /// Not an error — they are simply waiting their turn.
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
      for (final op in _store.ready(limit: limit)) {
        final chain = _executors.chainKeyOf(op);
        if (blockedChains.contains(chain)) {
          blocked++;
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
            _succeed(op, result.serverRow);
            sent++;
          case OutboxOutcome.retry:
            _store.markFailed(op.id, result.error ?? 'unknown error');
            retrying++;
            blockedChains.add(chain);
          case OutboxOutcome.permanent:
            _fail(op, result.error ?? 'rejected', permanent: true);
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

  void _succeed(OutboxOperation op, Map<String, dynamic>? serverRow) {
    _db.transaction(() {
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
        _reconcile(op, entityId, serverRow);
        return;
      }
      if (serverRow != null) {
        _applier.applyOne(
          entity: op.entity,
          action: 'update',
          entityId: entityId,
          payload: serverRow,
        );
      }
    });
  }

  /// Replaces a provisional row with the server's, and repoints anything still
  /// queued that referred to it.
  ///
  /// Runs inside `_succeed`'s transaction: the old row's removal, the new row's
  /// arrival and the reference rewrite are one atomic step, so there is no
  /// instant where a queued operation points at a row that no longer exists.
  void _reconcile(
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
      return;
    }

    if (serverId != provisionalId) {
      // Same reason as above — a peer that kept the provisional row while
      // receiving the server's would show the same hall, user or table twice.
      _applier.applyOne(
        entity: op.entity,
        action: 'delete',
        entityId: provisionalId,
      );
      _store.rewriteReferences(oldId: provisionalId, newId: serverId);
    }
    _db.clearProvisional(op.entity, provisionalId);
    _applier.applyOne(
      entity: op.entity,
      action: 'update',
      entityId: serverId,
      payload: row!,
    );
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
