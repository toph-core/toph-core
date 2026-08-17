import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/db/transaction_pickers_query.dart';
import 'package:mary_ai_pos/core/db/transactions_query.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

class TransactionsRepositoryImpl implements TransactionsRepository {
  final TransactionsQuery _query;
  final TransactionPickersQuery _pickers;

  // One engine now. The paginated ledger, the transaction-group picker and the
  // cash-register picker all read the SQLite replica the change feed fills. The
  // group and register catalogues moved here once tenants migration 70
  // (change_log_missing_triggers) started replicating `group_transactions` and
  // `cash_registers`; serving them from the Hive `LocalDatabase` was the last
  // thing tying this repository to a second database.
  TransactionsRepositoryImpl({required replica.LocalDatabase replicaDb})
      : _query = TransactionsQuery(replicaDb),
        _pickers = TransactionPickersQuery(replicaDb);

  @override
  Stream<List<Map<String, dynamic>>> watchTransactionGroups() =>
      _pickers.watchTransactionGroups();

  @override
  List<Map<String, dynamic>> getTransactionGroups() =>
      _pickers.transactionGroups();

  @override
  Stream<List<Map<String, dynamic>>> watchCashRegisters() =>
      _pickers.watchCashRegisters();

  @override
  List<Map<String, dynamic>> getCashRegisters() => _pickers.cashRegisters();

  @override
  TransactionsPage getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) =>
      (
        items: _query.transactions(
          limit: limit,
          offset: offset,
          search: search,
          type: type,
          cashRegisterId: cashRegisterId,
        ),
        total: _query.transactionsCount(
          search: search,
          type: type,
          cashRegisterId: cashRegisterId,
        ),
      );

  @override
  Stream<TransactionsPage> watchTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) =>
      _query.watch(() => getTransactions(
            limit: limit,
            offset: offset,
            search: search,
            type: type,
            cashRegisterId: cashRegisterId,
          ));
}
