import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/utils/order_conflict_helper.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/order_line_item/order_line_item_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/waiter_local_repository.dart';

class WaiterLocalRepositoryImpl implements WaiterLocalRepository {
  final DioClient _client;
  final MainRepository _remote;
  final CacheService _cache;
  final ConnectivityCubit _connectivity;

  WaiterLocalRepositoryImpl(
    this._client,
    this._remote,
    this._cache,
    this._connectivity,
  );

  @override
  Future<Either<Failure, List<OpenOrderModel>>> getOpenOrders({
    required WaiterOrdersListMode mode,
    String lang = 'uz',
    String scope = 'active',
    int limit = 50,
    int offset = 0,
  }) async {
    if (_connectivity.isOnline) {
      final result = await _fetchOpenOrders(
        mode: mode,
        lang: lang,
        scope: scope,
        limit: limit,
        offset: offset,
      );
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        // Only the default first-page view is cached — same "what's on
        // screen when connectivity drops" scope as archives/menu.
        if (offset == 0) {
          await _cache.saveWaiterOpenOrders(
            mode.name,
            ok.map((o) => o.toJson()).toList(),
          );
        }
        return result;
      }
      // Online but the call itself failed — fall through to cache below.
    }
    final cachedList = _cache.getWaiterOpenOrders(mode.name);
    if (cachedList.isEmpty) return const Left(ConnectionFailure());
    try {
      return Right(cachedList.map(OpenOrderModel.fromJson).toList());
    } catch (_) {
      return const Left(ConnectionFailure());
    }
  }

  Future<Either<Failure, List<OpenOrderModel>>> _fetchOpenOrders({
    required WaiterOrdersListMode mode,
    required String lang,
    required String scope,
    required int limit,
    required int offset,
  }) async {
    try {
      final response = mode == WaiterOrdersListMode.branchOrders
          ? await _client.get(
              ListAPI.orders,
              queryParameters: {'lang': lang, 'limit': limit, 'offset': offset},
            )
          : await _client.get(
              ListAPI.ordersMy,
              queryParameters: {
                'lang': lang,
                'scope': scope,
                'limit': limit,
                'offset': offset,
              },
            );
      final rawData = response.data['data'];
      List<dynamic> list;
      if (rawData is List) {
        list = rawData;
      } else if (rawData is Map && rawData['data'] is List) {
        list = rawData['data'] as List;
      } else {
        list = [];
      }
      final orders = list
          .map((e) => OpenOrderModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return Right(orders);
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, OpenOrderModel?>> getOrderDetail(
    String orderId,
  ) async {
    if (orderId.isEmpty) return const Right(null);
    try {
      final response = await _client.get(
        ListAPI.orderById(orderId),
        queryParameters: {'lang': 'uz'},
      );
      final raw = response.data['data'];
      if (raw is! Map<String, dynamic>) return const Right(null);
      return Right(OpenOrderModel.fromJson(raw));
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<OrderLineItemModel>>> getOrderItems(
    String orderId,
  ) async {
    if (orderId.isEmpty) return const Right([]);
    try {
      final response = await _client.get(
        ListAPI.orderItemsListByOrder(orderId),
        queryParameters: {'lang': 'uz'},
      );
      final raw = response.data['data'];
      List<dynamic> list;
      if (raw is List) {
        list = raw;
      } else if (raw is Map<String, dynamic>) {
        if (raw['items'] is List) {
          list = raw['items'] as List;
        } else if (raw['order'] is Map) {
          final o = raw['order'] as Map;
          list = o['items'] is List ? o['items'] as List : [];
        } else {
          list = [];
        }
      } else {
        list = [];
      }
      final items = list
          .whereType<Map>()
          .map(
            (e) => OrderLineItemModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
      return Right(items);
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<UserModel>>> getStaffWaiters() async {
    final result = await _remote.getUsers();
    return result.map(
      (users) => users.where((u) => u.role == UserRole.waiter).toList(),
    );
  }

  @override
  Future<Either<Failure, bool>> cancelOrderItem({
    required String orderItemId,
    String? comment,
  }) async {
    try {
      await _client.post(
        ListAPI.orderItemCancel(orderItemId),
        queryParameters: {'lang': 'uz'},
        data: <String, dynamic>{
          if (comment != null && comment.trim().isNotEmpty)
            'comment': comment.trim(),
        },
      );
      return const Right(true);
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> sendItems({
    required String orderId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await _client.post(
        ListAPI.orderItems(orderId),
        queryParameters: {'lang': 'uz'},
        data: {'items': items},
      );
      return const Right(true);
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> closeOrder({
    required String orderId,
    required Map<String, dynamic> payBody,
  }) async {
    try {
      await _client.post(ListAPI.payToOrder(orderId), data: payBody);
      return const Right(true);
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, WaiterCreateOrderResult>> createOrder(
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.post(ListAPI.orders, data: body);
      final raw = response.data['data'];
      final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final orderId = data['id'] as String? ?? '';
      if (orderId.isEmpty) return const Left(EmptyFailure());
      double? sp;
      final rawSp = data['service_percent'];
      if (rawSp is num) {
        sp = rawSp.toDouble();
      } else if (rawSp != null) {
        sp = double.tryParse(rawSp.toString());
      }
      return Right(
        WaiterCreateOrderResult(
          orderId,
          servicePercent: sp,
          totalAmount: data['total_amount']?.toString(),
          serviceAmount: data['service_amount']?.toString(),
          orderType: data['order_type'] as String?,
        ),
      );
    } on DioException catch (e) {
      // 409 Conflict: stol allaqachon faol buyurtmaga ega. Xato ko'rsatish
      // o'rniga mavjud buyurtmani yuklab, panelni o'shanga ochamiz — shu
      // orqali orphan/duplicate bill hosil bo'lishining oldi olinadi.
      if (e.response?.statusCode == 409) {
        final raw = e.response?.data;
        final msg = raw is Map
            ? (raw['error'] ?? raw['message'])?.toString()
            : null;
        final existingId = extractExistingOrderIdFromConflict(msg);
        if (existingId != null && existingId.isNotEmpty) {
          return Right(WaiterCreateOrderResult(existingId, wasExisting: true));
        }
      }
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }
}
