import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/core/media/local_image_cache.dart';
import 'package:mary_ai_pos/core/service/minio/minio_service.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';

class MenuRepositoryImpl implements MenuRepository {
  final LocalDatabase _localDb;

  MenuRepositoryImpl({required LocalDatabase localDb}) : _localDb = localDb;

  /// The image state machine, wired to the Hive store and the Minio fetcher.
  /// Lives in `core/media` so it can be tested without either.
  late final LocalImageCache _images = LocalImageCache(
    watch: _localDb.watchImage,
    read: _localDb.getImage,
    write: _localDb.saveImage,
    fetch: MinioService.instance.getImageByObjectName,
  );

  @override
  Stream<LocalImage> imageStream(String objectName) =>
      _images.stream(objectName);

  @override
  Stream<List<CategoryModel>> watchCategories() => _localDb.watchCategories();

  @override
  List<CategoryModel> getCategories() => _localDb.getCategories();

  @override
  Stream<List<DepartmentModel>> watchDepartments() => _localDb.watchDepartments();

  @override
  List<DepartmentModel> getDepartments() => _localDb.getDepartments();

  @override
  Stream<List<GoodsModel>> watchGoodsForCategory(String categoryId) =>
      _localDb.watchGoodsForCategory(categoryId);

  @override
  List<GoodsModel> getGoodsForCategory(String categoryId) =>
      _localDb.getGoodsForCategory(categoryId);

  @override
  List<GoodsModel> searchGoodsByName(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _localDb
        .getGoods()
        .where(
          (g) =>
              g.name.toLowerCase().contains(q) ||
              (g.nameI18n?.toLowerCase().contains(q) ?? false),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchIngredients() => _localDb.watchIngredients();

  @override
  List<Map<String, dynamic>> getIngredients() => _localDb.getIngredients();

  @override
  Stream<List<Map<String, dynamic>>> watchCompounds() => _localDb.watchCompounds();

  @override
  List<Map<String, dynamic>> getCompounds() => _localDb.getCompounds();

  @override
  Stream<List<int>?> watchImage(String objectName) => _localDb.watchImage(objectName);

  @override
  List<int>? getImage(String objectName) => _localDb.getImage(objectName);

  @override
  Future<void> saveImage(String objectName, List<int> bytes) =>
      _localDb.saveImage(objectName, bytes);
}
