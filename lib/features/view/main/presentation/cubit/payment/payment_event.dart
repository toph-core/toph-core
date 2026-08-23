part of 'payment_bloc.dart';

@freezed
class PaymentEvent with _$PaymentEvent {
  const factory PaymentEvent.started({String? tableId,String? orderId,}) = _Started;
  const factory PaymentEvent.updateEnterSum({required String symbol}) =
      _UpdateEnterSum;
  const factory PaymentEvent.getDetail() = _GetDetail;

  /// Fired whenever `OrdersRepository.watchOrderDetail`'s subscription
  /// (started by `_onGetDetail`) emits — the reactive read side of §4/V6,
  /// routed through an event per the same BLoC-pattern rule
  /// `itemTimestampsLoaded` below already follows (emit only from inside a
  /// handler, never directly off a raw stream callback).
  const factory PaymentEvent.detailUpdated({ArchiveDetailModel? detail}) =
      _DetailUpdated;
  const factory PaymentEvent.payment() = _Payment;
  const factory PaymentEvent.updateDiscountType({
    required DiscountType dicountType,
  }) = _DiscountType;
  const factory PaymentEvent.updateDiscountAmount({required String amount}) =
      _UpdateDiscountAmount;
  const factory PaymentEvent.updatePaymentType({
    required PaymentType paymentType,
  }) = _UpdatePaymentType;

  const factory PaymentEvent.upadeHourPrice({required double hourPrice,}) =
      _UpdateHourPrice;

  const factory PaymentEvent.updateApplyService({required bool applyService}) =
      _UpdateApplyService;
}
