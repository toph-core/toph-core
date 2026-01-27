import 'dart:io';

import 'package:mary_ai_pos/core/common/custom_empty_widget.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:flutter/material.dart';
import 'package:open_settings_plus/core/open_settings_plus.dart';

class NoInternetScreen extends StatelessWidget {
  const NoInternetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomEmptyWidget(
        iconH: 200,
        icon: AppIcons.icLogo,
        title: S.current.strNoInternetConnection,
        subTitle: S.current.strCheckInternetConnection,
        buttonText: S.current.strRetry,
        onTap: () {
          if (Platform.isAndroid) {
            (OpenSettingsPlus.shared as OpenSettingsPlusAndroid).wifi();
          } else if (Platform.isIOS) {
            (OpenSettingsPlus.shared as OpenSettingsPlusIOS).wifi();
          }
        },
      ),
    );
  }
}
