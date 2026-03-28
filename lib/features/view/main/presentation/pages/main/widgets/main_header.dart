import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';

class MainHeader extends StatelessWidget {
  final String title;
  const MainHeader({super.key, this.title = 'Stollar'});

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
          BlocBuilder<UserBloc, UserState>(
            builder: (context, state) {
              final name = state.userMOdel?.fullName ?? '';
              final role = _roleLabel(state.userMOdel?.role);
              return Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  if (name.isNotEmpty)
                    Column(
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
                    ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.bgSecondary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_outline,
                      size: 18,
                      color: colors.textSecondary,
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

  String _roleLabel(dynamic role) {
    if (role == null) return '';
    final s = role.toString();
    if (s.contains('admin')) return 'Admin';
    if (s.contains('waiter')) return 'Ofitsiant';
    if (s.contains('cashier')) return 'Kassir';
    if (s.contains('kitchen')) return 'Oshpaz';
    return s;
  }
}
