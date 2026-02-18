import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';

class ArchiveTopBar extends StatelessWidget {
  const ArchiveTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bgDefault,
        borderRadius: context.radius.card24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomHoverEffectWidget(
                bgColor: context.colors.bgSecondary,
                onTap: () => Navigator.pop(context),
                borderRadius: context.radius.buttonLg,
                child: SvgPicture.asset(AppIcons.icArrowLeft).paddingAll(14),
              ),
              12.wBox,

              Text(
                "Arxiv",
                style: context.textStyles.bold20.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              67.wBox,
              Expanded(
                child: SizedBox(
                  width: context.w,
                  height: 52,
                  child: CustomTextField(
                    hintText: "Chek raqami yoki stol raqami bo'yicha qidirish",
                    textInputType: TextInputType.text,
                    suffixIcon: SvgPicture.asset(Assets.icons.icSearch.path),
                  ),
                ),
              ),
            ],
          ),
          16.hBox,
          Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CustomHoverEffectWidget(
                  onTap: () {},
                  borderRadius: context.radius.buttonLg,
                  child: SvgPicture.asset(
                    Assets.icons.icCalendar.path,
                  ).paddingAll(12),
                ),
              ),
              8.wBox,
              SizedBox(
                height: 52,
                child: CustomHoverEffectWidget(
                  onTap: () {},
                  borderRadius: context.radius.buttonLg,
                  child: Center(
                    child: Text(
                      "Hammasi",
                      style: context.textStyles.bold16.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ).paddingSymmetric(horizontal: 20),
                ),
              ),
              8.wBox,
              SizedBox(
                height: 52,
                child: CustomHoverEffectWidget(
                  onTap: () {},
                  bgColor: context.colors.textOnBrandDark,
                  borderRadius: context.radius.buttonLg,
                  child: Center(
                    child: Text(
                      "Bugun",
                      style: context.textStyles.bold16.copyWith(
                        fontWeight: FontWeight.w500,
                        color: context.colors.textOnBrand,
                      ),
                    ),
                  ).paddingSymmetric(horizontal: 20),
                ),
              ),
              8.wBox,
              SizedBox(
                height: 52,
                child: CustomHoverEffectWidget(
                  onTap: () {},
                  borderRadius: context.radius.buttonLg,
                  child: Center(
                    child: Text(
                      "Hafta",
                      style: context.textStyles.bold16.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ).paddingSymmetric(horizontal: 20),
                ),
              ),
              8.wBox,
              SizedBox(
                height: 52,
                child: CustomHoverEffectWidget(
                  onTap: () {},
                  borderRadius: context.radius.buttonLg,
                  child: Center(
                    child: Text(
                      "Oy",
                      style: context.textStyles.bold16.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ).paddingSymmetric(horizontal: 20),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Jami:",style: context.textStyles.bodyMd,),
                  Text("16 ta chek",style: context.textStyles.bold20.copyWith(fontWeight: FontWeight.w500,color: context.colors.bgBrand),)
                ],
              ),
            ],
          ),
        ],
      ).paddingAll(16),
    );
  }
}
