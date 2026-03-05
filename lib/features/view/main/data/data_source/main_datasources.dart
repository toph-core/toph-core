import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_response/archives_response_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/close_shift/close_shift_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_shift/open_shift_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/shift/shift_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';

import 'package:mary_ai_pos/features/view/main/domain/entities/payment_pay_request_entity.dart';

abstract class MainDataSources {
  Future<Either<Failure, List<CafeTableModel>>> getTablesByHallId(
    String hallId,
  );
  Future<Either<Failure, List<HallModel>>> getHalls();
  Future<Either<Failure, List<CategoryModel>>> getCategories();
  Future<Either<Failure, List<GoodsModel>>> getGoodsByCategoryId(
    String categoryId,
  );
  Future<Either<Failure, List<GoodsModel>>> getGoodsWithName(String name);
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    ArchivesFilterRequestEntity request,
  );
  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(String id);

  Future<Either<Failure, ArchiveDetailEntity>> getPaymentDetailWithTableId(
    String id,
  );

  Future<Either<Failure, ArchiveDetailEntity>> getPaymentDetailWithId(
    String id,
  );

  Future<Either<Failure, bool>> createPayment({
    required PaymentPayRequestEntity request,
  });

  Future<Either<Failure, bool>> createOrder({
    required CreateOrderRequestModel request,
  });

  Future<Either<Failure, String>> createTakewayOrder({
    required CreateOrderRequestModel request,
  });

  Future<String> getOrderIdWithTableId({required String tableId});

  Future<Either<Failure, UserModel>> getUser();

  Future<Either<Failure, ShiftResponseModel?>> checkShift({required String id});

  Future<Either<Failure, ShiftResponseModel>> openShift({
    required OpenShiftModel request,
  });

  Future<Either<Failure, bool>> closeShift({
    required CloseShiftRequestModel request,
  });
}

class MainDataSourcesImpl implements MainDataSources {
  final DioClient _client;

  MainDataSourcesImpl(this._client);

  @override
  Future<Either<Failure, bool>> closeShift({
    required CloseShiftRequestModel request,
  }) async{
    try {
      await _client.post(ListAPI.closeShift(request.shiftId),data: request.toJson());
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on String catch (e) {
      return Left(MessageFailure(e));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, ShiftResponseModel>> openShift({
    required OpenShiftModel request,
  }) async {
    try {
      final response = await _client.post(ListAPI.openShift,data: request.toJson());
      return Right(ShiftResponseModel.fromJson(response.data['data']));
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on String catch (e) {
      return Left(MessageFailure(e));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, ShiftResponseModel?>> checkShift({
    required String id,
  }) async {
    try {
      final response = await _client.get(
        ListAPI.activeShift,
        queryParameters: {"cash_register_id": id},
      );
      return Right(ShiftResponseModel.fromJson(response.data['data']));
    } catch (e) {
      return const Right(null);
    }
  }

  @override
  Future<Either<Failure, UserModel>> getUser() async {
    try {
      final response = await _client.get(ListAPI.user);
      return Right(UserModel.fromJson(response.data['data']));
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on String catch (e) {
      return Left(MessageFailure(e));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<String> getOrderIdWithTableId({required String tableId}) async {
    try {
      final orders = await _client.dio.get(ListAPI.orderWithTableId(tableId));
      return orders.data['data'][0]['id'] ?? '';
    } catch (e) {
      return '';
    }
  }

  @override
  Future<Either<Failure, bool>> createPayment({
    required PaymentPayRequestEntity request,
  }) async {
    try {
      await _client.post(
        ListAPI.payToOrder(request.orderId),
        data: request.request(),
      );
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on String catch (e) {
      return Left(MessageFailure(e));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, String>> createTakewayOrder({
    required CreateOrderRequestModel request,
  }) async {
    try {
      final response = await _client.post(
        ListAPI.orders,
        data: request.createOrder(),
      );
      return Right(response.data['data']['id']);
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
  Future<Either<Failure, bool>> createOrder({
    required CreateOrderRequestModel request,
  }) async {
    try {
      if (request.tableStatus == TableStatus.busy) {
        Map<String, dynamic> requestJson = request.request();
        requestJson['order_id'] = await getOrderIdWithTableId(
          tableId: request.tableId,
        );
        if (requestJson['order_id'] != null) {
          await _client.dio.post(ListAPI.createOrderItems, data: requestJson);
        }
      } else if (request.tableStatus == TableStatus.away) {
        await _client.post(ListAPI.orders, data: request.request());
      } else {
        await _client.post(ListAPI.orders, data: request.request());
      }
      return const Right(true);
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
  Future<Either<Failure, ArchiveDetailEntity>> getPaymentDetailWithId(
    String id,
  ) async {
    try {
      final response = await _client.dio.get(ListAPI.archiveWithId(id));
      return Right(ArchiveDetailModel.fromJson(response.data['data']));
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on String catch (e) {
      return Left(MessageFailure(e));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, ArchiveDetailEntity>> getPaymentDetailWithTableId(
    String id,
  ) async {
    try {
      final orderId = await getOrderIdWithTableId(tableId: id);
      if (orderId.isEmpty) {
        throw "To'lov ma'lumotlarini olishda xatolik yuzaga keldi";
      }
      final response = await _client.dio.get(ListAPI.archiveWithId(orderId));
      return Right(ArchiveDetailModel.fromJson(response.data['data']));
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } on FormatException catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on TypeError catch (e, st) {
      if (kDebugMode) print('ParsingError: $e\n$st');
      return const Left(ParsingFailure());
    } on String catch (e) {
      return Left(MessageFailure(e));
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
      if (categoryId == 'all') {
        final response = await _client.get(ListAPI.goods);

        return Right(
          (response.data['data'] as List?)
                  ?.map((e) => GoodsModel.fromJson(e))
                  .toList() ??
              [],
        );
      } else {
        final response = await _client.get(ListAPI.categoriesGoods(categoryId));

        return Right(
          (response.data as List?)
                  ?.map((e) => GoodsModel.fromJson(e))
                  .toList() ??
              [],
        );
      }
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
  Future<Either<Failure, List<GoodsModel>>> getGoodsWithName(
    String name,
  ) async {
    try {
      final response = await _client.dio.get(
        ListAPI.goodsSearch,
        queryParameters: {'query': name},
      );

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

  @override
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    ArchivesFilterRequestEntity request,
  ) async {
    try {
      final response = await _client.dio.get(
        ListAPI.archives,
        queryParameters: request.request(),
      );
      Map<String, dynamic> json = response.data['data'];
      json['pagination'] = {
        "total": response.data['data']['total'],
        "limit": response.data['data']['limit'],
        "offset": response.data['data']['offset'],
      };
      return Right(ArchivesResponseModel.fromJson(json));
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
  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(
    String id,
  ) async {
    try {
      final response = await _client.dio.get(ListAPI.archiveWithId(id));
      return Right(ArchiveDetailModel.fromJson(response.data['data']));
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
