import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the transaction-groups section reads
/// through this instead of resolving repositories itself (§9.2 guard: widgets
/// under presentation/pages must not inject repositories).
///
/// Two sources, on purpose:
/// - **The unfiltered list is a reactive replica read** — [TransactionsRepository]
///   over the local `LocalDatabase`, live and offline.
/// - **Search + create/update/delete go to the backend** via [MainRepository].
///   There is no bounded local mirror to search against (same reasoning as the
///   live goods search), and the group write path is not yet on the outbox —
///   both unchanged here, just moved off the widget.
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

  /// Server-side search for an active query — no local mirror to search.
  Future<Either<Failure, List<Map<String, dynamic>>>> searchGroups(String query) =>
      _remote.getTransactionGroups(search: query);

  Future<Either<Failure, bool>> createGroup(String name) =>
      _remote.createTransactionGroup(name);

  Future<Either<Failure, bool>> updateGroup(String id, String name) =>
      _remote.updateTransactionGroup(id, name);

  Future<Either<Failure, bool>> deleteGroup(String id) =>
      _remote.deleteTransactionGroup(id);
}
