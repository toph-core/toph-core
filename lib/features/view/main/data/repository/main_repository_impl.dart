import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/pagination_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

class MainRepositoryImpl implements MainRepository {
  final MainDataSources _dataSources;

  MainRepositoryImpl(this._dataSources);

  @override
  Future<Either<Failure, List<CafeTableModel>>> getTablesByHallId(
    String hallId,
  ) {
    return _dataSources.getTablesByHallId(hallId);
  }

  @override
  Future<Either<Failure, bool>> createOrder({
    required CreateOrderRequestModel request,
  }) async => await _dataSources.createOrder(request: request);

  @override
  Future<Either<Failure, List<HallModel>>> getHalls() {
    return _dataSources.getHalls();
  }

  @override
  Future<Either<Failure, List<CategoryModel>>> getCategories() {
    return _dataSources.getCategories();
  }

  @override
  Future<Either<Failure, List<GoodsModel>>> getGoodsByCategoryId(
    String categoryId,
  ) {
    return _dataSources.getGoodsByCategoryId(categoryId);
  }

  @override
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    PaginationRequestEntity request,
  ) {
    return _dataSources.getArchives(request);
  }
}
