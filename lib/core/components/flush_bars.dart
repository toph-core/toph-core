import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:flutter/material.dart';

void showErrorMessage(BuildContext bc, String error, {int duration = 3}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AnimatedSnackBar.material(
      error,
      type: AnimatedSnackBarType.error,
      duration: const Duration(seconds: 5),
      borderRadius: BorderRadius.circular(10),
      mobilePositionSettings: const MobilePositionSettings(
        topOnAppearance: 100,
      ),
      animationDuration: const Duration(milliseconds: 600),
      desktopSnackBarPosition: DesktopSnackBarPosition.topRight,
    ).show(bc);
  });
}

void showSuccessMessage(BuildContext bc, String success, {int duration = 3}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AnimatedSnackBar.material(
      success,
      type: AnimatedSnackBarType.success,
      duration: const Duration(seconds: 5),
      mobilePositionSettings: const MobilePositionSettings(
        topOnAppearance: 100,
      ),
      borderRadius: BorderRadius.circular(10),
      animationDuration: const Duration(milliseconds: 600),
      mobileSnackBarPosition: MobileSnackBarPosition.top,
      desktopSnackBarPosition: DesktopSnackBarPosition.topRight,
    ).show(bc);
  });
}

void showInfoMessage(BuildContext bc, String info, {int duration = 3}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AnimatedSnackBar.material(
      info,
      type: AnimatedSnackBarType.info,
      duration: const Duration(seconds: 3),
      mobilePositionSettings: const MobilePositionSettings(
        topOnAppearance: 100,
      ),
      borderRadius: BorderRadius.circular(10),
      animationDuration: const Duration(milliseconds: 600),
      mobileSnackBarPosition: MobileSnackBarPosition.top,
      desktopSnackBarPosition: DesktopSnackBarPosition.topRight,
    ).show(bc);
  });
}
