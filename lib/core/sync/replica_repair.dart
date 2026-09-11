/// Brings the replica back into agreement with the server when the change feed
/// cannot.
///
/// The feed is a stream of differences, and a terminal that misses one never
/// hears it again: `change_log` does not repeat itself. Two ways that happens,
/// both by design elsewhere in this system —
///
/// * **Retention.** `compact_change_log()` removes rows beyond its window, so a
///   terminal whose cursor sits below the surviving tail can no longer catch up.
///   The server detects exactly this and answers `POST /sync/pull` with
///   `snapshot_required: true`.
/// * **The pending guard.** `ChangeApplier` refuses an incoming row while the
///   local copy carries an unsynced local edit, and the cursor advances anyway.
///   For an ordinary update that is right — this terminal's own write is about
///   to supersede it. For a *delete* it is permanent: the row stays on the
///   floor plan forever, on a terminal whose operator has no way to tell it is
///   looking at something the venue deleted last month.
///
/// So this walks `GET /sync/snapshot` — the server's current rows — applies
/// them, and then removes what the walk did not deliver. That second half is
/// the part the feed can never do, and the reason this class exists rather than
/// "just pull again harder".
///
/// ## What it will not do
///
/// It is a reconciliation, not a reset. `LocalDatabase.clearAll` (the brand
/// switch's tool) empties the outbox with everything else, which on a terminal
/// that has been offline for a day would throw away a day of unsent sales. This
/// touches the outbox not at all, and `LocalDatabase.unsweptRowIds` excludes
/// every row a local write still owns — pending or provisional — so unsynced
/// work survives a repair unchanged.
///
/// It is also entirely background. Nothing awaits it, no screen shows a spinner
/// for it, and a pass interrupted by a dead uplink resumes from its stored
/// coordinate on the next tick rather than starting over.
library;

import 'package:flutter/foundation.dart';

import '../db/apply_change.dart';
import '../db/entity_registry.dart';
import '../db/local_database.dart';
import 'snapshot_api_client.dart';

/// Why a repair pass stopped.
enum RepairOutcome {
  /// Nothing to do — no repair is pending.
  notNeeded,

  /// The walk finished and the replica was reconciled.
  repaired,

  /// The page ceiling was hit. The coordinate is stored; the next tick resumes.
  moreAvailable,

  /// A pass was already running.
  alreadyRunning,

  /// The network or the server failed. Flags and coordinate are unchanged, so
  /// the next attempt continues from where this one stopped.
  failed,
}

@immutable
class RepairResult {
  final RepairOutcome outcome;
  final int pages;
  final int rowsApplied;
  final int rowsSwept;
  final Object? error;

  const RepairResult(
    this.outcome, {
    this.pages = 0,
    this.rowsApplied = 0,
    this.rowsSwept = 0,
    this.error,
  });

  @override
  String toString() =>
      'RepairResult(${outcome.name}, pages: $pages, applied: $rowsApplied, '
      'swept: $rowsSwept${error == null ? '' : ', error: $error'})';
}

class ReplicaRepair {
  final SnapshotApi _api;
  final LocalDatabase _db;
  final ChangeApplier _applier;

  ReplicaRepair({
    required SnapshotApi api,
    required LocalDatabase db,
    required ChangeApplier applier,
  }) : _api = api,
       _db = db,
       _applier = applier;

  /// Set when the server reports `snapshot_required`: the whole replica is
  /// suspect, so every entity is swept.
  static const _fullKey = 'replica_repair_full';

  /// Entities that had a row refused on the way in. Only these are swept when
  /// a full repair is not required — a narrow sweep costs the same walk but
  /// cannot delete a row on the strength of an entity nothing went wrong in.
  static const _entitiesKey = 'replica_repair_entities';

  /// The in-progress walk, so a pass interrupted by a dead uplink resumes
  /// instead of restarting: snapshot cursor, keyset coordinate, and the
  /// timestamp the sweep measures "not delivered" against.
  static const _cursorKey = 'replica_repair_cursor';
  static const _entityKey = 'replica_repair_at_entity';
  static const _afterIdKey = 'replica_repair_after_id';
  static const _startedAtKey = 'replica_repair_started_at';

  /// Pages per pass. 40 × 500 = 20 000 rows, enough to finish a venue's replica
  /// in one pass while leaving a large tenant to finish across a few ticks
  /// rather than monopolising the app.
  static const maxPagesPerPass = 40;

  bool _running = false;

  /// Whether a pass has anything to do.
  bool get isNeeded => _fullRequired || _refusedEntities.isNotEmpty;

  bool get _fullRequired => _db.getMeta(_fullKey) == '1';

  Set<String> get _refusedEntities {
    final raw = _db.getMeta(_entitiesKey) ?? '';
    return {
      for (final name in raw.split(','))
        if (name.trim().isNotEmpty) name.trim(),
    };
  }

  /// The server told us the feed can no longer reconstruct this replica.
  void requireFull() => _db.setMeta(_fullKey, '1');

  /// A pull refused rows for these entities, so their local copies may hold
  /// something the server has since removed.
  ///
  /// Accumulated rather than acted on immediately: the refusal itself is
  /// usually harmless (this terminal's own edit winning over an older server
  /// copy), and a walk per refusal would put the app on the network constantly.
  /// The sweep is what settles it, once.
  void noteRefused(Set<String> entities) {
    final known = entities.where(kEntitiesByName.containsKey).toSet();
    if (known.isEmpty) return;
    final merged = {..._refusedEntities, ...known};
    _db.setMeta(_entitiesKey, merged.join(','));
  }

  /// Runs one repair pass. Safe to call on every sync tick — it returns
  /// [RepairOutcome.notNeeded] immediately when there is nothing pending.
  Future<RepairResult> run({int maxPages = maxPagesPerPass}) async {
    if (_running) return const RepairResult(RepairOutcome.alreadyRunning);
    if (!isNeeded) return const RepairResult(RepairOutcome.notNeeded);
    _running = true;

    // Captured before the first request: any row the walk writes is stamped
    // after this, so "stamped before it" is exactly "the snapshot did not carry
    // this row". Persisted so a resumed pass keeps measuring against the
    // moment the walk started, not the moment it resumed.
    final startedAt = _resumeStartedAt();
    final fullSweep = _fullRequired;
    final narrowSweep = _refusedEntities;

    var cursor = int.tryParse(_db.getMeta(_cursorKey) ?? '') ?? 0;
    var entity = _db.getMeta(_entityKey) ?? '';
    var afterId = _db.getMeta(_afterIdKey) ?? '';

    var pages = 0;
    var applied = 0;
    // `entity/id` of every row the snapshot delivered and the applier refused.
    final kept = <String>{};

    try {
      while (pages < maxPages) {
        final page = await _api.fetch(
          cursor: cursor > 0 ? cursor : null,
          entity: entity.isEmpty ? null : entity,
          afterId: afterId.isEmpty ? null : afterId,
        );
        pages++;

        // The first page chooses the cursor; every page after echoes it back.
        if (cursor <= 0) cursor = page.snapshotCursor;
        applied += _applyPage(page, kept);

        if (page.done) {
          final swept = _finish(
            cursor: cursor,
            startedAt: startedAt,
            sweepAll: fullSweep,
            sweepOnly: narrowSweep,
            kept: kept,
          );
          return RepairResult(
            RepairOutcome.repaired,
            pages: pages,
            rowsApplied: applied,
            rowsSwept: swept,
          );
        }

        entity = page.next?.entity ?? '';
        afterId = page.next?.afterId ?? '';
        _storeCoordinate(cursor: cursor, entity: entity, afterId: afterId);
      }

      return RepairResult(
        RepairOutcome.moreAvailable,
        pages: pages,
        rowsApplied: applied,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ReplicaRepair] pass failed: $e\n$st');
      return RepairResult(
        RepairOutcome.failed,
        pages: pages,
        rowsApplied: applied,
        error: e,
      );
    } finally {
      _running = false;
    }
  }

  int _resumeStartedAt() {
    final stored = int.tryParse(_db.getMeta(_startedAtKey) ?? '');
    if (stored != null && stored > 0) return stored;
    // From the same sequence the writes use, so "written before the walk
    // began" is exact rather than a millisecond's coincidence.
    final now = _db.nextSyncStamp();
    _db.setMeta(_startedAtKey, '$now');
    return now;
  }

  void _storeCoordinate({
    required int cursor,
    required String entity,
    required String afterId,
  }) {
    _db.setMeta(_cursorKey, '$cursor');
    _db.setMeta(_entityKey, entity);
    _db.setMeta(_afterIdKey, afterId);
  }

  /// Applies one page through the ordinary inbound path.
  ///
  /// Shaped as a pull batch on purpose: snapshot rows are `to_jsonb` of the
  /// table row, the same as a `created` payload, so they get the same
  /// normalization, the same pending guard and the same occupancy
  /// reconciliation. A second apply path would be a second set of bugs.
  ///
  /// `advanceCursor: false` because the snapshot's cursor is only valid once
  /// the walk completes — adopting it mid-walk would skip every change between
  /// the terminal's real position and the snapshot's.
  int _applyPage(SnapshotPage page, Set<String> keptByThisTerminal) {
    var applied = 0;
    for (final entry in page.rows.entries) {
      if (!kEntitiesByName.containsKey(entry.key)) continue;
      if (entry.value.isEmpty) continue;
      final stats = _applier.applyPullResponse({
        'changes': {
          entry.key: {'created': entry.value},
        },
      }, advanceCursor: false);
      applied += stats.applied;
      // A row the applier refused is a row the server sent and this terminal
      // chose to keep its own copy of. It is emphatically NOT evidence the
      // server deleted it — but it goes unstamped, which is what the sweep
      // reads as absence. Collected here so the sweep can leave it alone.
      keptByThisTerminal.addAll(stats.refusedIds);
    }
    return applied;
  }

  /// Sweeps, adopts the snapshot's cursor, and clears the flags.
  ///
  /// One transaction: a sweep that committed without the cursor would leave the
  /// terminal short of rows it now believes it has seen.
  int _finish({
    required int cursor,
    required int startedAt,
    required bool sweepAll,
    required Set<String> sweepOnly,
    required Set<String> kept,
  }) {
    final targets = sweepAll
        ? kEntitiesByName.keys.toSet()
        : sweepOnly.where(kEntitiesByName.containsKey).toSet();

    return _db.transaction(() {
      var swept = 0;
      for (final entity in targets) {
        for (final id in _db.unsweptRowIds(entity, startedAt)) {
          if (kept.contains('$entity/$id')) continue;
          // Through the applier rather than `deleteRow`: a table that vanished
          // here has vanished for the terminals sharing this LAN too, and they
          // are behind the same feed. It also keeps occupancy derived from
          // orders correct, which a raw delete would not.
          _applier.applyOne(entity: entity, action: 'delete', entityId: id);
          swept++;
        }
      }

      // The snapshot's cursor, even when it sits *below* the terminal's own:
      // the rows in between are then simply redelivered by the next pull, and
      // anything this sweep removed that the server actually still has comes
      // back with them. Keeping a higher cursor would skip that repair.
      _db.syncCursor = cursor;

      _db.setMeta(_fullKey, '0');
      // Subtract what this pass actually swept rather than clearing the key:
      // a refusal recorded by a pull *during* the walk has not been repaired
      // by it, and wiping the key wholesale would drop that request on the
      // floor — leaving the very divergence the flag was raised for.
      final outstanding = _refusedEntities.difference(targets);
      _db.setMeta(_entitiesKey, outstanding.join(','));
      _db.setMeta(_cursorKey, '0');
      _db.setMeta(_entityKey, '');
      _db.setMeta(_afterIdKey, '');
      _db.setMeta(_startedAtKey, '0');
      return swept;
    });
  }
}
