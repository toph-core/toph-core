import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/w_shift_bottom.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/w_shift_header.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/w_shift_input_sum_container.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/w_shift_time_card.dart';

class CloseShiftScreen extends StatefulWidget {
  const CloseShiftScreen({super.key});

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  late final DateTime enterDate = DateTime.now();
  final List<String> keyboardKeys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'delete',
    '0',
    '00',
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bgTritary,
      body: SafeArea(
        child: BlocBuilder<ShiftBloc, ShiftState>(
          builder: (context, state) {
            return Column(
              children: [
                const WShiftHeader(),
                16.hBox,
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.bgDefault,
                    borderRadius: context.radius.card24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Smena ma’lumotlari",
                        style: context.textStyles.bold24.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      12.hBox,
                      Row(
                        children: [
                          WShiftTimeCard(
                            title: "Ochilish vaqti",
                            value: state.shift == null
                                ? "${enterDate.hour}:${enterDate.minute}"
                                : "${state.shift!.openedAt!.hour}:${state.shift!.openedAt!.minute}",
                          ),
                          12.wBox,
                          WShiftTimeCard(
                            title: "Yopilish vaqti",
                            value:
                                state.shift != null &&
                                    state.shift!.openedAt != null
                                ? state.shift == null
                                      ? "${enterDate.hour}:${enterDate.minute}"
                                      : "${state.shift!.openedAt!.hour}:${state.shift!.openedAt!.minute}"
                                : "--:--",
                          ),
                        ],
                      ),
                    ],
                  ).paddingAll(16),
                ),
                12.hBox,
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.iconOnBrand,
                    borderRadius: context.radius.card24,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: WShiftInputSumContainer(
                              onTap: () => context.read<ShiftBloc>().add(const ShiftEvent.updateSumType(type: ShiftSumType.cash)),
                              selected: state.sum == ShiftSumType.cash,
                              title: "Naqt summani kiriting",
                              value: int.parse(state.cashSum).formatN,
                            ),
                          ),
                          12.wBox,
                          Expanded(
                            child: WShiftInputSumContainer(
                              onTap: () => context.read<ShiftBloc>().add(const ShiftEvent.updateSumType(type: ShiftSumType.card)),
                              selected: state.sum == ShiftSumType.card,
                              title: "Terminal summani kiriting",
                              value: int.parse(state.cardSum).formatN,
                            ),
                          ),
                        ],
                      ),
                      16.hBox,
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              mainAxisExtent: 56,
                            ),
                        itemCount: keyboardKeys.length,
                        itemBuilder: (context, index) {
                          final String key = keyboardKeys[index];
                          return _keyboardKey(context, key, state.sum);
                        },
                      ),
                    ],
                  ).paddingAll(16),
                ),
                const WShiftBottom(),
              ],
            );
          },
        ).paddingAll(32),
      ),
    );
  }

  Widget _keyboardKey(BuildContext context, String key, ShiftSumType type) {
    final bool isDelete = key == 'delete';
    return CustomHoverEffectWidget(
      onTap: () {
        if(type == ShiftSumType.card){
          context.read<ShiftBloc>().add(ShiftEvent.updateCardSum(value: key));
        }else{
          context.read<ShiftBloc>().add(ShiftEvent.updateCashSum(value: key));
        }
      },
      bgColor: isDelete
          ? AppColors.ffDB2020.withOpacity(.10)
          : context.colors.bgSecondary,
      borderRadius: context.radius.buttonLg,
      child: Center(
        child: isDelete
            ? const Icon(
                Icons.backspace_outlined,
                color: AppColors.ffDB2020,
                size: 26,
              )
            : Text(
                key,
                style: context.textStyles.headingMd.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
      ),
    );
  }
}
