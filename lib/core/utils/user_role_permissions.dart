import 'package:mary_ai_pos/core/constants/constants.dart';

/// POS uchun asosiy rollar: **kassir**, **manager (admin)**, **ofitsiant**.
/// Menyu boshqaruvi faqat admin yoki manager.
extension UserRolePermissions on UserRole? {
  bool get canManageMenu =>
      this == UserRole.admin || this == UserRole.manager;

  bool get canViewAllOrders =>
      this == UserRole.admin || this == UserRole.manager;

  bool get canAccessSettings =>
      this == UserRole.admin ||
      this == UserRole.manager ||
      this == UserRole.superadmin;
}
