part of 'detail_bloc.dart';

@freezed
class DetailEvent with _$DetailEvent {
  const factory DetailEvent.started() = _Started;
  const factory DetailEvent.getCategories() = _GetCategories;
  const factory DetailEvent.initSavedGoods({
    required List<OrderItem> savedGoods,
  }) = _InitSavedGoods;
  const factory DetailEvent.setSelectedCategoryId({required String id}) =
      _SetSelectedCategoryId;
  const factory DetailEvent.addFoodAdditional({
    required List<FoodAdditionalModel> additionals,
    required String orderId,
    required String comment,
  }) = _AddFoodAdditional;
  const factory DetailEvent.selectGood({required GoodsModel good}) =
      _SelectGood;
  const factory DetailEvent.incrementQuantity({required String goodsId}) =
      _IncrementQuantity;
  const factory DetailEvent.decrementQuantity({required String goodsId}) =
      _DecrementQuantity;
  const factory DetailEvent.clearGoods() = _ClearGoods;
  const factory DetailEvent.searchTextChanged({required String text}) =
      _SearchTextChanged;
  const factory DetailEvent.fetchBillOrders({
    required String billId,
    @Default(false) bool force,
  }) = _FetchBillOrders;
  const factory DetailEvent.setActiveOrderId({required String orderId}) =
      _SetActiveOrderId;
  const factory DetailEvent.cancelOrderItem({
    required String itemId,
    required String tableId,
  }) = _CancelOrderItem;
}
