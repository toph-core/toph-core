import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';

class DailyDataContainer extends StatelessWidget {
  const DailyDataContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Smena ma'lumotlari",
          style: context.textStyles.bold24.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        16.hBox,
        LayoutBuilder(
          builder: (context, constrants) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  height: 92,
                  width: constrants.maxWidth / 3.2,
                  child: CustomHoverEffectWidget(
                    onTap: () {},
                    borderRadius: context.radius.card,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Yoqilgan vat', style: context.textStyles.bodyLg),
                        Text(
                          "08:00",
                          style: context.textStyles.bold20.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ).paddingSymmetric(horizontal: 44),
                  ),
                ),
                SizedBox(
                  height: 92,
                  width: constrants.maxWidth / 3.2,
                  child: CustomHoverEffectWidget(
                    onTap: () {},
                    borderRadius: context.radius.card,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "O'chirilgan vaqt",
                          style: context.textStyles.bodyLg,
                        ),
                        Text(
                          "08:00",
                          style: context.textStyles.bold20.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 92,
                  width: constrants.maxWidth / 3.2,
                  child: CustomHoverEffectWidget(
                    onTap: () {},
                    borderRadius: context.radius.card,
                    bgColor: AppColors.ffF1FAF1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Jami sotuvlar", style: context.textStyles.bodyLg),
                        Text(
                          2459232.formatN,
                          style: context.textStyles.bold20.copyWith(
                            fontWeight: FontWeight.w500,
                            color: context.colors.responseTextColor,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ).paddingAll(16);
  }
}
