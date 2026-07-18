import 'package:mary_ai_pos/core/constants/constants.dart';

abstract class PaymentPayRequestEntity {
  final String orderId;
  final String cashRegisterId;
  final String cashierId;
  final int customPaidAmount;
  final int discountAmount;
  final int discountPercent;
  final PaymentType paymentType;
  final String comment;
  final int tableCharge;

  PaymentPayRequestEntity({
    required this.orderId,
    required this.cashRegisterId,
    required this.cashierId,
    required this.customPaidAmount,
    required this.discountAmount,
    required this.discountPercent,
    required this.paymentType,
    required this.comment,
    this.tableCharge = 0,
  });

  Map<String, dynamic> request();
}
