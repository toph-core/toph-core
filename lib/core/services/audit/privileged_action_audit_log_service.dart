import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';

import 'privileged_action_audit_entry.dart';

/// Persists every manager-pincode authorization attempt for a privileged
/// action — §11 Phase 6. Deliberately thin: `requireManagerPincode` is the
/// single call site that ever writes to this, so every privileged-action
/// gate is audited by construction rather than relying on each of its
/// callers to remember to log.
class PrivilegedActionAuditLogService {
  static const _boxName = 'privileged_action_audit_log';
  final Box<PrivilegedActionAuditEntry> _box;

  PrivilegedActionAuditLogService(this._box);

  static Future<PrivilegedActionAuditLogService> init() async {
    final box = await Hive.openBox<PrivilegedActionAuditEntry>(_boxName);
    return PrivilegedActionAuditLogService(box);
  }

  /// Newest-first — a reviewer cares about recent activity, not the oldest
  /// record.
  List<PrivilegedActionAuditEntry> get entries => _box.values.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  ValueListenable<Box<PrivilegedActionAuditEntry>> get listenable =>
      _box.listenable();

  Future<void> record({
    required PrivilegedAction action,
    required bool approved,
    required bool verifiedOffline,
    String? reason,
    String? approverUserId,
    String? approverName,
    String? requestedByUserId,
    String? requestedByName,
  }) {
    final entry = PrivilegedActionAuditEntry(
      id: _newId(),
      action: action.name,
      timestamp: DateTime.now().toUtc(),
      approved: approved,
      verifiedOffline: verifiedOffline,
      reason: reason,
      approverUserId: approverUserId,
      approverName: approverName,
      requestedByUserId: requestedByUserId,
      requestedByName: requestedByName,
    );
    return _box.put(entry.id, entry);
  }

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 31)}';
}
