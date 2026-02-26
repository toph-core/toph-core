import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';

class SellsInformation extends StatelessWidget {
  const SellsInformation({super.key});

  Widget _sellInformation(
    BuildContext context,
    String title,
    int count, [
    Color? backgroundColor,
    Color? textColor,
  ]) {
    return SizedBox(
      width: context.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor ?? context.colors.bgTritary,
          borderRadius: context.radius.buttonMd,
        ),
        child: Row(
          children: [
            Text(
              title,
              style: context.textStyles.bodyLg.copyWith(color: textColor),
            ),
            const Spacer(),
            Text(
              count.formatN,
              style: context.textStyles.bold20.copyWith(
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ).paddingSymmetric(vertical: 12, horizontal: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Sotuvlar tavsiloti",
          style: context.textStyles.bold24.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        16.hBox,
        _sellInformation(context, "Naqd to'lovlar", 1200000),
        8.hBox,
        _sellInformation(context, "Kartadan to'lovlar", 1100000),
        8.hBox,
        _sellInformation(context, "QR to'lovlar", 150000),
        8.hBox,
        _sellInformation(
          context,
          "Jami buyurtmalar",
          1200000,
          context.colors.informationColor.newWithOpacity(.1),
          context.colors.textBrand,
        ),
      ],
    ).paddingAll(16);
  }
}
