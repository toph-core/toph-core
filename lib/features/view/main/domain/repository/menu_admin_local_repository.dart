import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';

/// One page of the admin goods list, with the count the paginator needs.
typedef GoodsPage = ({List<GoodsModel> items, int total});

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the two menu-admin screens.
///
/// These were the last screens I expected to migrate, because the plan's note
/// about missing `modifiers` blocking "the order screen" reads as if it covers
/// anything menu-shaped. It does not: neither screen references modifiers, and
/// everything they do read — goods, calculations, ingredients, categories,
/// translations — replicates today.
abstract class MenuAdminLocalRepository {
  /// The category list both screens show.
  ///
  /// From the replica, not the Hive store the rest of `MenuRepository` still
  /// reads — same rule as everywhere else this migration has gone: a screen
  /// whose writes land in the replica must read the replica, or it cannot see
  /// its own edits.
  Stream<List<CategoryModel>> watchCategories();
  List<CategoryModel> getCategories();

  /// A page of goods matching the filters, and the total that match.
  ///
  /// Synchronous: both come from one local database, so there is no window
  /// where the list has loaded and the count has not.
  GoodsPage searchGoods({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  });

  Stream<GoodsPage> watchGoods({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  });

  /// The manage screen's two picker lists.
  Stream<List<Map<String, dynamic>>> watchIngredients();
  List<Map<String, dynamic>> getIngredients();
  Stream<List<Map<String, dynamic>>> watchCompounds();
  List<Map<String, dynamic>> getCompounds();

  /// The good, its calculation rows and its ingredient rows, assembled locally.
  ///
  /// Replaces `GET /goods/{id}?include=calculations`, which the editor called
  /// three times per open — once for the good, once for calculations, once
  /// after saving.
  Map<String, dynamic>? goodWithCalculations(String id);

  /// Every translation row, keyed as the editor wants them.
  List<Map<String, dynamic>> translations();

  Either<Failure, Unit> createCategory(String name);

  /// Saves a good and its calculation rows as one operation.
  ///
  /// [mealId] null means create, which queues rather than applying — see
  /// `LocalWriteResult`. An edit applies locally and immediately.
  /// [headers] is the caller's brand/branch scope.
  ///
  /// Carried in the queued operation rather than resolved when it is sent: the
  /// drain happens later, possibly after a shift change, and the write belongs
  /// to the scope of whoever made it — not whoever happens to be logged in when
  /// the network comes back. Any queued write with request context has this
  /// problem; this is the first one that has any.
  Either<Failure, Unit> saveGood({
    String? mealId,
    required Map<String, dynamic> body,
    Map<String, String> headers = const {},
  });

  Either<Failure, Unit> deleteGood(String id);

  Either<Failure, Unit> createTranslation(Map<String, dynamic> body);

  Either<Failure, Unit> updateTranslation(
    String id,
    Map<String, dynamic> body,
  );
}
