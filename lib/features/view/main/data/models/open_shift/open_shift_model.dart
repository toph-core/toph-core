import 'package:freezed_annotation/freezed_annotation.dart';

part 'open_shift_model.freezed.dart';

@freezed
class OpenShiftModel with _$OpenShiftModel {
  const factory OpenShiftModel({
    @Default('') String cashRegisterId,
    @Default('') String cashierId,
    @Default(0) int openCardSum,
    @Default(0) int openCashSum,
  }) = _OpenShiftModel;

  const OpenShiftModel._();

//   Map<String, dynamic> request() => {
//   "cash_register_id": cashRegisterId,
//   "cashier_id": "7fb82f74-3e43-4a51-8a41-a7f871c25f51",
//   "opening_card": "0.00",
//   "opening_cash": "0.00"
// };
}
