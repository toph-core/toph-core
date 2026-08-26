import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/menu_admin_query.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/features/view/main/data/outbox/menu_admin_outbox.dart' show kOutboxHeadersKey;
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
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
  Stream<List<Map<String, dynamic>>> watchIngredients() =>
      _query.watch(getIngredients);

  @override
  List<Map<String, dynamic>> getIngredients() => _query.ingredients();

  @override
  Stream<List<Map<String, dynamic>>> watchCompounds() =>
      _query.watch(getCompounds);

  @override
  List<Map<String, dynamic>> getCompounds() => _query.compounds();

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
  Either<Failure, Unit> createCategory(String name) =>
      _guard(() {
        _writer.create(
          entity: 'categories',
          row: {'name': name},
          request: {'name': name},
        );
        return unit;
      });

  @override
  Either<Failure, Unit> saveGood({
    String? mealId,
    required Map<String, dynamic> body,
    Map<String, String> headers = const {},
  }) =>
      _guard(() {
        final request = headers.isEmpty
            ? body
            : {...body, kOutboxHeadersKey: headers};
        if (mealId == null) {
          // The good's own columns land locally; `calculations` stays out of
          // the row for the same reason an edit does — those are the server's
          // rows, in their own table.
          _writer.create(
            entity: 'goods',
            row: {...body}..remove('calculations'),
            request: request,
          );
          return unit;
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
          request: request,
        );
        return unit;
      });

  @override
  Either<Failure, Unit> deleteGood(String id) => _guard(() {
        _writer.delete(entity: 'goods', id: id);
        return unit;
      });

  @override
  Either<Failure, String> createTranslation(
    Map<String, dynamic> body,
  ) =>
      _guardValue(() {
        // Written locally under a provisional id, which a good referencing it
        // can now carry: the drainer repoints that reference when the real id
        // arrives. This is what unblocks D11.
        //
        // The id is returned rather than swallowed — it is the whole point. A
        // caller composing a good needs something to put in `name_i18n` before
        // the server has spoken, and this is it.
        return _writer.create(entity: 'translations', row: body, request: body);
      });

  @override
  Either<Failure, Unit> updateTranslation(
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
        return unit;
      });

  Either<Failure, Unit> _guard(Unit Function() body) => _guardValue(body);

  Either<Failure, T> _guardValue<T>(T Function() body) {
    try {
      return Right(body());
    } catch (e) {
      return Left(MessageFailure('$e'));
    }
  }
}
