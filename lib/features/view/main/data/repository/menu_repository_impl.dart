import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';

class MenuRepositoryImpl implements MenuRepository {
  final LocalDatabase _localDb;

  MenuRepositoryImpl({required LocalDatabase localDb}) : _localDb = localDb;

  @override
  Stream<List<CategoryModel>> watchCategories() => _localDb.watchCategories();

  @override
  List<CategoryModel> getCategories() => _localDb.getCategories();

  @override
  Stream<List<GoodsModel>> watchGoodsForCategory(String categoryId) =>
      _localDb.watchGoodsForCategory(categoryId);

  @override
  List<GoodsModel> getGoodsForCategory(String categoryId) =>
      _localDb.getGoodsForCategory(categoryId);

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
