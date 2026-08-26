import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/db/transaction_pickers_query.dart';
import 'package:mary_ai_pos/core/db/transactions_query.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the transactions screen, off the
/// network on both sides.
///
/// One engine: the paginated ledger, the transaction-group picker and the
/// cash-register picker all read the SQLite replica, and all seven writes go
/// through [LocalWriter] — the local row and the outbox operation commit in one
/// transaction, and the call returns. No `await` on the network on any path.
///
/// ## Server-assigned ids, and what happens to the row you just saw
///
/// None of these endpoints accept a client-supplied id (`service/transaction.go`
/// calls `uuid.New()` for every row it writes), so creates take the answer
/// DECISIONS.md D1 settled and `UsersLocalRepositoryImpl.createUser` /
/// `HallsTablesLocalRepositoryImpl.createHall` already use: write the row under
/// a provisional id, mark it, and let the drainer swap it for the server's when
/// the create's response comes back.
///
/// The swap is invisible, as it is for halls and users. It was not always:
/// `MainRepository.createIncomeExpenseTransaction` and its siblings used to
/// return a bare `bool`, so the drainer took its documented no-id branch and
/// deleted the provisional row on success — a movement the operator had just
/// entered vanished from the ledger until the next pull delivered the server's
/// copy. Those three methods now return the created row, so the local row is
/// replaced in place and anything still queued that quoted its provisional id
/// — a movement filed under a group created in the same offline stretch — is
/// repointed before it is sent.
///
/// What remains open is a lost *response*: `POST /transactions/…` accepts no
/// client-supplied id or idempotency key, so a create whose reply is dropped
/// after the server committed is retried and posts a second movement. That
/// needs the endpoint to take a client id, the way `CreateOrder` does.
///
/// ## Money
///
/// `amount`, `customer_paid_amount` and `change_amount` are Postgres `numeric`,
/// which the REST API marshals as a **string** and the change feed as a JSON
/// number — [PayloadNormalizer] reconciles the two on the way in. A locally
/// written row has to land in the same shape or it would decode differently
/// from a replicated one, so numerics are canonicalised here before the row is
/// stored ([_canonicalNumerics]). The *request* keeps whatever the screen
/// composed: the server parses `"15000"` and `15000` alike, and the queued body
/// should be the write that was made, not a reinterpretation of it.
class TransactionsRepositoryImpl implements TransactionsRepository {
  final LocalWriter _writer;
  final TransactionsQuery _query;
  final TransactionPickersQuery _pickers;

  static const _transactions = 'transactions';
  static const _groups = 'group_transactions';

  /// [writer] is optional only so `di.dart` keeps compiling while this class
  /// grows a write half. [LocalWriter], [ChangeApplier] and [OutboxStore] are
  /// all thin, stateless wrappers over the one database handle — the queue
  /// itself lives in `_outbox`, not in memory — so the fallback is the same
  /// writer the container holds, built from the same `replicaDb`. Pass
  /// `writer: inject<LocalWriter>()` when that registration is updated and this
  /// default becomes dead.
  TransactionsRepositoryImpl({
    required replica.LocalDatabase replicaDb,
    LocalWriter? writer,
  })  : _query = TransactionsQuery(replicaDb),
        _pickers = TransactionPickersQuery(replicaDb),
        _writer = writer ??
            LocalWriter(
              db: replicaDb,
              applier: ChangeApplier(replicaDb),
              outbox: OutboxStore(replicaDb),
            );

  // ── Reads ──────────────────────────────────────────────────────────────

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

  @override
  bool get transactionsAwaitingBackendReplication =>
      _query.awaitingBackendReplication;

  @override
  bool get groupsAwaitingBackendReplication =>
      _pickers.groupsAwaitingBackendReplication;

  @override
  bool get registersAwaitingBackendReplication =>
      _pickers.registersAwaitingBackendReplication;

  // ── Writes ─────────────────────────────────────────────────────────────

  @override
  Either<Failure, Unit> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  ) =>
      _guard(() {
        _writer.create(
          entity: _transactions,
          row: _canonicalNumerics(_transactions, body),
          request: body,
        );
        return unit;
      });

  @override
  Either<Failure, Unit> createTransferTransaction(Map<String, dynamic> body) =>
      _guard(() {
        // The sending leg, shaped exactly as the server shapes it: the money
        // leaves `from_cash_register_id`, and the row keeps a reference to
        // where it went. The receiving `transfer_income` row is the server's
        // to create and to name; it appears on the next pull.
        final row = <String, dynamic>{
          ...body,
          'type': 'transfer_expense',
          'cash_register_id': body['from_cash_register_id'],
          'to_cash_register_id': body['to_cash_register_id'],
        }..remove('from_cash_register_id');
        _writer.create(
          entity: _transactions,
          row: _canonicalNumerics(_transactions, row),
          request: body,
        );
        return unit;
      });

  @override
  Either<Failure, Unit> updateTransaction(
    String id,
    Map<String, dynamic> changes,
  ) =>
      _guard(() {
        // A patch, not a replacement: the dialog sends the four fields it owns
        // and the replica must keep a whole entity. A row missing locally is
        // not worth blocking on — the update still queues, and replication
        // reconciles.
        _writer.write(
          entity: _transactions,
          id: id,
          row: _canonicalNumerics(_transactions, {...changes, 'id': id}),
          request: changes,
          merge: true,
        );
        return unit;
      });

  @override
  Either<Failure, Unit> deleteTransaction(String id) => _guard(() {
        _writer.delete(entity: _transactions, id: id);
        return unit;
      });

  @override
  Either<Failure, Unit> createTransactionGroup(String name) => _guard(() {
        _writer.create(
          entity: _groups,
          row: {'name': name},
          request: {'name': name},
        );
        return unit;
      });

  @override
  Either<Failure, Unit> updateTransactionGroup(String id, String name) =>
      _guard(() {
        _writer.write(
          entity: _groups,
          id: id,
          row: {'name': name, 'id': id},
          request: {'name': name},
          merge: true,
        );
        return unit;
      });

  @override
  Either<Failure, Unit> deleteTransactionGroup(String id) => _guard(() {
        _writer.delete(entity: _groups, id: id);
        return unit;
      });

  /// Renders every `numeric` column of [entity] the way a replicated row
  /// renders it, so one model parses both.
  ///
  /// [PayloadNormalizer] already does this for a value that arrives as a JSON
  /// number, which is the change-feed case. A screen sends the same field as a
  /// string it built from a text field, and a string is passed through
  /// untouched — so `"15000.00"` would sit on disk beside a replicated
  /// `"15000"` for the same money. Parsing and re-rendering here removes that
  /// difference at the only point where a local row is authored.
  static Map<String, dynamic> _canonicalNumerics(
    String entity,
    Map<String, dynamic> row,
  ) {
    final spec = kEntitiesByName[entity];
    if (spec == null || spec.numericKeys.isEmpty) return row;
    final out = <String, dynamic>{...row};
    for (final key in spec.numericKeys) {
      final value = out[key];
      if (value == null) continue;
      final parsed =
          value is num ? value : num.tryParse(value.toString().trim());
      // An unparseable amount is left exactly as typed rather than silently
      // becoming 0: the server is the one that gets to reject it.
      if (parsed != null) {
        out[key] = PayloadNormalizer.numToCanonicalString(parsed);
      }
    }
    return out;
  }

  /// A local write can still fail — a malformed row, a disk error. What it can
  /// no longer be is a connection failure, so the message says what happened
  /// rather than telling the operator to check the network.
  Either<Failure, Unit> _guard(Unit Function() body) {
    try {
      return Right(body());
    } catch (e) {
      return Left(MessageFailure('$e'));
    }
  }
}
