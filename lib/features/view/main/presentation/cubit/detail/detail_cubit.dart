import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
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

part 'detail_cubit.freezed.dart';
part 'detail_state.dart';

class DetailCubit extends Cubit<DetailState> {
  final GetCategoriesUsecase _getCategoriesUsecase;
  final GetGoodsByCategoryIdUseCase _getGoodsByCategoryIdUseCase;
  DetailCubit(this._getCategoriesUsecase, this._getGoodsByCategoryIdUseCase)
    : super(const DetailState());

  Future<void> getCategories() async {
    emit(state.copyWith(status: Status.OTHER_LOADING));
    final result = await _getCategoriesUsecase(NoParams());
    result.fold(
      (failure) => emit(state.copyWith(status: Status.ERROR, failure: failure)),
      (categories) {
        emit(state.copyWith(status: Status.SUCCESS, categories: categories));
        if (categories.isNotEmpty) {
          setSelectedCategoryId(categories.first.id);
        }
      },
    );
  }

  void initSavedGoods(List<OrderItem> savedGoods) {
    emit(state.copyWith(selectedGoods: savedGoods));
  }

  void setSelectedCategoryId(String id) {
    emit(state.copyWith(selectedCategoryId: id));
    _getGoodsByCategoryId(id);
  }

  Future<void> _getGoodsByCategoryId(String categoryId) async {
    emit(state.copyWith(status: Status.LOADING));
    final result = await _getGoodsByCategoryIdUseCase(categoryId);
    result.fold(
      (failure) => emit(state.copyWith(status: Status.ERROR, failure: failure)),
      (goods) => emit(state.copyWith(status: Status.SUCCESS, goods: goods)),
    );
  }

  void addFoodAdditional(
    List<FoodAdditionalModel> additionals,
    String orderId,
    String comment,
  ) {
    final id = state.selectedGoods.indexWhere(
      (value) => value.uniqueId == orderId,
    );
    if (id != -1) {
      List<OrderItem> orders = List.from(state.selectedGoods);
      orders[id] = orders[id].copyWith(
        goods: orders[id].goods.copyWith(additionals: additionals),
        commet: comment,
      );
      emit(state.copyWith(selectedGoods: orders));
    }
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
  }

  void selectGood(GoodsModel good) {
    final selectedGoods = List<OrderItem>.from(state.selectedGoods);
    final index = selectedGoods.indexWhere((item) => item.goods.id == good.id);

    if (index != -1) {
      selectedGoods[index] = selectedGoods[index].copyWith(
        quantity: selectedGoods[index].quantity + 1,
      );
    } else {
      selectedGoods.add(
        OrderItem(goods: good, uniqueId: UniqueKey().toString()),
      );
    }
    emit(state.copyWith(selectedGoods: selectedGoods));
  }

  void incrementQuantity(String goodsId) {
    final selectedGoods = List<OrderItem>.from(state.selectedGoods);
    final index = selectedGoods.indexWhere((item) => item.goods.id == goodsId);

    if (index != -1) {
      selectedGoods[index] = selectedGoods[index].copyWith(
        quantity: selectedGoods[index].quantity + 1,
      );
      emit(state.copyWith(selectedGoods: selectedGoods));
    }
  }

  void decrementQuantity(String goodsId) {
    final selectedGoods = List<OrderItem>.from(state.selectedGoods);
    final index = selectedGoods.indexWhere((item) => item.goods.id == goodsId);

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

  void clearGoods() {
    emit(state.copyWith(selectedGoods: []));
  }
}
