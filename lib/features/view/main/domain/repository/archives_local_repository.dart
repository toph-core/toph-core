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
}
