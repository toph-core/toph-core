import 'package:hive_flutter/hive_flutter.dart';

part 'privileged_action_audit_entry.g.dart';

/// One record of a manager-pincode authorization attempt — approved or
/// denied, online or offline — for a privileged action (void, shift
/// open/close). §11 Phase 6: before this, none of this was logged anywhere;
/// `requireManagerPincode` just returned a bare bool. Local-only for now —
/// no backend endpoint exists yet to submit these for server-side review
/// (confirmed: nothing audit-shaped in `ListAPI`), so this is a device-local
/// record a manager/admin can review on this terminal, not yet a synced
/// entity. Append-only: nothing here is ever deleted or edited by the app
/// itself.
@HiveType(typeId: 14)
class PrivilegedActionAuditEntry extends HiveObject {
  @HiveField(0)
  final String id;

  /// `PrivilegedAction.name` — what was being authorized.
  @HiveField(1)
  final String action;

  @HiveField(2)
  final DateTime timestamp;

  /// Whether this was approved (`true`) or denied (`false`) — a definite
  /// rejection, a wrong pincode, or an unresolvable offline lookup all count
  /// as denied; see [reason] for which.
  @HiveField(3)
  final bool approved;

  /// True if this was resolved from the offline cache rather than a live
  /// server check — the whole point of this slice being buildable at all.
  @HiveField(4)
  final bool verifiedOffline;

  /// Short machine-readable reason for a denial (e.g. `'wrong_pincode'`,
  /// `'not_manager'`, `'offline_unverified'`) — `null` when [approved].
  @HiveField(5)
  final String? reason;

  /// The manager/admin whose pincode was entered — `null` if the pincode
  /// didn't resolve to anyone at all (wrong pincode entirely, not just a
  /// non-manager).
  @HiveField(6)
  final String? approverUserId;

  @HiveField(7)
  final String? approverName;

  /// Who was performing the gated action (the currently logged-in user on
  /// this terminal) — distinct from the approver, who is very often a
  /// different person overriding on someone else's behalf.
  @HiveField(8)
  final String? requestedByUserId;

  @HiveField(9)
  final String? requestedByName;

  PrivilegedActionAuditEntry({
    required this.id,
    required this.action,
    required this.timestamp,
    required this.approved,
    required this.verifiedOffline,
    this.reason,
    this.approverUserId,
    this.approverName,
    this.requestedByUserId,
    this.requestedByName,
  });
}
