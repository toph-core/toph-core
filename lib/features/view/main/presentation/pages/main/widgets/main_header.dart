import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class MainHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  final Widget? trailing;
  const MainHeader({super.key, this.title = 'Stollar', this.leading, this.trailing});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colors.bgDefault,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 4),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textDefault,
              fontFamily: 'Inter',
            ),
          ),
          const Spacer(),
          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 12),
          ],
          const _LangToggle(),
          const SizedBox(width: 12),
          BlocBuilder<UserBloc, UserState>(
            builder: (context, state) {
              final name = state.userMOdel?.fullName ?? '';
              final role = _roleLabel(state.userMOdel?.role);
              if (name.isEmpty) return const SizedBox.shrink();
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textDefault,
                      fontFamily: 'Inter',
                    ),
                  ),
                  Text(
                    role,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _roleLabel(UserRole? role) {
    if (role == null || role == UserRole.none) return '';
    return switch (role) {
      UserRole.admin => S.current.strRoleAdmin,
      UserRole.superadmin => S.current.strRoleSuperadmin,
      UserRole.manager => S.current.strRoleManager,
      UserRole.cashier => S.current.strRoleCashier,
      UserRole.waiter => S.current.strRoleWaiter,
      UserRole.kitchen => S.current.strRoleChef,
      UserRole.user => S.current.strRoleUser,
      UserRole.none => '',
    };
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle();

  @override
  Widget build(BuildContext context) {
    final lang = context.select((SettingsCubit c) => c.state.language);
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['uz', 'ru'].map((code) {
          final selected = lang == code;
          return GestureDetector(
            onTap: () => context
                .read<SettingsCubit>()
                .saveAppLang(context, languageCode: code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? c.textBrand : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                code.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : c.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
