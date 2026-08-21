import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the transactions-list section reads
/// through this instead of resolving repositories itself (§9.2 guard: widgets
/// under presentation/pages must not inject repositories).
///
/// Two sources, on purpose:
/// - **The cash-register and group pickers are reactive replica reads**
///   ([TransactionsRepository] over the local `LocalDatabase`), live and
///   offline.
/// - **The paginated ledger and the transaction writes go to the backend** via
///   [MainRepository] — server-side pagination/search over the full history,
///   and a write path not yet on the outbox. Both unchanged, just off the
///   widget.
class TransactionsListController {
  final TransactionsRepository _local;
  final MainRepository _remote;

  TransactionsListController({
    required TransactionsRepository local,
    required MainRepository remote,
  })  : _local = local,
        _remote = remote;

  Stream<List<Map<String, dynamic>>> watchCashRegisters() =>
      _local.watchCashRegisters();

  Stream<List<Map<String, dynamic>>> watchGroups() =>
      _local.watchTransactionGroups();

  /// One page of the ledger — server-side paginated/filtered; there is no
  /// bounded local mirror of the full transaction history to page over.
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) =>
          _remote.getTransactions(
            limit: limit,
            offset: offset,
            search: search,
            type: type,
            cashRegisterId: cashRegisterId,
          );

  Future<Either<Failure, bool>> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  ) =>
      _remote.createIncomeExpenseTransaction(body);

  Future<Either<Failure, bool>> createTransferTransaction(
    Map<String, dynamic> body,
  ) =>
      _remote.createTransferTransaction(body);

  Future<Either<Failure, bool>> updateTransaction(
    String id,
    Map<String, dynamic> body,
  ) =>
      _remote.updateTransaction(id, body);

  Future<Either<Failure, bool>> deleteTransaction(String id) =>
      _remote.deleteTransaction(id);
}
