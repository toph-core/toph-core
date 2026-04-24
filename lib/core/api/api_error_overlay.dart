import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';

/// Dio xatoliklaridagi `message` / `detail` ni premium toast orqali ko'rsatish.
/// `flush_bars.dart` ichidagi yagona toast controller orqali ketadi —
/// boshqa joylardagi xatolar bilan bir xil dizayn, ekranda bittadan ortiq
/// toast bo'lib ketishining oldini oladi.
void showApiErrorOverlayIfPossible(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return;
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  // API xatolarini 6s ko'rsatamiz — default 4s dan uzunroq, foydalanuvchi o'qib ulgursin.
  showErrorMessage(ctx, trimmed, duration: 6);
}

String messageFromDioErrorData(Object? data) {
  if (data is Map) {
    final m = data['message'] ?? data['detail'] ?? data['error'];
    if (m != null) return m.toString().trim();
  }
  if (data is String && data.trim().isNotEmpty) return data.trim();
  return '';
}
