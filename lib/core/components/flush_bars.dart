import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Premium animated error toast — 4s auto-dismiss, spring slide-in from top.
// HTML belgilari tozalanadi, uzun matn qisqartiriladi.
// ─────────────────────────────────────────────────────────────────────────────

String _sanitizeErrorText(String raw) {
  var s = raw.trim();
  // HTML tags olib tashlash
  s = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
  // HTML entitylar
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');
  // Ortiqcha bo'shliqlar
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Agar "502 Bad Gateway" kabi server xatosi bo'lsa — qisqa xabar
  final low = s.toLowerCase();
  if (low.contains('bad gateway') || low.contains('502')) {
    return 'Server bilan ulanishda muammo (502). Birozdan so\'ng qayta urinib ko\'ring.';
  }
  if (low.contains('gateway timeout') || low.contains('504')) {
    return 'Server javob bermayapti (504). Internetni tekshiring.';
  }
  if (low.contains('service unavailable') || low.contains('503')) {
    return 'Xizmat vaqtincha mavjud emas (503).';
  }
  if (low.contains('internal server error') || low.contains('500')) {
    return 'Serverda ichki xatolik (500). Admin bilan bog\'laning.';
  }
  // Umumiy holat: 200 belgidan uzun bo'lsa — qisqartirish
  if (s.length > 200) return '${s.substring(0, 197)}…';
  return s;
}

void showErrorMessage(BuildContext bc, String error, {int duration = 4}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final overlay = Overlay.maybeOf(bc, rootOverlay: true);
    if (overlay == null) return;
    final sanitized = _sanitizeErrorText(error);
    _ToastController.show(
      overlay: overlay,
      message: sanitized,
      variant: _ToastVariant.error,
      autoDismissMs: duration * 1000,
    );
  });
}

/// Sarlavha + paragraflar; ikonka, yumaloq burchak, scroll.
void showStructuredErrorDismissible(
  BuildContext context, {
  required String title,
  List<String> paragraphs = const [],
  IconData icon = Icons.error_outline_rounded,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFFBE123C),
        elevation: 10,
        dismissDirection: DismissDirection.none,
        duration: const Duration(days: 365),
        showCloseIcon: true,
        closeIconColor: Colors.white,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (paragraphs.isNotEmpty) const SizedBox(height: 10),
                      for (final p in paragraphs) ...[
                        if (p.isEmpty)
                          const SizedBox(height: 6)
                        else ...[
                          Text(
                            p,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  });
}

/// X tugmasi bilan yopiladi; avtomatik yo‘qolmaydi (printer xatolari kabi).
/// Uzun matn: birinchi qator sarlavha, qolgani paragraflar sifatida.
void showErrorMessageDismissible(BuildContext context, String message) {
  final trimmed = message.trim();
  final idx = trimmed.indexOf('\n');
  if (idx <= 0) {
    showStructuredErrorDismissible(
      context,
      title: S.current.strError,
      paragraphs: trimmed.isEmpty ? const [] : [trimmed],
      icon: Icons.error_outline_rounded,
    );
    return;
  }
  final head = trimmed.substring(0, idx).trim();
  final tail = trimmed.substring(idx + 1).trim();
  final parts = tail
      .split(RegExp(r'\n\s*\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  showStructuredErrorDismissible(
    context,
    title: head.isEmpty ? S.current.strError : head,
    paragraphs: parts,
    icon: Icons.error_outline_rounded,
  );
}

void showSuccessMessage(BuildContext bc, String success, {int duration = 4}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final overlay = Overlay.maybeOf(bc, rootOverlay: true);
    if (overlay == null) return;
    _ToastController.show(
      overlay: overlay,
      message: success,
      variant: _ToastVariant.success,
      autoDismissMs: duration * 1000,
    );
  });
}

void showInfoMessage(BuildContext bc, String info, {int duration = 4}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final overlay = Overlay.maybeOf(bc, rootOverlay: true);
    if (overlay == null) return;
    _ToastController.show(
      overlay: overlay,
      message: info,
      variant: _ToastVariant.info,
      autoDismissMs: duration * 1000,
    );
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// PREMIUM TOAST WIDGET
// ═════════════════════════════════════════════════════════════════════════════

enum _ToastVariant { error, success, info }

class _ToastPalette {
  final Color bg;
  final Color border;
  final Color iconBg;
  final Color accent;
  final IconData icon;
  final String title;

  const _ToastPalette({
    required this.bg,
    required this.border,
    required this.iconBg,
    required this.accent,
    required this.icon,
    required this.title,
  });

  static _ToastPalette of(_ToastVariant v) {
    switch (v) {
      case _ToastVariant.error:
        return const _ToastPalette(
          bg: Color(0xFF1C1013),
          border: Color(0x33F87171),
          iconBg: Color(0x26F87171),
          accent: Color(0xFFF87171),
          icon: Icons.error_outline_rounded,
          title: 'Xatolik',
        );
      case _ToastVariant.success:
        return const _ToastPalette(
          bg: Color(0xFF0D1A12),
          border: Color(0x3334D399),
          iconBg: Color(0x2634D399),
          accent: Color(0xFF34D399),
          icon: Icons.check_circle_outline_rounded,
          title: 'Muvaffaqiyatli',
        );
      case _ToastVariant.info:
        return const _ToastPalette(
          bg: Color(0xFF0F1624),
          border: Color(0x3360A5FA),
          iconBg: Color(0x2660A5FA),
          accent: Color(0xFF60A5FA),
          icon: Icons.info_outline_rounded,
          title: "Ma'lumot",
        );
    }
  }
}

/// Toast'larni boshqaradigan static controller — ekranda bir nechta bo'lib ketishining
/// oldini oladi va yangisi kelganda eskisini darhol o'chiradi.
class _ToastController {
  static OverlayEntry? _currentEntry;
  static _ToastWidgetState? _currentState;

  static void show({
    required OverlayState overlay,
    required String message,
    required _ToastVariant variant,
    required int autoDismissMs,
  }) {
    // Avvalgi toast bo'lsa — darhol animatsiya bilan yopamiz
    _currentState?.dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        variant: variant,
        autoDismissMs: autoDismissMs,
        onStateCreated: (s) => _currentState = s,
        onRemoved: () {
          if (_currentEntry == entry) {
            _currentEntry = null;
            _currentState = null;
          }
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final _ToastVariant variant;
  final int autoDismissMs;
  final ValueChanged<_ToastWidgetState> onStateCreated;
  final VoidCallback onRemoved;

  const _ToastWidget({
    required this.message,
    required this.variant,
    required this.autoDismissMs,
    required this.onStateCreated,
    required this.onRemoved,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;
  late final Animation<double> _fade;
  Timer? _dismissTimer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 280),
    );
    // Custom spring-like cubic-bezier (slightly over-shoot feel)
    _slide = CurvedAnimation(
      parent: _ctrl,
      curve: const Cubic(0.22, 1.12, 0.36, 1),
      reverseCurve: const Cubic(0.4, 0, 1, 1),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    widget.onStateCreated(this);
    _ctrl.forward();
    _dismissTimer = Timer(
      Duration(milliseconds: widget.autoDismissMs),
      dismiss,
    );
  }

  Future<void> dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _dismissTimer?.cancel();
    try {
      await _ctrl.reverse();
    } catch (_) {}
    if (!mounted) return;
    widget.onRemoved();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _ToastPalette.of(widget.variant);
    final media = MediaQuery.of(context);
    // Desktop: top-right (360px max). Mobile: top-center with padding.
    final isWide = media.size.width >= 720;

    return Positioned(
      top: media.padding.top + 18,
      left: isWide ? null : 16,
      right: isWide ? 24 : 16,
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final dy = (1 - _slide.value) * -80;
            return Opacity(
              opacity: _fade.value.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: child,
              ),
            );
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 420 : double.infinity),
            child: _ToastCard(
              palette: palette,
              message: widget.message,
              onClose: dismiss,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  final _ToastPalette palette;
  final String message;
  final VoidCallback onClose;

  const _ToastCard({
    required this.palette,
    required this.message,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 14),
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 40,
              offset: const Offset(0, 20),
              spreadRadius: -12,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon pill (double-bezel: tint bg + inner highlight)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.iconBg,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: palette.border, width: 1),
              ),
              child: Icon(palette.icon, size: 20, color: palette.accent),
            ),
            const SizedBox(width: 12),
            // Title + message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    palette.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.accent,
                      fontFamily: 'Inter',
                      letterSpacing: 0.1,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFE2E8F0),
                      fontFamily: 'Inter',
                      height: 1.42,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Close X
            _ToastCloseButton(onTap: onClose),
          ],
        ),
      ),
    );
  }
}

class _ToastCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ToastCloseButton({required this.onTap});

  @override
  State<_ToastCloseButton> createState() => _ToastCloseButtonState();
}

class _ToastCloseButtonState extends State<_ToastCloseButton> {
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
          duration: const Duration(milliseconds: 140),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 16,
            color: Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}
