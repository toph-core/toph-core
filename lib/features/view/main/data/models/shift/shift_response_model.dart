import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';

part 'shift_response_model.freezed.dart';
part 'shift_response_model.g.dart';

@freezed
class ShiftResponseModel with _$ShiftResponseModel {
  const factory ShiftResponseModel({
    @Default('') String id,
    @JsonKey(name: "branch_id") @Default('') String branchId,
    @JsonKey(name: "cash_register_id") @Default('') String cashRegisterId,
    @JsonKey(name: "cashier_id") @Default('') String cashierId,
    @JsonKey(name: "opened_at") DateTime? openedAt,
    @JsonKey(name: "opening_cash",fromJson: int.parse) @Default(0) int openingCash,
    @JsonKey(name: "opening_card",fromJson: int.parse) @Default(0) int openinCard,
    @Default(CashStatus.none) CashStatus status,
    @JsonKey(name: "created_at") DateTime? createdAt,
    @JsonKey(name: "updated_at") DateTime? updatedAt,
  }) = _ShiftResponseModel;

  const ShiftResponseModel._();

  factory ShiftResponseModel.fromJson(Map<String, dynamic> json) =>
      _$ShiftResponseModelFromJson(json);
}
