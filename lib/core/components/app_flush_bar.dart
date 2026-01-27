import 'package:another_flushbar/flushbar.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/utils/size_config.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

void showAppFlushbarMessage(
  BuildContext bc, {
  String? title,
  required String msg,
  FlushbarType type = FlushbarType.normal,
  FlushbarPosition flushbarPosition = FlushbarPosition.TOP,
  int duration = 3,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Flushbar(
      //! title
      title: title,
      titleColor: type.primaryColor,
      titleSize: bc.textStyles.bold14.fontSize,

      //! message
      message: msg,
      messageColor: type.primaryColor,

      //! General
      flushbarPosition: flushbarPosition,
      isDismissible: false,
      backgroundColor: type.bgColor,
      borderRadius: bc.radius.buttonMd,
      duration: Duration(seconds: duration),
      margin: EdgeInsets.symmetric(horizontal: wi(20)).copyWith(
        bottom: flushbarPosition == FlushbarPosition.BOTTOM
            ? customBottomPadding
            : 0,
      ),

      //! actions
      icon: SvgPicture.asset(
        type.icon,
        height: he(24),
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(type.primaryColor, BlendMode.srcIn),
      ),

      mainButton: GestureDetector(
        onTap: () {
          if (Navigator.canPop(bc)) {
            Navigator.pop(bc);
          }
        },
        child: SvgPicture.asset(
          AppIcons.icXMark,
          colorFilter: ColorFilter.mode(
            type.primaryColor.withOpacity(.3),
            BlendMode.srcIn,
          ),
        ).paddingAll(12),
      ),
    ).show(bc);
  });
}

enum FlushbarType {
  normal(
    icon: AppIcons.icInfo,
    bgColor: Color(0xFFF4F4F5),
    primaryColor: Color(0xFF000000),
  ),
  primary(
    icon: AppIcons.icInfo,
    bgColor: Color(0xFFE6F1FE),
    primaryColor: Color(0xFF006FEE),
  ),
  premium(
    icon: AppIcons.icInfo,
    bgColor: Color(0xFFF2EAFA),
    primaryColor: Color(0xFF7828C8),
  ),
  success(
    icon: AppIcons.icTickCircle,
    bgColor: Color(0xFFE8FAF0),
    primaryColor: Color(0xFF17C964),
  ),
  warning(
    icon: AppIcons.icWarning,
    bgColor: Color(0xFFFEFCE8),
    primaryColor: Color(0xFFF5A524),
  ),
  failure(
    icon: AppIcons.icFailure,
    bgColor: Color(0xFFFEE7EF),
    primaryColor: Color(0xFFEB295B),
  );

  final String icon;
  final Color bgColor;
  final Color primaryColor;

  const FlushbarType({
    required this.icon,
    required this.bgColor,
    required this.primaryColor,
  });
}
