import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/dio_exception_handler.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archives_response/archives_response_model.dart';
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


abstract class MainDataSources {
  Future<Either<Failure, List<CafeTableModel>>> getTablesByHallId(
    String hallId,
  );

  /// All tables across every hall, unfiltered — used only by the login/
  /// periodic hydration pass (`SyncEngine`) to warm the cache ahead of any
  /// specific hall being opened. Regular table reads stay per-hall via
  /// [getTablesByHallId], matching what `MainCubit` already does.
  Future<Either<Failure, List<CafeTableModel>>> getAllTables();
  Future<Either<Failure, List<HallModel>>> getHalls();
  Future<Either<Failure, List<CategoryModel>>> getCategories();
  Future<Either<Failure, List<DepartmentModel>>> getDepartments();
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

  Future<Either<Failure, bool>> createOrder({
    required CreateOrderRequestModel request,
  });

  Future<Either<Failure, String>> createTakewayOrder({
    required CreateOrderRequestModel request,
  });

  Future<String> getOrderIdWithTableId({required String tableId});

  Future<Either<Failure, UserModel>> getUser();

  Future<Either<Failure, List<UserModel>>> getUsers();

  Future<Either<Failure, ShiftResponseModel?>> checkShift({required String id});

  Future<Either<Failure, ShiftResponseModel>> openShift({
    required OpenShiftModel request,
  });

  Future<Either<Failure, bool>> closeShift({
    required CloseShiftRequestModel request,
  });

  Future<Either<Failure, List<PrinterSettingEntry>>> getPrinterSettings();

  // ─── Order-item mutations (moved out of DetailBloc/CreateOrderBloc/
  // PaymentBloc, which previously called DioClient directly for these) ────

  /// Raw `/api/v1/order-items/order/{orderId}` response — kept as a decoded
  /// Map rather than a parsed model because callers (`DetailBloc`'s existing-
  /// item timestamp/line-id enrichment) do their own detailed parsing of a
  /// shape this layer doesn't otherwise model; this only moves the network
  /// call itself behind the interface, not the parsing logic.
  Future<Either<Failure, Map<String, dynamic>>> getOrderItemsRaw(
    String orderId,
  );

  /// `POST /api/v1/order-items/{itemId}/cancel`. A 404 (already cancelled by
  /// another client) is treated as success by the caller, not here — mirrors
  /// how `OfflineQueueService._execCancelLineItems` already handles it.
  Future<Either<Failure, bool>> cancelOrderItem(String itemId, {String? comment});

  /// `POST /api/v1/orders/{orderId}/cancel` — whole-order cancel (e.g. a
  /// zero-total/fully-discounted check).
  Future<Either<Failure, bool>> cancelOrder(String orderId);

  /// `POST /api/v1/orders/{orderId}/transfer` — move an order to a different
  /// table. Deliberately online-only, same as before this moved behind a
  /// repository interface — a table transfer racing another terminal's
  /// concurrent transfer/order-close is exactly the 409 case callers need a
  /// live answer for, not a queued one.
  Future<Either<Failure, bool>> transferTable({
    required String orderId,
    required String targetTableId,
  });

  /// `GET /api/v1/branches/{id}` — reads just `default_service_percent`.
  Future<Either<Failure, double>> getServiceCharge(String branchId);

  /// `PUT /api/v1/branches/{id}` — updates `default_service_percent`.
  Future<Either<Failure, bool>> saveServiceCharge(String branchId, double value);

  /// `POST`/`PUT /api/v1/settings/printer-settings[/{id}]` — best-effort
  /// backend mirror of a printer routing entry. Local storage
  /// (`PrinterConfigStorage`) is always the source of truth on this
  /// terminal; this is a background sync attempt, not a required step.
  Future<Either<Failure, bool>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  });

  /// `DELETE /api/v1/settings/printer-settings/{id}` — best-effort mirror
  /// of a local printer-entry deletion.
  Future<Either<Failure, bool>> deletePrinterSetting(String id);

  /// `GET /api/v1/group-transactions` — kept as raw maps (`{id, name}`)
  /// rather than a dedicated model; this data is only ever consumed by the
  /// transactions-settings screen and has no other reader.
  Future<Either<Failure, List<Map<String, dynamic>>>> getTransactionGroups({
    String? search,
  });

  Future<Either<Failure, bool>> createTransactionGroup(String name);

  Future<Either<Failure, bool>> updateTransactionGroup(String id, String name);

  Future<Either<Failure, bool>> deleteTransactionGroup(String id);

  /// `GET /api/v1/cash-registers` — kept as raw maps, same reasoning as
  /// [getTransactionGroups]: only consumed by the transactions-settings
  /// screen's dropdowns.
  Future<Either<Failure, List<Map<String, dynamic>>>> getCashRegisters();

  /// `GET /api/v1/transactions` — paginated, filtered ledger. Genuinely live
  /// data (like archives), not reference data — no cache layer, same as
  /// `ArchivesLocalRepositoryImpl` only caching the default unfiltered page.
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  });

  Future<Either<Failure, bool>> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  );

  Future<Either<Failure, bool>> createTransferTransaction(
    Map<String, dynamic> body,
  );

  Future<Either<Failure, bool>> updateTransaction(
    String id,
    Map<String, dynamic> body,
  );

  Future<Either<Failure, bool>> deleteTransaction(String id);

  /// `GET /api/v1/users` (admin-only, distinct from the role-appropriate
  /// [getUsers] used by the waiter-assignment dropdown) or
  /// `GET /api/v1/users/search` when [search] is non-empty.
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getAdminUsers({
    required int limit,
    required int offset,
    String? search,
    String? role,
  });

  /// `POST /api/v1/auth/register` — creates a new staff account.
  Future<Either<Failure, bool>> createUser(Map<String, dynamic> body);

  /// `PUT /api/v1/users/{id}`.
  Future<Either<Failure, bool>> updateUser(String id, Map<String, dynamic> body);

  /// `DELETE /api/v1/users/{id}`.
  Future<Either<Failure, bool>> deleteUser(String id);

  /// `DELETE /api/v1/halls/{id}`.
  Future<Either<Failure, bool>> deleteHall(String id);

  /// `POST /api/v1/halls`.
  Future<Either<Failure, bool>> createHall(Map<String, dynamic> body);

  /// `PUT /api/v1/halls/{id}`.
  Future<Either<Failure, bool>> updateHall(String id, Map<String, dynamic> body);

  /// `POST /api/v1/cafe-tables`.
  Future<Either<Failure, bool>> createTable(Map<String, dynamic> body);

  /// `PUT /api/v1/cafe-tables/{id}` — used both for a full edit and for a
  /// position-only move (caller builds the full payload either way; the
  /// backend has no partial-update variant).
  Future<Either<Failure, bool>> updateTable(String id, Map<String, dynamic> body);

  /// `DELETE /api/v1/cafe-tables/{id}`.
  Future<Either<Failure, bool>> deleteTable(String id);

  /// `POST /api/v1/categories`.
  Future<Either<Failure, bool>> createCategory(String name);

  /// `GET /api/v1/goods` with admin-facing pagination/search/category
  /// filters — kept as a raw decoded response (not a parsed `List<GoodsModel>`)
  /// because the menu-management screen's own response-shape-tolerant
  /// parsing (several possible envelope shapes) stays in the widget, this
  /// only moves the network call itself behind the interface.
  Future<Either<Failure, Map<String, dynamic>>> searchGoodsAdmin({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  });

  /// `GET /api/v1/orders/{orderId}/table-timer`.
  Future<Either<Failure, Map<String, dynamic>?>> getOrderTableTimer(String orderId);

  /// `POST /api/v1/orders/{orderId}/table-timer/resume`.
  Future<Either<Failure, bool>> resumeOrderTableTimer(String orderId);

  /// `POST /api/v1/orders/{orderId}/table-timer/pause`.
  Future<Either<Failure, bool>> pauseOrderTableTimer(String orderId);

  /// `GET /api/v1/goods/{id}` — raw response, kept undecoded for the same
  /// reason as [searchGoodsAdmin]: the menu-management screen's own
  /// tolerant-of-several-shapes parsing stays in the widget.
  Future<Either<Failure, Map<String, dynamic>>> getGoodById(String id);

  /// `GET /api/v1/translations?limit=1000&offset=0`.
  Future<Either<Failure, Map<String, dynamic>>> getTranslationsList();

  /// `GET /api/v1/goods/{id}/with-calculations`.
  Future<Either<Failure, Map<String, dynamic>>> getGoodWithCalculationsById(
    String id, {
    bool includeTranslations = false,
  });

  /// `POST /api/v1/translations`.
  Future<Either<Failure, Map<String, dynamic>>> createTranslation(
    Map<String, dynamic> body,
  );

  /// `PUT /api/v1/translations/{id}`.
  Future<Either<Failure, bool>> updateTranslation(
    String id,
    Map<String, dynamic> body,
  );

  /// `POST`/`PUT /api/v1/goods/with-calculations[/{id}]` — [mealId] null
  /// means create, non-null means update.
  Future<Either<Failure, bool>> saveGoodWithCalculations({
    String? mealId,
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  });

  /// `DELETE /api/v1/goods/{id}`.
  Future<Either<Failure, bool>> deleteGood(String id);

  /// Recipe-editor reference data — tries `/ingredients` then falls back to
  /// `/ingredients-lang` (backend deployment-dependent), matching the
  /// fallback behavior already in the menu-management screen this replaces.
  Future<Either<Failure, List<Map<String, dynamic>>>> getIngredients();

  Future<Either<Failure, List<Map<String, dynamic>>>> getCompounds();
}

class MainDataSourcesImpl implements MainDataSources {
  final DioClient _client;

  MainDataSourcesImpl(this._client);

  @override
  Future<Either<Failure, List<PrinterSettingEntry>>> getPrinterSettings() async {
    try {
      final response = await _client.get(ListAPI.printerSettings);
      final root = response.data;
      List<dynamic>? dataList;
      if (root is Map<String, dynamic>) {
        final data = root['data'];
        if (data is List) dataList = data;
      } else if (root is List) {
        dataList = root;
      }
      if (dataList == null) {
        return const Left(ParsingFailure());
      }
      return Right(PrinterSettingEntry.listFromJsonList(dataList));
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
  Future<Either<Failure, bool>> closeShift({
    required CloseShiftRequestModel request,
  }) async {
    try {
      // shiftId is in the URL path only; body must not include it
      await _client.post(
        ListAPI.closeShift(request.shiftId),
        data: {
          'closing_cash': request.closingCash.toString(),
          'closing_card': request.closingCard.toString(),
        },
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
  Future<Either<Failure, ShiftResponseModel>> openShift({
    required OpenShiftModel request,
  }) async {
    try {
      // README: cashier_id is taken from JWT token — do NOT send it
      final response = await _client.post(
        ListAPI.openShift,
        data: {
          'cash_register_id': request.cashRegisterId,
          'opening_cash': request.openCashSum.toString(),
          'opening_card': request.openCardSum.toString(),
        },
      );
      return Right(ShiftResponseModel.fromJson(response.data['data']));
    } on DioException catch (exception) {
      // Server already has an open shift for this kassa — fetch & return it.
      final data = exception.response?.data;
      final message = data is Map ? (data['error'] ?? data['message']) : null;
      final alreadyOpen =
          message is String && message.toLowerCase().contains('already');
      if (alreadyOpen) {
        final existing = await checkShift(id: request.cashRegisterId);
        return existing.fold(
          (_) => Left(handleDioException(exception)),
          (shift) => shift != null
              ? Right(shift)
              : Left(handleDioException(exception)),
        );
      }
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
      final raw = response.data;
      final data = raw is Map<String, dynamic> ? raw['data'] : null;
      if (data is! Map<String, dynamic> || data.isEmpty) {
        return const Right(null);
      }
      return Right(ShiftResponseModel.fromJson(data));
    } on DioException catch (e) {
      // 404 / "no active shift" is a real "none" answer — let UI show the open flow.
      if (e.response?.statusCode == 404) {
        return const Right(null);
      }
      if (kDebugMode) {
        print('[checkShift] DioException ${e.response?.statusCode}: ${e.response?.data}');
      }
      return Left(handleDioException(e));
    } on TypeError catch (e, st) {
      if (kDebugMode) print('[checkShift] parse TypeError: $e\n$st');
      return const Left(ParsingFailure());
    } on FormatException catch (e, st) {
      if (kDebugMode) print('[checkShift] FormatException: $e\n$st');
      return const Left(ParsingFailure());
    } catch (e, st) {
      if (kDebugMode) print('[checkShift] unexpected: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<UserModel>>> getUsers() async {
    // `GET /api/v1/users` is admin-only server-side (confirmed against the
    // backend's RBAC config) — a normal waiter/cashier terminal session
    // legitimately 403s there, which is why this used to be hard-disabled.
    // `GET /api/v1/users/staff` is the role-appropriate endpoint (the
    // backend's own doc comment: "Use for endpoints that Flutter reads
    // during initial data pull") — reachable by admin/manager/superadmin AND
    // a terminal-scoped session, so this now genuinely returns data instead
    // of an unconditional empty list.
    try {
      final response = await _client.get(
        ListAPI.usersStaff,
        queryParameters: {'limit': 500, 'offset': 0},
      );
      final raw = response.data['data'];
      List<dynamic> list;
      if (raw is List) {
        list = raw;
      } else if (raw is Map && raw['data'] is List) {
        list = raw['data'] as List;
      } else {
        list = [];
      }
      return Right(
        list
            .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on DioException catch (exception) {
      // A role that still can't reach /users/staff (unexpected, but not
      // impossible) degrades to an empty list rather than surfacing a raw
      // 403 to the waiter-assignment dropdown — same fail-soft behavior the
      // previous hard-disabled stub gave every caller, just no longer
      // unconditional.
      if (exception.response?.statusCode == 403) {
        if (kDebugMode) print('[getUsers] 403 on /users/staff — role lacks access');
        return const Right(<UserModel>[]);
      }
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
        final orderId = await getOrderIdWithTableId(
          tableId: request.tableId,
        );
        if (orderId.isNotEmpty) {
          final req = request.request();
          await _client.post(
            ListAPI.orderItems(orderId),
            queryParameters: {'lang': 'uz'},
            data: {'items': req['items']},
          );
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
        queryParameters: {'limit': 1000},
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
  Future<Either<Failure, List<CafeTableModel>>> getAllTables() async {
    try {
      final response = await _client.get(
        ListAPI.cafeTables,
        queryParameters: {'limit': 1000},
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
  Future<Either<Failure, List<DepartmentModel>>> getDepartments() async {
    try {
      final response = await _client.get(
        ListAPI.departments,
        queryParameters: {'limit': 200, 'offset': 0},
      );

      return Right(
        (response.data['data'] as List?)
                ?.map((e) => DepartmentModel.fromJson(e as Map<String, dynamic>))
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
  Future<Either<Failure, ArchiveDetailEntity>> getPaymentDetailWithTableId(
    String id,
  ) async {
    try {
      // orders/table endpoint — orderIdni VA service_percentni birga olamiz
      final ordersRes = await _client.dio.get(ListAPI.orderWithTableId(id));
      final orderData =
          ordersRes.data['data'][0] as Map<String, dynamic>? ?? {};
      final orderId = orderData['id'] as String? ?? '';
      if (orderId.isEmpty) {
        throw "To'lov ma'lumotlarini olishda xatolik yuzaga keldi";
      }
      final rawSp = orderData['service_percent'];
      final orderServicePercent = rawSp is num ? rawSp.toDouble() : 0.0;

      final response = await _client.dio.get(ListAPI.archiveWithId(orderId));
      var detail = ArchiveDetailModel.fromJson(response.data['data']);
      // bills endpoint open order uchun service_percent qaytarmasligi mumkin —
      // orders/table javobidagini fallback sifatida ishlatamiz
      if (detail.servicePercent == 0.0 && orderServicePercent > 0) {
        detail = detail.copyWith(servicePercent: orderServicePercent);
      }
      return Right(detail);
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
        // API defaults to limit=20 — pull every page so POS client pagination works.
        const batchSize = 500;
        var offset = 0;
        final all = <GoodsModel>[];
        while (true) {
          final response = await _client.get(
            ListAPI.goods,
            queryParameters: {'limit': batchSize, 'offset': offset},
          );
          final raw = response.data['data'];
          final List<dynamic> items = raw is List
              ? raw
              : (raw is Map ? (raw['data'] as List? ?? []) : []);
          if (items.isEmpty) break;
          all.addAll(items.map((e) => GoodsModel.fromJson(e)));
          if (items.length < batchSize) break;
          offset += batchSize;
        }
        return Right(all);
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
        ListAPI.goods,
        queryParameters: {'search': name, 'limit': 100},
      );

      final list = response.data['data'] as List? ??
          (response.data is List ? response.data as List : []);
      return Right(
        list.map((e) => GoodsModel.fromJson(e)).toList(),
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

  @override
  Future<Either<Failure, Map<String, dynamic>>> getOrderItemsRaw(
    String orderId,
  ) async {
    try {
      final response = await _client.get(
        ListAPI.orderItemsListByOrder(orderId),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return const Left(ParsingFailure());
      return Right(data);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> cancelOrderItem(
    String itemId, {
    String? comment,
  }) async {
    try {
      await _client.dio.post(
        ListAPI.orderItemCancel(itemId),
        data: <String, dynamic>{
          if (comment != null && comment.isNotEmpty) 'comment': comment,
        },
      );
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>?>> getOrderTableTimer(
    String orderId,
  ) async {
    try {
      final response = await _client.get(ListAPI.orderTableTimer(orderId));
      final raw = response.data['data'];
      if (raw is! Map) return const Right(null);
      return Right(raw.cast<String, dynamic>());
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> cancelOrder(String orderId) async {
    try {
      await _client.dio.post(ListAPI.cancelOrder(orderId));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> resumeOrderTableTimer(String orderId) async {
    try {
      await _client.dio.post(ListAPI.orderTableTimerResume(orderId));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> transferTable({
    required String orderId,
    required String targetTableId,
  }) async {
    try {
      await _client.dio.post(
        ListAPI.orderTransfer(orderId),
        data: {'target_table_id': targetTableId},
      );
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, double>> getServiceCharge(String branchId) async {
    try {
      final res = await _client.get(ListAPI.branchById(branchId));
      final data = res.data;
      final body = (data is Map && data['data'] is Map)
          ? data['data'] as Map
          : (data as Map);
      final raw = body['default_service_percent'];
      double parsed = 0;
      if (raw is num) {
        parsed = raw.toDouble();
      } else if (raw is String) {
        parsed = double.tryParse(raw) ?? 0;
      }
      return Right(parsed);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> saveServiceCharge(
    String branchId,
    double value,
  ) async {
    try {
      final asString = value == value.truncateToDouble()
          ? value.toStringAsFixed(0)
          : value.toString();
      await _client.put(
        ListAPI.branchById(branchId),
        data: {'default_service_percent': asString},
      );
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  }) async {
    try {
      if (existingId == null) {
        await _client.post(ListAPI.printerSettings, data: body);
      } else {
        await _client.put('${ListAPI.printerSettings}/$existingId', data: body);
      }
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deletePrinterSetting(String id) async {
    try {
      await _client.delete('${ListAPI.printerSettings}/$id');
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getTransactionGroups({
    String? search,
  }) async {
    try {
      final res = await _client.get(
        ListAPI.groupTransactions,
        queryParameters: {
          'limit': 100,
          'offset': 0,
          if (search != null && search.isNotEmpty) 'search': search,
        },
      );
      final root = res.data;
      final List<dynamic> data =
          (root is Map && root['data'] is List) ? root['data'] as List : const [];
      return Right(
        data.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createTransactionGroup(String name) async {
    try {
      await _client.post(ListAPI.groupTransactions, data: {'name': name});
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> updateTransactionGroup(String id, String name) async {
    try {
      await _client.put(ListAPI.groupTransactionById(id), data: {'name': name});
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deleteTransactionGroup(String id) async {
    try {
      await _client.delete(ListAPI.groupTransactionById(id));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getCashRegisters() async {
    try {
      final res = await _client.get(
        ListAPI.cashRegisters,
        queryParameters: {'limit': 200},
      );
      final root = res.data;
      final List<dynamic> data =
          (root is Map && root['data'] is List) ? root['data'] as List : const [];
      return Right(
        data.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getTransactions({
    required int limit,
    required int offset,
    String? search,
    String? type,
    String? cashRegisterId,
  }) async {
    try {
      final res = await _client.get(
        ListAPI.transactions,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (search != null && search.isNotEmpty) 'search': search,
          if (type != null) 'type': type,
          if (cashRegisterId != null) 'cash_register_id': cashRegisterId,
        },
      );
      final root = res.data;
      List<dynamic> data = const [];
      int? total;
      if (root is Map) {
        if (root['data'] is List) data = root['data'] as List;
        if (root['pagination'] is Map) {
          total = ((root['pagination'] as Map)['total'] as num?)?.toInt();
        }
      }
      return Right((
        items: data.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        total: total,
      ));
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createIncomeExpenseTransaction(
    Map<String, dynamic> body,
  ) async {
    try {
      await _client.post(ListAPI.transactionsIncomeExpense, data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createTransferTransaction(
    Map<String, dynamic> body,
  ) async {
    try {
      await _client.post(ListAPI.transactionsTransfer, data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> updateTransaction(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      await _client.put(ListAPI.transactionById(id), data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deleteTransaction(String id) async {
    try {
      await _client.delete(ListAPI.transactionById(id));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, ({List<Map<String, dynamic>> items, int? total})>>
      getAdminUsers({
    required int limit,
    required int offset,
    String? search,
    String? role,
  }) async {
    try {
      final isSearching = search != null && search.isNotEmpty;
      final res = await _client.get(
        isSearching ? ListAPI.usersSearch : ListAPI.users,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (isSearching) 'query': search,
          // List endpoint qo'shimcha `role` filtrini qo'llaydi; search endpoint
          // server tomonida role filtrini qabul qilmaydi — natija filtri caller'da.
          if (!isSearching && role != null) 'role': role,
        },
      );
      final root = res.data;
      List<dynamic> data = const [];
      int? total;
      if (root is List) {
        data = root;
      } else if (root is Map) {
        if (root['data'] is List) data = root['data'] as List;
        if (root['pagination'] is Map) {
          total = ((root['pagination'] as Map)['total'] as num?)?.toInt();
        }
      }
      return Right((
        items: data.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        total: total,
      ));
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createUser(Map<String, dynamic> body) async {
    try {
      await _client.post(ListAPI.authRegister, data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> updateUser(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      await _client.put(ListAPI.userById(id), data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deleteUser(String id) async {
    try {
      await _client.delete(ListAPI.userById(id));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deleteHall(String id) async {
    try {
      await _client.delete('${ListAPI.halls}/$id');
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createHall(Map<String, dynamic> body) async {
    try {
      await _client.post(ListAPI.halls, data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> updateHall(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      await _client.put('${ListAPI.halls}/$id', data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createTable(Map<String, dynamic> body) async {
    try {
      await _client.post(ListAPI.cafeTables, data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> updateTable(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      await _client.put(ListAPI.cafeTableById(id), data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deleteTable(String id) async {
    try {
      await _client.delete(ListAPI.cafeTableById(id));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createCategory(String name) async {
    try {
      await _client.post(ListAPI.categories, data: {'name': name});
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> searchGoodsAdmin({
    required int limit,
    required int offset,
    String? categoryId,
    String? search,
  }) async {
    try {
      final res = await _client.get(
        ListAPI.goods,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (categoryId != null) 'category_id': categoryId,
          if (search != null && search.isNotEmpty) 'search': search,
        },
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) return const Left(ParsingFailure());
      return Right(data);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> pauseOrderTableTimer(String orderId) async {
    try {
      await _client.dio.post(ListAPI.orderTableTimerPause(orderId));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getGoodById(String id) async {
    try {
      final res = await _client.get(ListAPI.goodById(id));
      final data = res.data;
      if (data is! Map<String, dynamic>) return const Left(ParsingFailure());
      return Right(data);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getTranslationsList() async {
    try {
      final res = await _client.get(ListAPI.translations(limit: 1000, offset: 0));
      final data = res.data;
      if (data is! Map<String, dynamic>) return const Left(ParsingFailure());
      return Right(data);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getGoodWithCalculationsById(
    String id, {
    bool includeTranslations = false,
  }) async {
    try {
      final res = await _client.get(
        ListAPI.goodWithCalculationsById(id),
        queryParameters: includeTranslations ? const {'include': 'translations'} : null,
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) return const Left(ParsingFailure());
      return Right(data);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> createTranslation(
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _client.post(ListAPI.createTranslation, data: body);
      final data = res.data;
      if (data is! Map<String, dynamic>) return const Left(ParsingFailure());
      return Right(data);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> updateTranslation(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      await _client.put(ListAPI.translationById(id), data: body);
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> saveGoodWithCalculations({
    String? mealId,
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    try {
      if (mealId != null) {
        await _client.put(
          ListAPI.goodWithCalculationsById(mealId),
          data: body,
          headers: headers,
        );
      } else {
        await _client.post(
          ListAPI.goodsWithCalculations,
          data: body,
          headers: headers,
        );
      }
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> deleteGood(String id) async {
    try {
      await _client.delete(ListAPI.goodById(id));
      return const Right(true);
    } on DioException catch (exception) {
      return Left(handleDioException(exception));
    } catch (e, st) {
      if (kDebugMode) print('Unknown error: $e\n$st');
      return const Left(UnknownFailure());
    }
  }

  List<Map<String, dynamic>> _extractDataListFromRaw(dynamic raw) {
    dynamic source = raw;
    if (source is Map<String, dynamic>) {
      source = source['data'] ?? source['items'] ?? source['results'] ?? const [];
    }
    if (source is Map<String, dynamic>) {
      source = source['items'] ?? source['results'] ?? source['data'] ?? const [];
    }
    if (source is! List) return const [];
    return source
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Either<Failure, List<Map<String, dynamic>>>> _fetchFirstAvailableList(
    List<String> paths,
  ) async {
    DioException? lastError;
    var hasSuccess = false;
    for (final path in paths) {
      try {
        final res = await _client.get(path);
        hasSuccess = true;
        final list = _extractDataListFromRaw(res.data);
        if (list.isNotEmpty) return Right(list);
      } on DioException catch (e) {
        lastError = e;
      }
    }
    if (hasSuccess) return const Right(<Map<String, dynamic>>[]);
    if (lastError != null) return Left(handleDioException(lastError));
    return const Right(<Map<String, dynamic>>[]);
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getIngredients() =>
      _fetchFirstAvailableList([ListAPI.ingredients, ListAPI.ingredientsLang]);

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getCompounds() =>
      _fetchFirstAvailableList([ListAPI.compounds, ListAPI.compoundsLang]);
}
