import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';

import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/di.dart' show inject;
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/utils/uuid.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/save_order/save_order_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/save_order_entity.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive_detail/archive_detail_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';

part 'detail_event.dart';
part 'detail_state.dart';
part 'detail_bloc.freezed.dart';

EventTransformer<T> debounce<T>(Duration duration) {
  return (events, mapper) => events.debounceTime(duration).switchMap(mapper);
}

/// offline-first-target-architecture.md §4/§9 (V3/V5/V6).
///
/// Reads (categories, goods-by-category, order/bill detail) are
/// `MenuRepository`/`OrdersRepository` `watchX()` subscriptions — no
/// throttle fields, no awaited fetch usecase for the common case. Order/bill
/// detail keeps one narrow live-fetch fallback (`_mainRepository
/// .getPaymentDetailWithTableId`, only when `LocalDatabase` has nothing yet
/// for this table) — a brand-new dine-in order has no other source for its
/// bill row until `SyncEngine`'s next hydration pass lands one, since a
/// dine-in create doesn't return the full order/bill payload synchronously
/// (see EXECUTION_CONCERNS.md).
///
/// Existing-item add/cancel/qty (`_deleteExistingByKey`/
/// `_onSyncExistingItem`) are local-first, always — a single
/// `OrdersRepository` commit that returns without awaiting the network, so
/// `existingSyncingNames` (the +/-/delete button-disable state) clears the
/// instant the *local* write lands, not after a network round trip. The
/// online-path 409/failure handling this file used to do inline is gone —
/// nothing left to catch, since nothing here awaits the network anymore.
class DetailBloc extends Bloc<DetailEvent, DetailState> {
  final CacheService _cache;
  final PrinterService _printerService;
  final MainRepository _mainRepository;
  final MenuRepository _menuRepository;
  final OrdersRepository _ordersRepository;

  ArchiveDetailEntity? lastDetail;

  StreamSubscription<List<CategoryModel>>? _categoriesSub;
  StreamSubscription<List<GoodsModel>>? _goodsSub;
  StreamSubscription<ArchiveDetailModel?>? _detailSub;

  // Existing item +/- backend sinxronizatsiya uchun:
  // - `_existingLineInfo`: UI itemining goods.name → underlying line item id'lari,
  //   good_id, va serverdagi joriy qty. Har bir /bills/{id} refetch dan keyin
  //   `_enrichExistingGoodsWithTimestamps` da yangilanadi.
  // - `_existingSnapshots`: foydalanuvchi tugmani bosgan paytdagi server holati
  //   (debounce davomida saqlanadi). Debounce tugagach, joriy UI qty bilan
  //   solishtirib net delta hisoblanadi.
  // - `_existingSyncTimers`: har bir item uchun debounce taymeri.
  final Map<String, _ExistingLineInfo> _existingLineInfo = {};
  final Map<String, _ExistingSnapshot> _existingSnapshots = {};
  final Map<String, Timer> _existingSyncTimers = {};
  static const _existingSyncDebounce = Duration(milliseconds: 500);

  /// User-entered reason for a pending quantity-decrease cancellation,
  /// captured immediately by `_onSetExistingItemQuantity` and consumed by
  /// `_onSyncExistingItem` when the actual cancel API calls run.
  final Map<String, String> _pendingCancelComments = {};

  DetailBloc(
    this._cache,
    this._printerService,
    this._mainRepository,
    this._menuRepository,
    this._ordersRepository,
  ) : super(const DetailState()) {
    on<_Started>(_onStarted);
    on<_GetCategories>(_onGetCategories);
    on<_CategoriesUpdated>(_onCategoriesUpdated);
    on<_InitSavedGoods>(_onInitSavedGoods);
    on<_FetchBillOrders>(_onFetchBillOrders);
    on<_OrderDetailUpdated>(_onOrderDetailUpdated);
    on<_SetActiveOrderId>(_onSetActiveOrderId);
    on<_CancelOrderItem>(_onCancelOrderItem);
    on<_SetSelectedCategoryId>(_onSetSelectedCategoryId);
    on<_GoodsForCategoryUpdated>(_onGoodsForCategoryUpdated);
    on<_AddFoodAdditional>(_onAddFoodAdditional);
    on<_SelectGood>(_onSelectGood);
    on<_IncrementQuantity>(_onIncrementQuantity);
    on<_DecrementQuantity>(_onDecrementQuantity);
    on<_IncrementExistingItem>(_onIncrementExistingItem);
    on<_DecrementExistingItem>(_onDecrementExistingItem);
    on<_DeleteExistingItem>(_onDeleteExistingItem);
    on<_SetExistingItemQuantity>(_onSetExistingItemQuantity);
    on<_SyncExistingItem>(_onSyncExistingItem);
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
    await _categoriesSub?.cancel();
    _categoriesSub = _menuRepository.watchCategories().listen((categories) {
      if (isClosed) return;
      add(DetailEvent.categoriesUpdated(categories: categories));
    });
  }

  void _onCategoriesUpdated(_CategoriesUpdated event, Emitter<DetailState> emit) {
    final cats = [
      const CategoryModel(id: "all", name: "Hammasi"),
      ...event.categories,
    ];
    emit(state.copyWith(status: Status.SUCCESS, categories: cats));
    if (state.selectedCategoryId == null && cats.isNotEmpty) {
      add(DetailEvent.setSelectedCategoryId(id: cats.first.id));
    }
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
    // Immediate, local: whatever LocalDatabase already has for this table
    // (SyncEngine's hydration pass, or an earlier fetch this session).
    final cachedDetail = _ordersRepository.getOrderDetail(event.billId);
    if (cachedDetail != null) {
      lastDetail = cachedDetail;
      _applyDetailToState(cachedDetail, event.billId, emit);
    }

    // Stay subscribed for future updates — SyncEngine's periodic hydration,
    // or this terminal's own next local write reflected back once it lands.
    await _detailSub?.cancel();
    _detailSub = _ordersRepository.watchOrderDetail(event.billId).listen((detail) {
      if (isClosed) return;
      add(DetailEvent.orderDetailUpdated(tableId: event.billId, detail: detail));
    });

    if (cachedDetail != null && !event.force) return;

    // Narrow live-fetch fallback — a brand-new dine-in order has nothing in
    // LocalDatabase yet (dine-in create doesn't return the full order/bill
    // payload synchronously, and SyncEngine's own hydration pass may not
    // have run yet). See class doc.
    final result = await _mainRepository.getPaymentDetailWithTableId(event.billId);
    if (isClosed) return;
    result.fold(
      (_) {}, // cache (if any) already shown; a fetch failure here is silent
      (detail) {
        if (isClosed || detail is! ArchiveDetailModel) return;
        lastDetail = detail;
        _ordersRepository.saveOrderDetailSnapshot(event.billId, detail.toJson());
        _applyDetailToState(detail, event.billId, emit);
        if (detail.id.isNotEmpty) {
          unawaited(_enrichExistingGoodsWithTimestamps(detail.id, emit));
        }
      },
    );
  }

  void _onOrderDetailUpdated(_OrderDetailUpdated event, Emitter<DetailState> emit) {
    final detail = event.detail;
    if (detail == null || isClosed) return;
    lastDetail = detail;
    _applyDetailToState(detail, event.tableId, emit);
    if (detail.id.isNotEmpty) {
      unawaited(_enrichExistingGoodsWithTimestamps(detail.id, emit));
    }
  }

  Future<void> _enrichExistingGoodsWithTimestamps(
    String orderId,
    Emitter<DetailState> emit,
  ) async {
    try {
      final result = await _mainRepository.getOrderItemsRaw(orderId);
      final res = result.fold((_) => null, (r) => r);
      if (res == null || isClosed) return;
      final raw = res['data'];
      final List<dynamic> list = raw is List
          ? raw
          : (raw is Map<String, dynamic> && raw['items'] is List
              ? raw['items'] as List
              : const []);
      // name -> earliest createdAt
      final tsByName = <String, DateTime>{};
      // name -> aggregated server-side info (line ids, good_id, total qty)
      // /api/v1/order-items/order/{id} har bir line uchun good_id qaytaradi —
      // increment/decrement uchun zarur (bekor qilish + qayta yaratish).
      final infoByName = <String, _ExistingLineInfo>{};
      for (final entry in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(entry);
        final name = (m['good_name'] ?? m['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final status = (m['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelled') continue; // bekor qilingan — ko'rsatmaymiz
        final lineId = (m['id'] ?? '').toString();
        final goodId = (m['good_id'] ?? '').toString();
        final qty = (m['quantity'] as num?)?.toInt() ?? 0;
        final comment = (m['comment'] ?? '').toString();

        final rawDate = m['created_at'] ?? m['createdAt'];
        DateTime? created;
        if (rawDate is String && rawDate.isNotEmpty) {
          created = DateTime.tryParse(rawDate)?.toLocal();
        }
        if (created != null) {
          final existingTs = tsByName[name];
          if (existingTs == null || created.isBefore(existingTs)) {
            tsByName[name] = created;
          }
        }

        if (lineId.isEmpty || goodId.isEmpty) continue;
        final existing = infoByName[name];
        if (existing == null) {
          infoByName[name] = _ExistingLineInfo(
            goodId: goodId,
            comment: comment,
            lineIds: [lineId],
            totalQuantity: qty,
          );
        } else {
          existing.lineIds.add(lineId);
          infoByName[name] = existing.copyWith(
            totalQuantity: existing.totalQuantity + qty,
            // Birinchi line'ning comment'ini saqlaymiz (oddiy holatda barcha
            // line'lar bir xil mahsulot uchun bir xil good_id ga ega).
          );
        }
      }

      // Line-info xaritasi — debounce snapshot lardan tashqari foydalaniladi
      _existingLineInfo
        ..clear()
        ..addAll(infoByName);

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

  /// Legacy event — `_DeleteExistingItem` bilan bir xil ishlaydi (UI shu eventni
  /// yuborib mahsulotni to'liq o'chiradi). Eski kod yo'llari uchun saqlandi.
  Future<void> _onCancelOrderItem(
    _CancelOrderItem event,
    Emitter<DetailState> emit,
  ) async {
    await _deleteExistingByKey(
      itemKey: event.itemId,
      tableId: event.tableId,
      emit: emit,
    );
  }

  // ─── Existing item +/- / delete (backend bilan sinxron) ──────────────

  /// Optimistic +1. Server bilan sinxronlash debounce orqali keyinroq.
  /// `existingSyncingNames` darhol set qilinadi — UI tugmalar zudlik bilan
  /// disable bo'ladi, mahalliy yozuv tugaguncha boshqa click qabul qilinmaydi.
  void _onIncrementExistingItem(
    _IncrementExistingItem event,
    Emitter<DetailState> emit,
  ) {
    final idx = state.existingGoods.indexWhere(
      (g) => g.uniqueId == event.itemKey,
    );
    if (idx == -1) return;
    final item = state.existingGoods[idx];
    if (item.commet == 'cancelled' || item.commet == 'pending_offline') return;
    if (state.existingSyncingNames.contains(item.goods.name)) return;
    _captureSnapshotIfNeeded(item);
    final updated = List<OrderItem>.from(state.existingGoods);
    updated[idx] = item.copyWith(quantity: item.quantity + 1);
    emit(state.copyWith(
      existingGoods: updated,
      existingSyncingNames: {
        ...state.existingSyncingNames,
        item.goods.name,
      },
    ));
    _scheduleExistingSync(event.itemKey, event.tableId);
  }

  /// Optimistic -1. Agar qty 1 da bo'lsa — itemni listdan olib tashlaymiz va
  /// server'ga delete yuborish uchun snapshot saqlanib qoladi (sync handler
  /// barcha line'larni bekor qiladi).
  void _onDecrementExistingItem(
    _DecrementExistingItem event,
    Emitter<DetailState> emit,
  ) {
    final idx = state.existingGoods.indexWhere(
      (g) => g.uniqueId == event.itemKey,
    );
    if (idx == -1) return;
    final item = state.existingGoods[idx];
    if (item.commet == 'cancelled' || item.commet == 'pending_offline') return;
    if (state.existingSyncingNames.contains(item.goods.name)) return;
    _captureSnapshotIfNeeded(item);
    final newQty = item.quantity - 1;
    final updated = List<OrderItem>.from(state.existingGoods);
    if (newQty <= 0) {
      updated.removeAt(idx);
    } else {
      updated[idx] = item.copyWith(quantity: newQty);
    }
    emit(state.copyWith(
      existingGoods: updated,
      existingSyncingNames: {
        ...state.existingSyncingNames,
        item.goods.name,
      },
    ));
    _scheduleExistingSync(event.itemKey, event.tableId);
  }

  Future<void> _onDeleteExistingItem(
    _DeleteExistingItem event,
    Emitter<DetailState> emit,
  ) async {
    await _deleteExistingByKey(
      itemKey: event.itemKey,
      tableId: event.tableId,
      emit: emit,
      cancelComment: event.cancelComment,
    );
  }

  /// Edit-modaldan "Saqlash" bosilganda — yangi miqdorni darhol qo'llaydi va
  /// backendga sinxronlash uchun `_SyncExistingItem` ni navbatga qo'yadi
  /// (debouncesiz, chunki user aniq tasdiq berdi).
  void _onSetExistingItemQuantity(
    _SetExistingItemQuantity event,
    Emitter<DetailState> emit,
  ) {
    final idx = state.existingGoods.indexWhere(
      (g) => g.uniqueId == event.itemKey,
    );
    if (idx == -1) return;
    final item = state.existingGoods[idx];
    if (item.commet == 'cancelled' || item.commet == 'pending_offline') return;
    if (state.existingSyncingNames.contains(item.goods.name)) return;
    if (event.quantity == item.quantity) return;
    if (event.quantity < 1) return;

    _captureSnapshotIfNeeded(item);
    final updated = List<OrderItem>.from(state.existingGoods);
    updated[idx] = item.copyWith(quantity: event.quantity);
    emit(state.copyWith(
      existingGoods: updated,
      existingSyncingNames: {
        ...state.existingSyncingNames,
        item.goods.name,
      },
    ));

    if (event.cancelComment != null && event.cancelComment!.trim().isNotEmpty) {
      _pendingCancelComments[event.itemKey] = event.cancelComment!.trim();
    }

    _existingSyncTimers.remove(event.itemKey)?.cancel();
    add(DetailEvent.syncExistingItem(
      itemKey: event.itemKey,
      tableId: event.tableId,
    ));
  }

  /// Re-cancelling an already-cancelled line on replay is harmless — the
  /// backend (and `OfflineQueueService`'s replay) both tolerate a 404 there
  /// as "already gone."
  Future<void> _deleteExistingByKey({
    required String itemKey,
    required String tableId,
    required Emitter<DetailState> emit,
    String? cancelComment,
  }) async {
    final idx = state.existingGoods.indexWhere((g) => g.uniqueId == itemKey);
    if (idx == -1) return;
    final item = state.existingGoods[idx];

    // Har qanday kutilayotgan +/- sinxronni bekor qilamiz — to'liq o'chirish
    // ustun.
    _existingSyncTimers.remove(itemKey)?.cancel();
    _existingSnapshots.remove(itemKey);

    // Optimistic remove
    final updated = List<OrderItem>.from(state.existingGoods)..removeAt(idx);
    final itemName = item.goods.name;
    emit(state.copyWith(
      existingGoods: updated,
      existingSyncingNames: {...state.existingSyncingNames, itemName},
    ));

    final lineIds = _resolveLineIds(item);
    final trimmedComment = cancelComment?.trim();

    // §4/§9 V3: single local commit, no network await — the optimistic
    // removal above is already the UI's "done." No `_fetchBillOrdersInline`
    // afterward: `lastDetail`'s server snapshot still includes this item
    // (the cancel hasn't synced yet) and `_applyDetailToState`'s
    // pending-merge only ever adds pending `addItems`, never subtracts a
    // pending cancel — reapplying it here would make the just-deleted item
    // reappear until the real sync lands.
    await _ordersRepository.cancelLineItems(lineIds: lineIds, comment: trimmedComment);

    if (!isClosed) {
      final next = Set<String>.from(state.existingSyncingNames)..remove(itemName);
      emit(state.copyWith(existingSyncingNames: next));
    }
  }

  /// Snapshot — bu item bilan birinchi marta o'zaro ta'sirda qachon bo'lganda
  /// saqlanadi. Net delta sync vaqtida shu snapshot bilan solishtiriladi.
  ///
  /// Diqqat: `OrderItem.goods.id` mavjud (saqlangan) itemlar uchun line item
  /// id ni saqlaydi, mahsulot id ni emas. Shuning uchun goodId ni faqat
  /// `_existingLineInfo` map'idan olamiz (u /order-items/order/{id} dan
  /// to'planadi). Agar map bo'sh bo'lsa — snapshot.goodId bo'sh qoladi va sync
  /// vaqtida operatsiya bekor qilinadi (UI refetch orqali revert qilinadi).
  void _captureSnapshotIfNeeded(OrderItem item) {
    if (_existingSnapshots.containsKey(item.uniqueId)) return;
    final info = _existingLineInfo[item.goods.name];
    _existingSnapshots[item.uniqueId] = _ExistingSnapshot(
      goodId: info?.goodId ?? '',
      comment: item.comment,
      originalQty: item.quantity,
      originalLineIds:
          info != null ? List<String>.from(info.lineIds) : <String>[],
    );
  }

  void _scheduleExistingSync(String itemKey, String tableId) {
    _existingSyncTimers.remove(itemKey)?.cancel();
    _existingSyncTimers[itemKey] = Timer(_existingSyncDebounce, () {
      if (isClosed) return;
      add(DetailEvent.syncExistingItem(
        itemKey: itemKey,
        tableId: tableId,
      ));
    });
  }

  Future<void> _onSyncExistingItem(
    _SyncExistingItem event,
    Emitter<DetailState> emit,
  ) async {
    final snapshot = _existingSnapshots.remove(event.itemKey);
    final pendingCancelComment = _pendingCancelComments.remove(event.itemKey);
    _existingSyncTimers.remove(event.itemKey)?.cancel();

    // Sync paytida UI'da +/-/X disable bo'lishi uchun nomni topamiz. Disable
    // flag allaqachon increment/decrement handler'da set qilingan — bu yerda
    // try/finally bilan TOZALAB chiqamiz (har qanday early return holatda
    // ham flag yopiq qolib ketmasligi uchun).
    String? itemName;
    for (final g in state.existingGoods) {
      if (g.uniqueId == event.itemKey) {
        itemName = g.goods.name;
        break;
      }
    }

    try {
      if (snapshot == null) return;
      if (state.activeOrderId == null || state.activeOrderId!.isEmpty) {
        return;
      }

      OrderItem? current;
      for (final g in state.existingGoods) {
        if (g.uniqueId == event.itemKey) {
          current = g;
          break;
        }
      }
      final desiredQty = current?.quantity ?? 0;
      final delta = desiredQty - snapshot.originalQty;
      if (delta == 0) return;

      if (snapshot.goodId.isEmpty) {
        // /order-items/order/{id} hali yuklanmagan yoki bo'sh — to'g'ri sync
        // qila olmaymiz.
        if (navigatorKey.currentContext != null) {
          showErrorMessage(
            navigatorKey.currentContext!,
            'Ma\'lumot yuklanmagan. Yana urinib ko\'ring.',
          );
        }
        return;
      }

      // §4/§9 V3: single local commit per branch, no network await, no
      // ConnectionFailure fork — matches the exact idempotency-key reuse
      // reasoning `create_order_bloc.dart` already documents (§13 risk #2).
      final addItemClientId = generateUuidV4();
      if (delta > 0) {
        // Plus: yangi line item qo'shamiz
        await _ordersRepository.addItems(
          tableId: event.tableId,
          orderId: state.activeOrderId!,
          items: [
            OrderItem(
              goods: GoodsModel(
                id: snapshot.goodId,
                name: itemName ?? '',
                price: '0',
                categoryId: '',
                cookTime: 0,
                costPrice: '0',
                description: '',
                profit: '0',
                profitMargin: '0',
              ),
              quantity: delta,
              comment: snapshot.comment,
            ),
          ],
          itemClientIds: [addItemClientId],
        );
        // Oshxona cheki: mavjud buyurtmaga qo'shilgan yangi porsiyalar.
        _printKitchenForExistingAdd(
          goodId: snapshot.goodId,
          fallbackName: itemName ?? '',
          quantity: delta,
          comment: snapshot.comment,
        );
      } else {
        // Minus: barcha original line'larni bekor qilamiz, qolgan qty bo'lsa
        // bitta yangi line yaratamiz. Backend bitta line'ni bo'lish API
        // qilmaydi — shu yo'l yagona to'g'ri ish.
        await _ordersRepository.cancelLineItems(
          lineIds: snapshot.originalLineIds,
          comment: (pendingCancelComment != null && pendingCancelComment.isNotEmpty)
              ? pendingCancelComment
              : null,
        );
        if (desiredQty > 0) {
          await _ordersRepository.addItems(
            tableId: event.tableId,
            orderId: state.activeOrderId!,
            items: [
              OrderItem(
                goods: GoodsModel(
                  id: snapshot.goodId,
                  name: itemName ?? '',
                  price: '0',
                  categoryId: '',
                  cookTime: 0,
                  costPrice: '0',
                  description: '',
                  profit: '0',
                  profitMargin: '0',
                ),
                quantity: desiredQty,
                comment: snapshot.comment,
              ),
            ],
            itemClientIds: [addItemClientId],
          );
        }
      }

      // Recompute from the last known server snapshot + the outbox op just
      // enqueued above — a pure local operation, no network. Matches the
      // pre-existing "pending delta shown as its own ⏳ line" convention
      // this codebase already used for its offline path.
      final detail = lastDetail;
      if (!isClosed && detail is ArchiveDetailModel) {
        _applyDetailToState(detail, event.tableId, emit);
      }
    } finally {
      if (itemName != null && !isClosed) {
        final next = Set<String>.from(state.existingSyncingNames)
          ..remove(itemName);
        emit(state.copyWith(existingSyncingNames: next));
      }
    }
  }

  /// Mavjud buyurtmaga +delta qo'shilganda oshxona chekini chiqarish.
  /// `existingGoods` dagi `goods.id` line-id ni saqlaydi (mahsulot id emas),
  /// `categoryId` esa bo'sh — shuning uchun real good_id/category_id ni
  /// goods cache'idan tiklaymiz; header [lastDetail] dan olinadi.
  void _printKitchenForExistingAdd({
    required String goodId,
    required String fallbackName,
    required int quantity,
    required String comment,
  }) {
    if (goodId.isEmpty || quantity <= 0) return;
    final goodJson = _cache.getGoods().firstWhere(
          (g) => g['id'] == goodId,
          orElse: () => <String, dynamic>{},
        );
    final detail = lastDetail;
    final tableNumber = detail?.tableNumber.toInt() ?? 0;
    unawaited(_printerService.printKitchenReceiptFor(
      tableLine: tableNumber > 0 ? 'Стол: $tableNumber' : 'Стол: —',
      hallName: detail?.hallName ?? '',
      guestCount: detail?.guestCount.toInt() ?? 0,
      orderNumber: (detail != null && detail.bilNumber > 0)
          ? '${detail.bilNumber}'
          : null,
      orderId: detail?.id,
      items: [
        OrderItem(
          goods: GoodsModel(
            id: goodId,
            name: (goodJson['name'] as String?) ?? fallbackName,
            price: goodJson['price']?.toString() ?? '0',
            categoryId: goodJson['category_id']?.toString() ?? '',
            cookTime: 0,
            costPrice: '0',
            description: '',
            profit: '0',
            profitMargin: '0',
          ),
          quantity: quantity,
          comment: comment,
        ),
      ],
    ));
  }

  /// Item uchun underlying server line id'larini topadi. Avval
  /// `_existingLineInfo` map'iga (bills+order-items dan to'plangan), agar
  /// topilmasa — `OrderItem.uniqueId` ni o'zini single id deb hisoblaymiz.
  List<String> _resolveLineIds(OrderItem item) {
    final info = _existingLineInfo[item.goods.name];
    if (info != null && info.lineIds.isNotEmpty) {
      return List<String>.from(info.lineIds);
    }
    return item.uniqueId.isNotEmpty ? <String>[item.uniqueId] : <String>[];
  }

  Future<void> _onSetSelectedCategoryId(
    _SetSelectedCategoryId event,
    Emitter<DetailState> emit,
  ) async {
    // Re-tapping the active category should not refetch or clear the list.
    if (state.selectedCategoryId == event.id &&
        state.goods != null &&
        state.goods!.isNotEmpty) {
      return;
    }

    // Immediate, local: whatever LocalDatabase already has for this
    // category — not a client-side filter of the "all categories" cache
    // (see MenuRepository's own doc for why that used to show a flash of
    // stale data on every category switch).
    final cachedForCategory = _menuRepository.getGoodsForCategory(event.id);
    emit(state.copyWith(
      selectedCategoryId: event.id,
      status: cachedForCategory.isNotEmpty ? Status.SUCCESS : Status.LOADING,
      goods: cachedForCategory,
    ));

    await _goodsSub?.cancel();
    _goodsSub = _menuRepository.watchGoodsForCategory(event.id).listen((goods) {
      if (isClosed) return;
      add(DetailEvent.goodsForCategoryUpdated(categoryId: event.id, goods: goods));
    });
  }

  void _onGoodsForCategoryUpdated(
    _GoodsForCategoryUpdated event,
    Emitter<DetailState> emit,
  ) {
    // Ignore stale updates if the user already switched category.
    if (state.selectedCategoryId != event.categoryId) return;
    emit(state.copyWith(status: Status.SUCCESS, goods: event.goods));
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

  /// CLIENT_FACING_OFFLINE_PLAN.md §3: search is a local filter over the
  /// already-synced goods box (`MenuRepository.searchGoodsByName`), not a
  /// network query — the login/setup phase pulls the full catalog into
  /// `LocalDatabase`, so the "no local mirror to search against" caveat this
  /// path was built around no longer holds.
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
    emit(
      state.copyWith(
        status: Status.SUCCESS,
        selectedCategoryId: "all",
        goods: _menuRepository.searchGoodsByName(event.text),
      ),
    );
  }

  SaveOrderEntity? saveOrder(CafeTableModel cafeTable, int guestCount) {
    if (state.selectedGoods.isNotEmpty) {
      return SaveOrderModel(
        cafeTable: cafeTable,
        createOrderRequest: CreateOrderRequestModel(
          id: generateUuidV4(),
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
    for (final t in _existingSyncTimers.values) {
      t.cancel();
    }
    _existingSyncTimers.clear();
    _existingSnapshots.clear();
    _existingLineInfo.clear();
    _categoriesSub?.cancel();
    _goodsSub?.cancel();
    _detailSub?.cancel();
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

/// Mavjud (saqlangan) itemning serverdagi aggregatlangan ko'rinishi.
/// `/api/v1/order-items/order/{id}` natijalaridan to'planadi.
class _ExistingLineInfo {
  final String goodId;
  final String comment;
  final List<String> lineIds; // underlying server line ids
  final int totalQuantity;

  _ExistingLineInfo({
    required this.goodId,
    required this.comment,
    required this.lineIds,
    required this.totalQuantity,
  });

  _ExistingLineInfo copyWith({
    String? goodId,
    String? comment,
    List<String>? lineIds,
    int? totalQuantity,
  }) =>
      _ExistingLineInfo(
        goodId: goodId ?? this.goodId,
        comment: comment ?? this.comment,
        lineIds: lineIds ?? this.lineIds,
        totalQuantity: totalQuantity ?? this.totalQuantity,
      );
}

/// Foydalanuvchi +/- bosgan paytdagi server snapshot. Debounce tugagach,
/// joriy UI qty bilan solishtirib backend sinxron qilinadi.
class _ExistingSnapshot {
  final String goodId;
  final String comment;
  final int originalQty;
  final List<String> originalLineIds;

  _ExistingSnapshot({
    required this.goodId,
    required this.comment,
    required this.originalQty,
    required this.originalLineIds,
  });
}
