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

  /// Smenani ko'rish/ochish/yopish huquqi — kassir, manager va admin.
  bool get canManageShift =>
      this == UserRole.cashier ||
      this == UserRole.manager ||
      this == UserRole.admin ||
      this == UserRole.superadmin;

  bool get canPrintReceipt =>
      this == UserRole.cashier ||
      this == UserRole.manager ||
      this == UserRole.admin ||
      this == UserRole.superadmin;

  /// Kassa tranzaksiyalari (kirim/chiqim/o'tkazma) va kategoriyalarini
  /// ko'rish/boshqarish huquqi — kassir, manager va admin.
  bool get canManageTransactions =>
      this == UserRole.cashier ||
      this == UserRole.manager ||
      this == UserRole.admin;

  /// Manager/admin PIN bilan tasdiqlash talab qilinadigan amallar uchun
  /// (masalan, tasdiqlangan order-item'ni bekor qilish) ruxsat tekshiruvi.
  bool get isManagerOrAdmin =>
      this == UserRole.manager ||
      this == UserRole.admin ||
      this == UserRole.superadmin;
}
