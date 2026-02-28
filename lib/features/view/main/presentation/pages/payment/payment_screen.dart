import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';

import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';

import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_right_side_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_top_bar.dart';
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';
import 'package:mary_ai_pos/core/utils/app_formatter.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  // late final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
  late final String tableId =
      ModalRoute.of(context)?.settings.arguments as String? ?? '';
  late final ValueNotifier<bool> keyboardOpen = ValueNotifier<bool>(false);
  late final TextEditingController discountAmountController =
      TextEditingController(text: "0");

  @override
  void dispose() {
    discountAmountController.dispose();
    super.dispose();
  }

  Widget _itemInfo(
    BuildContext context,
    String title,
    int sum, [
    Color? textColor,
  ]) {
    return Row(
      children: [
        Text(title, style: context.textStyles.bodyMd),
        const Spacer(),
        Text(
          sum.formatN,
          style: context.textStyles.bold16.copyWith(
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bgTritary,
      body: BlocProvider(
        create: (context) =>
            inject<PaymentBloc>()..add(PaymentEvent.started(tableId: tableId)),
        child: BlocBuilder<PaymentBloc, PaymentState>(
          builder: (context, state) {
            if (state.detail == null && state.status == Status.LOADING) {
              return Center(
                child: CircularProgressIndicator.adaptive(
                  backgroundColor: context.colors.bgBrand,
                ),
              );
            }

            if (state.detail == null) {
              return const Center(child: Text("To'lov ma'lumotlari topilmadi"));
            }

            return GestureDetector(
              onTap: () {
                if (keyboardOpen.value) {
                  keyboardOpen.value = false;
                }
              },
              child: ValueListenableBuilder(
                valueListenable: keyboardOpen,
                builder: (context, value, child) {
                  return Stack(
                    children: [
                      Row(
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "% Chegirma",
                                          style: context.textStyles.bold20
                                              .copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: CustomTextField(
                                                hintText: "",
                                                style: context
                                                    .textStyles
                                                    .semibold20
                                                    .copyWith(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                textInputType:
                                                    TextInputType.number,
                                                formatter: [
                                                  PriceFormatter(
                                                    additional:
                                                        state.discountType ==
                                                            DiscountType.money
                                                        ? "so'm"
                                                        : "%",
                                                    limit:
                                                        state.discountType ==
                                                            DiscountType.money
                                                        ? state
                                                              .detail!
                                                              .grandTotal
                                                        : null,
                                                  ),
                                                ],
                                                onTap: () =>
                                                    keyboardOpen.value = true,
                                                textEditingController:
                                                    discountAmountController,
                                                onChange: (val) {
                                                  final value = val.replaceAll(
                                                    RegExp(r'\D'),
                                                    '',
                                                  );
                                                  context.read<PaymentBloc>().add(
                                                    PaymentEvent.updateDiscountAmount(
                                                      amount: value,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            16.wBox,
                                            SizedBox(
                                              height: 52,
                                              width: 143,
                                              child: CustomHoverEffectWidget(
                                                onTap: () => context
                                                    .read<PaymentBloc>()
                                                    .add(
                                                      const PaymentEvent.updateDiscountType(
                                                        dicountType:
                                                            DiscountType
                                                                .percent,
                                                      ),
                                                    ),
                                                bgColor:
                                                    state.discountType ==
                                                        DiscountType.percent
                                                    ? context.colors.bgBrand
                                                    : context.colors.bgBrand
                                                          .newWithOpacity(.15),
                                                borderRadius:
                                                    context.radius.buttonLg,
                                                child: Center(
                                                  child: Text(
                                                    "Foiz",
                                                    style: context
                                                        .textStyles
                                                        .bold16
                                                        .copyWith(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color:
                                                              state.discountType ==
                                                                  DiscountType
                                                                      .percent
                                                              ? context
                                                                    .colors
                                                                    .textOnBrand
                                                              : context
                                                                    .colors
                                                                    .bgBrand,
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
                                                onTap: () => context
                                                    .read<PaymentBloc>()
                                                    .add(
                                                      const PaymentEvent.updateDiscountType(
                                                        dicountType:
                                                            DiscountType.money,
                                                      ),
                                                    ),
                                                bgColor:
                                                    state.discountType ==
                                                        DiscountType.money
                                                    ? context.colors.bgBrand
                                                    : context.colors.bgBrand
                                                          .newWithOpacity(.15),
                                                borderRadius:
                                                    context.radius.buttonLg,
                                                child: Center(
                                                  child: Text(
                                                    "Summa",
                                                    style: context
                                                        .textStyles
                                                        .bold16
                                                        .copyWith(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color:
                                                              state.discountType ==
                                                                  DiscountType
                                                                      .money
                                                              ? context
                                                                    .colors
                                                                    .textOnBrand
                                                              : context
                                                                    .colors
                                                                    .bgBrand,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Buyurtma tafsilotlari",
                                          style: context.textStyles.bold20
                                              .copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        16.hBox,
                                        if (state.detail != null)
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: List.generate(
                                              state.detail!.goods.length,
                                              (index) => _itemInfo(
                                                context,
                                                state
                                                            .detail!
                                                            .goods[index]
                                                            .quantity ==
                                                        1
                                                    ? state
                                                          .detail!
                                                          .goods[index]
                                                          .name
                                                    : "${state.detail!.goods[index].quantity}x ${state.detail!.goods[index].name}",
                                                state
                                                    .detail!
                                                    .goods[index]
                                                    .price,
                                              ),
                                            ),
                                          ),
                                        12.hBox,
                                        const Divider(),
                                        _itemInfo(
                                          context,
                                          "Jami",
                                          state.detail!.grandTotal,
                                        ),
                                        12.hBox,
                                        _itemInfo(
                                          context,
                                          "Xizmat haqqi(5%)",
                                          state.detail!.serviceAmount,
                                        ),
                                        12.hBox,
                                        Row(
                                          children: [
                                            Text(
                                              "Chegirma",
                                              style: context.textStyles.bodyMd,
                                            ),
                                            const Spacer(),
                                            Text(
                                              "${int.tryParse(state.discountAmount) != null ? int.parse(state.discountAmount) : ""} ${state.discountType == DiscountType.money ? "so'm" : '%'}",
                                              style: context.textStyles.bold16
                                                  .copyWith(
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
                          Expanded(
                            flex: 1,
                            child: PaymentRightSideBar(detail: state.detail!),
                          ),
                        ],
                      ),
                      if (value)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.colors.bgDefault,
                            ),
                            child: VirtualKeyboard(
                              textController: discountAmountController,
                              type: VirtualKeyboardType.Numeric,
                              fontSize: 24,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ).paddingAll(32),
    );
  }
}
