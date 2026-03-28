import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/logout_dialog.dart';

class AppSidebar extends StatelessWidget {
  final String activeRoute;
  const AppSidebar({super.key, required this.activeRoute});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 72,
      color: colors.sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Logo
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFB6633), Color(0xFFFF8C5A)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'M',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              children: [
                _NavItem(
                  icon: Icons.grid_view_rounded,
                  label: 'Stollar',
                  isActive: activeRoute == AppRoutes.mainScreen,
                  onTap: () => _navigate(context, AppRoutes.mainScreen),
                ),
                _NavItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Arxiv',
                  isActive: activeRoute == AppRoutes.archiveScreen,
                  onTap: () => _navigate(context, AppRoutes.archiveScreen),
                ),
                _NavItem(
                  icon: Icons.notifications_outlined,
                  label: 'Xabarlar',
                  isActive: activeRoute == AppRoutes.notificationsScreen,
                  onTap: () =>
                      _navigate(context, AppRoutes.notificationsScreen),
                ),
                _NavItem(
                  icon: Icons.lock_clock_outlined,
                  label: 'Smena',
                  isActive: activeRoute == AppRoutes.closeShiftScreen,
                  onTap: () => _navigate(context, AppRoutes.closeShiftScreen),
                ),
              ],
            ),
          ),
          // Logout at bottom
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _NavItem(
              icon: Icons.logout_rounded,
              label: 'Chiqish',
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
