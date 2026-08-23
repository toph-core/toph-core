/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 2 — durable storage for pending writes.
///
/// Backed by the `_outbox` table in the same SQLite file as the replica, so a
/// local write and its queue entry commit or roll back together. That atomicity
/// is the whole reason the queue lives in the database rather than beside it:
/// a row the UI shows but that nothing will ever send, or a queued send with no
/// local row behind it, are both worse than either alone.
library;

import 'dart:convert';
import 'dart:math';

import '../db/entity_registry.dart';
import '../db/local_database.dart';
import 'outbox_operation.dart';

class OutboxStore {
  final LocalDatabase _db;
  final Random _random;

  /// Injectable so tests can drive backoff and readiness deterministically.
  final DateTime Function() _now;

  OutboxStore(
    this._db, {
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random();

  /// Matches the retry envelope the Hive queue this replaces already used, so
  /// replay pacing against the server does not change with the storage swap.
  static const baseBackoff = Duration(seconds: 5);
  static const maxBackoff = Duration(minutes: 2);

  /// Attempts before an operation stops retrying on its own.
  ///
  /// With the envelope above, eight attempts spans roughly ten minutes of
  /// wall clock — long enough to ride out a router reboot or a deploy, short
  /// enough that a genuinely broken write reaches a human the same shift.
  static const maxAttempts = 8;

  /// Queues a write. Returns the operation id.
  ///
  /// Call inside [LocalDatabase.transaction] together with the local row write
  /// — see `LocalWriter`, which is the only thing that should call this
  /// directly.
  String enqueue({
    required String id,
    required String entity,
    required String action,
    String? entityId,
    Map<String, dynamic> payload = const {},
  }) {
    _db.executeOn(
      LocalTables.outbox,
      'INSERT OR REPLACE INTO ${LocalTables.outbox} '
      '(id, entity, action, entity_id, payload, created_at, attempts, '
      ' next_attempt_at, last_error, status) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, 0, NULL, ?)',
      [
        id,
        entity,
        action,
        entityId,
        jsonEncode(payload),
        _now().millisecondsSinceEpoch,
        OutboxStatus.pending.name,
      ],
    );
    return id;
  }

  /// Operations eligible to send right now, oldest first.
  ///
  /// Global FIFO by creation time, **not** grouped by entity or action. Causal
  /// order is creation order — an order exists before its items, its items
  /// before its payment — so replaying in the sequence the cashier produced
  /// preserves those dependencies without encoding any of them. Grouping by
  /// type, which the Hive queue did, actively breaks this: it reorders a
  /// pause→resume→pause timer sequence into something that never happened.
  /// Operations due for a send attempt, oldest first.
  ///
  /// The tie-break is `rowid`, not `id`, and that is the whole point.
  /// `created_at` is millisecond resolution while `id` is a random UUID, so two
  /// operations enqueued inside the same millisecond — an order and its own
  /// line items, which is the common case, since they are written in one
  /// synchronous call — sorted in *random* order. When a line sorted ahead of
  /// the order that owns it, the server was asked to attach a line to an order
  /// it had never heard of; that is a 4xx, which this outbox treats as
  /// permanent, so the line was dropped and never retried.
  ///
  /// The chain-key mechanism in `OutboxDrainer` does not save this. It holds a
  /// chain back once one of its operations has *failed*, which is one pass too
  /// late — within a single pass the drainer iterates in exactly this order.
  ///
  /// `rowid` is sqlite's implicit insertion counter (this table has a TEXT
  /// primary key, so it is a rowid table and one exists). It is monotonic per
  /// insert, which makes replay order equal enqueue order and makes causality a
  /// property of the queue rather than something each handler has to defend.
  List<OutboxOperation> ready({int limit = 100}) {
    final rows = _db.select(
      'SELECT * FROM ${LocalTables.outbox} '
      'WHERE status = ? AND next_attempt_at <= ? '
      'ORDER BY created_at ASC, rowid ASC LIMIT ?',
      [OutboxStatus.pending.name, _now().millisecondsSinceEpoch, limit],
    );
    return [for (final row in rows) OutboxOperation.fromRow(row)];
  }

  /// Every pending operation, ready or backing off — for queue-depth display.
  /// Replaces every reference to [oldId] with [newId] across operations that
  /// have not been sent.
  ///
  /// This is what makes a provisional id safe to reference before the server
  /// has spoken. A meal queued with `name_i18n` pointing at a locally-invented
  /// translation id is rewritten the moment that translation's real id arrives,
  /// so the server receives a body that points at a row it knows about.
  ///
  /// The match is on whole string values rather than a substring replace: ids
  /// are UUIDs, and a substring pass would happily corrupt a description that
  /// merely quoted one.
  ///
  /// Only `pending` rows are touched. An operation already sent cannot be
  /// amended, and a quarantined one is waiting on a human who should see what
  /// was actually attempted.
  int rewriteReferences({required String oldId, required String newId}) {
    if (oldId == newId || oldId.isEmpty) return 0;
    final rows = _db.select(
      'SELECT id, entity_id, payload FROM ${LocalTables.outbox} '
      'WHERE status = ?',
      [OutboxStatus.pending.name],
    );
    var changed = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      final entityId = row['entity_id'] as String?;
      final decoded = _decodePayload(row['payload'] as String?);
      final rewritten = _replaceIds(decoded, oldId, newId);
      final newEntityId = entityId == oldId ? newId : entityId;

      final payloadChanged = !identical(rewritten, decoded);
      if (!payloadChanged && newEntityId == entityId) continue;

      _db.executeOn(
        LocalTables.outbox,
        'UPDATE ${LocalTables.outbox} SET entity_id = ?, payload = ? '
        'WHERE id = ?',
        [newEntityId, jsonEncode(rewritten), id],
      );
      changed++;
    }
    return changed;
  }

  Map<String, dynamic> _decodePayload(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Returns the same instance when nothing matched, so callers can skip a
  /// write with `identical`.
  static Object? _replaceIds(Object? node, String oldId, String newId) {
    if (node is String) return node == oldId ? newId : node;
    if (node is List) {
      List<Object?>? copy;
      for (var i = 0; i < node.length; i++) {
        final replaced = _replaceIds(node[i], oldId, newId);
        if (!identical(replaced, node[i])) {
          copy ??= List<Object?>.from(node);
          copy[i] = replaced;
        }
      }
      return copy ?? node;
    }
    if (node is Map) {
      Map<String, dynamic>? copy;
      for (final entry in node.entries) {
        final replaced = _replaceIds(entry.value, oldId, newId);
        if (!identical(replaced, entry.value)) {
          copy ??= Map<String, dynamic>.from(node);
          copy[entry.key.toString()] = replaced;
        }
      }
      return copy ?? node;
    }
    return node;
  }

  List<OutboxOperation> pending({int limit = 500}) {
    final rows = _db.select(
      'SELECT * FROM ${LocalTables.outbox} WHERE status = ? '
      'ORDER BY created_at ASC LIMIT ?',
      [OutboxStatus.pending.name, limit],
    );
    return [for (final row in rows) OutboxOperation.fromRow(row)];
  }

  List<OutboxOperation> quarantined({int limit = 200}) {
    final rows = _db.select(
      'SELECT * FROM ${LocalTables.outbox} WHERE status = ? '
      'ORDER BY created_at DESC LIMIT ?',
      [OutboxStatus.quarantined.name, limit],
    );
    return [for (final row in rows) OutboxOperation.fromRow(row)];
  }

  int get depth => _countWhere(OutboxStatus.pending);

  int get quarantineDepth => _countWhere(OutboxStatus.quarantined);

  bool get hasWork => depth > 0;

  int _countWhere(OutboxStatus status) {
    final rows = _db.select(
      'SELECT COUNT(*) AS n FROM ${LocalTables.outbox} WHERE status = ?',
      [status.name],
    );
    return (rows.first['n'] as num).toInt();
  }

  /// The server accepted it. The row is removed — a sent operation has no
  /// further use, and the replica now holds the authoritative version.
  void markSucceeded(String id) {
    _db.executeOn(
      LocalTables.outbox,
      'DELETE FROM ${LocalTables.outbox} WHERE id = ?',
      [id],
    );
  }

  /// A retryable failure: schedule the next attempt, or quarantine once the
  /// attempt budget is spent.
  void markFailed(String id, String error) {
    final current = _byId(id);
    if (current == null) return;
    final attempts = current.attempts + 1;

    if (attempts >= maxAttempts) {
      _quarantine(id, attempts, error);
      return;
    }

    _db.executeOn(
      LocalTables.outbox,
      'UPDATE ${LocalTables.outbox} '
      'SET attempts = ?, next_attempt_at = ?, last_error = ? WHERE id = ?',
      [
        attempts,
        _now().add(_backoffFor(attempts)).millisecondsSinceEpoch,
        error,
        id,
      ],
    );
  }

  /// A failure that retrying cannot fix — a validation rejection, a malformed
  /// payload. Quarantined immediately rather than burning eight attempts on a
  /// request the server will refuse identically every time.
  void markPermanentlyFailed(String id, String error) {
    final current = _byId(id);
    if (current == null) return;
    _quarantine(id, current.attempts + 1, error);
  }

  void _quarantine(String id, int attempts, String error) {
    _db.executeOn(
      LocalTables.outbox,
      'UPDATE ${LocalTables.outbox} '
      'SET status = ?, attempts = ?, last_error = ? WHERE id = ?',
      [OutboxStatus.quarantined.name, attempts, error, id],
    );
  }

  /// Human resolution: put a quarantined operation back in line with a clean
  /// attempt budget.
  void retryQuarantined(String id) {
    _db.executeOn(
      LocalTables.outbox,
      'UPDATE ${LocalTables.outbox} '
      'SET status = ?, attempts = 0, next_attempt_at = 0, last_error = NULL '
      'WHERE id = ? AND status = ?',
      [OutboxStatus.pending.name, id, OutboxStatus.quarantined.name],
    );
  }

  /// Human resolution: discard it for good.
  void dismissQuarantined(String id) {
    _db.executeOn(
      LocalTables.outbox,
      'DELETE FROM ${LocalTables.outbox} WHERE id = ? AND status = ?',
      [id, OutboxStatus.quarantined.name],
    );
  }

  /// Clears every backoff so the next drain tries everything — for a
  /// user-pressed "sync now", where waiting out a backoff from an outage that
  /// has since ended would defeat the point of pressing it.
  void clearBackoff() {
    _db.executeOn(
      LocalTables.outbox,
      'UPDATE ${LocalTables.outbox} SET next_attempt_at = 0 WHERE status = ?',
      [OutboxStatus.pending.name],
    );
  }

  OutboxOperation? _byId(String id) {
    final rows = _db.select(
      'SELECT * FROM ${LocalTables.outbox} WHERE id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : OutboxOperation.fromRow(rows.first);
  }

  /// Exponential with full jitter, capped.
  ///
  /// Jitter matters more here than in a single-client system: when a venue's
  /// terminals all lose the leader or the uplink at the same instant, an
  /// unjittered backoff reconnects them in lockstep and they retry as a burst.
  Duration _backoffFor(int attempts) {
    final exponent = min(attempts, 5);
    final raw = baseBackoff.inMilliseconds * pow(2, exponent).toInt();
    final capped = min(raw, maxBackoff.inMilliseconds);
    return Duration(milliseconds: capped ~/ 2 + _random.nextInt(capped ~/ 2 + 1));
  }
}
