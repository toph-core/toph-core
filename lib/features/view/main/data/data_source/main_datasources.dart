import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/restaurant_table.dart';

abstract class MainDataSources {
  Future<Either<Failure, List<RestaurantTable>>> getTables();
}

class MainDataSourcesImpl implements MainDataSources {
  final DioClient _client;

  MainDataSourcesImpl(this._client);
  @override
  Future<Either<Failure, List<RestaurantTable>>> getTables() async {
    try {
      final response = await _client.get(ListAPI.cafeTables);

      return Right(
        (response.data['data'] as List)
            .map((e) => RestaurantTable.fromJson(e))
            .toList(),
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
