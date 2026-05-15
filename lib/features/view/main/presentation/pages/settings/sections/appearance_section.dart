import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/settings/settings_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/service_charge/service_charge_cubit.dart';
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
          const SizedBox(height: 14),
          const _ServiceChargeCard(),
          // Mavzu tanlovi vaqtincha o'chirilgan — faqat yorug' ishlatilmoqda.
        ],
      ),
    );
  }
}

class _ServiceChargeCard extends StatefulWidget {
  const _ServiceChargeCard();

  @override
  State<_ServiceChargeCard> createState() => _ServiceChargeCardState();
}

class _ServiceChargeCardState extends State<_ServiceChargeCard> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  double? _syncedValue;

  String get _branchId =>
      context.read<UserBloc>().state.userMOdel?.branchId ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _branchId;
      if (id.isNotEmpty) {
        context.read<ServiceChargeCubit>().load(id);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncControllerWith(double value) {
    final formatted = value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
    _controller.text = formatted;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    _syncedValue = value;
  }

  Future<void> _save() async {
    final raw = _controller.text.replaceAll(',', '.').trim();
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0 || parsed > 100) {
      showErrorMessage(context, S.current.strServiceChargeInvalid);
      return;
    }
    final ok = await context.read<ServiceChargeCubit>().save(
      _branchId,
      parsed,
    );
    if (!mounted) return;
    if (ok) {
      _syncedValue = parsed;
      showSuccessMessage(context, S.current.strServiceChargeSaved);
      _focusNode.unfocus();
      setState(() {});
    } else {
      showErrorMessage(context, S.current.strServiceChargeInvalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = context.watch<ServiceChargeCubit>().state;

    if (state.value != null && state.value != _syncedValue) {
      _syncControllerWith(state.value!);
    }

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
            child: Icon(
              Icons.percent_rounded,
              color: colors.buttonBrand,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.current.strServiceCharge,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  S.current.strServiceChargeHint,
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
          if (state.loading)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.buttonBrand,
              ),
            )
          else ...[
            _PercentInput(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !state.saving,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(width: 10),
            _SaveButton(saving: state.saving, onTap: _save),
          ],
        ],
      ),
    );
  }
}

class _PercentInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _PercentInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: onChanged,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textDefault,
                  fontFamily: 'Inter',
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: '0',
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveButton({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.buttonBrand,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: saving ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textOnBrand,
                  ),
                )
              : Text(
                  S.current.strSave,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textOnBrand,
                    fontFamily: 'Inter',
                  ),
                ),
        ),
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
