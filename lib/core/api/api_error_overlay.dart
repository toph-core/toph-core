import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';

/// Dio xatoliklaridagi `message` / `detail` ni overlayda ko‘rsatish.
void showApiErrorOverlayIfPossible(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF7F1D1D),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        trimmed,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                      onPressed: () {
                        if (entry.mounted) entry.remove();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (entry.mounted) entry.remove();
    });
  });
}

String messageFromDioErrorData(Object? data) {
  if (data is Map) {
    final m = data['message'] ?? data['detail'] ?? data['error'];
    if (m != null) return m.toString().trim();
  }
  if (data is String && data.trim().isNotEmpty) return data.trim();
  return '';
}
