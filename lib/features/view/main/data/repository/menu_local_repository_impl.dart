import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_local_repository.dart';

class MenuLocalRepositoryImpl implements MenuLocalRepository {
  final MainRepository _remote;
  final CacheService _cache;
  final ConnectivityCubit _connectivity;

  MenuLocalRepositoryImpl(this._remote, this._cache, this._connectivity);

  @override
  Future<Either<Failure, List<DepartmentModel>>> getDepartments() async {
    if (_connectivity.isOnline) {
      final result = await _remote.getDepartments();
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        await _cache.saveDepartments(ok.map((d) => d.toJson()).toList());
        return result;
      }
      // Online but the call itself failed — fall through to cache below.
    }
    final cached = _cache.getDepartments();
    if (cached.isEmpty) return const Left(ConnectionFailure());
    try {
      return Right(cached.map(DepartmentModel.fromJson).toList());
    } catch (_) {
      return const Left(ConnectionFailure());
    }
  }

  @override
  Future<Either<Failure, List<CategoryModel>>> getCategories() async {
    if (_connectivity.isOnline) {
      final result = await _remote.getCategories();
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        await _cache.saveCategories(ok.map((c) => c.toJson()).toList());
        return result;
      }
    }
    final cached = _cache.getCategories();
    if (cached.isEmpty) return const Left(ConnectionFailure());
    try {
      return Right(cached.map(CategoryModel.fromJson).toList());
    } catch (_) {
      return const Left(ConnectionFailure());
    }
  }

  @override
  Future<Either<Failure, List<GoodsModel>>> searchGoodsByName(String query) {
    return _remote.getGoodsWithName(query);
  }
}
