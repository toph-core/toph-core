/// offline-first-target-architecture.md §8 Phase 5 (back-office tier) — read
/// side only. Transaction *groups* and *cash registers* are small,
/// unfiltered reference lists SyncEngine already hydrates (§8 Phase 1) —
/// this gives `transactions_list_section.dart`/
/// `transaction_categories_section.dart` a reactive `watchX()` surface for
/// them instead of a fetch-on-`initState`.
///
/// Deliberately does **not** cover `getTransactions` (the paginated
/// transaction ledger itself) or any write (`create*`/`update*`/`delete*`
/// transaction/transaction-group) — per the design doc's own open question
/// 1, this phase's write policy for back-office screens is an explicitly
/// unresolved product tradeoff, not decided here. Those stay direct
/// `MainRepository` calls, unchanged. See EXECUTION_CONCERNS.md.
abstract class TransactionsRepository {
  Stream<List<Map<String, dynamic>>> watchTransactionGroups();
  List<Map<String, dynamic>> getTransactionGroups();

  Stream<List<Map<String, dynamic>>> watchCashRegisters();
  List<Map<String, dynamic>> getCashRegisters();
}
