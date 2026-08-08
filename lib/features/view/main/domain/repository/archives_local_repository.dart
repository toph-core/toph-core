import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';

/// What `ArchivesBloc`/`ArchiveBloc` depend on instead of calling usecases
/// (and, transitively, `DioClient`) directly — cache-first, connectivity-aware.
/// See offline-first-architecture-plan.md §3/§11 Phase 2.
abstract class ArchivesLocalRepository {
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    ArchivesFilterRequestEntity params,
  );

  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(String id);

  /// Reactive read over the default (unfiltered, "today", first page) view —
  /// `SyncEngine`-hydrated, per §8 Phase 6/V8. Emits `null` until the first
  /// hydration lands. Filtered/searched/paginated-beyond-page-1 queries have
  /// no local mirror and must still go through [getArchives] — a real
  /// cross-side dependency (CLIENT_FACING_OFFLINE_PLAN.md §4): converting
  /// them client-side is pointless until the sync side hydrates more than
  /// "today, page 1" into the archives box.
  Stream<ArchivesResponseEntity?> watchArchives();

  /// Synchronous snapshot of the same hydrated default view — `null` until
  /// the first hydration lands. Lets `ArchivesBloc` decide on open whether
  /// the default view can be served locally (plan §4) or still needs the
  /// one legacy network fetch as a first-fill fallback.
  ArchivesResponseEntity? getHydratedArchives();
}
