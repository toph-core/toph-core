import 'package:mary_ai_pos/core/media/local_image_cache.dart';
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

  /// CLIENT_FACING_OFFLINE_PLAN.md §3: goods search is a local filter over
  /// the already-synced goods box — the full catalog is pulled into
  /// `LocalDatabase` at first-time setup / by `SyncEngine`'s hydration pass,
  /// so there is no reason left to hit the network per keystroke. Matches on
  /// `name` (and `nameI18n` when present), case-insensitive contains.
  List<GoodsModel> searchGoodsByName(String query);

  /// §8 Phase 5 — the recipe editor's ingredient/semi-finished picker
  /// (`menu_manage_screen.dart`). No dedicated model upstream — raw maps,
  /// same shape `MainRepository.getIngredients()`/`getCompounds()` return.
  Stream<List<Map<String, dynamic>>> watchIngredients();
  List<Map<String, dynamic>> getIngredients();

  Stream<List<Map<String, dynamic>>> watchCompounds();
  List<Map<String, dynamic>> getCompounds();

  /// The only way a widget should ask for a menu image.
  ///
  /// Emits from the local store, and on a miss fetches once in the background
  /// and write-throughs, so the same subscription turns into [ImageStatus.ready]
  /// when the bytes land. That is the whole reason this replaced two
  /// `FutureBuilder`s: a future rebuilt on every build refetches on every
  /// build, and the widget ends up owning retry, dedupe and caching decisions
  /// it has no business making.
  ///
  /// It also closes a real hole. The `minioObjectName` path in
  /// `CustomCachedNetworkImage` had no local store at all — `MinioService`
  /// memoizes per process, so it was one fetch per image per app run and
  /// nothing survived a restart. Those images did not exist offline. Now every
  /// image a terminal has ever displayed is on disk.
  Stream<LocalImage> imageStream(String objectName);
}
