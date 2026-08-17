import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the transactions screen's two
/// picker lists (transaction groups, cash registers), moved off the Hive
/// `LocalDatabase` onto the SQLite replica.
///
/// Both are small id+name catalogues the change feed now carries: tenants
/// migration 70 (change_log_missing_triggers) added the `group_transactions`
/// and `cash_registers` triggers and backfilled the live rows. The feed is
/// branch-scoped on the backend (change_log_branch_id*), so — like
/// [TransactionsQuery] — these read every live row with no branch filter and
/// return the raw server map the pickers already decode (`id`, `name`).
class TransactionPickersQuery {
  final LocalDatabase _db;

  const TransactionPickersQuery(this._db);

  static const _groupsTable = 'group_transactions';
  static const _registersTable = 'cash_registers';

  /// Live transaction groups, ordered by name — the picker's whole contract.
  List<Map<String, dynamic>> transactionGroups() => _liveByName(_groupsTable);

  /// Rebuilds when any group changes, so an edit on another terminal lands
  /// without a reload.
  Stream<List<Map<String, dynamic>>> watchTransactionGroups() =>
      _db.watch({_groupsTable}, transactionGroups);

  /// Live cash registers, ordered by name.
  List<Map<String, dynamic>> cashRegisters() => _liveByName(_registersTable);

  Stream<List<Map<String, dynamic>>> watchCashRegisters() =>
      _db.watch({_registersTable}, cashRegisters);

  List<Map<String, dynamic>> _liveByName(String table) => _db.selectData(
        'SELECT data FROM $table WHERE deleted_at IS NULL ORDER BY name',
      );
}
