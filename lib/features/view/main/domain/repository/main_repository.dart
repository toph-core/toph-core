import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/close_shift/close_shift_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_shift/open_shift_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/shift/shift_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';


abstract class MainRepository {
  Future<Either<Failure, ShiftResponseModel>> openShift({
    required OpenShiftModel request,
  });

  Future<Either<Failure, bool>> closeShift({
    required CloseShiftRequestModel request,
  });

  Future<Either<Failure, ShiftResponseModel?>> checkShift({required String id});

  Future<Either<Failure, bool>> createOrder({
    required CreateOrderRequestModel request,
  });

  Future<Either<Failure, UserModel>> getUser();

  Future<Either<Failure, String>> createTakewayOrder({
    required CreateOrderRequestModel request,
  });

  Future<Either<Failure, List<GoodsModel>>> getGoodsWithName(String name);
  Future<Either<Failure, ArchiveDetailEntity>> getArchiveWithId(String id);
  Future<Either<Failure, ArchiveDetailEntity>> getPaymentDetailWithTableId(
    String id,
  );
  Future<Either<Failure, List<PrinterSettingEntry>>> getPrinterSettings();

  Future<Either<Failure, bool>> cancelOrderItem(String itemId, {String? comment});

  Future<Either<Failure, bool>> cancelOrder(String orderId);

  Future<Either<Failure, bool>> transferTable({
    required String orderId,
    required String targetTableId,
  });

  Future<Either<Failure, Map<String, dynamic>?>> getOrderTableTimer(String orderId);

  Future<Either<Failure, bool>> resumeOrderTableTimer(String orderId);

  Future<Either<Failure, bool>> pauseOrderTableTimer(String orderId);

  Future<String> getOrderIdWithTableId(String tableId);

  Future<Either<Failure, double>> getServiceCharge(String branchId);

  Future<Either<Failure, bool>> saveServiceCharge(String branchId, double value);

  Future<Either<Failure, bool>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  });

  Future<Either<Failure, bool>> deletePrinterSetting(String id);

  Future<Either<Failure, Map<String, dynamic>>> createTransactionGroup(String name);

  Future<Either<Failure, bool>> updateTransactionGroup(String id, String name);

  Future<Either<Failure, bool>> deleteTransactionGroup(String id);

  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  });

  Future<Either<Failure, Map<String, dynamic>>> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  );

  Future<Either<Failure, Map<String, dynamic>>> createTransferTransaction(
    Map<String, dynamic> body,
  );

  Future<Either<Failure, bool>> updateTransaction(
    String id,
    Map<String, dynamic> body,
  );

  Future<Either<Failure, bool>> deleteTransaction(String id);

  Future<Either<Failure, Map<String, dynamic>>> createUser(Map<String, dynamic> body);

  Future<Either<Failure, bool>> updateUser(String id, Map<String, dynamic> body);

  Future<Either<Failure, bool>> deleteUser(String id);

  Future<Either<Failure, bool>> deleteHall(String id);

  Future<Either<Failure, Map<String, dynamic>>> createHall(Map<String, dynamic> body);

  Future<Either<Failure, bool>> updateHall(String id, Map<String, dynamic> body);

  Future<Either<Failure, Map<String, dynamic>>> createTable(Map<String, dynamic> body);

  Future<Either<Failure, bool>> updateTable(String id, Map<String, dynamic> body);

  Future<Either<Failure, bool>> deleteTable(String id);

  Future<Either<Failure, Map<String, dynamic>>> createCategory(String name);

  Future<Either<Failure, Map<String, dynamic>>> searchGoodsAdmin({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  });

  Future<Either<Failure, Map<String, dynamic>>> getGoodById(String id);

  Future<Either<Failure, Map<String, dynamic>>> getTranslationsList();

  Future<Either<Failure, Map<String, dynamic>>> getGoodWithCalculationsById(
    String id, {
    bool includeTranslations = false,
  });

  Future<Either<Failure, Map<String, dynamic>>> createTranslation(
    Map<String, dynamic> body,
  );

  Future<Either<Failure, bool>> updateTranslation(
    String id,
    Map<String, dynamic> body,
  );

  Future<Either<Failure, Map<String, dynamic>>> saveGoodWithCalculations({
    String? mealId,
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  });

  Future<Either<Failure, bool>> deleteGood(String id);

}
