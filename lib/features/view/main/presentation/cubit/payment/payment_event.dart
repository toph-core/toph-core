part of 'payment_bloc.dart';

@freezed
class PaymentEvent with _$PaymentEvent {
  const factory PaymentEvent.started({required String tableId}) = _Started;
  const factory PaymentEvent.getDetail() = _GetDetail;
  const factory PaymentEvent.updatePaymentType({
    required PaymentType paymentType,
  }) = _UpdatePaymentType;
}
