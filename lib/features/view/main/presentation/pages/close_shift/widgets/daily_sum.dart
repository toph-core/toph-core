import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';

final List<String> keyboardKeys = [
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "⌫",
  "0",
  "00",
];

class DailySum extends StatelessWidget {
  const DailySum({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Kassadagi summa",
              style: context.textStyles.bold24.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            16.hBox,
            const Divider(),
            23.hBox,
            Text(
              "Kassadagi summani kiriting",
              style: context.textStyles.bodyMd,
            ),
            8.hBox,
            SizedBox(
              width: context.w,
              height: 60,
              child: CustomHoverEffectWidget(
                onTap: () {},
                borderRadius: context.radius.card,
                child: Center(
                  child: Text(
                    100000.formatN,
                    style: context.textStyles.bold24.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            16.hBox,
            GridView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 70,
              ),
              itemBuilder: (context, index) => DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.bgTritary,
                  borderRadius: context.radius.buttonLg,
                ),
                child: Center(
                  child: Text(
                    keyboardKeys[index],
                    style: context.textStyles.headingMd,
                  ),
                ),
              ),
              itemCount: keyboardKeys.length,
            ),
          ],
        ).paddingAll(16),
        SizedBox(
          width: context.w,
          height: 88,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.bgDefault,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.newWithOpacity(.04),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: CustomHoverEffectWidget(
              onTap: () {},
              bgColor: context.colors.bgBrand,
              borderRadius: context.radius.card,
              child: Center(
                child: Text(
                  "Tasdiqlash",
                  style: context.textStyles.bold20.copyWith(
                    fontSize: 22,
                    color: context.colors.textOnBrand,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ).paddingAll(16),
          ),
        ),
      ],
    );
  }
}
