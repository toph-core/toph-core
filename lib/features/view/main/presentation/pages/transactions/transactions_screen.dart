import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/transactions/sections/transaction_categories_section.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/transactions/sections/transactions_list_section.dart';

enum _TransactionsSection { list, categories }

extension _SectionMeta on _TransactionsSection {
  IconData get icon {
    switch (this) {
      case _TransactionsSection.list:
        return Icons.receipt_long_outlined;
      case _TransactionsSection.categories:
        return Icons.sell_outlined;
    }
  }

  String get label {
    switch (this) {
      case _TransactionsSection.list:
        return S.current.strTransactions;
      case _TransactionsSection.categories:
        return S.current.strTransactionCategories;
    }
  }
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  _TransactionsSection _section = _TransactionsSection.list;

  @override
  Widget build(BuildContext context) {
    final role = context.select((UserBloc b) => b.state.userMOdel?.role);
    final allowed = role.canManageTransactions;
    final colors = context.colors;

    return AppScaffold(
      activeRoute: AppRoutes.transactionsScreen,
      body: Column(
        children: [
          MainHeader(title: S.current.strTransactions),
          Expanded(
            child: Container(
              color: colors.bgSecondary,
              child: !allowed
                  ? _AccessDenied(colors: colors)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TransactionsSideNav(
                          current: _section,
                          onChange: (s) => setState(() => _section = s),
                        ),
                        Expanded(
                          child: Container(
                            color: colors.bgDefault,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.015, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: _sectionBody(),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionBody() {
    switch (_section) {
      case _TransactionsSection.list:
        return const TransactionsListSection(key: ValueKey('transactions'));
      case _TransactionsSection.categories:
        return const TransactionCategoriesSection(key: ValueKey('categories'));
    }
  }
}

class _AccessDenied extends StatelessWidget {
  final ThemeColors colors;
  const _AccessDenied({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: colors.bgDefault,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.systemError.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.lock_outline,
                  size: 28, color: colors.systemError),
            ),
            const SizedBox(height: 14),
            Text(
              S.current.strAccessRestricted,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.textDefault,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.current.strTransactionsAdminOnly,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionsSideNav extends StatelessWidget {
  final _TransactionsSection current;
  final ValueChanged<_TransactionsSection> onChange;
  const _TransactionsSideNav({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: PosBreakpoints.pick<double>(
        context,
        compact: 220,
        comfortable: 280,
      ),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        PosDimensions.l,
        PosDimensions.xxl,
        PosDimensions.l,
        PosDimensions.l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: PosDimensions.m),
            child: Text(
              S.current.strTransactions.toUpperCase(),
              style: TextStyle(
                fontSize: PosTypography.captionSm,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: colors.textSecondary,
                fontFamily: PosTypography.family,
              ),
            ),
          ),
          ..._TransactionsSection.values.map(
            (s) => _NavItem(
              section: s,
              selected: current == s,
              onTap: () => onChange(s),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final _TransactionsSection section;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;
    final bgColor = selected
        ? colors.buttonBrand.withOpacity(0.12)
        : (_hover ? colors.buttonBrand.withOpacity(0.06) : Colors.transparent);
    final iconBg = selected
        ? colors.buttonBrand
        : (_hover ? colors.buttonBrand.withOpacity(0.10) : colors.bgDefault);
    final iconColor = selected
        ? colors.textOnBrand
        : (_hover ? colors.buttonBrand : colors.textSecondary);
    final titleColor = selected ? colors.buttonBrand : colors.textDefault;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: PosDimensions.m, vertical: PosDimensions.m),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius:
                            BorderRadius.circular(PosDimensions.radiusSm),
                        border: selected
                            ? null
                            : Border.all(
                                color: _hover
                                    ? colors.buttonBrand.withOpacity(0.30)
                                    : colors.border,
                              ),
                      ),
                      child: Icon(widget.section.icon,
                          size: 20, color: iconColor),
                    ),
                    const SizedBox(width: PosDimensions.m),
                    Expanded(
                      child: Text(
                        widget.section.label,
                        style: TextStyle(
                          fontSize: PosTypography.bodyMd,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                          fontFamily: PosTypography.family,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: colors.buttonBrand),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
