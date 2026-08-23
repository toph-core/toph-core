import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';

/// The branch's service-charge percent, read and written locally.
///
/// Replaces the last "this one is small enough to stay online" carve-out in the
/// app. `saveServiceCharge` went straight to Dio and `ServiceChargeCubit`
/// refused the edit outright when offline — the only write in the product that
/// told the operator to go find some internet. The value is one number on a
/// replicated `branches` row, so it has a local answer and an outbox operation
/// like every other write, and the size of the value was never the reason to
/// treat it differently.
abstract class ServiceChargeRepository {
  /// The configured percent, re-emitted when the branch row changes — this
  /// terminal's own edit, or one made elsewhere and replicated in.
  Stream<double?> watchServicePercent(String branchId);

  /// The same value read once, for the first frame.
  double? getServicePercent(String branchId);

  /// Writes the percent onto the local branch row and queues the `PUT` for
  /// replay. Returns as soon as both are committed; never awaits the network.
  Either<Failure, Unit> saveServicePercent(String branchId, double value);
}
