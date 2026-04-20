import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/ui_prefs/ui_prefs_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final language = context.select((SettingsCubit c) => c.state.language);
    final showImages = context.select(
      (UiPrefsCubit c) => c.state.menuShowImages,
    );

    return SectionShell(
      title: S.current.strSettings,
      subtitle: S.current.strInterfaceSettings,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SettingCard(
            icon: Icons.language_rounded,
            title: S.current.strInterfaceLanguage,
            subtitle: S.current.strAppliesToAllUsers,
            control: _SegmentedPicker<String>(
              value: language,
              options: const [
                _Option(value: 'uz', label: 'O\'zbek', flag: '🇺🇿'),
                _Option(value: 'ru', label: 'Русский', flag: '🇷🇺'),
              ],
              onChanged: (v) => context.read<SettingsCubit>().saveAppLang(
                context,
                languageCode: v,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SettingCard(
            icon: Icons.image_outlined,
            title: S.current.strMenuImages,
            subtitle: S.current.strShowProductImages,
            control: _StyledSwitch(
              value: showImages,
              onChanged: (v) =>
                  context.read<UiPrefsCubit>().setMenuShowImages(v),
            ),
          ),
          // Mavzu tanlovi vaqtincha o'chirilgan — faqat yorug' ishlatilmoqda.
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget control;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.buttonBrand.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.buttonBrand, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

class _Option<T> {
  final T value;
  final String label;
  final String? flag;
  const _Option({required this.value, required this.label, this.flag});
}

class _SegmentedPicker<T> extends StatelessWidget {
  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onChanged;

  const _SegmentedPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final selected = o.value == value;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? colors.bgDefault : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(o.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (o.flag != null) ...[
                        Text(o.flag!, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        o.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? colors.buttonBrand
                              : colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StyledSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _StyledSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 50,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? colors.buttonBrand : colors.border,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
