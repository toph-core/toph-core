import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/core/widgets/app_pincode_dialog.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/verify_manager_pincode_usecase.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// Prompts for a PIN and only resolves `true` if it belongs to a
/// manager/admin/superadmin user. The entered PIN is verified against the
/// login-pincode endpoint without touching the currently active session
/// (see `AuthDatasource.verifyPincodeRole`).
///
/// Used to gate manager-only actions (cancelling a committed order item,
/// opening/closing a shift) behind the same PIN-entry UI already used
/// elsewhere in the app.
Future<bool> requireManagerPincode(BuildContext context, {String? subtitle}) async {
  final usecase = inject<VerifyManagerPincodeUsecase>();
  final confirmed = await AppPincodeDialog.show(
    context,
    title: S.current.strManagerPincodeTitle,
    subtitle: subtitle ?? S.current.strManagerPincodeSubtitle,
    onConfirm: (pin) async {
      final result = await usecase(pin);
      return result.fold((_) => false, (role) => role.isManagerOrAdmin);
    },
  );
  return confirmed == true;
}
