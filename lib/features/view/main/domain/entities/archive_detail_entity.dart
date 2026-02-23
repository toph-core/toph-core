import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';

abstract class ArchiveDetailEntity {
  final String id;
  final int bilNumber;
  final OrderStatus status;
  final DateTime? opened;
  final String tableId;
  final int tableNumber;
  final List<OrderFoodEntity> goods;

  ArchiveDetailEntity({
    required this.id,
    required this.bilNumber,
    required this.status,
    required this.opened,
    required this.tableId,
    required this.tableNumber,
    required this.goods,
  });
}
