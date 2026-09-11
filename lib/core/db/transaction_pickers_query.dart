import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/branch_scope.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the transactions screen's two
/// picker lists (transaction groups, cash registers), moved off the Hive
/// `LocalDatabase` onto the SQLite replica.
///
/// Both are small id+name catalogues, read straight off the replica: like
/// `TransactionsQuery`, these read every live row with no branch filter and
/// return the raw server map the pickers already decode (`id`, `name`).
///
/// "No branch filter" used to be justified by the feed being branch-scoped
/// upstream (`change_log.branch_id`). It is not — that column does not exist,
/// and `SyncS.Pull` filters by cursor alone — so on a multi-branch brand these
/// pickers do list every branch's rows. Recorded as the open gap it is.
///
/// **Whether either table can receive a row is a server-side question, and
/// this class answers it out loud.** Both are fed by a `trg_change_log_*`
/// trigger; while one is missing, its picker renders a blank list that reads
/// as "this venue has none" — a different statement, and a wrong one.
/// [awaitingBackendReplication] is the difference between the two, so a picker
/// can say the second rather than implying the first.
///
/// The queries below do not change with the answer. [ReplicationStatus] on the
/// registry entry is the record, and `test/registry_backend_pin_test.dart`
/// pins it to the backend's own SQL in both directions — so these getters go
/// false on their own when the trigger lands, and true again if it is ever
/// dropped, without anyone editing this file.
class TransactionPickersQuery {
  final LocalDatabase _db;

  /// Both catalogues are branch-scoped on the backend — `group_transactions`
  /// and `cash_registers` each carry a `branch_id` their list queries filter
  /// on. Neither column is promoted locally, so the filter reads it out of the
  /// stored row; both tables are short enough that the unindexed lookup costs
  /// nothing.
  final BranchScope _scope;

  TransactionPickersQuery(this._db, {String Function()? branchId})
    : _scope = BranchScope(_db, branchId: branchId);

  static const _groupsTable = 'group_transactions';
  static const _registersTable = 'cash_registers';

  /// True while neither catalogue can receive a row from `/sync/pull`.
  ///
  /// A caller rendering an empty picker should use this to choose between two
  /// very different messages. The check is per-entity underneath
  /// ([groupsAwaitingBackendReplication], [registersAwaitingBackendReplication])
  /// because the backend may well add one trigger before the other; this is
  /// the "is any of it missing" shorthand for a screen that shows both.
  bool get awaitingBackendReplication =>
      groupsAwaitingBackendReplication || registersAwaitingBackendReplication;

  bool get groupsAwaitingBackendReplication => !isFedByChangeLog(_groupsTable);

  bool get registersAwaitingBackendReplication =>
      !isFedByChangeLog(_registersTable);

  /// Live transaction groups, ordered by name — the picker's whole contract.
  List<Map<String, dynamic>> transactionGroups() => _liveByName(_groupsTable);

  /// Rebuilds when any group changes, so an edit on another terminal lands
  /// without a reload.
  Stream<List<Map<String, dynamic>>> watchTransactionGroups() =>
      _db.watch({_groupsTable, BranchScope.channel}, transactionGroups);

  /// Groups whose name contains [query], case-insensitively — the picker's
  /// search box, answered locally.
  ///
  /// This used to be a `GET` with a `search` param, on the reasoning that
  /// there was "no bounded local mirror to search against". There is: the feed
  /// replicates the whole `group_transactions` catalogue, and it is a short
  /// list of names. An empty or blank query returns the full list, matching
  /// what the endpoint did.
  List<Map<String, dynamic>> searchTransactionGroups(String query) {
    final q = query.trim();
    if (q.isEmpty) return transactionGroups();
    final branch = _scope.clause(_groupsTable, json: true);
    return _db.selectData(
      'SELECT data FROM $_groupsTable WHERE deleted_at IS NULL '
      "AND name LIKE ? ESCAPE '\\' ${branch.sql}ORDER BY name",
      ['%${_escapeLike(q)}%', ...branch.args],
    );
  }

  /// `%` and `_` are wildcards in LIKE; a cashier typing them means the
  /// literal character.
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  /// Live cash registers, ordered by name.
  List<Map<String, dynamic>> cashRegisters() => _liveByName(_registersTable);

  Stream<List<Map<String, dynamic>>> watchCashRegisters() =>
      _db.watch({_registersTable, BranchScope.channel}, cashRegisters);

  List<Map<String, dynamic>> _liveByName(String table) {
    final branch = _scope.clause(table, json: true);
    return _db.selectData(
      'SELECT data FROM $table WHERE deleted_at IS NULL '
      '${branch.sql}ORDER BY name',
      branch.args,
    );
  }
}
