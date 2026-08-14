import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/db/transactions_query.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

class TransactionsRepositoryImpl implements TransactionsRepository {
  final LocalDatabase _localDb;
  final TransactionsQuery _query;

  // Two stores on purpose, for now. The transaction-group and cash-register
  // picker lists still live in the Hive `LocalDatabase`; the paginated ledger
  // reads the SQLite replica the change feed fills, through [TransactionsQuery].
  // Collapsing these onto one engine is the larger migration tracked in
  // OFFLINE_FIRST_EVERYWHERE_PLAN.md's definition of done ("exactly one
  // database class").
  TransactionsRepositoryImpl({
    required LocalDatabase localDb,
    required replica.LocalDatabase replicaDb,
  })  : _localDb = localDb,
        _query = TransactionsQuery(replicaDb);

  @override
  Stream<List<Map<String, dynamic>>> watchTransactionGroups() =>
      _localDb.watchTransactionGroups();

  @override
  List<Map<String, dynamic>> getTransactionGroups() =>
      _localDb.getTransactionGroups();

  @override
  Stream<List<Map<String, dynamic>>> watchCashRegisters() =>
      _localDb.watchCashRegisters();

  @override
  List<Map<String, dynamic>> getCashRegisters() => _localDb.getCashRegisters();

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
