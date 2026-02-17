import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/payment_screen_mixin.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';

class PaymentRightSideBar extends StatelessWidget with PaymentScreenMixin {
  PaymentRightSideBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.bgDefault,
          borderRadius: context.radius.card24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Jami to'lov", style: context.textStyles.bodyMd),
            12.hBox,
            Text(
              "80 500",
              style: context.textStyles.bold20.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            16.hBox,
            const Divider(),
            20.hBox,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 87,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: context.radius.buttonLg,
                      color: context.colors.bgTritary,
                      border: Border.all(color: AppColors.ffFB6633, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(Assets.icons.icCash.path),
                        Text(
                          "Naqd",
                          style: context.textStyles.title14.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 87,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: context.radius.buttonLg,
                      color: context.colors.bgTritary,
                      // border: Border.all(color: AppColors.ffFB6633, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(Assets.icons.icCard.path),
                        Text(
                          "Karta",
                          style: context.textStyles.title14.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 87,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: context.radius.buttonLg,
                      color: context.colors.bgTritary,
                      // border: Border.all(color: AppColors.ffFB6633, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(Assets.icons.icQr.path),
                        Text(
                          "QR",
                          style: context.textStyles.title14.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            20.hBox,
            Text("Berilayotgan summa", style: context.textStyles.bodySm),
            8.hBox,
            SizedBox(
              width: context.w,
              height: 60,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: context.radius.buttonLg,
                  color: context.colors.bgTritary,
                ),
                child: Center(
                  child: Text(
                    "100 000 so'm",
                    style: context.textStyles.bold20.copyWith(
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
                mainAxisExtent: 56,
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
            16.hBox,
            const Spacer(),
            SizedBox(
              width: context.w,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.bgDefault,
                  border: const Border.symmetric(
                    vertical: BorderSide(
                      color: AppColors.ffC9C9C9,
                      width: 0.33,
                    ),
                  ),
                  // boxShadow: [
                  //   BoxShadow(
                  //     color: AppColors.black.newWithOpacity(.04),
                  //     offset: const Offset(0, -4),
                  //     spreadRadius: 12,
                  //   ),
                  // ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          "Qaytim",
                          style: context.textStyles.bold16.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "19 500 so'm",
                          style: context.textStyles.bold20.copyWith(
                            color: AppColors.ff13AF1B,
                          ),
                        ),
                      ],
                    ),
                    16.hBox,
                    Row(
                      children: [
                        SizedBox(
                          width: 84,
                          height: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.colors.bgTritary,
                              borderRadius: context.radius.buttonLg,
                            ),
                            child: SvgPicture.asset(
                              Assets.icons.icPrinter.path,
                            ).paddingSymmetric(vertical: 15),
                          ),
                        ),
                        12.wBox,
                        Expanded(
                          child: SizedBox(
                            width: context.w,
                            height: 56,
                            child: CustomHoverEffectWidget(
                              onTap: () {},
                              bgColor: context.colors.bgBrand,
                              borderRadius: context.radius.buttonLg,
                              child: Center(
                                child: Text(
                                  "Tasdiqlash",
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
            ),
          ],
        ).paddingAll(16),
      ),
    );
  }
}
