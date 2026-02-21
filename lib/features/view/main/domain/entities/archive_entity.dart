import 'package:mary_ai_pos/core/constants/constants.dart';

abstract class ArchiveEntity {
  final String id;
  final int bilNumber;
  final OrderStatus status;
  final DateTime? opened;
  final int tableNumber;
  final int totalPrice;

  ArchiveEntity({
    required this.id,
    required this.bilNumber,
    required this.status,
   this.opened,
    required this.tableNumber,
    required this.totalPrice,
  });
}
