import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
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

  DetailBloc(
    this._getCategoriesUsecase,
    this._getGoodsByCategoryIdUseCase,
    this._getGoodsWithNameUseCase,
  ) : super(const DetailState()) {
    on<_Started>(_onStarted);
    on<_GetCategories>(_onGetCategories);
    on<_InitSavedGoods>(_onInitSavedGoods);
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
    emit(state.copyWith(status: Status.OTHER_LOADING));
    final result = await _getCategoriesUsecase(NoParams());
    result.fold(
      (failure) => emit(state.copyWith(status: Status.ERROR, failure: failure)),
      (categories) {
        categories.insert(0, const CategoryModel(id: "all", name: "Hammasi"));
        emit(state.copyWith(status: Status.SUCCESS, categories: categories));
        if (categories.isNotEmpty) {
          add(DetailEvent.setSelectedCategoryId(id: categories.first.id));
        }
      },
    );
  }

  void _onInitSavedGoods(_InitSavedGoods event, Emitter<DetailState> emit) {
    emit(state.copyWith(selectedGoods: event.savedGoods));
  }

  Future<void> _onSetSelectedCategoryId(
    _SetSelectedCategoryId event,
    Emitter<DetailState> emit,
  ) async {
    emit(state.copyWith(selectedCategoryId: event.id));
    emit(state.copyWith(status: Status.LOADING));
    final result = await _getGoodsByCategoryIdUseCase(event.id);
    result.fold(
      (failure) => emit(state.copyWith(status: Status.ERROR, failure: failure)),
      (goods) => emit(state.copyWith(status: Status.SUCCESS, goods: goods)),
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
        commet: event.comment,
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
      if (state.selectedCategoryId != null) {
        add(DetailEvent.setSelectedCategoryId(id: state.selectedCategoryId!));
      }
      return;
    }
    emit(state.copyWith(status: Status.LOADING,selectedCategoryId: "all"));
    final result = await _getGoodsWithNameUseCase(event.text);
    result.fold(
      (failure) => emit(state.copyWith(status: Status.ERROR, failure: failure)),
      (goods) => emit(state.copyWith(status: Status.SUCCESS, goods: goods)),
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
}
