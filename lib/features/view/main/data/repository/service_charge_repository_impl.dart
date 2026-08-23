import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/branch_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/service_charge_repository.dart';

/// [ServiceChargeRepository] over the replica.
///
/// The write is a *merge*: `branches` is a whole replicated entity — name,
/// address, timezone, the lot — and this screen owns exactly one field of it.
/// Replacing the row with `{default_service_percent}` would blank the rest
/// until the next pull put it back.
class ServiceChargeRepositoryImpl implements ServiceChargeRepository {
  final LocalWriter _writer;
  final BranchQuery _branches;

  ServiceChargeRepositoryImpl(LocalDatabase db, this._writer)
      : _branches = BranchQuery(db);

  static const _entity = BranchQuery.table;

  @override
  Stream<double?> watchServicePercent(String branchId) =>
      _branches.watchDefaultServicePercent(branchId);

  @override
  double? getServicePercent(String branchId) =>
      _branches.defaultServicePercent(branchId);

  @override
  Either<Failure, Unit> saveServicePercent(String branchId, double value) {
    if (branchId.isEmpty) {
      return const Left(MessageFailure('Filial aniqlanmadi'));
    }
    try {
      // Stored as a string, because that is what arrives on the feed:
      // `default_service_percent` is a Postgres `numeric` and the registry
      // lists it in `numericKeys`, which coerces it to a string on the way in
      // so the REST-shaped models parse it. Writing a double here would make
      // this terminal's own row a different shape from every replicated one,
      // and `BranchQuery` would be the only thing that ever noticed.
      final asString = value == value.truncateToDouble()
          ? value.toStringAsFixed(0)
          : value.toString();
      _writer.write(
        entity: _entity,
        id: branchId,
        row: {'id': branchId, 'default_service_percent': asString},
        merge: true,
        request: {'default_service_percent': asString},
      );
      return const Right(unit);
    } catch (e) {
      // A local write can still fail — a malformed row, a disk error. What it
      // can no longer be is a connection failure.
      return Left(MessageFailure('$e'));
    }
  }
}
