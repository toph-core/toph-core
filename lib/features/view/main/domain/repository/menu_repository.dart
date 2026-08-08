import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';

/// offline-first-target-architecture.md §9 (V5) + V9 (menu images). Not to
/// be confused with `MenuLocalRepository` (`menu_local_repository.dart`) —
/// that's an earlier, still-live cache-first/Future-based repository for
/// `DepartmentSelectionCubit`'s own screen, from a different, earlier
/// migration pass (`offline-first-architecture-plan.md`); this one is the
/// purely-reactive `watchX()` surface `DetailBloc`'s category/goods reads
/// use, per this document's §1.2 shape. Both currently exist side by side —
/// consolidating them is out of scope here (see EXECUTION_CONCERNS.md).
abstract class MenuRepository {
  Stream<List<CategoryModel>> watchCategories();
  List<CategoryModel> getCategories();

  Stream<List<GoodsModel>> watchGoodsForCategory(String categoryId);
  List<GoodsModel> getGoodsForCategory(String categoryId);

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
