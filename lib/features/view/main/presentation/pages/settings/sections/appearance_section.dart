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

class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  final ValueNotifier<TextEditingController?> _kbTarget = ValueNotifier(null);

  /// 1.0 at compact baseline (~1024×640), 1.5 at 1920×1080 (capped).
  static double numpadScaleOf(Size size) {
    const minW = 1024.0, minH = 640.0;
    const maxW = 1920.0, maxH = 1080.0;
    final t = ((
              ((size.width - minW) / (maxW - minW)) +
              ((size.height - minH) / (maxH - minH))
            ) /
            2)
        .clamp(0.0, 1.0);
    return 1.0 + 0.5 * t;
  }

  @override
  void dispose() {
    _kbTarget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = context.select((SettingsCubit c) => c.state.language);
    final showImages = context.select(
      (UiPrefsCubit c) => c.state.menuShowImages,
    );
    final windowSize = MediaQuery.sizeOf(context);
    final scale = numpadScaleOf(windowSize);

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_kbTarget.value != null) {
              _kbTarget.value = null;
              FocusManager.instance.primaryFocus?.unfocus();
            }
          },
          child: SectionShell(
            title: S.current.strSettings,
            subtitle: S.current.strInterfaceSettings,
            child: ValueListenableBuilder<TextEditingController?>(
              valueListenable: _kbTarget,
              builder: (context, ctrl, _) {
                return ListView(
                  padding: EdgeInsets.only(
                    bottom: ctrl != null ? 240.0 * scale : 0,
                  ),
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
                        onChanged: (v) => context
                            .read<SettingsCubit>()
                            .saveAppLang(context, languageCode: v),
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
                    _ServiceChargeCard(kbTarget: _kbTarget),
                  ],
                );
              },
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingController?>(
          valueListenable: _kbTarget,
          builder: (context, ctrl, _) {
            if (ctrl == null) return const SizedBox.shrink();
            return Positioned(
              right: 16 * scale,
              bottom: 16 * scale,
              child: GestureDetector(
                onTap: () {}, // absorb taps so backdrop dismiss doesn't fire
                child: _CompactNumpad(
                  controller: ctrl,
                  scale: scale,
                  onClose: () {
                    _kbTarget.value = null;
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CompactNumpad extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClose;
  final double scale;

  const _CompactNumpad({
    required this.controller,
    required this.onClose,
    required this.scale,
  });

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '⌫'],
  ];

  void _onKey(String key) {
    final text = controller.text;
    final sel = controller.selection.isValid
        ? controller.selection
        : TextSelection.collapsed(offset: text.length);

    if (key == '⌫') {
      if (sel.start != sel.end) {
        final next = text.replaceRange(sel.start, sel.end, '');
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: sel.start),
        );
      } else if (sel.start > 0) {
        final next = text.replaceRange(sel.start - 1, sel.start, '');
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: sel.start - 1),
        );
      }
      return;
    }

    if (key == '.' && text.contains('.')) return;

    final next = text.replaceRange(sel.start, sel.end, key);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + key.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = scale;

    final keySize = 44.0 * s;
    final gap = 6.0 * s;
    final pad = 10.0 * s;
    final radius = 12.0 * s;
    final fontSize = 18.0 * s;
    final closeSize = 32.0 * s;
    final iconSize = 18.0 * s;

    return Material(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.18),
      borderRadius: BorderRadius.circular(radius),
      color: colors.bgDefault,
      child: Container(
        padding: EdgeInsets.fromLTRB(pad, pad * 0.65, pad, pad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: keySize * 3 + gap * 2,
              child: Row(
                children: [
                  const Spacer(),
                  Container(
                    width: 28 * s,
                    height: 3,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: closeSize,
                        height: closeSize,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: onClose,
                          icon: Icon(
                            Icons.keyboard_hide_outlined,
                            size: iconSize,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: gap * 0.75),
            for (var r = 0; r < _keys.length; r++) ...[
              if (r > 0) SizedBox(height: gap),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var c = 0; c < _keys[r].length; c++) ...[
                    if (c > 0) SizedBox(width: gap),
                    _NumpadKey(
                      label: _keys[r][c],
                      size: keySize,
                      fontSize: fontSize,
                      radius: radius * 0.75,
                      onTap: () => _onKey(_keys[r][c]),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NumpadKey extends StatefulWidget {
  final String label;
  final double size;
  final double fontSize;
  final double radius;
  final VoidCallback onTap;

  const _NumpadKey({
    required this.label,
    required this.size,
    required this.fontSize,
    required this.radius,
    required this.onTap,
  });

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isBackspace = widget.label == '⌫';

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed
              ? colors.bgSecondary
              : colors.bgSecondary.withOpacity(0.55),
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: colors.border),
        ),
        alignment: Alignment.center,
        child: isBackspace
            ? Icon(
                Icons.backspace_outlined,
                size: widget.fontSize,
                color: colors.textDefault,
              )
            : Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w600,
                  color: colors.textDefault,
                  fontFamily: 'Inter',
                ),
              ),
      ),
    );
  }
}

class _ServiceChargeCard extends StatefulWidget {
  final ValueNotifier<TextEditingController?> kbTarget;
  const _ServiceChargeCard({required this.kbTarget});

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
    _controller.addListener(_onControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = _branchId;
      final cubit = context.read<ServiceChargeCubit>();
      if (id.isNotEmpty && cubit.state.value == null) {
        cubit.load(id);
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
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
      widget.kbTarget.value = null;
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
              kbTarget: widget.kbTarget,
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

class _PercentInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueNotifier<TextEditingController?> kbTarget;
  final ValueChanged<String> onChanged;

  const _PercentInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.kbTarget,
    required this.onChanged,
  });

  @override
  State<_PercentInput> createState() => _PercentInputState();
}

class _PercentInputState extends State<_PercentInput> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final enabled = widget.enabled;
    final onChanged = widget.onChanged;
    final colors = context.colors;
    final focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 160,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? colors.buttonBrand : colors.border,
          width: focused ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              readOnly: true,
              showCursor: true,
              cursorColor: colors.buttonBrand,
              keyboardType: TextInputType.none,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onTap: () => widget.kbTarget.value = controller,
              onChanged: onChanged,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: colors.textDefault,
                fontFamily: 'Inter',
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '0',
                hintStyle: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textTertiary,
                  fontFamily: 'Inter',
                ),
                filled: false,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '%',
            style: TextStyle(
              fontSize: 18,
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
