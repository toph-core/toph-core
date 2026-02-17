part of 'detail_cubit.dart';

@freezed
class OrderItem with _$OrderItem {
  const factory OrderItem({
    @Default('') String uniqueId,
    required GoodsModel goods,
    @Default(1) int quantity,
    @Default('') String commet,
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
