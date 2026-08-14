/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 0 — the single local database.
///
/// This is the application's **one** source of truth, replacing both stores the
/// architecture review found (`CacheService`'s `pos_cache` blob box and the
/// Hive `LocalDatabase`). It is a replica of the tenant database, not a cache
/// of API responses: rows arrive from the change-log feed and are stored in the
/// server's own shape.
///
/// ## Why raw `sqlite3` and not Drift
///
/// The plan named Drift. Building it exposed a better fit:
///
/// * The inbound shape is uniform (`entity`, `action`, `payload`), so the
///   schema is generated from [kReplicatedEntities] rather than written 35
///   times. Drift's value is compile-time-typed columns, which a
///   registry-driven schema cannot use anyway.
/// * Drift requires `build_runner`, and this repo commits its generated files.
///   A codegen step that has to run before the tree compiles is a sharp edge on
///   a foundational layer.
/// * `package:sqlite3` is **synchronous**. A screen can read the database
///   inside `build()` with no `await` and no `FutureBuilder` — which is exactly
///   the "always feels local" property the architecture is for. An async
///   database would have reintroduced a loading state on every screen, in the
///   name of offline-first.
///
/// Reactivity, the one thing Drift would have given us for free, is ~40 lines
/// here ([watch]) because invalidation is per-table and writes are already
/// funnelled through this class.
library;

import 'dart:async';
import 'dart:convert';

// `sqlite3` exports its own `SqlType` (the C-level column type constants).
// This layer's `SqlType` is the schema-registry enum that drives column
// generation, and it is the one every call site here means, so the package's
// is hidden rather than prefixed.
import 'package:sqlite3/sqlite3.dart' hide SqlType;

import 'entity_registry.dart';

/// Opens, migrates and serves the local replica.
///
/// Threading: `package:sqlite3` is synchronous and this class is not
/// thread-safe. It is used from the main isolate only — every read is fast
/// enough to stay there (indexed lookups over a venue-sized dataset), and the
/// sync engine's network work happens off the database entirely, touching it
/// only to apply a finished batch.
class LocalDatabase {
  final Database _db;

  /// Broadcasts the set of table names touched by each committed write.
  /// [watch] filters this; nothing else should listen directly.
  final StreamController<Set<String>> _changes =
      StreamController<Set<String>>.broadcast();

  /// Tables written during the current transaction, flushed on commit so a
  /// 500-row pull batch produces one notification per table, not 500.
  final Set<String> _pendingNotify = {};
  int _txDepth = 0;

  LocalDatabase._(this._db);

  /// Current schema version. Bump when [_migrate] gains a step.
  static const schemaVersion = 3;

  /// Opens the database at [path], creating and migrating the schema.
  /// Pass `:memory:` for tests.
  factory LocalDatabase.open(String path) {
    final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
    final instance = LocalDatabase._(db);
    instance._configure();
    instance._migrate();
    return instance;
  }

  void _configure() {
    // WAL keeps readers from blocking on the sync engine's write batches — the
    // UI must never stall behind replication.
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA synchronous = NORMAL');
    _db.execute('PRAGMA foreign_keys = OFF');
  }

  /// Builds the schema from the registry.
  ///
  /// Deliberately **not** foreign-keyed between replicated tables. The feed
  /// delivers rows in change-log order, so a child row can legitimately arrive
  /// before its parent; enforcing referential integrity locally would reject
  /// rows the server considers valid. Integrity is the server's job — this is a
  /// replica.
  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.meta} (
        key   TEXT PRIMARY KEY NOT NULL,
        value TEXT
      )
    ''');

    // The outbox. Phase 2 owns the drain logic; the table lives here because
    // "one database" means the queue is in it too, not in a second store.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.outbox} (
        id              TEXT PRIMARY KEY NOT NULL,
        entity          TEXT NOT NULL,
        action          TEXT NOT NULL,
        entity_id       TEXT,
        payload         TEXT NOT NULL,
        created_at      INTEGER NOT NULL,
        attempts        INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL DEFAULT 0,
        last_error      TEXT,
        status          TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_outbox_ready '
      'ON ${LocalTables.outbox}(status, next_attempt_at)',
    );

    // Rows written locally and not yet confirmed by the server. `applyChange`
    // refuses to overwrite these, so a replication pass can never stomp an edit
    // the cashier just made but that hasn't round-tripped yet.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.pending} (
        entity    TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        since     INTEGER NOT NULL,
        PRIMARY KEY (entity, entity_id)
      )
    ''');

    // Rows waiting for the server to tell us their real id.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.provisional} (
        entity   TEXT NOT NULL,
        local_id TEXT NOT NULL,
        since    INTEGER NOT NULL,
        PRIMARY KEY (entity, local_id)
      )
    ''');

    // Local-authority table occupancy. Never written by replication, never
    // read from the feed — see [LocalTables.tableStatus].
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.tableStatus} (
        table_id   TEXT PRIMARY KEY NOT NULL,
        status     TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    for (final spec in kReplicatedEntities) {
      final columns = <String>[
        'id TEXT PRIMARY KEY NOT NULL',
        for (final c in spec.promoted) '${c.name} ${c.sqlType}',
        // Present on every table for uniformity even where the server row has
        // no such column; it simply stays NULL there.
        'deleted_at INTEGER',
        'data TEXT NOT NULL',
        'synced_at INTEGER NOT NULL',
      ];
      _db.execute(
        'CREATE TABLE IF NOT EXISTS ${spec.name} (${columns.join(', ')})',
      );
      for (final c in spec.promoted.where((c) => c.indexed)) {
        _db.execute(
          'CREATE INDEX IF NOT EXISTS idx_${spec.name}_${c.name} '
          'ON ${spec.name}(${c.name})',
        );
      }
      _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${spec.name}_deleted '
        'ON ${spec.name}(deleted_at)',
      );
    }

    setMeta('schema_version', '$schemaVersion');
  }

  // ── Reactive reads ─────────────────────────────────────────────────────

  /// The UI contract: a stream that emits [read]'s result immediately, then
  /// again whenever any of [tables] changes.
  ///
  /// Repositories build typed streams on this; screens never call it directly.
  /// [read] runs synchronously against the current state, so the first frame
  /// after subscribing already has data — there is no loading state to render.
  Stream<T> watch<T>(Set<String> tables, T Function() read) {
    return Stream.multi((controller) {
      void emit() {
        try {
          controller.add(read());
        } catch (e, st) {
          controller.addError(e, st);
        }
      }

      emit();
      final sub = _changes.stream
          .where((changed) => changed.any(tables.contains))
          .listen((_) => emit());
      controller.onCancel = sub.cancel;
    });
  }

  /// Runs an arbitrary query. Returns plain maps so callers can feed rows
  /// straight into existing `fromJson` constructors.
  List<Map<String, Object?>> select(String sql, [List<Object?> params = const []]) {
    final result = _db.select(sql, params);
    return [for (final row in result) Map<String, Object?>.from(row)];
  }

  /// Decodes the stored server row for each result of [sql].
  ///
  /// The `data` column holds the complete normalized row, so this is what most
  /// repository reads want: query on promoted columns, decode the full entity.
  List<Map<String, dynamic>> selectData(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final rows = _db.select(sql, params);
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['data'];
      if (raw is! String) continue;
      final decoded = _tryDecode(raw);
      if (decoded != null) out.add(decoded);
    }
    return out;
  }

  /// All live (not soft-deleted) rows of [entity].
  List<Map<String, dynamic>> allOf(String entity, {String? orderBy}) {
    final order = orderBy == null ? '' : ' ORDER BY $orderBy';
    return selectData('SELECT data FROM $entity WHERE deleted_at IS NULL$order');
  }

  /// One row by primary key, or null. Returns soft-deleted rows as null.
  Map<String, dynamic>? byId(String entity, String id) {
    final rows = selectData(
      'SELECT data FROM $entity WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // A row that cannot be decoded is treated as absent rather than fatal;
      // the next pull that touches it will overwrite it.
      return null;
    }
  }

  // ── Writes ─────────────────────────────────────────────────────────────

  /// Inserts or replaces a replicated row. [data] must already be normalized
  /// ([PayloadNormalizer]); this method does no transformation.
  void upsert(EntitySpec spec, String id, Map<String, dynamic> data) {
    final columns = <String>['id', for (final c in spec.promoted) c.name]
      ..addAll(['deleted_at', 'data', 'synced_at']);
    final values = <Object?>[
      id,
      for (final c in spec.promoted) _coerce(data[c.name], c.type),
      _deletedAt(data),
      jsonEncode(data),
      DateTime.now().millisecondsSinceEpoch,
    ];
    final placeholders = List.filled(columns.length, '?').join(', ');
    _db.execute(
      'INSERT OR REPLACE INTO ${spec.name} (${columns.join(', ')}) '
      'VALUES ($placeholders)',
      values,
    );
    _touch(spec.name);
  }

  /// Hard-deletes a row. Used for change-log `delete` actions — the server has
  /// removed the row, so keeping a tombstone would only make local queries
  /// filter it out forever.
  void deleteRow(String entity, String id) {
    _db.execute('DELETE FROM $entity WHERE id = ?', [id]);
    _touch(entity);
  }

  /// Runs a statement against a local-only table and wakes its watchers.
  ///
  /// The narrow seam `OutboxStore` needs: replicated rows are written through
  /// [upsert]/[deleteRow], but `_outbox` has its own columns and lifecycle and
  /// does not belong in the entity registry. Notification still routes through
  /// [_touch] so a queue-depth indicator observes the outbox exactly the way a
  /// screen observes `goods` — and so a write inside [transaction] coalesces
  /// with the rest of the batch.
  void executeOn(String table, String sql, [List<Object?> params = const []]) {
    _db.execute(sql, params);
    _touch(table);
  }

  /// The local soft-delete marker: NULL for a live row, epoch seconds for a
  /// deleted one.
  ///
  /// **Zero means live, and must be stored as NULL.** `deleted_at` is
  /// `BIGINT DEFAULT 0` across the tenant schema, so `to_jsonb(NEW)` puts
  /// `"deleted_at": 0` in the payload of every live row — while every local
  /// read filters `WHERE deleted_at IS NULL`. Passing the 0 through stored it
  /// verbatim, and `0 IS NULL` is false, so every replicated live row was
  /// written to the database and then invisible to all 16 of those reads.
  ///
  /// It went unnoticed because no test fixture ever had the shape the server
  /// actually sends: fixtures omit `deleted_at` entirely, which stores NULL and
  /// reads back fine. `deletedAtOf` in [PayloadNormalizer] carries the same
  /// mapping for the same reason.
  int? _deletedAt(Map<String, dynamic> data) {
    final raw = data['deleted_at'];
    if (raw == null) return null;
    final value = switch (raw) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };
    return (value == null || value == 0) ? null : value;
  }

  /// Maps a JSON value onto a promoted column's storage class.
  ///
  /// Booleans become 0/1 (SQLite has no boolean); maps and lists are stored as
  /// their JSON text so a promoted column can never fail on an unexpected
  /// shape. Everything else passes through, letting SQLite's dynamic typing
  /// handle the common cases.
  static Object? _coerce(Object? value, SqlType type) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is Map || value is List) return jsonEncode(value);
    switch (type) {
      case SqlType.text:
        return value is String ? value : value.toString();
      case SqlType.integer:
        if (value is int) return value;
        if (value is num) return value.toInt();
        return int.tryParse(value.toString());
      case SqlType.real:
        if (value is num) return value.toDouble();
        return double.tryParse(value.toString());
    }
  }

  // ── Transactions ───────────────────────────────────────────────────────

  /// Runs [body] in a transaction, coalescing change notifications so the whole
  /// batch produces one event per touched table on commit — and none at all if
  /// it rolls back. Nested calls join the outer transaction.
  T transaction<T>(T Function() body) {
    if (_txDepth > 0) return body();

    _db.execute('BEGIN');
    _txDepth++;
    var committed = false;
    try {
      final result = body();
      _db.execute('COMMIT');
      committed = true;
      return result;
    } finally {
      // The depth counter is restored in `finally` rather than on each exit
      // path: if a ROLLBACK were to throw, an unbalanced counter would leave
      // every later transaction() call taking the "already in a transaction"
      // branch, silently dropping atomicity for the rest of the session.
      if (!committed) {
        try {
          _db.execute('ROLLBACK');
        } catch (_) {
          // Swallowed so a failed rollback cannot mask the original error.
        }
        _pendingNotify.clear();
      }
      _txDepth--;
      if (committed) _flushNotify();
    }
  }

  void _touch(String table) {
    if (_txDepth > 0) {
      _pendingNotify.add(table);
    } else {
      _changes.add({table});
    }
  }

  void _flushNotify() {
    if (_pendingNotify.isEmpty) return;
    final touched = Set<String>.from(_pendingNotify);
    _pendingNotify.clear();
    _changes.add(touched);
  }

  // ── Local table occupancy ──────────────────────────────────────────────

  /// Records a table as free/busy/away. Local authority — see
  /// [LocalTables.tableStatus].
  ///
  /// Notifies `cafe_tables` watchers rather than its own table name, because
  /// every consumer reads occupancy *through* a table query. One notification
  /// key means a status change and a floor-plan edit wake the same streams,
  /// and no caller has to subscribe to both.
  void setTableStatus(String tableId, String status) {
    _db.execute(
      'INSERT OR REPLACE INTO ${LocalTables.tableStatus} '
      '(table_id, status, updated_at) VALUES (?, ?, ?)',
      [tableId, status, DateTime.now().millisecondsSinceEpoch],
    );
    _touch('cafe_tables');
  }

  /// Every locally-known occupancy, as `tableId → status`.
  Map<String, String> tableStatuses() {
    final rows = _db.select(
      'SELECT table_id, status FROM ${LocalTables.tableStatus}',
    );
    return {
      for (final row in rows) row['table_id'] as String: row['status'] as String,
    };
  }

  /// Drops occupancy for tables that no longer exist, so the overlay does not
  /// accumulate rows for deleted tables forever.
  void pruneTableStatuses() {
    _db.execute(
      'DELETE FROM ${LocalTables.tableStatus} WHERE table_id NOT IN '
      '(SELECT id FROM cafe_tables)',
    );
  }

  // ── Provisional ids ────────────────────────────────────────────────────

  /// Marks [localId] as a client-invented stand-in for a server-assigned id.
  void markProvisional(String entity, String localId) {
    _db.execute(
      'INSERT OR REPLACE INTO ${LocalTables.provisional} '
      '(entity, local_id, since) VALUES (?, ?, ?)',
      [entity, localId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  bool isProvisional(String entity, String localId) => _db
      .select(
        'SELECT 1 FROM ${LocalTables.provisional} '
        'WHERE entity = ? AND local_id = ? LIMIT 1',
        [entity, localId],
      )
      .isNotEmpty;

  void clearProvisional(String entity, String localId) {
    _db.execute(
      'DELETE FROM ${LocalTables.provisional} '
      'WHERE entity = ? AND local_id = ?',
      [entity, localId],
    );
  }

  // ── Local-write guard ──────────────────────────────────────────────────

  /// Marks a row as locally modified and not yet confirmed by the server.
  void markPending(String entity, String entityId) {
    _db.execute(
      'INSERT OR REPLACE INTO ${LocalTables.pending} (entity, entity_id, since) '
      'VALUES (?, ?, ?)',
      [entity, entityId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  /// Clears the guard once the server has acknowledged the write, letting the
  /// next pull overwrite the row with the authoritative version.
  void clearPending(String entity, String entityId) {
    _db.execute(
      'DELETE FROM ${LocalTables.pending} WHERE entity = ? AND entity_id = ?',
      [entity, entityId],
    );
  }

  bool isPending(String entity, String entityId) {
    final rows = _db.select(
      'SELECT 1 FROM ${LocalTables.pending} '
      'WHERE entity = ? AND entity_id = ? LIMIT 1',
      [entity, entityId],
    );
    return rows.isNotEmpty;
  }

  // ── Meta ───────────────────────────────────────────────────────────────

  String? getMeta(String key) {
    final rows = _db.select(
      'SELECT value FROM ${LocalTables.meta} WHERE key = ? LIMIT 1',
      [key],
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'];
    return value is String ? value : null;
  }

  void setMeta(String key, String value) {
    _db.execute(
      'INSERT OR REPLACE INTO ${LocalTables.meta} (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  /// The replication cursor — `last_sync_cursor` for the next `POST /sync/pull`.
  /// Zero means "never synced", which is what triggers first-login bootstrap.
  int get syncCursor => int.tryParse(getMeta(_cursorKey) ?? '') ?? 0;

  set syncCursor(int value) => setMeta(_cursorKey, '$value');

  /// Whether first-login bootstrap has completed. Until it has, the app has no
  /// data and the sync engine keeps pulling from the cursor it left off at.
  bool get isBootstrapped => getMeta(_bootstrapKey) == '1';

  void markBootstrapped() => setMeta(_bootstrapKey, '1');

  static const _cursorKey = 'sync_cursor';
  static const _bootstrapKey = 'bootstrap_complete';

  /// Wipes every replicated row and resets the cursor.
  ///
  /// Used on brand/branch switch and on logout: the replica describes one
  /// tenant, so carrying it across a login to a different one would show the
  /// previous tenant's data. Local-only tables are cleared too — an outbox
  /// belonging to a different tenant must never be replayed into this one.
  void clearAll() {
    transaction(() {
      // Rows waiting for the server to tell us their real id.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.provisional} (
        entity   TEXT NOT NULL,
        local_id TEXT NOT NULL,
        since    INTEGER NOT NULL,
        PRIMARY KEY (entity, local_id)
      )
    ''');

    // Local-authority table occupancy. Never written by replication, never
    // read from the feed — see [LocalTables.tableStatus].
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.tableStatus} (
        table_id   TEXT PRIMARY KEY NOT NULL,
        status     TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    for (final spec in kReplicatedEntities) {
        _db.execute('DELETE FROM ${spec.name}');
        _touch(spec.name);
      }
      _db.execute('DELETE FROM ${LocalTables.outbox}');
      _db.execute('DELETE FROM ${LocalTables.pending}');
      _db.execute('DELETE FROM ${LocalTables.meta}');
      setMeta('schema_version', '$schemaVersion');
    });
  }

  /// Row counts per replicated table — for the sync-status screen and tests.
  Map<String, int> tableCounts() {
    final out = <String, int>{};
    // Rows waiting for the server to tell us their real id.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.provisional} (
        entity   TEXT NOT NULL,
        local_id TEXT NOT NULL,
        since    INTEGER NOT NULL,
        PRIMARY KEY (entity, local_id)
      )
    ''');

    // Local-authority table occupancy. Never written by replication, never
    // read from the feed — see [LocalTables.tableStatus].
    _db.execute('''
      CREATE TABLE IF NOT EXISTS ${LocalTables.tableStatus} (
        table_id   TEXT PRIMARY KEY NOT NULL,
        status     TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    for (final spec in kReplicatedEntities) {
      final rows = _db.select('SELECT COUNT(*) AS n FROM ${spec.name}');
      out[spec.name] = (rows.first['n'] as num).toInt();
    }
    return out;
  }

  void dispose() {
    _changes.close();
    _db.dispose();
  }
}
