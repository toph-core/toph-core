import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/users_query.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/users_local_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the staff screen, read and write,
/// off the network entirely.
///
/// This is the first repository to write through [LocalWriter], and therefore
/// the first place the Phase 2 outbox actually carries a production write. The
/// ordering was deliberate: Phase 2 shipped the queue with an empty executor
/// registry because migrating a screen's writes without its reads would make an
/// online operator's own edit invisible until the next pull. Read and write
/// move together, per screen, and this is the first screen.
class UsersLocalRepositoryImpl implements UsersLocalRepository {
  final LocalDatabase _db;
  final LocalWriter _writer;
  final UsersQuery _users;

  UsersLocalRepositoryImpl(this._db, this._writer) : _users = UsersQuery(_db);

  static const _entity = 'users';

  @override
  Stream<UsersPage> watchUsers({
    required int limit,
    required int offset,
    String? search,
    String? role,
  }) =>
      _users.watch(limit: limit, offset: offset, search: search, role: role);

  @override
  UsersPage getUsers({
    required int limit,
    required int offset,
    String? search,
    String? role,
  }) =>
      _users.page(limit: limit, offset: offset, search: search, role: role);

  @override
  Either<Failure, UserWriteResult> createUser(Map<String, dynamic> body) {
    return _guard(() {
      // No local row: the register endpoint assigns the id. See the interface
      // for why inventing one here would be worse than the delay.
      _writer.enqueueOnly(
        entity: _entity,
        action: 'create',
        request: body,
      );
      return UserWriteResult.queued;
    });
  }

  @override
  Either<Failure, UserWriteResult> updateUser(
    String id,
    Map<String, dynamic> changes,
  ) {
    return _guard(() {
      // Merge over the stored row, not replace it: the screen sends only the
      // fields its form owns, and the replica must keep a whole entity. A row
      // missing locally is not an error worth blocking on — the update still
      // queues, and replication reconciles.
      final existing = _db.byId(_entity, id) ?? const <String, dynamic>{};
      final row = <String, dynamic>{...existing, ...changes, 'id': id};

      // `row` goes to disk (redacted by the normalizer), `request` goes to the
      // server intact. Same call, two shapes, one transaction.
      _writer.write(
        entity: _entity,
        id: id,
        row: row,
        request: changes,
      );
      return UserWriteResult.applied;
    });
  }

  @override
  Either<Failure, UserWriteResult> deleteUser(String id) {
    return _guard(() {
      _writer.delete(entity: _entity, id: id);
      return UserWriteResult.applied;
    });
  }

  /// A local write can still fail — a malformed row, a disk error. What it can
  /// no longer be is a connection failure, so the message says what happened
  /// rather than telling the operator to check the network.
  Either<Failure, UserWriteResult> _guard(UserWriteResult Function() body) {
    try {
      return Right(body());
    } catch (e) {
      return Left(MessageFailure('$e'));
    }
  }
}
