import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/archives_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_filter_request/archives_filter_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_response/archives_response_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/archives_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the archives *list* is a local
/// query now.
///
/// What this used to be: online-first with a cache fallback, mirroring only the
/// unfiltered "today, page 1" view. Any date range, bill-number search or page
/// beyond the first had no local answer and went to the network, so the screen
/// was offline-capable in exactly one of its states. `getArchives` no longer
/// reaches for the network in any of them, and there is no `ConnectivityCubit`
/// fork left to take.
///
/// [getArchiveWithId] is the one method still on the old path. Building a bill
/// detail locally needs a projection over `orders` + `order_items` + `goods`
/// that does not exist yet; migrating the list without it is safe because the
/// list is pure read (archives are closed bills — nothing on this screen
/// writes), so there is no write path that could land locally and go unseen.
class ArchivesLocalRepositoryImpl implements ArchivesLocalRepository {
  final MainRepository _remote;
  final CacheService _cache;
  final ArchivesQuery _archives;

  ArchivesLocalRepositoryImpl(this._remote, this._cache, LocalDatabase replica)
      : _archives = ArchivesQuery(replica);

  /// What the screen shows on open, and the only view the old cache mirrored.
  static ArchivesFilterRequestEntity get _defaultView =>
      const ArchivesFilterRequestModel(
        filterType: ArchivesFilterType.Today,
        pagination: PaginationRequestModel(limit: 20),
      );

  @override
  Stream<ArchivesResponseEntity?> watchArchives() =>
      _archives.watch(_defaultView).map(ArchivesResponseModel.fromJson);

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
    final result = await _remote.getArchiveWithId(id);
    final ok = result.fold((_) => null, (r) => r);
    if (ok != null) {
      await _cache.saveArchiveDetail(id, (ok as ArchiveDetailModel).toJson());
      return result;
    }
    final cachedJson = _cache.getArchiveDetail(id);
    if (cachedJson == null) return const Left(ConnectionFailure());
    try {
      return Right(ArchiveDetailModel.fromJson(cachedJson));
    } catch (_) {
      return const Left(ConnectionFailure());
    }
  }
}
