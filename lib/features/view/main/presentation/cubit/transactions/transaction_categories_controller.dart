import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the transaction-groups section reads
/// through this instead of resolving repositories itself (§9.2 guard: widgets
/// under presentation/pages must not inject repositories).
///
/// Two sources, on purpose:
/// - **Every read is the replica** — [TransactionsRepository] over the local
///   database, live and offline. Search moved here too: the feed replicates
///   the whole `group_transactions` catalogue, so the "no bounded local mirror
///   to search against" that justified a `GET` is no longer true, and the box
///   now filters a short list of names locally.
/// - **create/update/delete go to the backend** via [MainRepository]. The
///   group write path is not yet on the outbox — unchanged here.
///
/// ## The list is empty, and the section must be allowed to say so
///
/// `group_transactions` has no `trg_change_log_*` trigger on the backend, so
/// the replica never receives a row and nothing writes one locally either. The
/// migration that adds it is written but unmerged (SERVER_PLAN.md P0-1); the
/// comment in this repo that claimed it had shipped as "tenants migration 70"
/// was wrong, and that wrongness is the reason this screen has been rendering
/// a blank panel that reads as "this venue has no transaction groups".
///
/// [groupsAwaitingBackendReplication] is the truthful version of that state,
/// and it is a plain synchronous getter rather than a stream or an error so
/// that adopting it costs a section one `if`. It flips to `false` on its own
/// the moment the registry entry is marked live, which
/// `test/registry_backend_pin_test.dart` forces to happen as soon as the
/// backend trigger exists.
class TransactionCategoriesController {
  final TransactionsRepository _local;
  final MainRepository _remote;

  TransactionCategoriesController({
    required TransactionsRepository local,
    required MainRepository remote,
  })  : _local = local,
        _remote = remote;

  /// Whether an empty group list means "none exist" or "the server does not
  /// send them yet".
  ///
  /// `true` ⇒ the list below can only ever be empty; render an explanation,
  /// not an empty state. Creating a group still works — the write goes to the
  /// backend over REST — it simply will not appear in this list afterwards,
  /// which is worth telling the operator before they try it twice.
  bool get groupsAwaitingBackendReplication =>
      !isFedByChangeLog('group_transactions');

  /// The unfiltered group list, live from the replica.
  Stream<List<Map<String, dynamic>>> watchGroups() =>
      _local.watchTransactionGroups();

  /// The group list narrowed by an active query — a local filter over the
  /// replicated catalogue, so the search box works offline like the list does.
  List<Map<String, dynamic>> searchGroups(String query) =>
      _local.searchTransactionGroups(query);

  Future<Either<Failure, bool>> createGroup(String name) =>
      _remote.createTransactionGroup(name);

  Future<Either<Failure, bool>> updateGroup(String id, String name) =>
      _remote.updateTransactionGroup(id, name);

  Future<Either<Failure, bool>> deleteGroup(String id) =>
      _remote.deleteTransactionGroup(id);
}
