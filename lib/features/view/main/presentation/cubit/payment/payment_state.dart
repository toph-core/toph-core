part of 'payment_bloc.dart';

@freezed
class PaymentState with _$PaymentState {
  const factory PaymentState({
    @Default(Status.UNKNOWN) Status status,
    @Default(Status.UNKNOWN) Status detailStatus,
    ArchiveDetailEntity? detail,
    @Default('') String tableId,
    TextEditingController? textController,
    @Default(PaymentType.cash) PaymentType paymentType,
    @Default('') String enterSum,
    Failure? failure,
  }) = _PaymentState;

}
