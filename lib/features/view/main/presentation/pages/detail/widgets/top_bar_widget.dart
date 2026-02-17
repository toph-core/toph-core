import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/detail_tab_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/leave_from_detail_screen_dialog.dart';

class TopBarWidget extends StatelessWidget {
  final CafeTableModel? cafeTable;
  final ValueNotifier<bool> showKeyboard;
  final TextEditingController textEditingController;
  const TopBarWidget({
    super.key,
   this.cafeTable,
    required this.showKeyboard,
    required this.textEditingController,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bgDefault,
        borderRadius: context.radius.card24,
      ),
      child: Column(
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              BlocBuilder<DetailCubit, DetailState>(
                builder: (context, state) {
                  return CustomHoverEffectWidget(
                    bgColor: context.colors.bgSecondary,
                    onTap: state.selectedGoods.isNotEmpty
                        ? () async {
                            await showDialog(
                              context: context,
                              builder: (context) =>
                                  const LeaveFromDetailScreenDialog(),
                            ).then(
                              (value) => value != null && value is bool && value
                                  ? Navigator.pop(context)
                                  : () {},
                            );
                          }
                        : () => Navigator.pop(context),
                    borderRadius: context.radius.buttonLg,
                    child: SvgPicture.asset(
                      AppIcons.icArrowLeft,
                    ).paddingAll(14),
                  );
                },
              ),
              if(cafeTable != null)
                Text(
                '${cafeTable!.number}-stol',
                style: context.textStyles.headingSm,
              ),
              Expanded(
                child: CustomTextField(
                  hintText: "Taom nomi bilan qidirish",
                  textInputType: TextInputType.webSearch,
                  onTap: () => showKeyboard.value = true,
                  suffixIcon: SvgPicture.asset(AppIcons.icSearch),
                  textEditingController: textEditingController,
                ),
              ),
            ],
          ),
          const DetailTabFilter(),
        ],
      ).paddingAll(16),
    );
  }
}
