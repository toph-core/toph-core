import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/logout_dialog.dart';

class MainHeader extends StatelessWidget {
  const MainHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.bgDefault,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                textAlign: TextAlign.right,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              CustomHoverEffectWidget(
                onTap: () {},
                borderRadius: context.radius.card,
                child: SvgPicture.asset(AppIcons.icBell).paddingAll(16),
              ),
              CustomHoverEffectWidget(
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.archiveScreen),
                borderRadius: context.radius.card,
                child: SvgPicture.asset(AppIcons.icArchive).paddingAll(16),
              ),
              CustomHoverEffectWidget(
                onTap: () {
                  context.read<AuthCubit>().logoutFromApp(
                    () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRoutes.loginScreen,
                      (route) => false,
                    ),
                  );
                  // showDialog(
                  //   context: context,
                  //   builder: (context) {
                  //     return const LogoutDialog(
                  //       routeName: AppRoutes.loginScreen,
                  //     );
                  //   },
                  // );
                },
                bgColor: const Color(0xFF2D2D2D),
                borderRadius: context.radius.card,
                child: Center(
                  child: const Text(
                    'Smenani yopish',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ).paddingSymmetric(horizontal: 20, vertical: 12),
                ),
              ),
              CustomHoverEffectWidget(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return const LogoutDialog(
                        routeName: AppRoutes.loginPinScreen,
                      );
                    },
                  );
                },
                bgColor: const Color(0x19DB1F1F),
                borderRadius: context.radius.card,
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
                ).paddingSymmetric(horizontal: 20, vertical: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
