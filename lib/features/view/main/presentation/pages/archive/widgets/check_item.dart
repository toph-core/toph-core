import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';

class CheckItem extends StatelessWidget {
  const CheckItem({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: context.radius.buttonLg,
        color: context.colors.bgTritary,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                "#1025",
                style: context.textStyles.bold20.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text("Naqd", style: context.textStyles.bodyMd),
            ],
          ),
          Row(
            children: [
              Text("Stol 04", style: context.textStyles.bodyMd),
              const Spacer(),
              Text(
                105000.formatN,
                style: context.textStyles.bold20.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            spacing: 12,
            children: [
              SvgPicture.asset(
                Assets.icons.icCalendar.path,
                height: 24,
                width: 24,
              ),
              Text(
                "2026.02.05",
                style: context.textStyles.title14.copyWith(fontSize: 16),
              ),
              Text(
                "14:00",
                style: context.textStyles.title14.copyWith(fontSize: 16),
              ),
              Text(
                "3 ta mahsulot",
                style: context.textStyles.title14.copyWith(fontSize: 16),
              ),
            ],
          ),
        ],
      ).paddingAll(16),
    );
  }
}
