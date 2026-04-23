import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

void showErrorMessage(BuildContext bc, String error, {int duration = 3}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AnimatedSnackBar.material(
      error,
      type: AnimatedSnackBarType.error,
      duration: const Duration(seconds: 5),
      borderRadius: BorderRadius.circular(10),
      mobilePositionSettings: const MobilePositionSettings(
        topOnAppearance: 100,
      ),
      animationDuration: const Duration(milliseconds: 600),
      desktopSnackBarPosition: DesktopSnackBarPosition.topRight,
    ).show(bc);
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

void showSuccessMessage(BuildContext bc, String success, {int duration = 3}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AnimatedSnackBar.material(
      success,
      type: AnimatedSnackBarType.success,
      duration: const Duration(seconds: 5),
      mobilePositionSettings: const MobilePositionSettings(
        topOnAppearance: 100,
      ),
      borderRadius: BorderRadius.circular(10),
      animationDuration: const Duration(milliseconds: 600),
      mobileSnackBarPosition: MobileSnackBarPosition.top,
      desktopSnackBarPosition: DesktopSnackBarPosition.topRight,
    ).show(bc);
  });
}

void showInfoMessage(BuildContext bc, String info, {int duration = 3}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AnimatedSnackBar.material(
      info,
      type: AnimatedSnackBarType.info,
      duration: const Duration(seconds: 3),
      mobilePositionSettings: const MobilePositionSettings(
        topOnAppearance: 100,
      ),
      borderRadius: BorderRadius.circular(10),
      animationDuration: const Duration(milliseconds: 600),
      mobileSnackBarPosition: MobileSnackBarPosition.top,
      desktopSnackBarPosition: DesktopSnackBarPosition.topRight,
    ).show(bc);
  });
}
