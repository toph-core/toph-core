import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/detail_tab_widget.dart';

class TopBarWidget extends StatelessWidget {
  final CafeTableModel cafeTable;
  const TopBarWidget({super.key, required this.cafeTable});

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
              CustomHoverEffectWidget(
                bgColor: context.colors.bgSecondary,
                onTap: () => Navigator.pop(context),
                borderRadius: context.radius.buttonLg,
                child: SvgPicture.asset(AppIcons.icArrowLeft).paddingAll(14),
              ),
              Text(
                '${cafeTable.number}-stol',
                style: context.textStyles.headingSm,
              ),
              Expanded(
                child: CustomTextField(
                  hintText: "Taom nomi bilan qidirish",
                  textInputType: .webSearch,
                  suffixIcon: SvgPicture.asset(AppIcons.icSearch),
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
