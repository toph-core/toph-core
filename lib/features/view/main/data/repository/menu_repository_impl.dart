import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/db/menu_query.dart';
import 'package:mary_ai_pos/core/media/local_image_cache.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';

class MenuRepositoryImpl implements MenuRepository {
  final MenuQuery _query;

  /// Injected rather than constructed: two owners of this would mean two
  /// dedupe sets and two fetches for the same bytes, which is the problem it
  /// exists to solve.
  final LocalImageCache _images;

  MenuRepositoryImpl({
    required replica.LocalDatabase replicaDb,
    required LocalImageCache images,
  })  : _query = MenuQuery(replicaDb),
        _images = images;

  @override
  Stream<LocalImage> imageStream(String objectName) =>
      _images.stream(objectName);

  @override
  Stream<List<CategoryModel>> watchCategories() => _query.watchCategories();

  @override
  List<CategoryModel> getCategories() => _query.categories();

  @override
  Stream<List<DepartmentModel>> watchDepartments() => _query.watchDepartments();

  @override
  List<DepartmentModel> getDepartments() => _query.departments();

  @override
  Stream<List<GoodsModel>> watchGoodsForCategory(String categoryId) =>
      _query.watchGoodsForCategory(categoryId);

  @override
  List<GoodsModel> getGoodsForCategory(String categoryId) =>
      _query.goodsForCategory(categoryId);

  @override
  List<GoodsModel> getAllGoods() => _query.goods();

  @override
  List<GoodsModel> searchGoodsByName(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _query
        .goods()
        .where(
          (g) =>
              g.name.toLowerCase().contains(q) ||
              (g.nameI18n?.toLowerCase().contains(q) ?? false),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchIngredients() =>
      _query.watchIngredients();

  @override
  List<Map<String, dynamic>> getIngredients() => _query.ingredients();

  @override
  Stream<List<Map<String, dynamic>>> watchCompounds() => _query.watchCompounds();

  @override
  List<Map<String, dynamic>> getCompounds() => _query.compounds();
}
