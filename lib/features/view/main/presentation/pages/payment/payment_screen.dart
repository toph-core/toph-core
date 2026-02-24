import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/top_bar_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_right_side_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_top_bar.dart';
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bgTritary,
      body: BlocProvider(
        create: (context) => inject<PaymentBloc>(),
        child: Row(
          spacing: 16,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                spacing: 12,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PaymentTopBar(),
                  16.hBox,
                  SizedBox(
                    width: context.w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colors.bgDefault,
                        borderRadius: context.radius.card24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "% Chegirma",
                            style: context.textStyles.bold20.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                flex: 3,
                                child: CustomTextField(
                                  hintText: "",
                                  style: context.textStyles.semibold20.copyWith(fontWeight: FontWeight.w500),
                                  textInputType: TextInputType.text,
                                  textEditingController: TextEditingController(
                                    text: "0 so'm",
                                  ),
                                ),
                              ),
                              16.wBox,
                              SizedBox(
                                height: 52,
                                width: 143,
                                child: CustomHoverEffectWidget(
                                  onTap: () {},
                                  bgColor: AppColors.ffFF6900.newWithOpacity(
                                    .15,
                                  ),
                                  borderRadius: context.radius.buttonLg,
                                  child: Center(
                                    child: Text(
                                      "Foiz",
                                      style: context.textStyles.bold16.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.ffFB6633,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              8.wBox,
                              SizedBox(
                                width: 143,
                                height: 52,
                                child: CustomHoverEffectWidget(
                                  onTap: () {},
                                  bgColor: AppColors.ffFB6633,
                                  borderRadius: context.radius.buttonLg,
                                  child: Center(
                                    child: Text(
                                      "Summa",
                                      style: context.textStyles.bold16.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ).paddingAll(16),
                    ),
                  ),
                  16.hBox,
                  SizedBox(
                    width: context.w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colors.bgDefault,
                        borderRadius: context.radius.card24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Buyurtma tafsilotlari",
                            style: context.textStyles.bold20.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          16.hBox,
                          Row(
                            children: [
                              Text(
                                "Gamburger",
                                style: context.textStyles.bodyMd,
                              ),
                              const Spacer(),
                              Text(
                                "60 000 so'm",
                                style: context.textStyles.bold16.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          12.hBox,
                          Row(
                            children: [
                              Text(
                                "2x Lavash",
                                style: context.textStyles.bodyMd,
                              ),
                              const Spacer(),
                              Text(
                                "160 000 so'm",
                                style: context.textStyles.bold16.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          12.hBox,
                          const Divider(),
                          Row(
                            children: [
                              Text("Jami", style: context.textStyles.bodyMd),
                              const Spacer(),
                              Text(
                                "230 000 so'm",
                                style: context.textStyles.bold16.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ).paddingOnly(bottom: 12),
                          Row(
                            children: [
                              Text(
                                "Xizmat haqqi (5%)",
                                style: context.textStyles.bodyMd,
                              ),
                              const Spacer(),
                              Text(
                                "12000",
                                style: context.textStyles.bold16.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ).paddingOnly(bottom: 12),
                          Row(
                            children: [
                              Text(
                                "Soliq (5%)",
                                style: context.textStyles.bodyMd,
                              ),
                              const Spacer(),
                              Text(
                                "12 000 so'm",
                                style: context.textStyles.bold16.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ).paddingOnly(bottom: 12),
                          Row(
                            children: [
                              Text(
                                "Chegirma",
                                style: context.textStyles.bodyMd,
                              ),
                              const Spacer(),
                              Text(
                                "8 000 so'm",
                                style: context.textStyles.bold16.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.c13AF1B,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ).paddingAll(16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 1, child: PaymentRightSideBar()),
          ],
        ),
      ).paddingAll(32),
    );
  }
}
