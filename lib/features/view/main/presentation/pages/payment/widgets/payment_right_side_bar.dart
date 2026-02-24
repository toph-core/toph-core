import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';
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
        child: BlocBuilder<PaymentBloc, PaymentState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Jami to'lov", style: context.textStyles.bodyMd),
                8.hBox,
                Text(
                  "80 500",
                  style: context.textStyles.bold24.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                16.hBox,
                const Divider(),
                20.hBox,
                LayoutBuilder(
                  builder: (context, constrants) {
                    return Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.read<PaymentBloc>().add(
                            const PaymentEvent.updatePaymentType(
                              paymentType: PaymentType.cash,
                            ),
                          ),
                          child: SizedBox(
                            width: (constrants.maxWidth - 24) * 0.33,
                            height: ((constrants.maxWidth - 24) * 0.33) * 0.6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: context.radius.buttonLg,
                                color: context.colors.bgTritary,
                                border: state.paymentType == PaymentType.cash
                                    ? Border.all(
                                        color: AppColors.ffFB6633,
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    Assets.icons.icCash.path,
                                    height: 24,
                                    width: 24,
                                  ),
                                  Text(
                                    "Naqd",
                                    style: context.textStyles.title14.copyWith(
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        12.wBox,
                        GestureDetector(
                          onTap: () => context.read<PaymentBloc>().add(
                            const PaymentEvent.updatePaymentType(
                              paymentType: PaymentType.card,
                            ),
                          ),
                          child: SizedBox(
                            width: (constrants.maxWidth - 24) * 0.33,
                            height: ((constrants.maxWidth - 24) * 0.33) * 0.6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: context.radius.buttonLg,
                                color: context.colors.bgTritary,
                                border: state.paymentType == PaymentType.card
                                    ? Border.all(
                                        color: AppColors.ffFB6633,
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    Assets.icons.icCard.path,
                                    height: 24,
                                    width: 24,
                                  ),
                                  Text(
                                    "Karta",
                                    style: context.textStyles.title14.copyWith(
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        12.wBox,
                        GestureDetector(
                          onTap: () => context.read<PaymentBloc>().add(
                            const PaymentEvent.updatePaymentType(
                              paymentType: PaymentType.qr,
                            ),
                          ),
                          child: SizedBox(
                            width: (constrants.maxWidth - 24) * 0.33,
                            height: ((constrants.maxWidth - 24) * 0.33) * 0.6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: context.radius.buttonLg,
                                color: context.colors.bgTritary,
                                border: state.paymentType == PaymentType.qr
                                    ? Border.all(
                                        color: AppColors.ffFB6633,
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    Assets.icons.icQr.path,
                                    height: 24,
                                    width: 24,
                                  ),
                                  Text(
                                    "QR",
                                    style: context.textStyles.title14.copyWith(
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (state.paymentType == PaymentType.cash)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        20.hBox,
                        Text(
                          "Berilayotgan summa",
                          style: context.textStyles.bodySm,
                        ),
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
                                "${state.enterSum} so'm",
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
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
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
                        16.hBox,
                        const Spacer(),
                      ],
                    ),
                  ),
                if (state.paymentType == PaymentType.card)
                  Expanded(
                    child: Center(
                      child: Text(
                        "Mijoz to’lovni karta orqali amalga oshirganini tasdiqlang",
                        style: context.textStyles.bodyMd,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                if (state.paymentType == PaymentType.qr)
                  Expanded(
                    child: Center(
                      child: Text(
                        "Mijoz to’lovni qr kodni skaner qilib amalga oshirganini tasdiqlang",
                        style: context.textStyles.bodyMd,
                        textAlign: TextAlign.center,
                      ),
                    ).paddingSymmetric(horizontal: 20),
                  ),
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
            );
          },
        ).paddingAll(16),
      ),
    );
  }
}
