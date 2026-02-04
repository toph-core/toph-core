import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_request_model.freezed.dart';
part 'login_request_model.g.dart';

@freezed
class LoginRequestModel with _$LoginRequestModel {
  const factory LoginRequestModel({
    @JsonKey(name: 'brand_id') required String brandId,
    // @JsonKey(name: 'fcm_token') required String fcmToken,
    required String password,
    required String pincode,
  }) = _LoginRequestModel;

  factory LoginRequestModel.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestModelFromJson(json);
}
