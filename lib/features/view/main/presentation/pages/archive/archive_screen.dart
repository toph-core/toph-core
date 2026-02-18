import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/archive/widgets/archive_right_sider_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/archive/widgets/check_item.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/top_bar_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/archive_top_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_right_side_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_top_bar.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bgTritary,
      // body: Expanded(
      //   child: Scrollbar(
      //     child: GridView.builder(
      //       // padding: const EdgeInsets.all(16),
      //       physics: const BouncingScrollPhysics(),
      //       gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      //         crossAxisCount: 2,
      //         crossAxisSpacing: 12,
      //         mainAxisSpacing: 12,
      //         mainAxisExtent: 130,
      //       ),
      //       itemBuilder: (context, index) => const CheckItem(),
      //       itemCount: 40,
      //     ),
      //   ),
      // ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ArchiveTopBar(),
                16.hBox,
                // Expanded(
                //   child: GridView.builder(
                //     padding: const EdgeInsets.all(16),
                //     physics: const ScrollPhysics(),
                //     gridDelegate:
                //         const SliverGridDelegateWithFixedCrossAxisCount(
                //           crossAxisCount: 2,
                //           crossAxisSpacing: 12,
                //           mainAxisSpacing: 12,
                //           mainAxisExtent: 130,
                //         ),
                //     itemBuilder: (context, index) => const CheckItem(),
                //     itemCount: 20,
                //   ),
                // ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    // clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: context.colors.bgDefault,
                      borderRadius: context.radius.card24,
                    ),
                    child: GridView.builder(
                      shrinkWrap: false,
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 130,
                          ),
                      itemBuilder: (context, index) => const CheckItem(),
                      itemCount: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          16.wBox,
          const Expanded(flex: 2, child: ArchiveRightSiderBar()),
        ],
      ).paddingAll(32),
    );
  }
}
