import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';

/// Alphanumeric virtual keyboard with bordered keys that have subtle depth.
/// Used by the ordering-page search field.
class StyledVirtualKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final double height;
  final VoidCallback? onClose;

  const StyledVirtualKeyboard({
    super.key,
    required this.controller,
    required this.height,
    this.onClose,
  });

  @override
  State<StyledVirtualKeyboard> createState() => _StyledVirtualKeyboardState();
}

class _StyledVirtualKeyboardState extends State<StyledVirtualKeyboard> {
  bool _shift = false;

  static const _rows = <List<Object>>[
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
      return;
    }
    if (sel.start <= 0) return;
    final next = text.replaceRange(sel.start - 1, sel.start, '');
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start - 1),
    );
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
    final rowCount = _rows.length;
    const rowGap = 6.0;
    final keyHeight =
        ((widget.height - 16 - rowGap * (rowCount - 1)) / rowCount)
            .clamp(36.0, 64.0);

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
          for (var r = 0; r < rowCount; r++) ...[
            if (r > 0) SizedBox(height: rowGap),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < _rows[r].length; c++) ...[
                    if (c > 0) const SizedBox(width: 5),
                    Expanded(
                      flex: _rows[r][c] == _KbAction.space ? 5 : 1,
                      child: _StyledKey(
                        label: _labelFor(_rows[r][c]),
                        icon: _iconFor(_rows[r][c]),
                        height: keyHeight,
                        active: _rows[r][c] == _KbAction.shift && _shift,
                        onTap: () => _onKey(_rows[r][c]),
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
