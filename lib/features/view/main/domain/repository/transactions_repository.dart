import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';

/// One page of the ledger, already filtered, sorted and counted.
typedef TransactionsPage = ({List<Map<String, dynamic>> items, int total});

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the transactions screen's whole
/// data surface, reads and writes, with no network call on either side.
///
/// The read half was finished first and sat unused: `TransactionsQuery` and
/// [watchTransactions] existed while `TransactionsListController` still paged
/// the ledger over REST, which made this the last screen in the app to open a
/// socket (the §9.3 suite measured it). Both halves are here now, so the screen
/// has nothing left to fetch.
///
/// The mutations are **synchronous on purpose**, exactly as
/// `UsersLocalRepository`'s are. A write commits the local row and its outbox
/// operation in one transaction and returns; there is no future to await
/// because there is nothing to wait for, which turns §7's "every user action
/// completes without awaiting a network call" from something a test has to
/// catch into something the signature makes unrepresentable.
///
/// [Failure] survives on the return type because a local write can still fail —
/// a malformed row, a disk error. What it can no longer be is a
/// `ConnectionFailure`.
abstract class TransactionsRepository {
  // ── Reads ──────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchTransactionGroups();
  List<Map<String, dynamic>> getTransactionGroups();

  /// The group list narrowed by the picker's search box — a local filter over
  /// the replicated catalogue, not a `GET` with a `search` param.
  List<Map<String, dynamic>> searchTransactionGroups(String query);

  Stream<List<Map<String, dynamic>>> watchCashRegisters();
  List<Map<String, dynamic>> getCashRegisters();

  /// One page of the ledger, matching the given filters. Synchronous, so the
  /// screen has rows before its first build rather than a spinner.
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

  // ── "Is this list empty, or is the server not sending it?" ──────────────

  /// True while the ledger table cannot receive a row from `/sync/pull`.
  ///
  /// A screen rendering an empty list should use this to pick between two very
  /// different messages. It flips to `false` on its own once the registry entry
  /// is marked live, which `test/registry_backend_pin_test.dart` forces to
  /// happen as soon as the backend trigger exists.
  bool get transactionsAwaitingBackendReplication;

  /// The same question for the transaction-group catalogue.
  bool get groupsAwaitingBackendReplication;

  /// And for the cash-register catalogue, which is this screen's filter.
  bool get registersAwaitingBackendReplication;

  // ── Writes ─────────────────────────────────────────────────────────────

  /// Queues an income or expense movement and shows it immediately.
  ///
  /// [body] is the request the endpoint takes (`type`, `cash_register_id`,
  /// `amount`, …). The local row is the same fields with the numerics
  /// canonicalised, so it decodes through the same model a replicated row
  /// does.
  ///
  /// `POST /transactions/income-expense` assigns the id, so the row is written
  /// under a provisional one — the same answer `UsersLocalRepository.createUser`
  /// and `HallsTablesLocalRepository.createHall` give. See the implementation
  /// for what happens to that id once the operation drains.
  Either<Failure, Unit> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  );

  /// Queues a transfer between two cash registers.
  ///
  /// The server writes **two** rows for one request — `transfer_expense` on the
  /// sending register and `transfer_income` on the receiving one
  /// (`service/transaction.go`, `CreateTransfer`). Only the expense leg is
  /// written locally: mirroring the second would mean inventing an id for a row
  /// the server owns, which is the same call
  /// `MenuAdminLocalRepository.saveGood` makes about a good's `calculations`.
  /// The income leg lands on the next pull.
  Either<Failure, Unit> createTransferTransaction(Map<String, dynamic> body);

  /// Applies [changes] to the local row and queues the `PUT`.
  ///
  /// [changes] is a partial row in server key shape (`amount`, `description`,
  /// `pay_type`, `date`); it is merged over the stored row so the replica keeps
  /// a complete entity rather than a fragment.
  Either<Failure, Unit> updateTransaction(
    String id,
    Map<String, dynamic> changes,
  );

  /// Removes the row locally and queues the `DELETE`. The row goes immediately;
  /// if the server refuses, quarantine releases the guard and replication
  /// brings it back — visibly, with the reason in the quarantine list.
  Either<Failure, Unit> deleteTransaction(String id);

  /// Queues a new transaction group. Same provisional-id story as the ledger
  /// creates above.
  Either<Failure, Unit> createTransactionGroup(String name);

  Either<Failure, Unit> updateTransactionGroup(String id, String name);

  Either<Failure, Unit> deleteTransactionGroup(String id);
}
