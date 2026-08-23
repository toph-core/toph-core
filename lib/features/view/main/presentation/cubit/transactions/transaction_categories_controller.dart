import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the transaction-groups section reads
/// through this instead of resolving repositories itself (§9.2 guard: widgets
/// under presentation/pages must not inject repositories).
///
/// **One source now.** Every read was already the replica: the list, and the
/// search box, which filters the replicated `group_transactions` catalogue
/// locally rather than issuing a `GET` with a `search` param. The three writes
/// have joined them — they go through [TransactionsRepository] onto the outbox,
/// synchronously, so a group created or renamed offline is queued rather than
/// lost.
///
/// ## The list can be empty for two different reasons
///
/// `group_transactions` is fed by a `trg_change_log_*` trigger on the backend.
/// While that trigger is missing the replica never receives a row, and the
/// screen renders a blank panel that reads as "this venue has no transaction
/// groups" — which is a different statement, and a wrong one.
///
/// [groupsAwaitingBackendReplication] is the truthful version of that state,
/// and it is a plain synchronous getter rather than a stream or an error so
/// that adopting it costs a section one `if`. It flips to `false` on its own
/// the moment the registry entry is marked live, which
/// `test/registry_backend_pin_test.dart` forces to happen as soon as the
/// backend trigger exists.
class TransactionCategoriesController {
  final TransactionsRepository _local;

  /// Accepted and ignored — see [TransactionsListController]'s copy of this
  /// note. The group writes were this controller's only use of
  /// [MainRepository]; the parameter stays optional so `di.dart` can drop
  /// `remote: inject()` in one line whenever it is next edited.
  TransactionCategoriesController({
    required TransactionsRepository local,
    MainRepository? remote,
  }) : _local = local;

  /// Whether an empty group list means "none exist" or "the server does not
  /// send them yet".
  ///
  /// `true` ⇒ the list below can only ever be empty; render an explanation,
  /// not an empty state. Creating a group still works and still queues — it
  /// simply will not stay in this list once it has been sent, which is worth
  /// telling the operator before they try it twice.
  bool get groupsAwaitingBackendReplication =>
      !isFedByChangeLog('group_transactions');

  /// The unfiltered group list, live from the replica.
  Stream<List<Map<String, dynamic>>> watchGroups() =>
      _local.watchTransactionGroups();

  /// The group list narrowed by an active query — a local filter over the
  /// replicated catalogue, so the search box works offline like the list does.
  List<Map<String, dynamic>> searchGroups(String query) =>
      _local.searchTransactionGroups(query);

  Either<Failure, Unit> createGroup(String name) =>
      _local.createTransactionGroup(name);

  Either<Failure, Unit> updateGroup(String id, String name) =>
      _local.updateTransactionGroup(id, name);

  Either<Failure, Unit> deleteGroup(String id) =>
      _local.deleteTransactionGroup(id);
}
