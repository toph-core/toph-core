import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/di.dart';

enum KeyboardLanguage { eng, uzb, rus }

/// The keyboard's typing-language choice (EN/UZ/RU) is shared by every
/// [StyledVirtualKeyboard] instance app-wide and persisted to disk, so
/// switching language on one screen sticks across screens and app restarts.
class KeyboardLanguagePreference {
  KeyboardLanguagePreference._();

  static final ValueNotifier<KeyboardLanguage> current =
      ValueNotifier(KeyboardLanguage.eng);
  static bool _loaded = false;

  /// Loads the persisted preference once per app run. Safe to call from
  /// every keyboard instance's `initState` — subsequent calls are no-ops.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final stored = await inject<AppTokenStorage>().readString(
      TokensStorageKeys.keyboardLanguage,
    );
    if (stored == null) return;
    for (final lang in KeyboardLanguage.values) {
      if (lang.name == stored) {
        current.value = lang;
        return;
      }
    }
  }

  static void set(KeyboardLanguage lang) {
    if (current.value == lang) return;
    current.value = lang;
    inject<AppTokenStorage>().writeString(
      TokensStorageKeys.keyboardLanguage,
      lang.name,
    );
  }
}

/// Alphanumeric virtual keyboard with bordered keys that have subtle depth.
/// Used by the ordering-page search field.
/// Supports English, Uzbek, and Russian languages with easy switching.
class StyledVirtualKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final double height;
  final VoidCallback? onClose;

  /// Called with the updated text after a key press changes [controller].
  ///
  /// Key presses mutate [controller] directly, which does not trigger a
  /// [TextField]'s own `onChanged` — callers that need to react to the
  /// updated text (e.g. live search) must use this instead.
  final ValueChanged<String>? onChanged;

  const StyledVirtualKeyboard({
    super.key,
    required this.controller,
    required this.height,
    this.onClose,
    this.onChanged,
  });

  @override
  State<StyledVirtualKeyboard> createState() => _StyledVirtualKeyboardState();
}

class _StyledVirtualKeyboardState extends State<StyledVirtualKeyboard> {
  bool _shift = false;

  // English layout
  static const _engRows = <List<Object>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', _KbAction.backspace],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", _KbAction.returnKey],
    [
      _KbAction.shift,
      'z',
      'x',
      'c',
      'v',
      'b',
      'n',
      'm',
      ',',
      '.',
      '/',
      _KbAction.shift,
    ],
    ['@', _KbAction.space, '-', '&', '_'],
  ];

  // Uzbek layout (Latin)
  static const _uzbRows = <List<Object>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 'g\'', _KbAction.backspace],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", _KbAction.returnKey],
    [
      _KbAction.shift,
      'z',
      'x',
      'c',
      'v',
      'b',
      'n',
      'm',
      ',',
      '.',
      '/',
      _KbAction.shift,
    ],
    ['@', _KbAction.space, '-', '&', '_'],
  ];

  // Russian layout
  static const _rusRows = <List<Object>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['й', 'ц', 'у', 'к', 'е', 'н', 'г', 'ш', 'щ', 'з', 'х', _KbAction.backspace],
    ['ф', 'ы', 'в', 'а', 'п', 'р', 'о', 'л', 'д', 'ж', 'э', _KbAction.returnKey],
    [
      _KbAction.shift,
      'я',
      'ч',
      'с',
      'м',
      'и',
      'т',
      'ь',
      'б',
      'ю',
      '.',
      _KbAction.shift,
    ],
    ['@', _KbAction.space, '-', '&', '_'],
  ];

  List<List<Object>> _rowsFor(KeyboardLanguage language) {
    switch (language) {
      case KeyboardLanguage.eng:
        return _engRows;
      case KeyboardLanguage.uzb:
        return _uzbRows;
      case KeyboardLanguage.rus:
        return _rusRows;
    }
  }

  @override
  void initState() {
    super.initState();
    KeyboardLanguagePreference.load();
  }

  void _insert(String value) {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection.isValid
        ? ctrl.selection
        : TextSelection.collapsed(offset: text.length);
    final next = text.replaceRange(sel.start, sel.end, value);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + value.length),
    );
    widget.onChanged?.call(next);
  }

  void _backspace() {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection.isValid
        ? ctrl.selection
        : TextSelection.collapsed(offset: text.length);
    if (sel.start != sel.end) {
      final next = text.replaceRange(sel.start, sel.end, '');
      ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start),
      );
      widget.onChanged?.call(next);
      return;
    }
    if (sel.start <= 0) return;
    final next = text.replaceRange(sel.start - 1, sel.start, '');
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start - 1),
    );
    widget.onChanged?.call(next);
  }

  void _onKey(Object key) {
    if (key is String) {
      _insert(_shift ? key.toUpperCase() : key);
      if (_shift) setState(() => _shift = false);
      return;
    }
    switch (key as _KbAction) {
      case _KbAction.backspace:
        _backspace();
        break;
      case _KbAction.space:
        _insert(' ');
        break;
      case _KbAction.shift:
        setState(() => _shift = !_shift);
        break;
      case _KbAction.returnKey:
        widget.onClose?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ValueListenableBuilder<KeyboardLanguage>(
      valueListenable: KeyboardLanguagePreference.current,
      builder: (context, language, _) {
        final rows = _rowsFor(language);
        final rowCount = rows.length;
        const rowGap = 6.0;
        // Slim reserved strip for the compact language pill — small screens
        // need every bit of height they can get for the actual key rows.
        const languageSwitcherHeight = 30.0;
        final keyHeight = ((widget.height -
                    16 -
                    languageSwitcherHeight -
                    rowGap * rowCount) /
                rowCount)
            .clamp(28.0, 64.0);

        return Container(
          height: widget.height,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: colors.bgSecondary,
            border: Border(top: BorderSide(color: colors.border, width: 1.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Compact language toggle — right-aligned, out of the way of
              // the keys instead of a full-width row above them.
              SizedBox(
                height: languageSwitcherHeight,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _LanguageSwitcher(
                    currentLanguage: language,
                    onLanguageChanged: (lang) {
                      setState(() => _shift = false);
                      KeyboardLanguagePreference.set(lang);
                    },
                  ),
                ),
              ),
              const SizedBox(height: rowGap),
              // Keyboard rows
              for (var r = 0; r < rowCount; r++) ...[
                if (r > 0) const SizedBox(height: rowGap),
                Expanded(
                  child: Row(
                    children: [
                      for (var c = 0; c < rows[r].length; c++) ...[
                        if (c > 0) const SizedBox(width: 5),
                        Expanded(
                          flex: rows[r][c] == _KbAction.space ? 5 : 1,
                          child: _StyledKey(
                            label: _labelFor(rows[r][c]),
                            icon: _iconFor(rows[r][c]),
                            height: keyHeight,
                            active: rows[r][c] == _KbAction.shift && _shift,
                            onTap: () => _onKey(rows[r][c]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String? _labelFor(Object key) {
    if (key is String) return _shift ? key.toUpperCase() : key;
    switch (key as _KbAction) {
      case _KbAction.space:
        return null;
      case _KbAction.shift:
        return null;
      case _KbAction.backspace:
        return null;
      case _KbAction.returnKey:
        return null;
    }
  }

  IconData? _iconFor(Object key) {
    if (key is! _KbAction) return null;
    switch (key) {
      case _KbAction.space:
        return Icons.space_bar_rounded;
      case _KbAction.shift:
        return Icons.arrow_upward_rounded;
      case _KbAction.backspace:
        return Icons.backspace_outlined;
      case _KbAction.returnKey:
        return Icons.keyboard_return_rounded;
    }
  }
}

enum _KbAction { backspace, space, shift, returnKey }

/// Compact single-button language toggle — tapping cycles EN → UZ → RU → EN.
/// Deliberately small and corner-anchored rather than a full-width row, so it
/// doesn't eat into the space the key rows need (especially on small screens).
class _LanguageSwitcher extends StatelessWidget {
  final KeyboardLanguage currentLanguage;
  final ValueChanged<KeyboardLanguage> onLanguageChanged;

  const _LanguageSwitcher({
    required this.currentLanguage,
    required this.onLanguageChanged,
  });

  static const _order = [
    KeyboardLanguage.eng,
    KeyboardLanguage.uzb,
    KeyboardLanguage.rus,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final next = _order[(_order.indexOf(currentLanguage) + 1) % _order.length];

    return GestureDetector(
      onTap: () => onLanguageChanged(next),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.bgDefault,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language_rounded, size: 14, color: colors.textSecondary),
            const SizedBox(width: 4),
            Text(
              currentLanguage.name.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textDefault,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StyledKey extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final double height;
  final bool active;
  final VoidCallback onTap;

  const _StyledKey({
    required this.label,
    required this.icon,
    required this.height,
    required this.active,
    required this.onTap,
  });

  @override
  State<_StyledKey> createState() => _StyledKeyState();
}

class _StyledKeyState extends State<_StyledKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = widget.active || _pressed
        ? colors.bgSecondary
        : colors.bgDefault;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
          boxShadow: _pressed
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        transform: Matrix4.translationValues(0, _pressed ? 1.5 : 0, 0),
        child: widget.icon != null
            ? Icon(widget.icon, size: 20, color: colors.textDefault)
            : Text(
                widget.label ?? '',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.textDefault,
                  fontFamily: 'Inter',
                ),
              ),
      ),
    );
  }
}
