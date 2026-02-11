part of 'detail_cubit.dart';

@freezed
class OrderItem with _$OrderItem {
  const factory OrderItem({
    required GoodsModel goods,
    @Default(1) int quantity,
  }) = _OrderItem;
}

@freezed
class DetailState with _$DetailState {
  const factory DetailState({
    @Default(Status.UNKNOWN) Status status,
    @Default(UnknownFailure()) Failure failure,
    List<CategoryModel>? categories,
    List<GoodsModel>? goods,
    String? selectedCategoryId,
    @Default([]) List<OrderItem> selectedGoods,
  }) = _DetailState;
}
