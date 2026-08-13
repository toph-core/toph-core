import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';

/// One page of the admin staff list, already filtered, sorted and counted.
typedef UsersPage = ({List<Map<String, dynamic>> items, int total});

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the staff screen's whole data
/// surface, reads and writes, with no network call on either side.
///
/// The mutations are **synchronous on purpose**. A write commits the local row
/// and its outbox operation in one transaction and returns; there is no future
/// to await because there is nothing to wait for. That turns §7's "every user
/// action completes without awaiting a network call" from something a test has
/// to catch into something the signature makes unrepresentable.
///
/// [Failure] survives on the return type because a local write can still fail —
/// a malformed row, a disk error. What it can no longer be is a
/// `ConnectionFailure`.
abstract class UsersLocalRepository {
  /// Emits the requested page immediately, then again on every change to
  /// `users` — replication's and this terminal's own edits alike.
  Stream<UsersPage> watchUsers({
    required int limit,
    required int offset,
    String? search,
    String? role,
  });

  /// The same page, read synchronously. Used for the first frame, so the screen
  /// has rows before its first build rather than a spinner.
  UsersPage getUsers({
    required int limit,
    required int offset,
    String? search,
    String? role,
  });

  /// Queues a new staff account.
  ///
  /// Unlike [updateUser] and [deleteUser] this writes **no local row**, and the
  /// distinction is not incidental. `POST /auth/register` assigns the user id
  /// server-side, so a locally-invented id would be a second identity for the
  /// same person: replication would later deliver the server's row under the
  /// real id and the invented one would linger beside it forever, undeletable
  /// because no server row matches it.
  ///
  /// The cost is that a staff account created offline is not visible until the
  /// operation drains. That is why this returns [LocalWriteResult.queued] rather
  /// than success — the screen says so instead of appearing to have done
  /// nothing. When §5.4's client-supplied ids land for `users`, this becomes an
  /// ordinary local write and the distinction disappears.
  Either<Failure, Unit> createUser(Map<String, dynamic> body);

  /// Applies [changes] to the local row and queues the `PUT`.
  ///
  /// [changes] is a partial row in server key shape (`full_name`, `is_active`,
  /// …); it is merged over the stored row so the replica keeps a complete
  /// entity rather than a fragment. Credentials in [changes] (`pincode`) are
  /// sent but never stored — `PayloadNormalizer` drops the registry's
  /// `redactKeys` on the way to disk, which is exactly the split
  /// `LocalWriter`'s separate `row` and `request` exist for.
  Either<Failure, Unit> updateUser(
    String id,
    Map<String, dynamic> changes,
  );

  /// Removes the row locally and queues the `DELETE`. The row goes immediately;
  /// if the server refuses, quarantine releases the guard and replication
  /// brings it back — visibly, with the reason in the quarantine list.
  Either<Failure, Unit> deleteUser(String id);
}
