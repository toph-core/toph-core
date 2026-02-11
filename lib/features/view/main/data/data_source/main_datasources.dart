import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';

abstract class MainDataSources {
  Future<Either<Failure, List<CafeTableModel>>> getTablesByHallId(
    String hallId,
  );
  Future<Either<Failure, List<HallModel>>> getHalls();
  Future<Either<Failure, List<CategoryModel>>> getCategories();
  Future<Either<Failure, List<GoodsModel>>> getGoodsByCategoryId(
    String categoryId,
  );
}

class MainDataSourcesImpl implements MainDataSources {
  final DioClient _client;

  MainDataSourcesImpl(this._client);
  @override
  Future<Either<Failure, List<CafeTableModel>>> getTablesByHallId(
    String hallId,
  ) async {
    try {
      final response = await _client.get(
        "${ListAPI.cafeTablesByHallId}/$hallId",
      );

      return Right(
        (response.data['data'] as List?)
                ?.map((e) => CafeTableModel.fromJson(e))
                .toList() ??
            [],
      );
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<HallModel>>> getHalls() async {
    try {
      final response = await _client.get(ListAPI.halls);

      return Right(
        (response.data['data'] as List?)
                ?.map((e) => HallModel.fromJson(e))
                .toList() ??
            [],
      );
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<CategoryModel>>> getCategories() async {
    try {
      final response = await _client.get(ListAPI.categories);

      return Right(
        (response.data['data'] as List?)
                ?.map((e) => CategoryModel.fromJson(e))
                .toList() ??
            [],
      );
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<GoodsModel>>> getGoodsByCategoryId(
    String categoryId,
  ) async {
    try {
      final response = await _client.get(ListAPI.categoriesGoods(categoryId));

      return Right(
        (response.data as List?)?.map((e) => GoodsModel.fromJson(e)).toList() ??
            [],
      );
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }
}
