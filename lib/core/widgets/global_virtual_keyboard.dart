import 'package:flutter/material.dart';
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';

/// KIOSK uchun global virtual klaviatura.
///
/// [child] ning istalgan joyidagi [TextField] fokus olganida ekranning pastidan
/// klaviatura suriladi. Bo'sh joyga bosilsa [KeyboardDismisser] orqali fokus
/// yo'qolib, klaviatura yana pastga suriladi.
class GlobalVirtualKeyboard extends StatefulWidget {
  final Widget child;

  const GlobalVirtualKeyboard({super.key, required this.child});

  /// Eng yangi (top of stack) `GlobalVirtualKeyboard`'ni topib, klaviaturani
  /// berilgan controller uchun ochadi. Search inputlardan to'g'ridan-to'g'ri
  /// chaqirish uchun ishlatiladi — FocusManager'ga qaramasdan ishlaydi.
  static void open(TextEditingController controller, {bool numeric = false}) {
    if (_stack.isNotEmpty) {
      _stack.last._openExplicit(controller, numeric);
    }
  }

  /// Klaviaturani majburiy yopadi.
  static void close() {
    if (_stack.isNotEmpty) {
      _stack.last._closeExplicit();
    }
  }

  static final List<_GlobalVirtualKeyboardState> _stack = [];

  @override
  State<GlobalVirtualKeyboard> createState() => _GlobalVirtualKeyboardState();
}

class _GlobalVirtualKeyboardState extends State<GlobalVirtualKeyboard> {
  bool _open = false;
  bool _shift = false;
  bool _numericOnly = false;
  TextEditingController? _controller;
  VoidCallback? _controllerListener;

  // Fokuslangan EditableText widget'i. Matn yozilgandan keyin uning
  // `onChanged` callback'ini sinxron chaqiramiz — aks holda TextField.onChanged
  // faqat fizik klaviaturada ishlaydi (Flutter'ning cheklovi).
  EditableText? _editableText;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
    GlobalVirtualKeyboard._stack.add(this);
  }

  @override
  void dispose() {
    GlobalVirtualKeyboard._stack.remove(this);
    FocusManager.instance.removeListener(_onFocusChange);
    _detachController();
    super.dispose();
  }

  /// Explicit API — `GlobalVirtualKeyboard.open(controller)` orqali chaqiriladi.
  void _openExplicit(TextEditingController controller, bool numeric) {
    if (!mounted) return;
    if (_controller != controller) {
      _detachController();
      _controller = controller;
      _controllerListener = () {};
      controller.addListener(_controllerListener!);
    }
    if (!_open || _numericOnly != numeric) {
      setState(() {
        _open = true;
        _numericOnly = numeric;
      });
    }
  }

  void _closeExplicit() {
    if (!mounted || !_open) return;
    _detachController();
    setState(() {
      _open = false;
      _shift = false;
    });
  }

  void _detachController() {
    final l = _controllerListener;
    final c = _controller;
    if (l != null && c != null) c.removeListener(l);
    _controllerListener = null;
    _controller = null;
    _editableText = null;
  }

  /// Fokuslangan FocusNode'ning context'idan `EditableText` widget'ini topadi.
  /// Avval to'g'ridan-to'g'ri tekshiradi (eski Flutter), keyin ajdod
  /// elementlar ichidan qidiradi (yangi Flutter — TextField'da EditableText
  /// `Focus` widget'i ichida bo'ladi). Avlodlarga kirmaymiz — aks holda
  /// FocusScope kabi keng kontekstda boshqa, fokuslanmagan TextField'lar
  /// topilib qolishi mumkin.
  EditableText? _findEditableTextFromFocus() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return null;
    final ctx = node.context;
    if (ctx == null) return null;
    final direct = ctx.widget;
    if (direct is EditableText) return direct;
    // Ajdod elementlar ichidan qidiramiz — fokus context'i odatda
    // EditableText'ning ichki widget'i (Focus/Listener) bo'ladi.
    EditableText? found;
    ctx.visitAncestorElements((el) {
      if (el.widget is EditableText) {
        found = el.widget as EditableText;
        return false;
      }
      return true;
    });
    return found;
  }

  void _onFocusChange() {
    final editable = _findEditableTextFromFocus();
    // Virtual klaviatura faqat qidiruv (search) input'larida chiqishi kerak.
    // TextInputAction.search bo'lgan TextField'lar — qidiruv maydonlari.
    final isSearch = editable?.textInputAction == TextInputAction.search;
    if (editable != null && isSearch) {
      final ctrl = editable.controller;
      final kt = editable.keyboardType;
      final numeric =
          kt == TextInputType.number ||
          kt == TextInputType.phone ||
          kt == const TextInputType.numberWithOptions(decimal: true) ||
          kt == const TextInputType.numberWithOptions(signed: true) ||
          kt.toString().contains('number');

      if (_controller != ctrl) {
        _detachController();
        _controller = ctrl;
        _controllerListener = () {
          // Controllerning tashqaridan o'zgartirilishi klaviaturaga ta'sir qilmaydi —
          // faqat holatni toza saqlash uchun listener.
        };
        ctrl.addListener(_controllerListener!);
      }
      // Fokuslangan widget — keyinchalik uning onChanged'ini chaqirish uchun saqlaymiz
      _editableText = editable;

      if (!_open || _numericOnly != numeric) {
        setState(() {
          _open = true;
          _numericOnly = numeric;
        });
      }
    } else if (_open) {
      _detachController();
      setState(() {
        _open = false;
        _shift = false;
      });
    }
  }

  /// Matn o'zgargandan keyin fokuslangan TextField.onChanged ni sinxron chaqiradi.
  /// Flutter dasturiy `controller.value` yozganda onChanged ni o'zi ishga
  /// tushirmaydi — bu metod shu bo'shliqni to'ldiradi.
  void _invokeOnChanged(String text) {
    final et = _editableText;
    if (et == null) return;
    try {
      et.onChanged?.call(text);
    } catch (_) {
      // Callback ichidagi xato klaviaturani bloklamasin.
    }
  }

  void _dismiss() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onKeyPress(VirtualKeyboardKey key) {
    final ctrl = _controller;
    if (ctrl == null) return;
    final text = ctrl.text;
    final sel = ctrl.selection.isValid
        ? ctrl.selection
        : TextSelection.collapsed(offset: text.length);

    void replace(String insert) {
      final next = text.replaceRange(sel.start, sel.end, insert);
      ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start + insert.length),
      );
      _invokeOnChanged(next);
    }

    if (key.keyType == VirtualKeyboardKeyType.String) {
      final char = (_shift ? key.capsText : key.text) ?? '';
      replace(char);
    } else if (key.keyType == VirtualKeyboardKeyType.Action) {
      switch (key.action) {
        case VirtualKeyboardKeyAction.Backspace:
          if (sel.start == sel.end && sel.start > 0) {
            final next = text.replaceRange(sel.start - 1, sel.start, '');
            ctrl.value = TextEditingValue(
              text: next,
              selection: TextSelection.collapsed(offset: sel.start - 1),
            );
            _invokeOnChanged(next);
          } else if (sel.start != sel.end) {
            final next = text.replaceRange(sel.start, sel.end, '');
            ctrl.value = TextEditingValue(
              text: next,
              selection: TextSelection.collapsed(offset: sel.start),
            );
            _invokeOnChanged(next);
          }
          break;
        case VirtualKeyboardKeyAction.Space:
          replace(' ');
          break;
        case VirtualKeyboardKeyAction.Shift:
          setState(() => _shift = !_shift);
          break;
        case VirtualKeyboardKeyAction.Return:
          _dismiss();
          break;
        default:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    // Ekran balandligiga qarab klaviatura balandligi — 220..320 oraliq.
    final kbHeight = (_numericOnly ? screenH * 0.30 : screenH * 0.36).clamp(
      220.0,
      340.0,
    );

    return Stack(
      children: [
        // Child — klaviatura ochilganda bo'sh joy qoldiramiz (content pastdan yuqoriga suriladi).
        AnimatedPadding(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: _open ? kbHeight : 0),
          child: _OutsideTapCatcher(
            enabled: _open,
            onTapOutside: _dismiss,
            child: widget.child,
          ),
        ),

        // Klaviatura — pastdan yuqoriga suriladi.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          bottom: _open ? 0 : -kbHeight - 32,
          height: kbHeight,
          child: _KeyboardPanel(
            numericOnly: _numericOnly,
            onKeyPress: _onKeyPress,
            onClose: _dismiss,
          ),
        ),
      ],
    );
  }
}

// ─── Outside-tap catcher ─────────────────────────────────────────────────────

class _OutsideTapCatcher extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback onTapOutside;

  const _OutsideTapCatcher({
    required this.child,
    required this.enabled,
    required this.onTapOutside,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // Listener + translucent: tegishli widget o'zini event bilan bajarishdan
    // so'ng bu Listener ham pointer-downni oladi va fokusni yopadi.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        // Hit-test textfield yoki button uchun birinchi ishlaydi. Shu yerda
        // yana bir kadr kutib fokus o'zgarganini tekshiramiz. Agar fokus hali
        // ham editable'da bo'lsa — demak, yangi TextField bosilgan; tegmaymiz.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final w = FocusManager.instance.primaryFocus?.context?.widget;
          if (w is! EditableText) onTapOutside();
        });
      },
      child: child,
    );
  }
}

// ─── Keyboard panel ──────────────────────────────────────────────────────────

class _KeyboardPanel extends StatelessWidget {
  final bool numericOnly;
  final ValueChanged<VirtualKeyboardKey> onKeyPress;
  final VoidCallback onClose;

  const _KeyboardPanel({
    required this.numericOnly,
    required this.onKeyPress,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag handle + close
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  _CloseBtn(onTap: onClose),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : 200.0;
                    return VirtualKeyboard(
                      height: h,
                      textColor: const Color(0xFF0F172A),
                      fontSize: 22,
                      type: numericOnly
                          ? VirtualKeyboardType.Numeric
                          : VirtualKeyboardType.Alphanumeric,
                      customLayoutKeys: VirtualKeyboardDefaultLayoutKeys([
                        VirtualKeyboardDefaultLayouts.English,
                      ]),
                      postKeyPress: onKeyPress,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseBtn extends StatefulWidget {
  final VoidCallback onTap;

  const _CloseBtn({required this.onTap});

  @override
  State<_CloseBtn> createState() => _CloseBtnState();
}

class _CloseBtnState extends State<_CloseBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE2E8F0) : Colors.white,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.keyboard_hide_outlined,
            size: 20,
            color: Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
