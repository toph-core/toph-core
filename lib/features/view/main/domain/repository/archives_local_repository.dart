import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';

/// What `ArchivesBloc`/`ArchiveBloc` depend on instead of calling usecases
/// (and, transitively, `DioClient`) directly.
///
/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4: the list side is a query over the
/// replicated `orders` table now, not a cache-first fetch. Every filter, date
/// range, bill-number search and page is answered locally and identically,
/// online or off — the old split, where only "today, page 1" had a local
/// answer, is gone.
abstract class ArchivesLocalRepository {
  /// One page of archives for [params]. Never touches the network, and
  /// therefore never fails with a `ConnectionFailure`.
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    ArchivesFilterRequestEntity params,
  );

  /// Bill detail by id. The one method still going to the network first,
  /// falling back to a per-id cache: a local detail needs a projection over
  /// `orders` + `order_items` + `goods` that does not exist yet.
  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(String id);

  /// Reactive read over the default view (unfiltered, "today", first page) —
  /// what the screen shows on open. Re-emits whenever replication changes any
  /// table the page reads from.
  Stream<ArchivesResponseEntity?> watchArchives();

  /// Synchronous snapshot of the same default view. Unlike the hydration-era
  /// version this is never `null` for lack of a mirror — an empty replica
  /// simply yields an empty page.
  ArchivesResponseEntity? getHydratedArchives();
}
