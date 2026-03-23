import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/payment_pay_request_entity.dart';

part 'payment_pay_request_model.freezed.dart';
part 'payment_pay_request_model.g.dart';

@freezed
class PaymentPayRequestModel
    with _$PaymentPayRequestModel
    implements PaymentPayRequestEntity {
  const PaymentPayRequestModel._();

  const factory PaymentPayRequestModel({
    @JsonKey(name: 'order_id') @Default('') String orderId,
    @JsonKey(name: 'cash_register_id') @Default('') String cashRegisterId,
    @JsonKey(name: 'cashier_id') @Default('') String cashierId,
    @JsonKey(name: 'customer_paid_amount') @Default(0) int customPaidAmount,
    @JsonKey(name: 'discount_amount') @Default(0) int discountAmount,
    @JsonKey(name: 'discount_percent') @Default(0) int discountPercent,
    @JsonKey(name: 'payment_type')
    @Default(PaymentType.cash)
    PaymentType paymentType,
    @Default('') String comment,
  }) = _PaymentPayRequestModel;

  factory PaymentPayRequestModel.fromJson(Map<String, dynamic> json) =>
      _$PaymentPayRequestModelFromJson(json);

  @override
  Map<String, dynamic> request() => {
    // "cash_register_id": cashRegisterId,
    // "cashier_id": cashierId,
    "customer_paid_amount": "$customPaidAmount",
    "discount_amount": "$discountAmount",
    "discount_comment": "",
    "discount_percent": "$discountPercent",
    "payment_type": paymentType.name,
  };
}
