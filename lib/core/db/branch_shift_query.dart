import 'package:mary_ai_pos/core/db/local_database.dart';

/// The branch's shift, read from the replica.
///
/// This is the single source of truth the POS reads. It replaced a
/// `SharedPreferences` record held privately by each terminal, which is why
/// two tills in one venue used to disagree about whether a shift was open and
/// each closed one of its own: nothing was shared, so nothing could agree.
///
/// The row gets here by two paths and this class does not care which — a peer's
/// `localChange` broadcast over the LAN (immediately, no internet needed) or
/// `/sync/pull` from the cloud. Both land in the same table through
/// [ChangeApplier], so a terminal that was switched off during the open still
/// finds the shift waiting for it, and one that is merely offline sees it the
/// moment the terminal beside it opens it.
class BranchShiftQuery {
  final LocalDatabase _db;

  const BranchShiftQuery(this._db);

  static const table = 'branch_shifts';

  /// The branch's open shift, or null when nobody has opened one.
  ///
  /// "Open" is `closed_at IS NULL`, matching the backend's partial unique index
  /// exactly — the same predicate decides it in both places, so a row cannot be
  /// active here and closed there.
  ///
  /// `ORDER BY opened_at DESC` is a tie-break that should never be needed: the
  /// server permits only one open shift per branch. It matters for the window
  /// in which two terminals opened offline and their outboxes have not drained
  /// yet — both rows exist locally, and until the loser is reconciled away the
  /// newest is the one to show rather than an arbitrary one.
  Map<String, dynamic>? activeShift(String branchId) {
    if (branchId.isEmpty) return null;
    final rows = _db.selectData(
      'SELECT data FROM $table '
      'WHERE branch_id = ? AND closed_at IS NULL AND deleted_at IS NULL '
      'ORDER BY opened_at DESC LIMIT 1',
      [branchId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// One shift by id, open or closed.
  Map<String, dynamic>? byId(String id) => _db.byId(table, id);

  /// Re-emits whenever any shift row changes.
  ///
  /// This is what makes the shift visible across the venue without a reload:
  /// a peer's open arrives over the LAN, `ChangeApplier` writes the row, and
  /// every screen listening here rebuilds — on a terminal that never touched
  /// the network.
  Stream<Map<String, dynamic>?> watchActiveShift(String branchId) =>
      _db.watch({table}, () => activeShift(branchId));

  /// The branch's shifts, newest first — the close-shift screen's history.
  List<Map<String, dynamic>> recentShifts(String branchId, {int limit = 50}) {
    if (branchId.isEmpty) return const [];
    return _db.selectData(
      'SELECT data FROM $table '
      'WHERE branch_id = ? AND deleted_at IS NULL '
      'ORDER BY opened_at DESC LIMIT ?',
      [branchId, limit],
    );
  }
}
