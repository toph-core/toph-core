import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';

class PaymentTopBar extends StatelessWidget {
  const PaymentTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bgDefault,
        borderRadius: context.radius.card24,
      ),
      child: Row(
        children: [
          CustomHoverEffectWidget(
            bgColor: context.colors.bgSecondary,
            onTap: () => Navigator.pop(context),
            borderRadius: context.radius.buttonLg,
            child: SvgPicture.asset(AppIcons.icArrowLeft).paddingAll(14),
          ),
          12.wBox,

          Text(
            "To'lov",
            style: context.textStyles.bold20.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ).paddingAll(16),
    );
  }
}
