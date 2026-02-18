import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';

class ArchiveRightSiderBar extends StatelessWidget {
  const ArchiveRightSiderBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.w,
      height: context.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.textOnBrand,
          borderRadius: context.radius.card24,
        ),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            SizedBox(
              width: context.w,
              height: 52,
              child: Row(
                children: [
                  Text(
                    80500.formatN,
                    style: context.textStyles.bold20.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 52,
                    child: CustomHoverEffectWidget(
                      onTap: () {},
                      borderRadius: context.radius.buttonMd,
                      bgColor: context.colors.bgBrand,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            Assets.icons.icPrinter.path,
                            color: AppColors.white,
                          ),
                          10.wBox,
                          Text(
                            "Chop etish",
                            style: context.textStyles.title14.copyWith(
                              fontSize: 16,
                              color: context.colors.textOnBrand,
                            ),
                          ),
                        ],
                      ).paddingSymmetric(horizontal: 16),
                    ),
                  ),
                ],
              ),
            ),
            16.hBox,
            SizedBox(
              width: context.w,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: context.radius.buttonLg,
                  color: context.colors.bgTritary,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Buyrutma tafsilotlari",
                      style: context.textStyles.bold20.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    16.hBox,
                    Row(
                      children: [
                        Text("Check raqami:", style: context.textStyles.bodySm),
                        const Spacer(),
                        Text(
                          "#1025",
                          style: context.textStyles.bold16.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    13.hBox,
                    Row(
                      children: [
                        Text("Stol:", style: context.textStyles.bodySm),
                        const Spacer(),
                        Text(
                          "04",
                          style: context.textStyles.bold16.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    13.hBox,
                    Row(
                      children: [
                        Text("Sana:", style: context.textStyles.bodySm),
                        const Spacer(),
                        Text(
                          "2026.02.20",
                          style: context.textStyles.bold16.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    13.hBox,
                    Row(
                      children: [
                        Text("Kassir:", style: context.textStyles.bodySm),
                        const Spacer(),
                        Text(
                          "Admin",
                          style: context.textStyles.bold16.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    13.hBox,
                    Row(
                      children: [
                        Text("To'lov usuli:", style: context.textStyles.bodySm),
                        const Spacer(),
                        Text(
                          "Naqd",
                          style: context.textStyles.bold16.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ).paddingAll(16),
              ),
            ),
            16.hBox,
            Text("Buyurtma tarkibi",style: context.textStyles.bold20.copyWith(fontWeight: FontWeight.w500,),),
            12.hBox,
            Column(
              spacing: 8,
              children: List.generate(3, (index) => SizedBox(
                width: context.w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: context.radius.buttonLg,
                    color: context.colors.bgTritary,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Osh",style: context.textStyles.bold16.copyWith(fontWeight: FontWeight.w500,),),
                          8.hBox,
                          Text("30000 x 2",style: context.textStyles.bodySm,)
                        ],
                      ),
                      Text(56000.formatN,style: context.textStyles.bold16.copyWith(fontWeight: FontWeight.w500,),)
                    ],
                  ).paddingSymmetric(horizontal: 16,vertical: 12),
                ),
              )),
            ),
            16.hBox,
            SizedBox(
              width: context.h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: context.radius.buttonLg,
                  color: context.colors.bgTritary,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Jami:",style: context.textStyles.bodySm,),
                        Text(90000.formatN,style: context.textStyles.bold16.copyWith(fontWeight: FontWeight.w500,),)
                      ],
                    ),
                    12.hBox,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Xizmat to'lovi:",style: context.textStyles.bodySm,),
                        Text(4500.formatN,style: context.textStyles.bold16.copyWith(fontWeight: FontWeight.w500,),)
                      ],
                    ),
                    12.hBox,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Soliq:",style: context.textStyles.bodySm,),
                        Text(10500.formatN,style: context.textStyles.bold16.copyWith(fontWeight: FontWeight.w500,),)
                      ],
                    ),
                  ],
                ).paddingAll(16),
              ),
            )
          ],
        ),
      ),
    );
  }
}
