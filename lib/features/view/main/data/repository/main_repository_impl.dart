import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/db/branch_query.dart';
import 'package:mary_ai_pos/core/db/local_database.dart' as replica;
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:mary_ai_pos/features/view/main/data/models/close_shift/close_shift_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_shift/open_shift_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/shift/shift_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';

import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

class MainRepositoryImpl implements MainRepository {
  final MainDataSources _dataSources;
  final BranchQuery _branches;

  MainRepositoryImpl(this._dataSources, replica.LocalDatabase replicaDb)
      : _branches = BranchQuery(replicaDb);

  @override
  Future<Either<Failure, bool>> closeShift({
    required CloseShiftRequestModel request,
  }) async {
    return await _dataSources.closeShift(request: request);
  }

  @override
  Future<Either<Failure, ShiftResponseModel>> openShift({
    required OpenShiftModel request,
  }) async {
    return await _dataSources.openShift(request: request);
  }

  @override
  Future<Either<Failure, ShiftResponseModel?>> checkShift({
    required String id,
  }) async => await _dataSources.checkShift(id: id);

  @override
  Future<Either<Failure, UserModel>> getUser() async =>
      await _dataSources.getUser();

  @override
  Future<Either<Failure, String>> createTakewayOrder({
    required CreateOrderRequestModel request,
  }) async => await _dataSources.createTakewayOrder(request: request);

  @override
  Future<Either<Failure, bool>> createOrder({
    required CreateOrderRequestModel request,
  }) async => await _dataSources.createOrder(request: request);

  @override
  Future<Either<Failure, List<GoodsModel>>> getGoodsWithName(String name) {
    return _dataSources.getGoodsWithName(name);
  }

  @override
  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(String id) {
    return _dataSources.getArchiveWithId(id);
  }

  @override
  Future<Either<Failure, ArchiveDetailEntity>> getPaymentDetailWithTableId(
    String id,
  ) {
    return _dataSources.getPaymentDetailWithTableId(id);
  }

  @override
  Future<Either<Failure, List<PrinterSettingEntry>>> getPrinterSettings() =>
      _dataSources.getPrinterSettings();

  @override
  Future<Either<Failure, bool>> cancelOrderItem(String itemId, {String? comment}) =>
      _dataSources.cancelOrderItem(itemId, comment: comment);

  @override
  Future<Either<Failure, bool>> cancelOrder(String orderId) =>
      _dataSources.cancelOrder(orderId);

  @override
  Future<Either<Failure, bool>> transferTable({
    required String orderId,
    required String targetTableId,
  }) => _dataSources.transferTable(orderId: orderId, targetTableId: targetTableId);

  @override
  Future<Either<Failure, Map<String, dynamic>?>> getOrderTableTimer(String orderId) =>
      _dataSources.getOrderTableTimer(orderId);

  @override
  Future<Either<Failure, bool>> resumeOrderTableTimer(String orderId) =>
      _dataSources.resumeOrderTableTimer(orderId);

  @override
  Future<Either<Failure, bool>> pauseOrderTableTimer(String orderId) =>
      _dataSources.pauseOrderTableTimer(orderId);

  @override
  Future<String> getOrderIdWithTableId(String tableId) =>
      _dataSources.getOrderIdWithTableId(tableId: tableId);

  /// A local read: `branches` replicates, so the settings screen shows the
  /// configured percent offline instead of an error. Replaces an online-first
  /// fetch with a last-known-value cache behind it, which only had a value
  /// because the deleted hydration pass put one there.
  @override
  Future<Either<Failure, double>> getServiceCharge(String branchId) async {
    final value = _branches.defaultServicePercent(branchId);
    if (value == null) return const Left(ConnectionFailure());
    return Right(value);
  }

  /// Still a direct write. One low-volume config value with no reason to carry
  /// offline-write machinery; the cubit already refuses the edit when offline.
  /// The next pull brings the server's row back and the read above sees it.
  @override
  Future<Either<Failure, bool>> saveServiceCharge(String branchId, double value) =>
      _dataSources.saveServiceCharge(branchId, value);

  @override
  Future<Either<Failure, bool>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  }) => _dataSources.pushPrinterSetting(body, existingId: existingId);

  @override
  Future<Either<Failure, bool>> deletePrinterSetting(String id) =>
      _dataSources.deletePrinterSetting(id);

  @override
  Future<Either<Failure, bool>> createTransactionGroup(String name) =>
      _dataSources.createTransactionGroup(name);

  @override
  Future<Either<Failure, bool>> updateTransactionGroup(String id, String name) =>
      _dataSources.updateTransactionGroup(id, name);

  @override
  Future<Either<Failure, bool>> deleteTransactionGroup(String id) =>
      _dataSources.deleteTransactionGroup(id);

  @override
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) => _dataSources.getTransactions(
        limit: limit,
        offset: offset,
        search: search,
        type: type,
        cashRegisterId: cashRegisterId,
      );

  @override
  Future<Either<Failure, bool>> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  ) => _dataSources.createIncomeExpenseTransaction(body);

  @override
  Future<Either<Failure, bool>> createTransferTransaction(
    Map<String, dynamic> body,
  ) => _dataSources.createTransferTransaction(body);

  @override
  Future<Either<Failure, bool>> updateTransaction(
    String id,
    Map<String, dynamic> body,
  ) => _dataSources.updateTransaction(id, body);

  @override
  Future<Either<Failure, bool>> deleteTransaction(String id) =>
      _dataSources.deleteTransaction(id);

  @override
  Future<Either<Failure, Map<String, dynamic>>> createUser(Map<String, dynamic> body) =>
      _dataSources.createUser(body);

  @override
  Future<Either<Failure, bool>> updateUser(String id, Map<String, dynamic> body) =>
      _dataSources.updateUser(id, body);

  @override
  Future<Either<Failure, bool>> deleteUser(String id) =>
      _dataSources.deleteUser(id);

  @override
  Future<Either<Failure, bool>> deleteHall(String id) =>
      _dataSources.deleteHall(id);

  @override
  Future<Either<Failure, Map<String, dynamic>>> createHall(Map<String, dynamic> body) =>
      _dataSources.createHall(body);

  @override
  Future<Either<Failure, bool>> updateHall(String id, Map<String, dynamic> body) =>
      _dataSources.updateHall(id, body);

  @override
  Future<Either<Failure, Map<String, dynamic>>> createTable(Map<String, dynamic> body) =>
      _dataSources.createTable(body);

  @override
  Future<Either<Failure, bool>> updateTable(String id, Map<String, dynamic> body) =>
      _dataSources.updateTable(id, body);

  @override
  Future<Either<Failure, bool>> deleteTable(String id) =>
      _dataSources.deleteTable(id);

  @override
  Future<Either<Failure, Map<String, dynamic>>> createCategory(String name) =>
      _dataSources.createCategory(name);

  @override
  Future<Either<Failure, Map<String, dynamic>>> searchGoodsAdmin({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  }) => _dataSources.searchGoodsAdmin(
        limit: limit,
        offset: offset,
        categoryId: categoryId,
        search: search,
      );

  @override
  Future<Either<Failure, Map<String, dynamic>>> getGoodById(String id) =>
      _dataSources.getGoodById(id);

  @override
  Future<Either<Failure, Map<String, dynamic>>> getTranslationsList() =>
      _dataSources.getTranslationsList();

  @override
  Future<Either<Failure, Map<String, dynamic>>> getGoodWithCalculationsById(
    String id, {
    bool includeTranslations = false,
  }) => _dataSources.getGoodWithCalculationsById(
        id,
        includeTranslations: includeTranslations,
      );

  @override
  Future<Either<Failure, Map<String, dynamic>>> createTranslation(
    Map<String, dynamic> body,
  ) => _dataSources.createTranslation(body);

  @override
  Future<Either<Failure, bool>> updateTranslation(
    String id,
    Map<String, dynamic> body,
  ) => _dataSources.updateTranslation(id, body);

  @override
  Future<Either<Failure, Map<String, dynamic>>> saveGoodWithCalculations({
    String? mealId,
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) => _dataSources.saveGoodWithCalculations(
        mealId: mealId,
        body: body,
        headers: headers,
      );

  @override
  Future<Either<Failure, bool>> deleteGood(String id) =>
      _dataSources.deleteGood(id);

}
