import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';

/// offline-first-target-architecture.md §9 (V5) + V9 (menu images). Not to
/// be confused with `MenuLocalRepository` (`menu_local_repository.dart`) —
/// that's the earlier, network-first-when-online/Future-based repository
/// from an earlier migration pass (`offline-first-architecture-plan.md`);
/// it's now only used for the live, uncached goods-name search
/// (`searchGoodsByName`). `DepartmentSelectionCubit` reads departments/
/// categories from this repository (purely-reactive `watchX()`/`getX()`
/// over `LocalDatabase`), same as `DetailBloc`.
abstract class MenuRepository {
  Stream<List<CategoryModel>> watchCategories();
  List<CategoryModel> getCategories();

  Stream<List<DepartmentModel>> watchDepartments();
  List<DepartmentModel> getDepartments();

  Stream<List<GoodsModel>> watchGoodsForCategory(String categoryId);
  List<GoodsModel> getGoodsForCategory(String categoryId);

  /// §8 Phase 5 — the recipe editor's ingredient/semi-finished picker
  /// (`menu_manage_screen.dart`). No dedicated model upstream — raw maps,
  /// same shape `MainRepository.getIngredients()`/`getCompounds()` return.
  Stream<List<Map<String, dynamic>>> watchIngredients();
  List<Map<String, dynamic>> getIngredients();

  Stream<List<Map<String, dynamic>>> watchCompounds();
  List<Map<String, dynamic>> getCompounds();

  /// V9: menu images, hydrated by `SyncEngine` (§8 Phase 1) instead of a
  /// `FutureBuilder` fetching on every build.
  Stream<List<int>?> watchImage(String objectName);
  List<int>? getImage(String objectName);

  /// Write-through for the one case `SyncEngine`'s own hydration pass can't
  /// cover yet — an image just uploaded this session, before the next
  /// hydration cycle would otherwise pick it up. The menu-editor screen's
  /// live-fetch fallback calls this so the result becomes durable/
  /// offline-capable immediately rather than only after the next tick.
  Future<void> saveImage(String objectName, List<int> bytes);
}
