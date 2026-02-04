import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/logout_dialog.dart';

class MainHeader extends StatelessWidget {
  const MainHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.bgDefault,
          borderRadius: .circular(24),
        ),
        child: Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  'Bosh sahifa',
                  style: TextStyle(
                    color: Color(0xFF7B7B7B),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  'Stol holatlari',
                  style: TextStyle(
                    color: Color(0xFF2D2D2D),
                    fontSize: 20,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Xodim',
                  textAlign: .right,
                  style: TextStyle(
                    color: Color(0xFF7B7B7B),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  'Admin',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Color(0xFF2D2D2D),
                    fontSize: 20,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SvgPicture.asset(AppIcons.icBell),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SvgPicture.asset(AppIcons.icArchive),
                ),
                CustomHoverEffectWidget(
                  onTap: () {},
                  // padding: const .symmetric(horizontal: 20, vertical: 18.50),
                  bgColor: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(16),

                  child: const Text(
                    'Smenani yopish',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ).paddingSymmetric(horizontal: 20, vertical: 18.50),
                ),
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return const LogoutDialog();
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x19DB1F1F),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Chiqish',
                          style: TextStyle(
                            color: Color(0xFFDB2020),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.logout, size: 24, color: Color(0xFFDB2020)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
