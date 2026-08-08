import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/close_shift/close_shift_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_shift/open_shift_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/shift/shift_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/hour_price_response_entity.dart';

import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

class MainRepositoryImpl implements MainRepository {
  final MainDataSources _dataSources;
  final CacheService _cache;
  final ConnectivityCubit _connectivity;

  MainRepositoryImpl(this._dataSources, this._cache, this._connectivity);

  @override
  Future<Either<Failure, HourPriceResponseEntity>> getHourPrice({
    required String orderId,
  }) async => await _dataSources.getHourPrice(orderId: orderId);

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
  Future<Either<Failure, List<UserModel>>> getUsers() async {
    // Cache-first — same pattern as `MenuLocalRepositoryImpl` for
    // categories/departments: try the network when online and write
    // through on success, otherwise (or on failure) fall back to whatever
    // was last cached rather than surfacing an empty/error state.
    if (_connectivity.isOnline) {
      final result = await _dataSources.getUsers();
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        if (ok.isNotEmpty) {
          await _cache.saveUsers(ok.map((u) => u.toJson()).toList());
        }
        return result;
      }
    }
    final cached = _cache.getUsers();
    if (cached.isEmpty) return const Left(ConnectionFailure());
    try {
      return Right(cached.map(UserModel.fromJson).toList());
    } catch (_) {
      return const Left(ConnectionFailure());
    }
  }

  @override
  Future<Either<Failure, List<CafeTableModel>>> getAllTables() {
    return _dataSources.getAllTables();
  }

  @override
  Future<Either<Failure, List<CafeTableModel>>> getTablesByHallId(
    String hallId,
  ) {
    return _dataSources.getTablesByHallId(hallId);
  }

  @override
  Future<Either<Failure, String>> createTakewayOrder({
    required CreateOrderRequestModel request,
  }) async => await _dataSources.createTakewayOrder(request: request);

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
  Future<Either<Failure, List<DepartmentModel>>> getDepartments() {
    return _dataSources.getDepartments();
  }

  @override
  Future<Either<Failure, List<GoodsModel>>> getGoodsByCategoryId(
    String categoryId,
  ) {
    return _dataSources.getGoodsByCategoryId(categoryId);
  }

  @override
  Future<Either<Failure, List<GoodsModel>>> getGoodsWithName(String name) {
    return _dataSources.getGoodsWithName(name);
  }

  @override
  Future<Either<Failure, ArchivesResponseEntity>> getArchives(
    ArchivesFilterRequestEntity request,
  ) {
    return _dataSources.getArchives(request);
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
  Future<Either<Failure, Map<String, dynamic>>> getOrderItemsRaw(
    String orderId,
  ) => _dataSources.getOrderItemsRaw(orderId);

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

  @override
  Future<Either<Failure, double>> getServiceCharge(String branchId) async {
    if (_connectivity.isOnline) {
      final result = await _dataSources.getServiceCharge(branchId);
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        await _cache.saveServiceCharge(branchId, {'default_service_percent': ok});
        return result;
      }
    }
    final cached = _cache.getServiceCharge(branchId);
    if (cached == null) return const Left(ConnectionFailure());
    final raw = cached['default_service_percent'];
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    return Right(value);
  }

  @override
  Future<Either<Failure, bool>> saveServiceCharge(String branchId, double value) async {
    final result = await _dataSources.saveServiceCharge(branchId, value);
    if (result.isRight()) {
      await _cache.saveServiceCharge(branchId, {'default_service_percent': value});
    }
    return result;
  }

  @override
  Future<Either<Failure, bool>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  }) => _dataSources.pushPrinterSetting(body, existingId: existingId);

  @override
  Future<Either<Failure, bool>> deletePrinterSetting(String id) =>
      _dataSources.deletePrinterSetting(id);

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getTransactionGroups({
    String? search,
  }) async {
    // Cache-first only for the unfiltered default list — a search query has
    // no bounded local mirror to fall back to, same reasoning
    // `MenuLocalRepositoryImpl.searchGoodsByName` already uses.
    final isDefaultList = search == null || search.isEmpty;
    if (_connectivity.isOnline) {
      final result = await _dataSources.getTransactionGroups(search: search);
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        if (isDefaultList) await _cache.saveTransactionGroups(ok);
        return result;
      }
    }
    if (!isDefaultList) return const Left(ConnectionFailure());
    final cached = _cache.getTransactionGroups();
    if (cached.isEmpty) return const Left(ConnectionFailure());
    return Right(cached);
  }

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
  Future<Either<Failure, List<Map<String, dynamic>>>> getCashRegisters() =>
      _dataSources.getCashRegisters();

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
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getAdminUsers({
    required int limit,
    required int offset,
    String? search,
    String? role,
  }) => _dataSources.getAdminUsers(
        limit: limit,
        offset: offset,
        search: search,
        role: role,
      );

  @override
  Future<Either<Failure, bool>> createUser(Map<String, dynamic> body) =>
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
  Future<Either<Failure, bool>> createHall(Map<String, dynamic> body) =>
      _dataSources.createHall(body);

  @override
  Future<Either<Failure, bool>> updateHall(String id, Map<String, dynamic> body) =>
      _dataSources.updateHall(id, body);

  @override
  Future<Either<Failure, bool>> createTable(Map<String, dynamic> body) =>
      _dataSources.createTable(body);

  @override
  Future<Either<Failure, bool>> updateTable(String id, Map<String, dynamic> body) =>
      _dataSources.updateTable(id, body);

  @override
  Future<Either<Failure, bool>> deleteTable(String id) =>
      _dataSources.deleteTable(id);

  @override
  Future<Either<Failure, bool>> createCategory(String name) =>
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
  Future<Either<Failure, bool>> saveGoodWithCalculations({
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

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getIngredients() async {
    if (_connectivity.isOnline) {
      final result = await _dataSources.getIngredients();
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        if (ok.isNotEmpty) await _cache.saveIngredients(ok);
        return result;
      }
    }
    final cached = _cache.getIngredients();
    if (cached.isEmpty) return const Left(ConnectionFailure());
    return Right(cached);
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getCompounds() async {
    if (_connectivity.isOnline) {
      final result = await _dataSources.getCompounds();
      final ok = result.fold((_) => null, (r) => r);
      if (ok != null) {
        if (ok.isNotEmpty) await _cache.saveCompounds(ok);
        return result;
      }
    }
    final cached = _cache.getCompounds();
    if (cached.isEmpty) return const Left(ConnectionFailure());
    return Right(cached);
  }
}
