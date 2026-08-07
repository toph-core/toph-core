import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_log_service.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/core/widgets/app_pincode_dialog.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/login/verify_manager_pincode_usecase.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// Prompts for a PIN and only resolves `true` if it belongs to a
/// manager/admin/superadmin user. The entered PIN is verified against the
/// login-pincode endpoint without touching the currently active session
/// (see `AuthDatasource.verifyPincodeRole`) — falling back to the same
/// offline pincode cache regular PIN login uses if the terminal has no
/// connectivity right now (§11 Phase 6: privileged actions no longer
/// require the terminal to be online).
///
/// Used to gate manager-only actions (cancelling a committed order item,
/// opening/closing a shift) behind the same PIN-entry UI already used
/// elsewhere in the app. [action] identifies which one, purely so this one
/// shared gate can record a meaningful audit entry — every call records
/// exactly once, whether approved or denied, so no call site needs to
/// remember to log anything itself.
Future<bool> requireManagerPincode(
  BuildContext context, {
  required PrivilegedAction action,
  String? subtitle,
}) async {
  final usecase = inject<VerifyManagerPincodeUsecase>();
  final auditLog = inject<PrivilegedActionAuditLogService>();
  final requestedBy = inject<UserBloc>().state.userMOdel;
  // Captured once up front — good enough for an audit record (this doesn't
  // need to track a mid-call connectivity flip), and cheaper than asking
  // the datasource to report back how it actually resolved the pincode.
  final wasOffline = !inject<ConnectivityCubit>().isOnline;

  final confirmed = await AppPincodeDialog.show(
    context,
    title: S.current.strManagerPincodeTitle,
    subtitle: subtitle ?? S.current.strManagerPincodeSubtitle,
    onConfirm: (pin) async {
      final result = await usecase(pin);
      return result.fold(
        (failure) {
          unawaited(auditLog.record(
            action: action,
            approved: false,
            verifiedOffline: wasOffline,
            reason: wasOffline ? 'offline_unverified' : 'verification_failed',
            requestedByUserId: requestedBy?.id,
            requestedByName: requestedBy?.fullName,
          ));
          return false;
        },
        (user) {
          final approved = user.role.isManagerOrAdmin;
          unawaited(auditLog.record(
            action: action,
            approved: approved,
            verifiedOffline: wasOffline,
            reason: approved ? null : 'not_manager',
            approverUserId: user.id,
            approverName: user.fullName,
            requestedByUserId: requestedBy?.id,
            requestedByName: requestedBy?.fullName,
          ));
          return approved;
        },
      );
    },
  );
  return confirmed == true;
}
