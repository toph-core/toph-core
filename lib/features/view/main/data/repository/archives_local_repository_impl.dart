import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_response/archives_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/archives_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

class ArchivesLocalRepositoryImpl implements ArchivesLocalRepository {
  final MainRepository _remote;
  final CacheService _cache;
  final ConnectivityCubit _connectivity;
  final LocalDatabase _localDb;

  ArchivesLocalRepositoryImpl(
    this._remote,
    this._cache,
    this._connectivity,
    this._localDb,
  );

  @override
  Stream<ArchivesResponseEntity?> watchArchives() => _localDb.watchArchives().map(
        (raw) => raw == null ? null : ArchivesResponseModel.fromJson(raw),
      );

  @override
  ArchivesResponseEntity? getHydratedArchives() {
    final raw = _localDb.getArchives();
    if (raw == null) return null;
    try {
      return ArchivesResponseModel.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isFiltered(ArchivesFilterRequestEntity params) =>
      params.archiveNum != null ||
      params.startDate != null ||
      params.endDate != null ||
      params.billStatus != null;

  @override
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    ArchivesFilterRequestEntity params,
  ) async {
    if (_connectivity.isOnline) {
      final result = await _remote.getArchives(params);
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        // Only cache the common "first page, unfiltered" view — what a
        // reopened archive screen shows immediately when offline. Filtered/
        // paginated queries aren't mirrored locally; the underlying dataset
        // can be large and query-shaped in ways a flat cache doesn't fit.
        if ((params.pagination?.offset ?? 0) == 0 && !_isFiltered(params)) {
          // `ok` is always the concrete model at runtime (see
          // MainDataSourcesImpl.getArchives) — the entity interface itself
          // deliberately has no toJson, that's a data-layer concern.
          await _cache.saveArchivesList((ok as ArchivesResponseModel).toJson());
        }
        return result;
      }
      // Online but the call itself failed (e.g. connection dropped mid-request)
      // — fall through to cache below rather than surfacing the failure.
    }
    final cachedJson = _cache.getArchivesList();
    if (cachedJson == null) return const Left(ConnectionFailure());
    try {
      return Right(ArchivesResponseModel.fromJson(cachedJson));
    } catch (_) {
      return const Left(ConnectionFailure());
    }
  }

  @override
  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(
    String id,
  ) async {
    if (_connectivity.isOnline) {
      final result = await _remote.getArchiveWithId(id);
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        await _cache.saveArchiveDetail(id, (ok as ArchiveDetailModel).toJson());
        return result;
      }
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
