import 'package:dartz/dartz.dart';
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
class TransactionCategoriesController {
  final TransactionsRepository _local;
  final MainRepository _remote;

  TransactionCategoriesController({
    required TransactionsRepository local,
    required MainRepository remote,
  })  : _local = local,
        _remote = remote;

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
