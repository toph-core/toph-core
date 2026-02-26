part of 'payment_bloc.dart';

@freezed
class PaymentEvent with _$PaymentEvent {
  const factory PaymentEvent.started({required String tableId}) = _Started;
  const factory PaymentEvent.updateEnterSum({required String symbol}) =
      _UpdateEnterSum;
  const factory PaymentEvent.getDetail() = _GetDetail;
  const factory PaymentEvent.payment() = _Payment;
  const factory PaymentEvent.updateDiscountType({
    required DiscountType dicountType,
  }) = _DiscountType;
  const factory PaymentEvent.updateDiscountAmount({required String amount}) =
      _UpdateDiscountAmount;
  const factory PaymentEvent.updatePaymentType({
    required PaymentType paymentType,
  }) = _UpdatePaymentType;
}
