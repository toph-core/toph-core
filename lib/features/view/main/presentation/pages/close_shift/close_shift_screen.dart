import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/daily_data_container.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/daily_sum.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/sells_information.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';

class CloseShiftScreen extends StatelessWidget {
  const CloseShiftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bgTritary,
      body: Column(
        children: [
          SizedBox(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.bgDefault,
                borderRadius: context.radius.card24,
              ),
              child: Row(
                children: [
                  CustomHoverEffectWidget(
                    bgColor: context.colors.bgTritary,
                    onTap: () => Navigator.pop(context),
                    borderRadius: context.radius.buttonLg,
                    child: SvgPicture.asset(
                      AppIcons.icArrowLeft,
                    ).paddingAll(14),
                  ).paddingAll(16),
                ],
              ),
            ),
          ),
          16.hBox,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.colors.bgDefault,
                            borderRadius: context.radius.card24,
                          ),
                          child: const DailyDataContainer(),
                        ),
                      ),
                      12.hBox,
                      SizedBox(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.colors.bgDefault,
                            borderRadius: context.radius.card24,
                          ),
                          child: const SellsInformation(),
                        ),
                      ),
                      16.hBox,
                      Row(
                        children: [
                          SizedBox(
                            height: 56,
                            child: CustomHoverEffectWidget(
                              onTap: () {},
                              bgColor: context.colors.textOnBrand,
                              borderRadius: context.radius.card,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(Assets.icons.icPrinter.path),
                                  10.wBox,
                                  Text(
                                    "Chop etish",
                                    style: context.textStyles.title14.copyWith(
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ).paddingSymmetric(horizontal: 16),
                            ),
                          ),
                          12.wBox,
                          Expanded(
                            child: SizedBox(
                              width: context.w,
                              height: 56,
                              child: CustomHoverEffectWidget(
                                onTap: () {},
                                bgColor: context.colors.iconBrand,
                                borderRadius: context.radius.card,
                                child: Center(
                                  child: Text(
                                    "Smenani yopish va hisobot yaratish",
                                    style: context.textStyles.bold16.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: context.colors.textOnBrand,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                16.wBox,
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    width: context.w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colors.bgDefault,
                        borderRadius: context.radius.card24,
                      ),
                      child: const DailySum(),
                    ),
                  ),
                ),
              ],
            ).paddingSymmetric(horizontal: 50),
          ),
        ],
      ).paddingAll(32),
    );
  }
}
