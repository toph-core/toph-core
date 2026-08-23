import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

/// The page shape the section renders. Re-exported so a widget under
/// `presentation/pages/` names it without importing the domain repository —
/// the §9.2 rule is that a screen talks to this controller and to nothing
/// behind it.
export 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart'
    show TransactionsPage;

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the transactions-list section reads
/// through this instead of resolving repositories itself (§9.2 guard: widgets
/// under presentation/pages must not inject repositories).
///
/// **One source now.** This used to be split: the pickers came off the replica
/// while the ledger itself paged over REST through [MainRepository], which made
/// the transactions screen the last one in the app to open a socket — pinned as
/// such by the §9.3 suite. The replica read (`watchTransactions`) had been
/// finished and left without a caller; this is that caller. Everything below
/// goes to [TransactionsRepository], and the writes go to it synchronously:
/// they land a local row and an outbox operation and return, so no user action
/// on this screen waits on anything.
class TransactionsListController {
  final TransactionsRepository _local;

  /// Accepted and ignored.
  ///
  /// `MainRepository` was this controller's ledger read and its four writes;
  /// none of them are left. The parameter stays only so `di.dart` — which is
  /// not this change's to edit — keeps compiling, and it is optional so that
  /// dropping `remote: inject()` from the registration is a one-line deletion
  /// with nothing to change here.
  TransactionsListController({
    required TransactionsRepository local,
    MainRepository? remote,
  }) : _local = local;

  // ── Reads ──────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchCashRegisters() =>
      _local.watchCashRegisters();

  Stream<List<Map<String, dynamic>>> watchGroups() =>
      _local.watchTransactionGroups();

  /// One page of the ledger, re-emitted whenever any transaction changes — so
  /// a sale rung on another terminal, or this terminal's own edit, reaches the
  /// list without a reload and without a refetch after save.
  Stream<TransactionsPage> watchTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) =>
      _local.watchTransactions(
        limit: limit,
        offset: offset,
        search: search,
        type: type,
        cashRegisterId: cashRegisterId,
      );

  /// The same page read synchronously, for the first frame. The query is a
  /// local `SELECT`, so there is no interval between "asked" and "answered" for
  /// a spinner to fill.
  TransactionsPage getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) =>
      _local.getTransactions(
        limit: limit,
        offset: offset,
        search: search,
        type: type,
        cashRegisterId: cashRegisterId,
      );

  /// Whether an empty ledger means "no cash has moved" or "the server does not
  /// send these yet". `true` ⇒ the list below can only ever be empty.
  bool get ledgerAwaitingBackendReplication =>
      _local.transactionsAwaitingBackendReplication;

  /// The same question for the cash-register filter.
  bool get registersAwaitingBackendReplication =>
      _local.registersAwaitingBackendReplication;

  // ── Writes ─────────────────────────────────────────────────────────────

  Either<Failure, Unit> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  ) =>
      _local.createIncomeExpenseTransaction(body);

  Either<Failure, Unit> createTransferTransaction(Map<String, dynamic> body) =>
      _local.createTransferTransaction(body);

  Either<Failure, Unit> updateTransaction(
    String id,
    Map<String, dynamic> body,
  ) =>
      _local.updateTransaction(id, body);

  Either<Failure, Unit> deleteTransaction(String id) =>
      _local.deleteTransaction(id);
}
