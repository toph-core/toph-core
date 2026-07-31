import 'package:mary_ai_pos/core/constants/constants.dart';

abstract class ArchiveEntity {
  final String id;
  final int bilNumber;
  final OrderStatus status;
  final DateTime? opened;
  final DateTime? closed;
  final int tableNumber;
  final String hallName;
  final int totalPrice;
  final int tableAmount;
  final int goodsTotal;
  final int serviceAmount;
  final int discountAmount;
  final int goodsQuantity;
  final int customerPaidAmount;

  ArchiveEntity({
    required this.id,
    required this.bilNumber,
    required this.status,
    this.opened,
    this.closed,
    required this.tableNumber,
    required this.hallName,
    required this.totalPrice,
    this.tableAmount = 0,
    required this.goodsTotal,
    required this.serviceAmount,
    required this.discountAmount,
    required this.goodsQuantity,
    required this.customerPaidAmount,
  });
}
