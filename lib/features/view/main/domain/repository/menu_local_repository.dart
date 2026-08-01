import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';

/// What `DepartmentSelectionCubit` depends on instead of calling usecases
/// (and, transitively, `DioClient`) directly — cache-first, connectivity-aware
/// for departments/categories. See offline-first-architecture-plan.md §3/§11
/// Phase 2.
abstract class MenuLocalRepository {
  Future<Either<Failure, List<DepartmentModel>>> getDepartments();

  Future<Either<Failure, List<CategoryModel>>> getCategories();

  /// Live search against the goods catalog — not cached. Offline just means
  /// no results, same as before this repository existed; there's no bounded
  /// local mirror of the full catalog to search against instead.
  Future<Either<Failure, List<GoodsModel>>> searchGoodsByName(String query);
}
