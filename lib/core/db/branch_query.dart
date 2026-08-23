import 'package:mary_ai_pos/core/db/local_database.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — branch configuration, read from
/// the replica.
///
/// `branches` replicates like any other entity, so the settings screen's
/// service-charge field has a local answer instead of a `GET` with a
/// last-known-value cache behind it. `default_service_percent` is a Postgres
/// `numeric`, which the registry coerces to a string on the way in (so the
/// REST-shaped Flutter models parse it) — hence the parse here rather than a
/// straight cast.
///
/// Reads only, but no longer because the write is somewhere else entirely:
/// `ServiceChargeRepositoryImpl` writes the same row through `LocalWriter`,
/// so the service charge is an ordinary local-first write now rather than the
/// direct call this comment used to describe.
class BranchQuery {
  final LocalDatabase _db;

  const BranchQuery(this._db);

  static const table = 'branches';

  /// The branch's configured service percent, or null when the branch is not
  /// in the replica yet or carries no value.
  double? defaultServicePercent(String branchId) {
    if (branchId.isEmpty) return null;
    final rows = _db.selectData(
      'SELECT data FROM $table WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [branchId],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['default_service_percent'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  /// Re-emits whenever the branch row changes, so an edit made on another
  /// terminal lands without a reload.
  Stream<double?> watchDefaultServicePercent(String branchId) =>
      _db.watch({table}, () => defaultServicePercent(branchId));
}
