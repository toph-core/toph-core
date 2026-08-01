import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/utils/order_conflict_helper.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/table_timer_local_repository.dart';

class TableTimerLocalRepositoryImpl implements TableTimerLocalRepository {
  final DioClient _client;

  TableTimerLocalRepositoryImpl(this._client);

  @override
  Future<Either<Failure, TableTimerResponse?>> getTimer(String orderId) async {
    try {
      final res = await _client.get(ListAPI.orderTableTimer(orderId));
      final raw = res.data['data'];
      if (raw is! Map<String, dynamic>) return const Right(null);
      return Right(TableTimerResponse.fromJson(raw));
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, TableBillDetails>> getBillDetails(
    String orderId,
  ) async {
    try {
      final res = await _client.get(ListAPI.archiveWithId(orderId));
      final raw = res.data['data'];
      if (raw is! Map<String, dynamic>) return const Right(TableBillDetails());
      final rawPauses = raw['pause_periods'];
      final pauses = rawPauses is List
          ? rawPauses
                .whereType<Map<String, dynamic>>()
                .map(PauseInterval.fromJson)
                .toList()
          : null;
      final segments = parseBillTableSessionsToSegments(raw['table_sessions']);
      return Right(TableBillDetails(pauses: pauses, segments: segments));
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, TimedOrderCreateResult>> createTimedOrder({
    required String tableId,
    required int guestCount,
  }) async {
    try {
      final orderRes = await _client.post(
        ListAPI.orders,
        data: {
          'table_id': tableId,
          'guest_count': guestCount,
          'items': <dynamic>[],
          'status': 'open',
          'order_type': 'dine_in',
          'comment': '',
        },
      );
      final data = orderRes.data['data'];
      final orderId = (data is Map<String, dynamic>)
          ? (data['id'] as String? ?? data['order_id'] as String?)
          : null;
      if (orderId == null || orderId.isEmpty) {
        return const Left(EmptyFailure());
      }
      return Right(TimedOrderCreateResult(orderId));
    } on DioException catch (e) {
      // 409 Conflict: stolda mavjud faol buyurtma bor. Javob:
      // {"error": "stol already has an active buyurtma: <uuid>", ...}
      if (e.response?.statusCode == 409) {
        final raw = e.response?.data;
        final msg = raw is Map
            ? (raw['error'] ?? raw['message']).toString()
            : '';
        final existingOrderId = extractExistingOrderIdFromConflict(msg);
        if (existingOrderId != null && existingOrderId.isNotEmpty) {
          return Right(
            TimedOrderCreateResult(existingOrderId, wasExisting: true),
          );
        }
      }
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, TableTimerResponse?>> startTimer(String orderId) =>
      _postAndParseTimer(ListAPI.orderTableTimerStart(orderId));

  @override
  Future<Either<Failure, TableTimerResponse?>> pauseTimer(String orderId) =>
      _postAndParseTimer(ListAPI.orderTableTimerPause(orderId));

  @override
  Future<Either<Failure, TableTimerResponse?>> resumeTimer(String orderId) =>
      _postAndParseTimer(ListAPI.orderTableTimerResume(orderId));

  Future<Either<Failure, TableTimerResponse?>> _postAndParseTimer(
    String path,
  ) async {
    try {
      final res = await _client.post(path);
      final raw = res.data['data'];
      if (raw is Map<String, dynamic>) {
        return Right(TableTimerResponse.fromJson(raw));
      }
      return const Right(null);
    } on DioException catch (e) {
      return Left(handleDioException(e));
    } catch (_) {
      return const Left(UnknownFailure());
    }
  }
}
