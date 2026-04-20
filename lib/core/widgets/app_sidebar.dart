import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/widgets/brand_logo.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/logout_dialog.dart';

class AppSidebar extends StatelessWidget {
  final String activeRoute;
  const AppSidebar({super.key, required this.activeRoute});

  @override
  Widget build(BuildContext context) {
    final role = context.select((UserBloc b) => b.state.userMOdel?.role);
    final canManageMenu = role.canManageMenu;
    final canAccessSettings = role.canAccessSettings;
    final colors = context.colors;
    return Container(
      width: 72,
      color: colors.sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Logo: full wordmark must fit — narrow sidebar, use contain (not cover).
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 64,
              height: 56,
              child: BrandLogo(
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                _NavItem(
                  icon: Icons.grid_view_rounded,
                  label: S.current.strTables,
                  isActive: activeRoute == AppRoutes.mainScreen,
                  onTap: () => _navigate(context, AppRoutes.mainScreen),
                ),
                _NavItem(
                  icon: Icons.receipt_long_rounded,
                  label: S.current.strArchive,
                  isActive: activeRoute == AppRoutes.archiveScreen,
                  onTap: () => _navigate(context, AppRoutes.archiveScreen),
                ),
                if (role == UserRole.cashier)
                  _NavItem(
                    icon: Icons.lock_clock_outlined,
                    label: S.current.strShift,
                    isActive: activeRoute == AppRoutes.closeShiftScreen,
                    onTap: () => _navigate(context, AppRoutes.closeShiftScreen),
                  ),
                if (canManageMenu)
                  _NavItem(
                    icon: Icons.restaurant_menu_rounded,
                    label: S.current.strMenu,
                    isActive: activeRoute == AppRoutes.menuMealsScreen ||
                        activeRoute == AppRoutes.menuManageScreen,
                    onTap: () => _navigate(context, AppRoutes.menuMealsScreen),
                  ),
                if (canAccessSettings)
                  _NavItem(
                    icon: Icons.settings_outlined,
                    label: S.current.strSettings,
                    isActive: activeRoute == AppRoutes.settingsScreen,
                    onTap: () => _navigate(context, AppRoutes.settingsScreen),
                  ),
              ],
            ),
          ),
          // Logout at bottom
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _NavItem(
              icon: Icons.logout_rounded,
              label: S.current.strLogout,
              isActive: false,
              isDestructive: true,
              onTap: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const LogoutDialog(
                    routeName: AppRoutes.loginPinScreen,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name == route) return;
    Navigator.pushReplacementNamed(context, route);
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDestructive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeColor =
        widget.isDestructive ? colors.systemError : colors.textBrand;
    final inactiveColor =
        widget.isDestructive ? colors.systemError.withOpacity(0.7) : colors.sidebarIcon;

    final bgColor = widget.isActive
        ? colors.sidebarActive
        : _hovered
        ? colors.sidebarActive.withOpacity(0.5)
        : Colors.transparent;

    final iconColor = widget.isActive ? activeColor : inactiveColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 56,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 22, color: iconColor),
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
