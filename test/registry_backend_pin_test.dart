/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §1 — the registry, pinned to the backend
/// that actually feeds it.
///
/// `kReplicatedEntities` is a claim about another repository: "the tenant
/// database has a `trg_change_log_*` trigger on this table, so `/sync/pull`
/// will deliver it." Nothing checked that claim, and it drifted. Four entities
/// — `transactions`, `group_transactions`, `cash_registers`,
/// `ingredient_visibility` — were listed as replicated with a comment citing
/// "tenants migration 70 (change_log_missing_triggers)". The backend's tenant
/// 70 is `70_order_items_client_id`. The migration named in that comment has
/// never been merged. The result was three screens and a tech-card ingredient
/// picker rendering a permanently empty list that looks exactly like real,
/// empty data — the worst failure shape available, because nothing is red.
///
/// So this test stops asserting against a hand-maintained list (which is what
/// `local_database_test.dart`'s `loggedByBackend` set does, and it admits as
/// much in its own comment) and reads the backend's migration SQL instead.
///
/// ## What it checks — both directions, both ratcheted
///
///  1. Every entity marked [ReplicationStatus.live] really has a trigger.
///  2. Every entity marked [ReplicationStatus.pendingBackendTrigger] really
///     has none. **This is the countdown.** When the backend adds the trigger,
///     this fails and names the entity to flip. The pending set cannot rot,
///     because the only way to keep the suite green is to shrink it.
///  3. Every table the backend logs is either replicated or in
///     [kIntentionallyNotReplicated] with a written reason — a new backend
///     trigger cannot land unnoticed.
///  4. [kIntentionallyNotReplicated] has no stale entries: an entry that is no
///     longer logged, or that the registry now mirrors, fails.
///  5. `EntitySpec.pk` matches the argument the trigger passes to
///     `log_change()`, which is what the feed reports as `entity_id`.
///
/// ## When the backend checkout is not there
///
/// The backend is a sibling clone, not a dependency. A machine without it —
/// CI, a fresh laptop — must not go red for that, so the group is skipped with
/// a message naming the paths that were tried and the env var that overrides
/// them. The parser's own tests run regardless, against inline SQL, so a
/// change to the parsing logic is still covered on such a machine.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';

/// Tables the backend logs on purpose and this client does not mirror.
///
/// Not an allowlist of debt in the same sense as the pending set above: this
/// is a genuine scope decision, and it is expected to have entries. Each one
/// still has to say why, and (4) above deletes it the moment it stops being
/// true.
const Map<String, String> kIntentionallyNotReplicated = {
  // All five arrived with 71_change_log_triggers_batch2.up.sql. Four of the
  // nine tables that migration covers were already in the registry and are
  // what it was written for; these five are ahead of the client, and each is
  // a screen's worth of work rather than a registry line.
  'table_time_sessions':
      'The local-authority billing engine stores timers in '
      "LocalTables.tableTimers, whose shape is not this table's — see the doc "
      'on that constant. SyncEngine._fillFeedGaps still hydrates from REST. '
      'Replicating this is the change that deletes that per-order call, and '
      'it needs the engine reworked, not an EntitySpec.',
  'modifiers':
      'Nothing in the client reads a modifier catalogue yet. '
      '`modifier_calculation` and `order_item_modifiers` are replicated '
      'because the tech-card and order-line shapes reference them, but no '
      'screen renders a modifier name or price, so a mirror would have no '
      'reader.',
  'goods_modifiers':
      'The good→modifier join, unreadable for the same reason '
      'as `modifiers` above: add both together when the order screen grows '
      'modifier support.',
  'printer_settings':
      'Printer settings are still fetched over REST '
      '(MainDataSources.getPrinterSettings) and written over REST '
      '(pushPrinterSetting/deletePrinterSetting — one of the outbox bypasses '
      'write_path_guard_test.dart counts). The read and the write move '
      'together, per the plan; neither has.',
  'cash_register_shifts':
      'The shift flow runs over REST '
      '(openShift/closeShift/checkShift) with the legacy OfflineQueueService '
      'carrying the offline half. Nothing reads a local shift row. Note the '
      'legacy `shifts` table is gone entirely — 55_employee_module.up.sql '
      'drops it — so this is the only shift entity the feed can offer.',
};

/// Where the backend clone is expected to sit, relative to this package root.
///
/// Ordered by how likely each is; the first hit wins. `MARY_AI_BACKEND_DIR`
/// overrides all of them, which is what a CI job that does check the backend
/// out should set.
const List<String> kBackendCandidatePaths = [
  '../back',
  '../mary-ai-backend',
  '../../back',
  '../../mary-ai-backend',
];

/// One `trg_change_log_*` trigger, reduced to the two things the client cares
/// about: which table it watches, and which column it reports as `entity_id`.
typedef ChangeLogTrigger = ({String table, String pk});

/// The backend's tenant migrations, read as a sequence of trigger statements.
///
/// Deliberately *not* a grep for `CREATE TRIGGER`. Migrations replay in order
/// and a later one may drop what an earlier one created, so the only correct
/// answer is the state after replaying every statement in order — which is
/// also what makes this robust against however the backend agent chooses to
/// write the migration that closes the current gap.
class BackendMigrations {
  /// Trigger name → what it watches. Keyed by trigger name because that is
  /// what `DROP TRIGGER` names.
  final Map<String, ChangeLogTrigger> triggers;

  const BackendMigrations(this.triggers);

  /// Tables that end up with a change-log trigger after the full replay.
  Set<String> get loggedTables => {for (final t in triggers.values) t.table};

  /// Table → the `log_change()` argument, i.e. the payload key the feed
  /// reports as `entity_id`.
  Map<String, String> get primaryKeys => {
    for (final t in triggers.values) t.table: t.pk,
  };

  /// The backend checkout, or null if it is not beside this one.
  static Directory? locate() {
    final override = Platform.environment['MARY_AI_BACKEND_DIR'];
    for (final path in [?override, ...kBackendCandidatePaths]) {
      final dir = Directory('$path/app/migrations/tenants');
      if (dir.existsSync()) return dir;
    }
    return null;
  }

  /// Replays every `*.up.sql` in [tenantsDir], in migration-number order.
  ///
  /// Only `.up.sql` is read. A `.down.sql` describes a rollback that has not
  /// happened; treating it as state would make every migration that ships a
  /// down file look like it had already been reverted.
  factory BackendMigrations.replay(Directory tenantsDir) {
    final files =
        tenantsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.up.sql'))
            .toList()
          ..sort((a, b) => _migrationNumber(a).compareTo(_migrationNumber(b)));

    final triggers = <String, ChangeLogTrigger>{};
    for (final file in files) {
      applyStatements(file.readAsStringSync(), triggers);
    }
    return BackendMigrations(triggers);
  }

  /// `70_order_items_client_id.up.sql` → 70. Files that do not start with a
  /// number sort last under a sentinel rather than throwing, since a
  /// non-conforming filename is the backend's business, not a client failure.
  static int _migrationNumber(File file) {
    final name = file.uri.pathSegments.last;
    return int.tryParse(RegExp(r'^\d+').stringMatch(name) ?? '') ?? 1 << 30;
  }

  /// Applies one SQL file's statements onto [triggers], in textual order.
  ///
  /// Order within the file matters as much as order between files:
  /// `8_movements.up.sql` writes `DROP TRIGGER IF EXISTS x; CREATE TRIGGER x
  /// ...` for every table, so a pass that handled all drops before all creates
  /// would come out empty.
  ///
  /// Splitting on `;` is crude but safe here. The only statements that match
  /// either pattern are trigger DDL, which never contains an embedded
  /// semicolon; the `$$`-quoted `log_change()` body does get chopped into
  /// fragments, and none of the fragments matches.
  static void applyStatements(
    String sql,
    Map<String, ChangeLogTrigger> triggers,
  ) {
    for (final statement in _stripSqlComments(sql).split(';')) {
      final droppedTable = _dropTable.firstMatch(statement);
      if (droppedTable != null) {
        // Dropping a table takes its triggers with it, and the migrations use
        // that instead of an explicit DROP TRIGGER at least once: migration 55
        // ends with `DROP TABLE IF EXISTS shifts CASCADE`, which is why
        // `shifts` is not in the feed even though 8_movements.up.sql created a
        // trigger for it. A parser that only tracked trigger DDL would report
        // a 35th logged table that no longer exists and send someone to
        // replicate it.
        for (final name in droppedTable.group(1)!.split(',')) {
          triggers.removeWhere((_, t) => t.table == name.trim());
        }
        continue;
      }
      final dropped = _drop.firstMatch(statement);
      if (dropped != null) {
        triggers.remove(dropped.group(1));
        continue;
      }
      final created = _create.firstMatch(statement);
      if (created != null) {
        triggers[created.group(1)!] = (
          table: created.group(2)!,
          pk: created.group(3)!,
        );
      }
    }
  }

  /// `DROP TRIGGER [IF EXISTS] name ON table`. The table is not captured —
  /// a trigger name is unique per table in Postgres and the map is keyed by
  /// name, so dropping by name is exact.
  /// `DROP TABLE [IF EXISTS] a[, b] [CASCADE|RESTRICT]`.
  static final _dropTable = RegExp(
    r'DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?([\w\s,]+?)(?:\s+CASCADE|\s+RESTRICT)?\s*$',
    caseSensitive: false,
    dotAll: true,
  );

  static final _drop = RegExp(
    r'DROP\s+TRIGGER\s+(?:IF\s+EXISTS\s+)?(\w+)\s+ON\s+\w+',
    caseSensitive: false,
    dotAll: true,
  );

  /// `CREATE TRIGGER name ... ON table ... EXECUTE FUNCTION log_change('pk')`.
  ///
  /// Matching through to `log_change` is what makes this specific: the tenant
  /// schema is full of `update_*_updated_at` triggers on the same tables, and
  /// those say nothing about replication. `dotAll` because the statement is
  /// written across three lines in some migrations and one line in others.
  static final _create = RegExp(
    r"CREATE\s+TRIGGER\s+(\w+)\s+"
    r"AFTER\s+INSERT\s+OR\s+UPDATE\s+OR\s+DELETE\s+ON\s+(\w+)\s+"
    r"FOR\s+EACH\s+ROW\s+EXECUTE\s+FUNCTION\s+log_change\(\s*'(\w+)'\s*\)",
    caseSensitive: false,
    dotAll: true,
  );

  /// Removes `-- line` and `/* block */` comments.
  ///
  /// A commented-out trigger is a trigger that does not exist, and the
  /// migrations do carry explanatory comments beside this DDL.
  static String _stripSqlComments(String sql) => sql
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .replaceAll(RegExp(r'--[^\n]*'), ' ');
}

/// The `skip:` reason for the backend-dependent group, or null to run it.
///
/// Extracted so the degradation path is itself testable: the interesting case
/// — no backend checkout — cannot be produced on a machine that has one.
String? backendMissingSkipReason(Directory? tenantsDir) => tenantsDir == null
    ? 'Backend checkout not found — this group reads the tenant migrations '
          'directly. Tried ${kBackendCandidatePaths.join(', ')} relative to the '
          'package root; set MARY_AI_BACKEND_DIR to the backend clone to run '
          'it. Skipped rather than failed on purpose: the backend is a sibling '
          'clone, not a dependency of this package, so its absence is an '
          'environment fact and not a defect in this repo. The parser tests '
          'still ran.'
    : null;

void main() {
  final tenantsDir = BackendMigrations.locate();

  group('the migration parser', () {
    test('reads a single-line trigger, as 8_movements.up.sql writes them', () {
      final triggers = <String, ChangeLogTrigger>{};
      BackendMigrations.applyStatements(
        "DROP TRIGGER IF EXISTS trg_change_log_goods ON goods;\n"
        "CREATE TRIGGER trg_change_log_goods AFTER INSERT OR UPDATE OR DELETE "
        "ON goods FOR EACH ROW EXECUTE FUNCTION log_change('id');",
        triggers,
      );
      expect(BackendMigrations(triggers).loggedTables, {'goods'});
      expect(BackendMigrations(triggers).primaryKeys['goods'], 'id');
    });

    test(
      'reads a multi-line trigger, as 41_modifier_calculation.up.sql does',
      () {
        // The shape a `grep` on one line misses, and the reason the first audit
        // of this registry counted 33 backend triggers instead of 35.
        final triggers = <String, ChangeLogTrigger>{};
        BackendMigrations.applyStatements('''
DROP TRIGGER IF EXISTS trg_change_log_modifier_calculation ON modifier_calculation;
CREATE TRIGGER trg_change_log_modifier_calculation
  AFTER INSERT OR UPDATE OR DELETE ON modifier_calculation
  FOR EACH ROW EXECUTE FUNCTION log_change('id');
''', triggers);
        expect(BackendMigrations(triggers).loggedTables, {
          'modifier_calculation',
        });
      },
    );

    test('keeps the non-id primary key the trigger argument carries', () {
      final triggers = <String, ChangeLogTrigger>{};
      BackendMigrations.applyStatements(
        "CREATE TRIGGER trg_change_log_bill_daily_counters AFTER INSERT OR "
        "UPDATE OR DELETE ON bill_daily_counters FOR EACH ROW EXECUTE "
        "FUNCTION log_change('day');",
        triggers,
      );
      expect(
        BackendMigrations(triggers).primaryKeys['bill_daily_counters'],
        'day',
      );
    });

    test('ignores the updated_at triggers on the same tables', () {
      // Every catalog table has one of these. Counting them would report the
      // whole tenant schema as replicated.
      final triggers = <String, ChangeLogTrigger>{};
      BackendMigrations.applyStatements(
        'CREATE TRIGGER update_goods_updated_at BEFORE UPDATE ON goods '
        'FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();',
        triggers,
      );
      expect(triggers, isEmpty);
    });

    test('a later drop wins over an earlier create', () {
      final triggers = <String, ChangeLogTrigger>{};
      BackendMigrations.applyStatements(
        "CREATE TRIGGER trg_change_log_goods AFTER INSERT OR UPDATE OR DELETE "
        "ON goods FOR EACH ROW EXECUTE FUNCTION log_change('id');",
        triggers,
      );
      BackendMigrations.applyStatements(
        'DROP TRIGGER IF EXISTS trg_change_log_goods ON goods;',
        triggers,
      );
      expect(triggers, isEmpty);
    });

    test('dropping the table drops its trigger with it', () {
      // Exactly what happened to `shifts`: 8_movements.up.sql armed a trigger
      // on it and 55_employee_module.up.sql ends with
      // `DROP TABLE IF EXISTS shifts CASCADE`, no DROP TRIGGER anywhere. A
      // parser that missed this reports a table the client "should" replicate
      // that has not existed since migration 55.
      final triggers = <String, ChangeLogTrigger>{};
      BackendMigrations.applyStatements(
        "CREATE TRIGGER trg_change_log_shifts AFTER INSERT OR UPDATE OR DELETE "
        "ON shifts FOR EACH ROW EXECUTE FUNCTION log_change('id');",
        triggers,
      );
      BackendMigrations.applyStatements(
        'DROP TABLE IF EXISTS shifts CASCADE;',
        triggers,
      );
      expect(triggers, isEmpty);
    });

    test('a commented-out trigger does not count', () {
      final triggers = <String, ChangeLogTrigger>{};
      BackendMigrations.applyStatements('''
-- CREATE TRIGGER trg_change_log_goods AFTER INSERT OR UPDATE OR DELETE ON goods FOR EACH ROW EXECUTE FUNCTION log_change('id');
/* CREATE TRIGGER trg_change_log_halls AFTER INSERT OR UPDATE OR DELETE ON halls
   FOR EACH ROW EXECUTE FUNCTION log_change('id'); */
''', triggers);
      expect(triggers, isEmpty);
    });

    test('the function body between \$\$ markers cannot produce a trigger', () {
      // `log_change()` itself is defined in 8_movements.up.sql, above the
      // triggers, and its body is full of semicolons. Splitting on `;` chops
      // it up; none of the pieces may look like DDL.
      final triggers = <String, ChangeLogTrigger>{};
      BackendMigrations.applyStatements(r'''
CREATE OR REPLACE FUNCTION log_change() RETURNS TRIGGER AS $$
DECLARE v_id TEXT;
BEGIN
  v_id := TG_ARGV[0];
  INSERT INTO change_log(entity, action) VALUES (TG_TABLE_NAME, 'create');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
''', triggers);
      expect(triggers, isEmpty);
    });
  });

  group(
    'the registry against the backend it mirrors',
    () {
      late BackendMigrations backend;

      setUpAll(() => backend = BackendMigrations.replay(tenantsDir!));

      test('the parse found a plausible trigger set at all', () {
        // A guard on the guard. If the migration layout changes shape and the
        // parser silently matches nothing, every assertion below inverts into
        // "the client replicates too much" and reads as a client bug. Thirty
        // is well under the 35 that exist today and well over anything a
        // broken parse would return.
        expect(
          backend.loggedTables.length,
          greaterThan(30),
          reason:
              'Parsed only ${backend.loggedTables.length} change-log '
              'triggers from ${tenantsDir!.path}. That is almost certainly a '
              'parser failure, not a backend change — check whether the '
              'trigger DDL has been rewritten.',
        );
      });

      test('every entity marked live is genuinely logged by the backend', () {
        final claimed = {
          for (final spec in kReplicatedEntities)
            if (spec.isFed) spec.name,
        };
        final unlogged = claimed.difference(backend.loggedTables).toList()
          ..sort();

        expect(
          unlogged,
          isEmpty,
          reason:
              'These entities are marked ReplicationStatus.live but the '
              'backend has no trg_change_log_* trigger for them, so nothing '
              'will ever arrive and their screens render an empty list that '
              'looks like data:\n'
              '${unlogged.map((e) => '  - $e').join('\n')}\n\n'
              'Either the backend lost a trigger, or the entry is aspirational '
              '— mark it ReplicationStatus.pendingBackendTrigger with a '
              'pendingReason so the gap is visible in code and a screen can '
              'say so.',
        );
      });

      test('the pending list is a countdown: nothing on it is logged yet', () {
        // The direction that makes this a ratchet rather than a rug. A backend
        // agent is adding exactly these triggers; the day one lands, this
        // fails and names the entry to flip. Nobody has to remember.
        final resolved =
            kEntitiesAwaitingBackendTrigger
                .intersection(backend.loggedTables)
                .toList()
              ..sort();

        expect(
          resolved,
          isEmpty,
          reason:
              'The backend now logs these, so they are no longer pending:\n'
              '${resolved.map((e) => '  - $e').join('\n')}\n\n'
              'In lib/core/db/entity_registry.dart, delete their `status:` and '
              '`pendingReason:` lines (live is the default) and delete the '
              '"NOT YET FED" comment block above them. Then drop the matching '
              'note from TransactionPickersQuery / '
              'TransactionsRepositoryImpl / TransactionCategoriesController.',
        );
      });

      test('no backend-logged table is ignored without a written reason', () {
        final ignored =
            backend.loggedTables
                .difference(kEntitiesByName.keys.toSet())
                .difference(kIntentionallyNotReplicated.keys.toSet())
                .toList()
              ..sort();

        expect(
          ignored,
          isEmpty,
          reason:
              'The backend logs these and the client neither replicates '
              'them nor says why not:\n'
              '${ignored.map((e) => '  - $e').join('\n')}\n\n'
              'Add an EntitySpec for each in kReplicatedEntities, or an entry '
              'in kIntentionallyNotReplicated (in this file) explaining what '
              'reads that data instead. Silence is the one option that is not '
              'available — an unregistered entity is skipped by ChangeApplier '
              'without a trace.',
        );
      });

      test('the not-replicated list has no stale entries', () {
        final gone =
            kIntentionallyNotReplicated.keys
                .where((t) => !backend.loggedTables.contains(t))
                .toList()
              ..sort();
        final nowReplicated =
            kIntentionallyNotReplicated.keys
                .where(kEntitiesByName.containsKey)
                .toList()
              ..sort();

        expect(
          gone,
          isEmpty,
          reason:
              'The backend no longer logs these, so the note explaining '
              'why we skip them is describing nothing:\n'
              '${gone.map((e) => '  - $e').join('\n')}',
        );
        expect(
          nowReplicated,
          isEmpty,
          reason:
              'These are in kReplicatedEntities now, so the "we do not '
              'replicate this" note contradicts the registry:\n'
              '${nowReplicated.map((e) => '  - $e').join('\n')}',
        );
      });

      test('each spec keys on the column its trigger reports as entity_id', () {
        // `log_change(pk)` decides what arrives in `entity_id`, and
        // ChangeApplier looks the row up by it. A mismatch does not throw —
        // it writes rows under the wrong key, which surfaces much later as
        // duplicates.
        final mismatched = <String>[];
        final backendPks = backend.primaryKeys;
        for (final spec in kReplicatedEntities) {
          final actual = backendPks[spec.name];
          if (actual == null) continue; // not logged yet; covered above
          if (actual != spec.pk) {
            mismatched.add(
              '${spec.name}: registry "${spec.pk}", '
              'trigger log_change(\'$actual\')',
            );
          }
        }
        mismatched.sort();

        expect(
          mismatched,
          isEmpty,
          reason:
              'EntitySpec.pk must match the trigger argument:\n'
              '${mismatched.map((e) => '  - $e').join('\n')}',
        );
      });
    },
    skip: backendMissingSkipReason(tenantsDir),
  );

  group('degrading without the backend checkout', () {
    test('a missing backend skips with a message, it does not fail', () {
      final reason = backendMissingSkipReason(null);
      expect(reason, isNotNull);
      expect(reason, contains('MARY_AI_BACKEND_DIR'));
      for (final candidate in kBackendCandidatePaths) {
        expect(
          reason,
          contains(candidate),
          reason: 'the message should name every path it tried',
        );
      }
    });

    test('a present backend does not skip', () {
      expect(backendMissingSkipReason(Directory('.')), isNull);
    });
  });
}
