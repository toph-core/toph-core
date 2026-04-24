part of 'detail_bloc.dart';

@freezed
class OrderItem with _$OrderItem {
  const factory OrderItem({
    @Default('') String uniqueId,
    required GoodsModel goods,
    @Default(1) int quantity,
    @Default('') String commet,
    // Item qachon buyurtmaga qo'shilgan (server `created_at` yoki
    // offline queue `createdAt`). UI HH:mm formatida ko'rsatadi.
    DateTime? createdAt,
  }) = _OrderItem;
}

@freezed
class DetailState with _$DetailState {
  const factory DetailState({
    @Default(Status.UNKNOWN) Status status,
    @Default(UnknownFailure()) Failure failure,
    TextEditingController? textController,
    List<CategoryModel>? categories,
    List<GoodsModel>? goods,
    String? selectedCategoryId,
    @Default([]) List<OrderItem> selectedGoods,
    @Default([]) List<OrderItem> existingGoods,
    String? activeOrderId,
  }) = _DetailState;
}
