/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 1 — the replication loop.
///
/// Replaces ~300 lines of per-entity hydration with one cursor-driven loop.
/// Where the old `SyncEngine._hydrateX` methods each knew about a specific
/// endpoint, response shape and cache key, this knows only "pull the next page
/// and apply it" — so an entity added to the backend needs one registry line
/// here and nothing else, and a screen never needs a fetch path at all.
///
/// ## The one user-triggered request in the product
///
/// [bootstrap] runs once, at first login, and is the only place in the app
/// where a person waits on the network by design. Everything after it is
/// background: [drain] is called by `SyncEngine`'s existing triggers (periodic,
/// reconnect, LAN reconnect, post-outbox) and never by a screen, a widget, a
/// controller, or a refresh button.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../db/apply_change.dart';
import '../db/local_database.dart';
import 'sync_api_client.dart';

/// Progress during a multi-page catch-up, for the bootstrap screen.
@immutable
class ReplicationProgress {
  final int batches;
  final int rowsApplied;
  final int cursor;

  const ReplicationProgress({
    required this.batches,
    required this.rowsApplied,
    required this.cursor,
  });
}

/// Why a replication run stopped.
enum ReplicationOutcome {
  /// Reached the end of the feed — the replica is current.
  caughtUp,

  /// Hit the batch ceiling with more to fetch. Not an error; the next tick
  /// continues from the stored cursor.
  moreAvailable,

  /// A run was already in flight; this call did nothing.
  alreadyRunning,

  /// The network or the server failed. The cursor is unchanged past the last
  /// successfully applied page, so the next attempt resumes cleanly.
  failed,
}

@immutable
class ReplicationResult {
  final ReplicationOutcome outcome;
  final int batches;
  final int rowsApplied;
  final int rowsSkipped;
  final Object? error;

  const ReplicationResult({
    required this.outcome,
    this.batches = 0,
    this.rowsApplied = 0,
    this.rowsSkipped = 0,
    this.error,
  });

  bool get ok =>
      outcome == ReplicationOutcome.caughtUp ||
      outcome == ReplicationOutcome.moreAvailable;

  @override
  String toString() => 'ReplicationResult(${outcome.name}, batches: $batches, '
      'applied: $rowsApplied, skipped: $rowsSkipped'
      '${error == null ? '' : ', error: $error'})';
}

class ReplicationService {
  final SyncApi _api;
  final LocalDatabase _db;
  final ChangeApplier _applier;

  bool _running = false;

  ReplicationService({
    required SyncApi api,
    required LocalDatabase db,
    required ChangeApplier applier,
  })  : _api = api,
        _db = db,
        _applier = applier;

  /// Safety ceiling for a steady-state pass, so one tick cannot monopolise the
  /// app if the feed is far behind. 200 × 500 = 100 000 rows, far more than a
  /// venue produces between ticks; hitting it returns [moreAvailable] and the
  /// next tick continues.
  static const defaultMaxBatches = 200;

  /// Ceiling for first-login bootstrap.
  ///
  /// Bootstrap replays the tenant's entire change-log history, because
  /// `change_log` has no compaction and cursor 0 means "from the beginning"
  /// (see the backend ask for a `/sync/snapshot` endpoint). This bound is
  /// generous rather than tight — running out mid-bootstrap leaves a usable,
  /// partially-populated replica that later ticks finish, not a broken one.
  static const bootstrapMaxBatches = 20000;

  bool get isRunning => _running;

  /// Whether this terminal still needs its one-time initialization.
  bool get needsBootstrap => !_db.isBootstrapped;

  /// Pulls pages until the replica is current.
  ///
  /// Re-entrant calls return [ReplicationOutcome.alreadyRunning] rather than
  /// queueing: every trigger that calls this is periodic or edge-driven, so a
  /// dropped overlapping call costs nothing — the next one picks up the same
  /// cursor.
  Future<ReplicationResult> drain({
    int maxBatches = defaultMaxBatches,
    void Function(ReplicationProgress)? onProgress,
  }) async {
    if (_running) {
      return const ReplicationResult(outcome: ReplicationOutcome.alreadyRunning);
    }
    _running = true;

    var batches = 0;
    var applied = 0;
    var skipped = 0;

    try {
      while (batches < maxBatches) {
        final cursor = _db.syncCursor;
        final page = await _api.pull(cursor: cursor, limit: SyncApiClient.batchSize);

        // Applying advances the cursor inside the same transaction as the rows,
        // so a crash here can never leave the cursor ahead of the data.
        final stats = _applier.applyPullResponse(page.body);
        applied += stats.applied + stats.deleted;
        skipped += stats.skippedPending + stats.skippedUnknown + stats.failed;
        batches++;

        onProgress?.call(ReplicationProgress(
          batches: batches,
          rowsApplied: applied,
          cursor: _db.syncCursor,
        ));

        // Two independent stop conditions. A short page means the feed is
        // exhausted. A cursor that did not advance means the same thing, and
        // also guards against looping forever if the server ever returns a full
        // page whose rows do not move the cursor.
        if (page.rowCount < SyncApiClient.batchSize) {
          return ReplicationResult(
            outcome: ReplicationOutcome.caughtUp,
            batches: batches,
            rowsApplied: applied,
            rowsSkipped: skipped,
          );
        }
        if (page.nextCursor <= cursor) {
          return ReplicationResult(
            outcome: ReplicationOutcome.caughtUp,
            batches: batches,
            rowsApplied: applied,
            rowsSkipped: skipped,
          );
        }
      }

      return ReplicationResult(
        outcome: ReplicationOutcome.moreAvailable,
        batches: batches,
        rowsApplied: applied,
        rowsSkipped: skipped,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Replication] drain failed: $e\n$st');
      return ReplicationResult(
        outcome: ReplicationOutcome.failed,
        batches: batches,
        rowsApplied: applied,
        rowsSkipped: skipped,
        error: e,
      );
    } finally {
      _running = false;
    }
  }

  /// First-login initialization: fills an empty replica from the start of the
  /// feed. The **only** network request in this application that a user action
  /// waits on.
  ///
  /// Idempotent and resumable. If it fails or is interrupted, the cursor holds
  /// whatever was applied, `bootstrap_complete` stays unset, and calling it
  /// again continues from there rather than starting over.
  Future<ReplicationResult> bootstrap({
    int maxBatches = bootstrapMaxBatches,
    void Function(ReplicationProgress)? onProgress,
  }) async {
    final result = await drain(
      maxBatches: maxBatches,
      onProgress: onProgress,
    );

    // Marked complete only on a clean finish. `moreAvailable` means the ceiling
    // was hit with rows still pending — usable, but not yet a full replica, so
    // the app keeps treating it as un-bootstrapped until a later pass finishes.
    if (result.outcome == ReplicationOutcome.caughtUp) {
      _db.markBootstrapped();
    }
    return result;
  }

  /// Drops the replica and re-initializes it.
  ///
  /// For a login that changes brand or branch: the replica describes exactly
  /// one tenant, so carrying it across would show the previous tenant's data.
  /// [LocalDatabase.clearAll] also empties the outbox, which is correct here
  /// and dangerous anywhere else — callers must be sure the outbox is drained
  /// before switching tenants, since those writes belong to the old one.
  Future<ReplicationResult> resetAndBootstrap({
    void Function(ReplicationProgress)? onProgress,
  }) async {
    _db.clearAll();
    return bootstrap(onProgress: onProgress);
  }
}
