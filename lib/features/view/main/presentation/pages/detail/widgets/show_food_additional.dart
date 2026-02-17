import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class ShowFoodAdditional extends StatelessWidget {
  final List<FoodAdditionalModel> additionals;
  final GoodsModel goods;
  const ShowFoodAdditional({
    super.key,
    required this.additionals,
    required this.goods,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        borderRadius: context.radius.card20,
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(20),
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    goods.name,
                    style: context.textStyles.bold20.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "Jami:",
                    style: context.textStyles.title14.copyWith(
                      fontSize: 16,
                      color: context.colors.iconSecondary,
                    ),
                  ),
                  Text(
                    num.parse(goods.price).formatNWithoutS,
                    style: context.textStyles.semibold20.copyWith(
                      color: AppColors.ffFB6633,
                    ),
                  ),
                ],
              ),
              16.hBox,
              ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  ValueNotifier<bool> selected = ValueNotifier<bool>(
                    additionals[index].selected,
                  );
                  return ValueListenableBuilder(
                    valueListenable: selected,
                    builder: (context, value, child) => SizedBox(
                      width: context.w,
                      height: 57,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.bgTritary,
                          borderRadius: context.radius.buttonLg,
                        ),
                        child: Row(
                          children: [
                            Text(
                              additionals[index].title,
                              style: context.textStyles.bodyLg.copyWith(
                                fontSize: 16,
                                color: value
                                    ? context.textStyles.displayXl.color
                                    : context.textStyles.bodyLg.color,
                              ),
                            ),
                            const Spacer(),
                            if (additionals[index].price > 0)
                              Text(
                                "+${additionals[index].price.formatN}",
                                style: context.textStyles.title14.copyWith(
                                  fontSize: 13,
                                  color: AppColors.ff1ECA27,
                                ),
                              ),
                            Material(
                              child: Checkbox(
                                value: value,
                                onChanged: (value) {
                                  if (value != null) {
                                    selected.value = value;
                                    additionals[index].selected = value;
                                  }
                                },
                              ),
                            ),
                          ],
                        ).paddingSymmetric(horizontal: 16),
                      ),
                    ),
                  );
                },
                separatorBuilder: (context, index) => 12.hBox,
                itemCount: additionals.length,
              ),
              24.hBox,
              Text(
                "Maxsus izoh",
                style: context.textStyles.semibold20.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              16.hBox,
              const CustomTextField(
                hintText: "Izoh uchun",
                textInputType: TextInputType.text,
                maxLines: 3,
              ),
              24.hBox,
              SizedBox(
                width: context.w,
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: CustomHoverEffectWidget(
                        onTap: () => Navigator.pop(context),
                        borderRadius: context.radius.buttonLg,
                        child: Center(child: Text(S.current.strCancel)),
                      ),
                    ),
                    8.wBox,
                    Expanded(
                      child: CustomHoverEffectWidget(
                        onTap: () => Navigator.pop(context,additionals.where((v) => v.selected).toList()),
                        borderRadius: context.radius.buttonLg,
                        bgColor: context.colors.buttonBrand,
                        child: Center(
                          child: Text(
                            S.current.strAdd,
                            style: context.textStyles.bold16.copyWith(
                              fontWeight: FontWeight.w500,
                              color: context.colors.textOnBrand,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
