import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/logout_dialog.dart';

const _kIndigo = Color(0xFFFB6633);
const _kSlate900 = Color(0xFF0F172A);
const _kSlate800 = Color(0xFF1E293B);
const _kSlate500 = Color(0xFF64748B);

class AppSidebar extends StatelessWidget {
  final String activeRoute;
  const AppSidebar({super.key, required this.activeRoute});

  @override
  Widget build(BuildContext context) {
    final role = context.select((UserBloc b) => b.state.userMOdel?.role);
    final canManageMenu = role.canManageMenu;
    final canAccessSettings = role.canAccessSettings;

    return Container(
      width: 76,
      color: _kSlate900,
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kIndigo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'M',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          ),
          Container(height: 1, color: _kSlate800),
          const SizedBox(height: 10),

          // Nav items
          Expanded(
            child: Column(
              children: [
                _NavItem(
                  icon: _IconTables(),
                  label: S.current.strTables,
                  isActive: activeRoute == AppRoutes.mainScreen,
                  onTap: () => _navigate(context, AppRoutes.mainScreen),
                ),
                _NavItem(
                  icon: _IconArchive(),
                  label: S.current.strArchive,
                  isActive: activeRoute == AppRoutes.archiveScreen,
                  onTap: () => _navigate(context, AppRoutes.archiveScreen),
                ),
                if (role == UserRole.cashier)
                  _NavItem(
                    icon: _IconShift(),
                    label: S.current.strShift,
                    isActive: activeRoute == AppRoutes.closeShiftScreen,
                    onTap: () =>
                        _navigate(context, AppRoutes.closeShiftScreen),
                  ),
                if (canManageMenu)
                  _NavItem(
                    icon: _IconMenu(),
                    label: S.current.strMenu,
                    isActive: activeRoute == AppRoutes.menuMealsScreen ||
                        activeRoute == AppRoutes.menuManageScreen,
                    onTap: () =>
                        _navigate(context, AppRoutes.menuMealsScreen),
                  ),
                if (canAccessSettings)
                  _NavItem(
                    icon: _IconSettings(),
                    label: S.current.strSettings,
                    isActive: activeRoute == AppRoutes.settingsScreen,
                    onTap: () =>
                        _navigate(context, AppRoutes.settingsScreen),
                  ),
              ],
            ),
          ),

          // Logout
          Container(height: 1, color: _kSlate800),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: _NavItem(
              icon: _IconLogout(),
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
  final Widget icon;
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
    final activeIconColor =
        widget.isDestructive ? const Color(0xFFEF4444) : _kIndigo;
    final inactiveIconColor =
        widget.isDestructive ? const Color(0xFFEF4444).withOpacity(0.7) : _kSlate500;
    final activeLabelColor =
        widget.isDestructive ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0);
    const inactiveLabelColor = _kSlate500;

    final bgColor = widget.isActive
        ? const Color(0x1AFB6633)
        : _hovered
            ? const Color(0x0DFB6633)
            : Colors.transparent;

    final iconColor = widget.isActive ? activeIconColor : inactiveIconColor;
    final labelColor = widget.isActive ? activeLabelColor : inactiveLabelColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 60,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(color: iconColor, size: 22),
                child: widget.icon,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      widget.isActive ? FontWeight.w500 : FontWeight.w400,
                  color: labelColor,
                  fontFamily: 'Inter',
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Custom SVG-like icons via paths ───────────────────────────────────────

class _IconTables extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color!;
    return CustomPaint(size: const Size(22, 22), painter: _TablesPainter(color));
  }
}

class _TablesPainter extends CustomPainter {
  final Color color;
  _TablesPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const rr = RRect.fromRectAndRadius;
    const r = Radius.circular(1.5);
    canvas.drawRRect(rr(Rect.fromLTWH(2, 2, 8, 8), r), p);
    canvas.drawRRect(rr(Rect.fromLTWH(12, 2, 8, 8), r), p);
    canvas.drawRRect(rr(Rect.fromLTWH(2, 12, 8, 8), r), p);
    canvas.drawRRect(rr(Rect.fromLTWH(12, 12, 8, 8), r), p);
  }
  @override bool shouldRepaint(_TablesPainter old) => old.color != color;
}

class _IconMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(Icons.menu_rounded,
        size: 22, color: IconTheme.of(context).color);
  }
}

class _IconArchive extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(Icons.archive_outlined,
        size: 22, color: IconTheme.of(context).color);
  }
}

class _IconShift extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(Icons.bar_chart_rounded,
        size: 22, color: IconTheme.of(context).color);
  }
}

class _IconSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(Icons.settings_outlined,
        size: 22, color: IconTheme.of(context).color);
  }
}

class _IconLogout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(Icons.logout_rounded,
        size: 22, color: IconTheme.of(context).color);
  }
}
