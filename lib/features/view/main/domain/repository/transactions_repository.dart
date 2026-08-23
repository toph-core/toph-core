/// offline-first-target-architecture.md §8 Phase 5 (back-office tier) — read
/// side only. Transaction *groups* and *cash registers* are small,
/// unfiltered reference lists SyncEngine already hydrates (§8 Phase 1) —
/// this gives `transactions_list_section.dart`/
/// `transaction_categories_section.dart` a reactive `watchX()` surface for
/// them instead of a fetch-on-`initState`.
///
/// The paginated ledger read (`watchTransactions`) is now covered too: it was
/// previously left out only because `transactions` was not replicated, which is
/// no longer true. It reads the local replica through [TransactionsQuery] with
/// the same limit/offset/search/type/cash-register filters the endpoint took.
///
/// Still deliberately out of scope: every WRITE
/// (`create*`/`update*`/`delete*`). Per the design doc's open question 1 the
/// write policy for back-office screens is an unresolved product tradeoff, so
/// those stay direct `MainRepository` calls. See EXECUTION_CONCERNS.md.
typedef TransactionsPage = ({List<Map<String, dynamic>> items, int total});

abstract class TransactionsRepository {
  Stream<List<Map<String, dynamic>>> watchTransactionGroups();
  List<Map<String, dynamic>> getTransactionGroups();

  /// The group list narrowed by the picker's search box — a local filter over
  /// the replicated catalogue, not a `GET` with a `search` param.
  List<Map<String, dynamic>> searchTransactionGroups(String query);

  Stream<List<Map<String, dynamic>>> watchCashRegisters();
  List<Map<String, dynamic>> getCashRegisters();

  /// One page of the ledger, matching the given filters.
  TransactionsPage getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  });

  /// The same page as a stream that re-emits whenever a transaction changes,
  /// so a sale rung on another terminal appears without a reload.
  Stream<TransactionsPage> watchTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  });
}
