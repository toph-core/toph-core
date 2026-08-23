import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/db/transaction_pickers_query.dart';
import 'package:mary_ai_pos/core/db/transactions_query.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

class TransactionsRepositoryImpl implements TransactionsRepository {
  final TransactionsQuery _query;
  final TransactionPickersQuery _pickers;

  // One engine now. The paginated ledger, the transaction-group picker and the
  // cash-register picker all read the SQLite replica — no second database, no
  // REST call from this class.
  //
  // What the replica does not yet contain is the rows. The comment this
  // replaces said the catalogues "moved here once tenants migration 70
  // (change_log_missing_triggers) started replicating `group_transactions` and
  // `cash_registers`". That migration was never merged — the backend's tenant
  // 70 is `70_order_items_client_id`, and no migration adds a change-log
  // trigger for `transactions`, `group_transactions` or `cash_registers`
  // (SERVER_PLAN.md P0-1 has the unmerged branch). So every method here is a
  // correct query over a table nothing fills.
  //
  // The registry records that as [ReplicationStatus.pendingBackendTrigger] and
  // `TransactionPickersQuery.awaitingBackendReplication` exposes it, so the
  // pickers can distinguish "no groups exist" from "the server is not sending
  // them"; `test/registry_backend_pin_test.dart` fails the moment the trigger
  // lands, which is the signal to delete this note.
  //
  // Two of the three are user-visible now: the group picker/list and the
  // cash-register filter render empty. `getTransactions`/`watchTransactions`
  // below are not — TransactionsListController still pages the ledger over
  // REST through MainRepository, so this side is a finished read path parked
  // until the feed carries it.
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
  List<Map<String, dynamic>> searchTransactionGroups(String query) =>
      _pickers.searchTransactionGroups(query);

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
