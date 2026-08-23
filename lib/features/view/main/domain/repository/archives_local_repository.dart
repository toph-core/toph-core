import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_summary_entity.dart';

/// What `ArchivesBloc`/`ArchiveBloc` depend on instead of calling usecases
/// (and, transitively, `DioClient`) directly.
///
/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4: the list side is a query over the
/// replicated `orders` table now, not a cache-first fetch. Every filter, date
/// range, bill-number search and page is answered locally and identically,
/// online or off — the old split, where only "today, page 1" had a local
/// answer, is gone.
/// How many bills the Orders list loads at a time, and how much more it loads
/// each time the operator reaches the bottom.
///
/// It is a page size, not a ceiling. The list used to ask for 20 rows and had
/// no way to ask for the next 20 — no scroll handler, no button, and the one
/// piece of arithmetic that would have built the next request computed a page
/// index where a row offset was needed. So a venue's 21st bill of the day was
/// unreachable from the terminal in every filter, while sitting in both the
/// local replica and the backend. `ArchivesBloc` grows its window by this much
/// per load and stops when it holds `pagination.total`.
const int kArchivesPageSize = 50;

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

  /// Reactive read over [params] — re-emits whenever replication changes any
  /// table the page reads from.
  ///
  /// [params] used to be implicit ("the default view: unfiltered, today, first
  /// page"), which is what forced `ArchivesBloc` to carry an `_isDefaultView`
  /// guard: any other view had to come from a one-shot fetch, and the stream
  /// had to be suppressed so it could not overwrite it. Every view is a query
  /// over the same table, so every view can be the live one, and the guard is
  /// gone with the split.
  Stream<ArchivesResponseEntity?> watchArchives(
    ArchivesFilterRequestEntity params,
  );

  /// Reactive totals over the whole window [params] describes, independent of
  /// how many rows the list has loaded.
  Stream<ArchivesSummaryEntity> watchSummary(
    ArchivesFilterRequestEntity params,
  );

  /// Synchronous snapshot of the default view. Unlike the hydration-era
  /// version this is never `null` for lack of a mirror — an empty replica
  /// simply yields an empty page.
  ArchivesResponseEntity? getHydratedArchives();
}
