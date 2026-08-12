import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/menu_admin_query.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/local_write_result.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_admin_local_repository.dart';

class MenuAdminLocalRepositoryImpl implements MenuAdminLocalRepository {
  final LocalDatabase _db;
  final LocalWriter _writer;
  final MenuAdminQuery _query;

  MenuAdminLocalRepositoryImpl(this._db, this._writer)
      : _query = MenuAdminQuery(_db);

  // ── Reads ────────────────────────────────────────────────────────────

  @override
  Stream<List<CategoryModel>> watchCategories() =>
      _query.watch(getCategories);

  @override
  List<CategoryModel> getCategories() {
    final out = <CategoryModel>[];
    for (final row in _query.categories()) {
      try {
        out.add(CategoryModel.fromJson(row));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  @override
  GoodsPage searchGoods({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  }) {
    final rows = _query.goods(
      limit: limit,
      offset: offset,
      categoryId: categoryId,
      search: search,
    );
    return (
      items: _decode(rows),
      total: _query.goodsCount(categoryId: categoryId, search: search),
    );
  }

  @override
  Stream<GoodsPage> watchGoods({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  }) =>
      _query.watch(() => searchGoods(
            limit: limit,
            offset: offset,
            categoryId: categoryId,
            search: search,
          ));

  /// One malformed row costs that row, not the page — same rule as the floor
  /// plan, and for the same reason: a replica holds whatever the server logged.
  static List<GoodsModel> _decode(List<Map<String, dynamic>> rows) {
    final out = <GoodsModel>[];
    for (final row in rows) {
      try {
        out.add(GoodsModel.fromJson(row));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  @override
  Map<String, dynamic>? goodWithCalculations(String id) {
    final good = _query.goodById(id);
    if (good == null) return null;
    // The join the endpoint did server-side. `calculation.good_id` is indexed,
    // so this is a lookup, not a scan.
    final calculations = _db.selectData(
      'SELECT data FROM calculation WHERE good_id = ? AND deleted_at IS NULL',
      [id],
    );
    return {...good, 'calculations': calculations};
  }

  @override
  List<Map<String, dynamic>> translations() => _db.selectData(
        'SELECT data FROM translations WHERE deleted_at IS NULL',
      );

  // ── Writes ───────────────────────────────────────────────────────────

  @override
  Either<Failure, LocalWriteResult> createCategory(String name) =>
      _guard(() {
        _writer.enqueueOnly(
          entity: 'categories',
          action: 'create',
          request: {'name': name},
        );
        return LocalWriteResult.queued;
      });

  @override
  Either<Failure, LocalWriteResult> saveGood({
    String? mealId,
    required Map<String, dynamic> body,
  }) =>
      _guard(() {
        if (mealId == null) {
          _writer.enqueueOnly(
            entity: 'goods',
            action: 'create',
            request: body,
          );
          return LocalWriteResult.queued;
        }
        // Only the good's own columns go into the local row. `calculations` is
        // a nested list the endpoint unpacks into its own table; mirroring that
        // unpack here would mean inventing ids for rows the server owns, so the
        // calculation side stays queued-only and lands on the next pull. The
        // good's name and price — what the list screen shows — are immediate.
        final existing = _db.byId('goods', mealId) ?? const <String, dynamic>{};
        final row = {...existing, ...body, 'id': mealId}..remove('calculations');
        _writer.write(
          entity: 'goods',
          id: mealId,
          row: row,
          request: body,
        );
        return LocalWriteResult.applied;
      });

  @override
  Either<Failure, LocalWriteResult> deleteGood(String id) => _guard(() {
        _writer.delete(entity: 'goods', id: id);
        return LocalWriteResult.applied;
      });

  @override
  Either<Failure, LocalWriteResult> createTranslation(
    Map<String, dynamic> body,
  ) =>
      _guard(() {
        _writer.enqueueOnly(
          entity: 'translations',
          action: 'create',
          request: body,
        );
        return LocalWriteResult.queued;
      });

  @override
  Either<Failure, LocalWriteResult> updateTranslation(
    String id,
    Map<String, dynamic> body,
  ) =>
      _guard(() {
        final existing =
            _db.byId('translations', id) ?? const <String, dynamic>{};
        _writer.write(
          entity: 'translations',
          id: id,
          row: {...existing, ...body, 'id': id},
          request: body,
        );
        return LocalWriteResult.applied;
      });

  Either<Failure, LocalWriteResult> _guard(LocalWriteResult Function() body) {
    try {
      return Right(body());
    } catch (e) {
      return Left(MessageFailure('$e'));
    }
  }
}
