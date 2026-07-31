import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/di.dart';

/// Shows [StyledVirtualKeyboard]/[StyledNumericKeyboard] as a floating
/// overlay pinned to the bottom of the screen, sized the same way as
/// [AppScaffold]'s app-wide keyboard.
///
/// Dialogs (`showDialog`) live in the same root [Overlay] as the app, but
/// their route's [OverlayEntry] is inserted *after* — and therefore paints
/// on top of — whatever [AppScaffold] renders in its own `Stack`. That's
/// why `AppScaffold.open` is invisible from inside a dialog. Inserting a
/// new [OverlayEntry] straight into the root overlay (instead of nesting
/// the keyboard inside the dialog's own widget tree) puts it above the
/// dialog too, and lets it span the full screen instead of being squeezed
/// into the dialog's width.
class FloatingKeyboard {
  FloatingKeyboard._();

  static OverlayEntry? _entry;

  static void openText(
    BuildContext context,
    TextEditingController controller, {
    ValueChanged<String>? onChanged,
    VoidCallback? onClose,
  }) {
    _show(
      context,
      StyledVirtualKeyboard(
        controller: controller,
        height: MediaQuery.of(context).size.height * .48,
        onClose: () {
          onClose?.call();
          close();
        },
        onChanged: onChanged,
      ),
    );
  }

  /// Shows [StyledNumericKeyboard] as a small floating card anchored just
  /// below [context]'s render box (the tapped field itself — pass the
  /// field's own `BuildContext`, e.g. via a `Builder`), rather than a
  /// full-width bar docked to the screen edge.
  static void openNumeric(
    BuildContext context,
    TextEditingController controller, {
    bool groupThousands = false,
    bool allowDecimal = false,
    ValueChanged<String>? onChanged,
    VoidCallback? onClose,
  }) {
    const cardWidth = 340.0;
    const cardHeight = 300.0;
    _showAnchored(
      context,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      keyboard: StyledNumericKeyboard(
        controller: controller,
        height: cardHeight,
        width: cardWidth,
        groupThousands: groupThousands,
        allowDecimal: allowDecimal,
        onClose: () {
          onClose?.call();
          close();
        },
        onChanged: onChanged,
      ),
    );
  }

  static void _show(BuildContext context, Widget keyboard) {
    close();
    final overlayState = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      // Positioned.fill (rather than a bare Stack) is what gives this entry
      // full-screen bounds inside Overlay's own internal Stack — a plain
      // Stack here would collapse to zero size since neither of its
      // children is a non-positioned child.
      builder: (_) => Positioned.fill(
        child: Stack(
          children: [
            // Tapping anywhere outside the keyboard closes it —
            // translucent so the tap still reaches whatever's underneath
            // (e.g. a dialog's Save button), matching AppScaffold's own
            // keyboard behavior.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: close,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                type: MaterialType.transparency,
                child: SafeArea(top: false, child: keyboard),
              ),
            ),
          ],
        ),
      ),
    );
    _entry = entry;
    overlayState.insert(entry);
  }

  static void _showAnchored(
    BuildContext anchorContext, {
    required double cardWidth,
    required double cardHeight,
    required Widget keyboard,
  }) {
    close();
    final overlayState = Overlay.of(anchorContext, rootOverlay: true);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject();

    var left = 12.0;
    var top = 12.0;
    final screenSize = overlayBox?.size ?? MediaQuery.of(anchorContext).size;
    if (anchorBox is RenderBox && overlayBox != null && anchorBox.attached) {
      final anchorTopLeft = anchorBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      left = anchorTopLeft.dx;
      top = anchorTopLeft.dy + anchorBox.size.height + 8;
      if (left + cardWidth > screenSize.width - 12) {
        left = screenSize.width - cardWidth - 12;
      }
      if (left < 12) left = 12;
      if (top + cardHeight > screenSize.height - 12) {
        top = anchorTopLeft.dy - cardHeight - 8;
      }
      if (top < 12) top = 12;
    }

    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: close,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(type: MaterialType.transparency, child: keyboard),
            ),
          ],
        ),
      ),
    );
    _entry = entry;
    overlayState.insert(entry);
  }

  /// Closes the floating keyboard, if one is open. Safe to call
  /// unconditionally (e.g. from a dialog's `dispose`).
  static void close() {
    _entry?.remove();
    _entry = null;
  }
}

enum KeyboardLanguage { eng, uzb, rus }

/// The keyboard's typing-language choice (EN/UZ/RU) is shared by every
/// [StyledVirtualKeyboard] instance app-wide and persisted to disk, so
/// switching language on one screen sticks across screens and app restarts.
class KeyboardLanguagePreference {
  KeyboardLanguagePreference._();

  static final ValueNotifier<KeyboardLanguage> current = ValueNotifier(
    KeyboardLanguage.eng,
  );
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
    [
      'a',
      's',
      'd',
      'f',
      'g',
      'h',
      'j',
      'k',
      'l',
      ';',
      "'",
      _KbAction.returnKey,
    ],
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
    ['@', _KbAction.space, '-', '&', '_', _KbAction.language],
  ];

  // Uzbek layout (Latin)
  static const _uzbRows = <List<Object>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    [
      'q',
      'w',
      'e',
      'r',
      't',
      'y',
      'u',
      'i',
      'o',
      'p',
      'g\'',
      _KbAction.backspace,
    ],
    [
      'a',
      's',
      'd',
      'f',
      'g',
      'h',
      'j',
      'k',
      'l',
      ';',
      "'",
      _KbAction.returnKey,
    ],
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
    ['@', _KbAction.space, '-', '&', '_', _KbAction.language],
  ];

  // Russian layout
  static const _rusRows = <List<Object>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    [
      'й',
      'ц',
      'у',
      'к',
      'е',
      'н',
      'г',
      'ш',
      'щ',
      'з',
      'х',
      _KbAction.backspace,
    ],
    [
      'ф',
      'ы',
      'в',
      'а',
      'п',
      'р',
      'о',
      'л',
      'д',
      'ж',
      'э',
      _KbAction.returnKey,
    ],
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
    ['@', _KbAction.space, '-', '&', '_', _KbAction.language],
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
      case _KbAction.language:
        const order = _LanguageSwitcher.order;
        final current = KeyboardLanguagePreference.current.value;
        final next = order[(order.indexOf(current) + 1) % order.length];
        setState(() => _shift = false);
        KeyboardLanguagePreference.set(next);
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
        final keyHeight =
            ((widget.height - 16 - rowGap * (rowCount - 1)) / rowCount).clamp(
              36.0,
              168.0,
            );

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
                          child: rows[r][c] == _KbAction.language
                              ? _LanguageSwitcher(
                                  currentLanguage: language,
                                  height: keyHeight,
                                  onLanguageChanged: (lang) {
                                    setState(() => _shift = false);
                                    KeyboardLanguagePreference.set(lang);
                                  },
                                )
                              : _StyledKey(
                                  label: _labelFor(rows[r][c]),
                                  icon: _iconFor(rows[r][c]),
                                  height: keyHeight,
                                  active:
                                      rows[r][c] == _KbAction.shift && _shift,
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
      case _KbAction.language:
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
      case _KbAction.language:
        return null;
    }
  }
}

enum _KbAction { backspace, space, shift, returnKey, language }

/// Numeric-only keypad with the same bordered-key styling as
/// [StyledVirtualKeyboard]. Used for amount/number inputs that shouldn't
/// show the full alphanumeric keyboard.
class StyledNumericKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final double height;
  final VoidCallback? onClose;
  final bool allowDecimal;

  /// Reformats the digits with thousands-space grouping after every key
  /// press (e.g. `10000` → `10 000`). Mutually exclusive with
  /// [allowDecimal] — grouped values are always treated as whole numbers.
  final bool groupThousands;

  /// Fixed card width. When set, renders as a small rounded, elevated card
  /// (all four corners, shadow on every side) instead of a full-width bar
  /// docked flush to the screen edge — used when the keypad floats next to
  /// the field it belongs to rather than spanning the whole screen.
  final double? width;

  /// See [StyledVirtualKeyboard.onChanged].
  final ValueChanged<String>? onChanged;

  const StyledNumericKeyboard({
    super.key,
    required this.controller,
    required this.height,
    this.onClose,
    this.allowDecimal = false,
    this.groupThousands = false,
    this.width,
    this.onChanged,
  });

  @override
  State<StyledNumericKeyboard> createState() => _StyledNumericKeyboardState();
}

enum _NumKey { decimal, backspace, done }

class _StyledNumericKeyboardState extends State<StyledNumericKeyboard> {
  static const _digitRows = <List<String>>[
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  String _digitsOf(String text) => text.replaceAll(RegExp(r'\D'), '');

  /// Reformats [rawDigits] with thousands-space grouping and writes it to
  /// the controller with the cursor pinned at the end — grouped values are
  /// re-derived from scratch on every key press rather than edited in
  /// place, so mid-string cursor tracking isn't meaningful here.
  void _setGroupedDigits(String rawDigits) {
    final ctrl = widget.controller;
    String next = '';
    if (rawDigits.isNotEmpty) {
      final n = int.tryParse(rawDigits) ?? 0;
      next = NumberFormat.currency(
        symbol: '',
        locale: 'uz',
        decimalDigits: 0,
      ).format(n).trim();
    }
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onChanged?.call(next);
  }

  void _insert(String value) {
    if (widget.groupThousands) {
      _setGroupedDigits(_digitsOf(widget.controller.text) + value);
      return;
    }
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
    if (widget.groupThousands) {
      final digits = _digitsOf(widget.controller.text);
      if (digits.isEmpty) return;
      _setGroupedDigits(digits.substring(0, digits.length - 1));
      return;
    }
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
      _insert(key);
      return;
    }
    switch (key as _NumKey) {
      case _NumKey.backspace:
        _backspace();
        break;
      case _NumKey.decimal:
        if (widget.allowDecimal && !widget.controller.text.contains('.')) {
          _insert('.');
        }
        break;
      case _NumKey.done:
        widget.onClose?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const rowGap = 6.0;
    const rowCount = 5; // 3 digit rows + (./0/backspace) row + done row
    final keyHeight =
        ((widget.height - 16 - rowGap * (rowCount - 1)) / rowCount).clamp(
          36.0,
          120.0,
        );

    final floating = widget.width != null;

    Widget buildKey(Object k) => _StyledKey(
      label: k is String ? k : null,
      icon: k == _NumKey.backspace
          ? Icons.backspace_outlined
          : k == _NumKey.done
          ? Icons.check_rounded
          : null,
      height: keyHeight,
      active: false,
      fillColor: k == _NumKey.done ? colors.buttonBrand : null,
      contentColor: k == _NumKey.done ? colors.textOnBrand : null,
      onTap: () => _onKey(k),
    );

    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: floating
          ? BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            )
          : BoxDecoration(
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
          for (final row in _digitRows) ...[
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < row.length; c++) ...[
                    if (c > 0) const SizedBox(width: 5),
                    Expanded(child: buildKey(row[c])),
                  ],
                ],
              ),
            ),
            const SizedBox(height: rowGap),
          ],
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: widget.allowDecimal
                      ? buildKey(_NumKey.decimal)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 5),
                Expanded(child: buildKey('0')),
                const SizedBox(width: 5),
                Expanded(child: buildKey(_NumKey.backspace)),
              ],
            ),
          ),
          const SizedBox(height: rowGap),
          Expanded(child: buildKey(_NumKey.done)),
        ],
      ),
    );
  }
}

/// Compact language toggle — tapping cycles EN → UZ → RU → EN. Sits inline
/// with the space-bar row, sized to match the surrounding keys.
class _LanguageSwitcher extends StatelessWidget {
  final KeyboardLanguage currentLanguage;
  final double height;
  final ValueChanged<KeyboardLanguage> onLanguageChanged;

  const _LanguageSwitcher({
    required this.currentLanguage,
    required this.height,
    required this.onLanguageChanged,
  });

  static const order = [
    KeyboardLanguage.eng,
    KeyboardLanguage.uzb,
    KeyboardLanguage.rus,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final next = order[(order.indexOf(currentLanguage) + 1) % order.length];

    return GestureDetector(
      onTap: () => onLanguageChanged(next),
      child: Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: colors.bgDefault,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language_rounded, size: 16, color: colors.textSecondary),
            const SizedBox(width: 4),
            Text(
              currentLanguage.name.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
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

  /// Solid background color overriding the default bordered look — used
  /// for the numeric keypad's "done" key (filled brand color).
  final Color? fillColor;
  final Color? contentColor;

  const _StyledKey({
    required this.label,
    required this.icon,
    required this.height,
    required this.active,
    required this.onTap,
    this.fillColor,
    this.contentColor,
  });

  @override
  State<_StyledKey> createState() => _StyledKeyState();
}

class _StyledKeyState extends State<_StyledKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filled = widget.fillColor != null;
    final bg = filled
        ? widget.fillColor!
        : (widget.active || _pressed ? colors.bgSecondary : colors.bgDefault);
    final contentColor = widget.contentColor ?? colors.textDefault;

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
          border: filled ? null : Border.all(color: colors.border),
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
            ? Icon(widget.icon, size: 28, color: contentColor)
            : Text(
                widget.label ?? '',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: contentColor,
                  fontFamily: 'Inter',
                ),
              ),
      ),
    );
  }
}
