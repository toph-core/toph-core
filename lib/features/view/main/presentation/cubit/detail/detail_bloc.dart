import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:dio/dio.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'dart:convert';

import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/save_order/save_order_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/save_order_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_categories_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_goods_by_category_id_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_goods_with_name_usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_payment_detail_with_table_id_usecase.dart';

part 'detail_event.dart';
part 'detail_state.dart';
part 'detail_bloc.freezed.dart';

EventTransformer<T> debounce<T>(Duration duration) {
  return (events, mapper) => events.debounceTime(duration).switchMap(mapper);
}

class DetailBloc extends Bloc<DetailEvent, DetailState> {
  final GetCategoriesUsecase _getCategoriesUsecase;
  final GetGoodsByCategoryIdUseCase _getGoodsByCategoryIdUseCase;
  final GetGoodsWithNameUseCase _getGoodsWithNameUseCase;
  final GetPaymentDetailWithTableIdUsecase _getPaymentDetailWithTableIdUsecase;
  final CacheService _cache;

  ArchiveDetailEntity? lastDetail;

  // Duplikat /orders/table/{id} + /bills/{id} chaqiriqlarini kamaytirish uchun
  DateTime? _lastBillFetchAt;
  String? _lastBillFetchTableId;
  static const _billFetchThrottle = Duration(seconds: 15);

  // Kategoriyani tez-tez tanlashda /goods ga burst so'rov yubormaslik uchun
  DateTime? _lastCategoryFetchAt;
  String? _lastCategoryFetchId;
  static const _categoryFetchThrottle = Duration(seconds: 10);

  DetailBloc(
    this._getCategoriesUsecase,
    this._getGoodsByCategoryIdUseCase,
    this._getGoodsWithNameUseCase,
    this._getPaymentDetailWithTableIdUsecase,
    this._cache,
  ) : super(const DetailState()) {
    on<_Started>(_onStarted);
    on<_GetCategories>(_onGetCategories);
    on<_InitSavedGoods>(_onInitSavedGoods);
    on<_FetchBillOrders>(_onFetchBillOrders);
    on<_SetActiveOrderId>(_onSetActiveOrderId);
    on<_CancelOrderItem>(_onCancelOrderItem);
    on<_SetSelectedCategoryId>(_onSetSelectedCategoryId);
    on<_AddFoodAdditional>(_onAddFoodAdditional);
    on<_SelectGood>(_onSelectGood);
    on<_IncrementQuantity>(_onIncrementQuantity);
    on<_DecrementQuantity>(_onDecrementQuantity);
    on<_ClearGoods>(_onClearGoods);

    // Debounce the search events so we don't spam the API or local filter directly
    on<_SearchTextChanged>(
      _onSearchTextChanged,
      transformer: debounce(const Duration(milliseconds: 500)),
    );
  }

  void _onStarted(_Started event, Emitter<DetailState> emit) {
    emit(state.copyWith(textController: TextEditingController()));
  }

  Future<void> _onGetCategories(
    _GetCategories event,
    Emitter<DetailState> emit,
  ) async {
    // Cache-first: darhol ko'rsat
    final cachedCats = _cache.getCategories();
    if (cachedCats.isNotEmpty) {
      final cats = [
        const CategoryModel(id: "all", name: "Hammasi"),
        ...cachedCats.map((e) => CategoryModel.fromJson(e)),
      ];
      emit(state.copyWith(status: Status.SUCCESS, categories: cats));
      if (state.selectedCategoryId == null) {
        add(DetailEvent.setSelectedCategoryId(id: cats.first.id));
      }
    } else {
      emit(state.copyWith(status: Status.OTHER_LOADING));
    }

    // Orqa fonda network dan yangilanadi
    final result = await _getCategoriesUsecase(NoParams());
    if (isClosed) return;
    result.fold(
      (failure) {
        if (cachedCats.isEmpty && !isClosed) {
          emit(state.copyWith(status: Status.ERROR, failure: failure));
        }
      },
      (categories) {
        if (isClosed) return;
        _cache.saveCategories(
          categories.map((c) => {'id': c.id, 'name': c.name}).toList(),
        );
        categories.insert(0, const CategoryModel(id: "all", name: "Hammasi"));
        emit(state.copyWith(status: Status.SUCCESS, categories: categories));
        if (state.selectedCategoryId == null && categories.isNotEmpty) {
          add(DetailEvent.setSelectedCategoryId(id: categories.first.id));
        }
      },
    );
  }

  void _onInitSavedGoods(_InitSavedGoods event, Emitter<DetailState> emit) {
    emit(state.copyWith(selectedGoods: event.savedGoods));
  }

  void _onSetActiveOrderId(_SetActiveOrderId event, Emitter<DetailState> emit) {
    if (state.activeOrderId == event.orderId) return;
    emit(state.copyWith(activeOrderId: event.orderId));
  }

  Future<void> _onFetchBillOrders(
    _FetchBillOrders event,
    Emitter<DetailState> emit,
  ) async {
    // Cache-first: avval saqlangan detalni ko'rsat
    final cached = _cache.getOrderDetail(event.billId);
    if (cached != null) {
      _applyDetailToState(ArchiveDetailModel.fromJson(cached), event.billId, emit);
    }

    // Throttle: shu tableId uchun 15s ichida takroriy /bills/ + /orders/table/
    // chaqiriqlari bloklanadi (widget rebuild dan kelgan duplicate eventlarni yutadi).
    // `force: true` — user mutatsiyasi (item qo'shildi/bekor qilindi) dan keyin
    // throttle'ni chetlab o'tamiz, yangi state darhol yuklanishi kerak.
    // Agar cache yo'q bo'lsa (masalan transfer keyin evict qilindi) — ham
    // throttle'ni chetlab o'tamiz, serverdan yangi ma'lumot olish shart.
    final cacheWasAbsent = cached == null;
    if (!event.force &&
        !cacheWasAbsent &&
        _lastBillFetchTableId == event.billId &&
        _lastBillFetchAt != null &&
        DateTime.now().difference(_lastBillFetchAt!) < _billFetchThrottle) {
      return;
    }
    _lastBillFetchTableId = event.billId;
    _lastBillFetchAt = DateTime.now();

    final result = await _getPaymentDetailWithTableIdUsecase.call(event.billId);
    if (isClosed) return;
    String? orderIdForTimestamps;
    result.fold(
      (_) => null, // cache allaqachon ko'rsatilgan, hech nima qilmaymiz
      (detail) {
        if (isClosed) return;
        lastDetail = detail;
        _cache.saveOrderDetail(event.billId, (detail as ArchiveDetailModel).toJson());
        _applyDetailToState(detail, event.billId, emit);
        orderIdForTimestamps = detail.id;
      },
    );

    // Bill javobida items.created_at yo'q — `/api/v1/order-items/order/{id}`
    // endpoint'idan timestamplarni olib, ko'rsatilgan itemlar ustidan merge
    // qilamiz. Aks holda foydalanuvchi vaqtni ko'rmaydi.
    if (orderIdForTimestamps != null && orderIdForTimestamps!.isNotEmpty) {
      await _enrichExistingGoodsWithTimestamps(orderIdForTimestamps!, emit);
    }
  }

  Future<void> _enrichExistingGoodsWithTimestamps(
    String orderId,
    Emitter<DetailState> emit,
  ) async {
    try {
      final res = await inject<DioClient>().get(
        ListAPI.orderItemsListByOrder(orderId),
      );
      if (isClosed) return;
      final raw = res.data['data'];
      final List<dynamic> list = raw is List
          ? raw
          : (raw is Map<String, dynamic> && raw['items'] is List
              ? raw['items'] as List
              : const []);
      // name -> earliest createdAt
      final tsByName = <String, DateTime>{};
      for (final entry in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(entry);
        final name = (m['good_name'] ?? m['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final rawDate = m['created_at'] ?? m['createdAt'];
        DateTime? created;
        if (rawDate is String && rawDate.isNotEmpty) {
          created = DateTime.tryParse(rawDate)?.toLocal();
        }
        if (created == null) continue;
        final existing = tsByName[name];
        if (existing == null || created.isBefore(existing)) {
          tsByName[name] = created;
        }
      }
      if (tsByName.isEmpty || isClosed) return;

      // Cache'ga saqlaymiz — offline'da ham itemlar uchun vaqt ko'rinadi
      await _cache.saveItemTimestamps(orderId, tsByName);

      final updated = state.existingGoods.map((g) {
        // Offline pending itemlar (⏳ prefix) o'z timestamp'iga ega — tegmaymiz
        if (g.commet == 'pending_offline') return g;
        final t = tsByName[g.goods.name];
        if (t == null) return g;
        return g.copyWith(createdAt: t);
      }).toList();
      emit(state.copyWith(existingGoods: updated));
    } catch (_) {
      // Endpoint ishlamasa yoki javob noto'g'ri — sukut bilan o'tamiz
    }
  }

  /// Server/cache detail + offline queue itemlarni birlashtiradi.
  /// Bir xil mahsulotlarni guruhlaydi (x2, x3 ko'rinishida).
  void _applyDetailToState(
    ArchiveDetailModel detail,
    String tableId,
    Emitter<DetailState> emit,
  ) {
    // Cache'da saqlangan timestamplar — offline rejimda ham vaqtlar ko'rinadi
    final cachedTs = _cache.getItemTimestamps(detail.id);

    // 1. Server itemlarini guruhlash: bir xil nom → miqdorini qo'sh
    final Map<String, OrderItem> grouped = {};
    for (final g in detail.goods) {
      if (g.status == 'cancelled') continue; // cancelled — ko'rsatmaymiz
      final key = g.name;
      // Bill javobida `created_at` yo'q, lekin avvalgi sessiyada
      // `/order-items/order/{id}` orqali olingan vaqt cache'da bo'lishi mumkin
      final ts = g.createdAt ?? cachedTs[g.name];
      if (grouped.containsKey(key)) {
        // Bir xil nomli itemlar guruhlansa — eng erta qo'shilgan vaqtni
        // saqlaymiz (foydalanuvchi "qachon birinchi marta urilgan" ni ko'radi).
        final existing = grouped[key]!;
        final earliest = _earlier(existing.createdAt, ts);
        grouped[key] = existing.copyWith(
          quantity: existing.quantity + g.quantity,
          createdAt: earliest,
        );
      } else {
        grouped[key] = OrderItem(
          uniqueId: g.id,
          goods: GoodsModel(
            id: g.id,
            name: g.name,
            price: g.price.toString(),
            categoryId: '',
            cookTime: 0,
            costPrice: '0',
            description: '',
            profit: '0',
            profitMargin: '0',
          ),
          quantity: g.quantity,
          commet: g.status,
          comment: g.comment,
          createdAt: ts,
        );
      }
    }

    // 2. Offline queue dan ushbu stol uchun kutayotgan itemlar
    final queue = inject<OfflineQueueService>();
    final cachedGoods = _cache.getGoods();
    final pending = queue.pending.where(
      (op) => op.tableId == tableId && op.type == PendingOperationType.addItems,
    );
    for (final op in pending) {
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        final items = payload['items'] as List<dynamic>;
        for (final item in items) {
          final goodId = item['good_id'] as String;
          final qty = (item['quantity'] as num).toInt();
          final goodJson = cachedGoods.firstWhere(
            (g) => g['id'] == goodId,
            orElse: () => <String, dynamic>{},
          );
          if (goodJson.isEmpty) continue;
          final name = goodJson['name'] as String? ?? goodId;
          final price = goodJson['price']?.toString() ?? '0';
          final key = '⏳$name'; // prefix — offline itemlar boshqa key
          if (grouped.containsKey(key)) {
            final existing = grouped[key]!;
            grouped[key] = existing.copyWith(
              quantity: existing.quantity + qty,
              createdAt: _earlier(existing.createdAt, op.createdAt),
            );
          } else {
            grouped[key] = OrderItem(
              uniqueId: '${op.id}_$goodId',
              goods: GoodsModel(
                id: goodId,
                name: '⏳ $name',
                price: price,
                categoryId: '',
                cookTime: 0,
                costPrice: '0',
                description: '',
                profit: '0',
                profitMargin: '0',
              ),
              quantity: qty,
              commet: 'pending_offline',
              createdAt: op.createdAt,
            );
          }
        }
      } catch (_) {}
    }

    if (!isClosed) {
      emit(state.copyWith(
        existingGoods: grouped.values.toList(),
        activeOrderId: detail.id,
      ));
    }
  }

  Future<void> _onCancelOrderItem(
    _CancelOrderItem event,
    Emitter<DetailState> emit,
  ) async {
    try {
      final dio = inject<DioClient>().dio;
      await dio.post(ListAPI.orderItemCancel(event.itemId));
      // Optimistic: darhol cancelled deb belgilaymiz
      final updated = state.existingGoods.map((g) {
        if (g.uniqueId == event.itemId) return g.copyWith(commet: 'cancelled');
        return g;
      }).toList();
      emit(state.copyWith(existingGoods: updated));
      // Serverdan ham yangilaymiz
      add(DetailEvent.fetchBillOrders(billId: event.tableId));
    } on DioException catch (e) {
      final msg = e.response?.data?['message']?.toString() ??
          e.message ??
          'Xato yuz berdi';
      if (navigatorKey.currentContext != null) {
        showErrorMessage(navigatorKey.currentContext!, msg);
      }
    } catch (e) {
      if (navigatorKey.currentContext != null) {
        showErrorMessage(navigatorKey.currentContext!, e.toString());
      }
    }
  }

  Future<void> _onSetSelectedCategoryId(
    _SetSelectedCategoryId event,
    Emitter<DetailState> emit,
  ) async {
    emit(state.copyWith(selectedCategoryId: event.id));

    // Cache-first: darhol ko'rsat
    final allCached = _cache.getGoods();
    if (allCached.isNotEmpty) {
      final filtered = allCached
          .map((e) => GoodsModel.fromJson(e))
          .where((g) => event.id == 'all' || g.categoryId == event.id)
          .toList();
      emit(state.copyWith(status: Status.SUCCESS, goods: filtered));
    } else {
      emit(state.copyWith(status: Status.LOADING));
    }

    // Throttle: kassir tez-tez kategoriyani bosganda serverga burst ketmasin.
    // Cache da goodlar bo'lsa — 10s ichida bir xil kategoriya takrorlanmaydi.
    if (allCached.isNotEmpty &&
        _lastCategoryFetchId == event.id &&
        _lastCategoryFetchAt != null &&
        DateTime.now().difference(_lastCategoryFetchAt!) <
            _categoryFetchThrottle) {
      return;
    }
    _lastCategoryFetchId = event.id;
    _lastCategoryFetchAt = DateTime.now();

    // Orqa fonda network dan yangilanadi
    final result = await _getGoodsByCategoryIdUseCase(event.id);
    if (isClosed) return;
    result.fold(
      (failure) {
        if (allCached.isEmpty && !isClosed) {
          emit(state.copyWith(status: Status.ERROR, failure: failure));
        }
      },
      (goods) {
        if (isClosed) return;
        // "all" kategoriyasi kelganda cache yangilanadi
        if (event.id == 'all') {
          _cache.saveGoods(goods.map((g) => g.toJson()).toList());
        }
        emit(state.copyWith(status: Status.SUCCESS, goods: goods));
      },
    );
  }

  void _onAddFoodAdditional(
    _AddFoodAdditional event,
    Emitter<DetailState> emit,
  ) {
    final id = state.selectedGoods.indexWhere(
      (value) => value.uniqueId == event.orderId,
    );
    if (id != -1) {
      List<OrderItem> orders = List.from(state.selectedGoods);
      orders[id] = orders[id].copyWith(
        goods: orders[id].goods.copyWith(additionals: event.additionals),
        comment: event.comment,
      );
      emit(state.copyWith(selectedGoods: orders));
    }
  }

  void _onSelectGood(_SelectGood event, Emitter<DetailState> emit) {
    final selectedGoods = List<OrderItem>.from(state.selectedGoods);
    final index = selectedGoods.indexWhere(
      (item) => item.goods.id == event.good.id,
    );

    if (index != -1) {
      selectedGoods[index] = selectedGoods[index].copyWith(
        quantity: selectedGoods[index].quantity + 1,
      );
    } else {
      selectedGoods.add(
        OrderItem(goods: event.good, uniqueId: UniqueKey().toString()),
      );
    }
    emit(state.copyWith(selectedGoods: selectedGoods));
  }

  void _onIncrementQuantity(
    _IncrementQuantity event,
    Emitter<DetailState> emit,
  ) {
    final selectedGoods = List<OrderItem>.from(state.selectedGoods);
    final index = selectedGoods.indexWhere(
      (item) => item.goods.id == event.goodsId,
    );

    if (index != -1) {
      selectedGoods[index] = selectedGoods[index].copyWith(
        quantity: selectedGoods[index].quantity + 1,
      );
      emit(state.copyWith(selectedGoods: selectedGoods));
    }
  }

  void _onDecrementQuantity(
    _DecrementQuantity event,
    Emitter<DetailState> emit,
  ) {
    final selectedGoods = List<OrderItem>.from(state.selectedGoods);
    final index = selectedGoods.indexWhere(
      (item) => item.goods.id == event.goodsId,
    );

    if (index != -1) {
      if (selectedGoods[index].quantity > 1) {
        selectedGoods[index] = selectedGoods[index].copyWith(
          quantity: selectedGoods[index].quantity - 1,
        );
      } else {
        selectedGoods.removeAt(index);
      }
      emit(state.copyWith(selectedGoods: selectedGoods));
    }
  }

  void _onClearGoods(_ClearGoods event, Emitter<DetailState> emit) {
    emit(state.copyWith(selectedGoods: []));
  }

  Future<void> _onSearchTextChanged(
    _SearchTextChanged event,
    Emitter<DetailState> emit,
  ) async {
    if (event.text.isEmpty) {
      if (state.selectedCategoryId != null && !isClosed) {
        add(DetailEvent.setSelectedCategoryId(id: state.selectedCategoryId!));
      }
      return;
    }
    emit(state.copyWith(status: Status.LOADING, selectedCategoryId: "all"));
    final result = await _getGoodsWithNameUseCase(event.text);
    if (isClosed) return;
    result.fold(
      (failure) {
        if (!isClosed) {
          emit(state.copyWith(status: Status.ERROR, failure: failure));
        }
      },
      (goods) {
        if (!isClosed) {
          emit(state.copyWith(status: Status.SUCCESS, goods: goods));
        }
      },
    );
  }

  SaveOrderEntity? saveOrder(CafeTableModel cafeTable, int guestCount) {
    if (state.selectedGoods.isNotEmpty) {
      return SaveOrderModel(
        cafeTable: cafeTable,
        createOrderRequest: CreateOrderRequestModel(
          tableId: cafeTable.id,
          comment: "Very good",
          guestCount: guestCount,
          foods: state.selectedGoods,
          status: OrderStatus.open,
          tableStatus: TableStatus.busy,
        ),
      );
    }
    return null;
  }

  @override
  Future<void> close() {
    state.textController?.dispose();
    return super.close();
  }

  /// Ikki vaqtdan eng erta bo'lganini qaytaradi (null-aware).
  /// Bir xil nomli itemlarni guruhlanganda eng birinchi "urilgan" vaqtni
  /// saqlash uchun ishlatiladi.
  DateTime? _earlier(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }
}
