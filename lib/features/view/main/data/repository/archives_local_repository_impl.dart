import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/archives_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/order_detail_query.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_filter_request/archives_filter_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_response/archives_response_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_summary_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/archives_local_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the archives screen, list and
/// detail, entirely on the replica.
///
/// What this used to be: online-first with a cache fallback, mirroring only the
/// unfiltered "today, page 1" view. Any date range, bill-number search or page
/// beyond the first had no local answer and went to the network, so the screen
/// was offline-capable in exactly one of its states. Nothing here reaches for
/// the network now, and there is no `ConnectivityCubit` fork left to take.
///
/// [getArchiveWithId] was the last method on the old path, waiting on "a
/// projection over `orders` + `order_items` + `goods` that does not exist yet".
/// It does: [OrderDetailQuery.liveOrderById] assembles exactly that — header,
/// joined table and hall, items with their goods' names — and does it
/// regardless of `bill_status`, because the payment screen needed to keep
/// showing a bill after it was paid. A closed bill is the same read.
///
/// A bill absent from the replica now returns a failure instead of a fetch.
/// That is reachable only in theory: the list this detail is opened from is
/// itself a query over the same `orders` table, so a row the detail cannot
/// find is a row the operator could not have tapped.
class ArchivesLocalRepositoryImpl implements ArchivesLocalRepository {
  final ArchivesQuery _archives;
  final OrderDetailQuery _detail;

  ArchivesLocalRepositoryImpl(LocalDatabase replica)
    : _archives = ArchivesQuery(replica),
      _detail = OrderDetailQuery(replica);

  /// What the screen shows on open, before the operator has touched a filter.
  static ArchivesFilterRequestEntity get _defaultView =>
      const ArchivesFilterRequestModel(
        filterType: ArchivesFilterType.Today,
        pagination: PaginationRequestModel(limit: kArchivesPageSize),
      );

  @override
  Stream<ArchivesResponseEntity?> watchArchives(
    ArchivesFilterRequestEntity params,
  ) => _archives.watch(params).map(ArchivesResponseModel.fromJson);

  @override
  Stream<ArchivesSummaryEntity> watchSummary(
    ArchivesFilterRequestEntity params,
  ) => _archives.watchSummary(params).map(ArchivesSummaryEntity.fromJson);

  @override
  ArchivesResponseEntity? getHydratedArchives() {
    try {
      return ArchivesResponseModel.fromJson(_archives.page(_defaultView));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    ArchivesFilterRequestEntity params,
  ) async {
    try {
      return Right(ArchivesResponseModel.fromJson(_archives.page(params)));
    } catch (e) {
      // A malformed replica row is a local fault, not a connection one — say so
      // rather than telling the cashier to check the network.
      return Left(MessageFailure('$e'));
    }
  }

  @override
  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(
    String id,
  ) async {
    final json = _detail.liveOrderById(id);
    if (json == null) {
      return const Left(MessageFailure('Chek topilmadi'));
    }
    try {
      return Right(ArchiveDetailModel.fromJson(json));
    } catch (e) {
      // A malformed replica row is a local fault, not a connection one.
      return Left(MessageFailure('$e'));
    }
  }
}
