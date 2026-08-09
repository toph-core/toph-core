import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/date_time_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_entry.dart';
import 'package:mary_ai_pos/core/services/audit/privileged_action_audit_log_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/leader_election_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/services/offline_queue/quarantined_operation.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_job.dart';
import 'package:mary_ai_pos/core/services/print_queue/print_queue_service.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';

/// "Real sync-status UI" — offline-first-architecture-plan.md §11 Phase 6.
/// Replaces guessing about outbox depth / cluster health / print reachability
/// with actual numbers pulled straight from the services that already track
/// them, plus manual resolution for the two places work can otherwise get
/// silently stuck: quarantined outbox operations (a definite 4xx/relay
/// rejection) and permanently-failed print jobs. The always-on `OfflineBanner`
/// /`LanSoloBanner` stay as the ambient glanceable indicator — this section is
/// the detail view for someone actually investigating a problem.
class SyncStatusSection extends StatelessWidget {
  const SyncStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      title: 'Sinxronizatsiya holati',
      subtitle: "Navbat, klaster, printer va sinxronlanmagan operatsiyalar",
      child: ListView(
        padding: EdgeInsets.zero,
        children: const [
          _OutboxCard(),
          SizedBox(height: 14),
          _LastSyncCard(),
          SizedBox(height: 14),
          _ClusterCard(),
          SizedBox(height: 14),
          _ElectionCard(),
          SizedBox(height: 14),
          _PrintQueueCard(),
          SizedBox(height: 14),
          _QuarantineCard(),
          SizedBox(height: 14),
          _AuditLogCard(),
        ],
      ),
    );
  }
}

String _typeLabel(PendingOperationType type) {
  switch (type) {
    case PendingOperationType.createOrder:
      return 'Buyurtma yaratish';
    case PendingOperationType.addItems:
      return "Mahsulot qo'shish";
    case PendingOperationType.payOrder:
      return "To'lov";
    case PendingOperationType.openShift:
      return 'Smena ochish';
    case PendingOperationType.closeShift:
      return 'Smena yopish';
    case PendingOperationType.cancelLineItems:
      return 'Pozitsiyani bekor qilish';
    case PendingOperationType.cancelOrder:
      return 'Buyurtmani bekor qilish';
    case PendingOperationType.transferTable:
      return "Stolni ko'chirish";
    case PendingOperationType.timerAction:
      return 'Stol taymeri amali';
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _CardHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textDefault,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;

  const _SmallButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = primary ? colors.buttonBrand : colors.bgSecondary;
    final fg = primary ? colors.textOnBrand : colors.textSecondary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    fontFamily: 'Inter',
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Outbox ──────────────────────────────────────────────────────────────

class _OutboxCard extends StatefulWidget {
  const _OutboxCard();

  @override
  State<_OutboxCard> createState() => _OutboxCardState();
}

class _OutboxCardState extends State<_OutboxCard> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await inject<SyncEngine>().tick(force: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = inject<OfflineQueueService>();
    final colors = context.colors;
    return ValueListenableBuilder<Box<PendingOperation>>(
      valueListenable: queue.listenable,
      builder: (context, box, _) {
        final depth = box.length;
        final attempt = queue.lastAttemptAt;
        // §12 per-op retry observability: a single stuck op is visible as a
        // high worst-case retry count even when the rest of the queue is
        // healthy.
        final maxRetries =
            box.values.fold<int>(0, (m, o) => o.retryCount > m ? o.retryCount : m);
        return SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icons.outbox_outlined,
                iconColor: depth == 0 ? colors.systemSuccess : colors.systemAccent,
                title: 'Chiquvchi navbat (outbox)',
                subtitle: depth == 0
                    ? "Barcha operatsiyalar sinxronlangan"
                    : '$depth ta operatsiya kutilmoqda'
                        '${attempt != null ? ' — oxirgi urinish ${attempt.timeAgo}' : ''}'
                        '${maxRetries > 0 ? " — eng ko'p qayta urinish: $maxRetries" : ''}',
                trailing: _SmallButton(
                  label: 'Hozir sinxronlash',
                  onTap: depth == 0 ? null : _syncNow,
                  loading: _syncing,
                  primary: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Last sync ───────────────────────────────────────────────────────────

class _LastSyncCard extends StatelessWidget {
  const _LastSyncCard();

  @override
  Widget build(BuildContext context) {
    final syncEngine = inject<SyncEngine>();
    final colors = context.colors;
    return ValueListenableBuilder<DateTime?>(
      valueListenable: syncEngine.lastSyncAt,
      builder: (context, lastSync, _) {
        return SoftCard(
          padding: const EdgeInsets.all(18),
          child: _CardHeader(
            icon: Icons.history_outlined,
            iconColor: colors.buttonBrand,
            title: 'Oxirgi sinxronizatsiya',
            subtitle: lastSync == null
                ? "Hali sinxronlanmagan"
                : "${lastSync.timeAgo} (${lastSync.toHourMinute})",
          ),
        );
      },
    );
  }
}

// ── Cluster ─────────────────────────────────────────────────────────────

class _ClusterCard extends StatelessWidget {
  const _ClusterCard();

  @override
  Widget build(BuildContext context) {
    final lanHub = inject<LanHubService>();
    final colors = context.colors;
    return StreamBuilder<LanMode>(
      stream: lanHub.onModeChanged,
      initialData: lanHub.mode,
      builder: (context, modeSnap) {
        final mode = modeSnap.data ?? lanHub.mode;
        return SoftCard(
          padding: const EdgeInsets.all(18),
          child: switch (mode) {
            LanMode.disabled => _CardHeader(
                icon: Icons.lan_outlined,
                iconColor: colors.textSecondary,
                title: 'Klaster',
                subtitle: "LAN o'chirilgan — faqat bulut orqali ishlaydi",
              ),
            LanMode.server => ValueListenableBuilder<int>(
                valueListenable: lanHub.clientCountListenable,
                builder: (context, count, _) => _CardHeader(
                  icon: Icons.dns_outlined,
                  iconColor: count > 0 ? colors.systemSuccess : colors.textSecondary,
                  title: 'Klaster — Hub',
                  subtitle: count == 0
                      ? 'Hech qanday qurilma ulanmagan'
                      : '$count ta qurilma ulangan',
                ),
              ),
            LanMode.client => StreamBuilder<bool>(
                stream: lanHub.onClientConnectionChanged,
                initialData: lanHub.isClientConnected,
                builder: (context, connSnap) {
                  final connected = connSnap.data ?? false;
                  return _CardHeader(
                    icon: Icons.wifi_outlined,
                    iconColor: connected ? colors.systemSuccess : colors.systemError,
                    title: 'Klaster — Client',
                    subtitle: connected
                        ? 'Hub ga ulangan'
                        : (lanHub.lastAuthFailReason != null
                            ? "Ulanmadi (${lanHub.lastAuthFailReason})"
                            : "Ulanmadi — qayta urinmoqda"),
                  );
                },
              ),
          },
        );
      },
    );
  }
}

// ── Leader election (BACKEND_SYNC_PLAN.md §7) ───────────────────────────

/// The enable path LeaderElectionService never had: a per-venue toggle,
/// default OFF, wired straight to [LeaderElectionService.setEnabled] (which
/// starts/stops the service immediately, no restart needed). Per the plan's
/// own rollout discipline this should be flipped on at a pilot
/// multi-terminal venue first, not globally — the toggle governs which
/// terminal thinks it's the LAN leader.
class _ElectionCard extends StatefulWidget {
  const _ElectionCard();

  @override
  State<_ElectionCard> createState() => _ElectionCardState();
}

class _ElectionCardState extends State<_ElectionCard> {
  final _election = inject<LeaderElectionService>();
  bool _busy = false;

  String _roleLabel(ElectionRole role) => switch (role) {
        ElectionRole.idle => "O'chirilgan",
        ElectionRole.follower => 'Follower — yetakchini kuzatmoqda',
        ElectionRole.candidate => 'Saylov ketmoqda…',
        ElectionRole.leader => 'Bu terminal yetakchi',
      };

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _election.setEnabled(value);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: StreamBuilder<ElectionRole>(
        stream: _election.onRoleChanged,
        initialData: _election.role,
        builder: (context, snap) {
          final role = snap.data ?? ElectionRole.idle;
          final enabled = _election.isEnabled;
          return Row(
            children: [
              Expanded(
                child: _CardHeader(
                  icon: Icons.how_to_vote_outlined,
                  iconColor: role == ElectionRole.leader
                      ? colors.systemSuccess
                      : colors.textSecondary,
                  title: 'Avtomatik yetakchi saylovi',
                  subtitle: enabled
                      ? _roleLabel(role)
                      : "O'chirilgan — LAN rejimi qo'lda boshqariladi",
                ),
              ),
              Switch(
                value: enabled,
                onChanged: _busy ? null : _toggle,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Print queue ─────────────────────────────────────────────────────────

class _PrintQueueCard extends StatelessWidget {
  const _PrintQueueCard();

  @override
  Widget build(BuildContext context) {
    final printQueue = inject<PrintQueueService>();
    final colors = context.colors;
    return ValueListenableBuilder<Box<PrintJob>>(
      valueListenable: printQueue.listenable,
      builder: (context, box, _) {
        final queued = printQueue.queuedCount;
        final claimed = printQueue.claimedCount;
        final failed = printQueue.failedCount;
        final failedJobs = printQueue.jobs
            .where((j) => j.stateEnum == PrintJobState.failed)
            .toList();
        return SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icons.print_outlined,
                iconColor: failed > 0 ? colors.systemError : colors.buttonBrand,
                title: 'Chop etish navbati',
                subtitle: 'Kutilmoqda: $queued · Egallangan: $claimed · Xato: $failed',
              ),
              if (failedJobs.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(color: colors.border, height: 1),
                const SizedBox(height: 10),
                ...failedJobs.map((job) => _FailedPrintJobRow(job: job)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FailedPrintJobRow extends StatefulWidget {
  final PrintJob job;
  const _FailedPrintJobRow({required this.job});

  @override
  State<_FailedPrintJobRow> createState() => _FailedPrintJobRowState();
}

class _FailedPrintJobRowState extends State<_FailedPrintJobRow> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await inject<PrintQueueService>().retryFailedJob(widget.job.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _busy = true);
    await inject<PrintQueueService>().dismissFailedJob(widget.job.id);
    // No `if (mounted) setState` needed after this — the row disappears
    // entirely once the box notifies (this widget gets disposed by the
    // parent's ValueListenableBuilder rebuild), same as _QuarantineRow.
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final job = widget.job;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.jobType} · ${job.createdAt.timeAgo}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                if (job.lastError != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    job.lastError!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.systemError,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(label: 'Qayta urinish', onTap: _retry, loading: _busy, primary: true),
          const SizedBox(width: 6),
          _SmallButton(label: "O'chirish", onTap: _dismiss, loading: _busy),
        ],
      ),
    );
  }
}

// ── Quarantine ──────────────────────────────────────────────────────────

class _QuarantineCard extends StatelessWidget {
  const _QuarantineCard();

  @override
  Widget build(BuildContext context) {
    final queue = inject<OfflineQueueService>();
    final colors = context.colors;
    return ValueListenableBuilder<Box<QuarantinedOperation>>(
      valueListenable: queue.quarantineListenable,
      builder: (context, box, _) {
        final items = queue.quarantined;
        return SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icons.report_gmailerrorred_outlined,
                iconColor: items.isEmpty ? colors.buttonBrand : colors.systemError,
                title: 'Karantin',
                subtitle: items.isEmpty
                    ? "Rad etilgan operatsiyalar yo'q"
                    : '${items.length} ta operatsiya serverdan rad etilgan',
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(color: colors.border, height: 1),
                const SizedBox(height: 10),
                ...items.map((op) => _QuarantineRow(op: op)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QuarantineRow extends StatefulWidget {
  final QuarantinedOperation op;
  const _QuarantineRow({required this.op});

  @override
  State<_QuarantineRow> createState() => _QuarantineRowState();
}

class _QuarantineRowState extends State<_QuarantineRow> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await inject<OfflineQueueService>().retryQuarantined(widget.op.id);
  }

  Future<void> _dismiss() async {
    setState(() => _busy = true);
    await inject<OfflineQueueService>().dismissQuarantined(widget.op.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final op = widget.op;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_typeLabel(op.type)} · stol ${op.tableId.isEmpty ? '—' : op.tableId} · ${op.quarantinedAt.timeAgo}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  op.reason,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.systemError,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(label: 'Qayta urinish', onTap: _retry, loading: _busy, primary: true),
          const SizedBox(width: 6),
          _SmallButton(label: "O'chirish", onTap: _dismiss, loading: _busy),
        ],
      ),
    );
  }
}

// ── Privileged-action audit log ────────────────────────────────────────

String _actionLabel(String actionName) {
  for (final action in PrivilegedAction.values) {
    if (action.name != actionName) continue;
    switch (action) {
      case PrivilegedAction.shiftOpen:
        return 'Smena ochish';
      case PrivilegedAction.shiftClose:
        return 'Smena yopish';
      case PrivilegedAction.voidOrderItem:
        return 'Pozitsiyani bekor qilish';
    }
  }
  return actionName;
}

String? _denialReasonLabel(String? reason) {
  switch (reason) {
    case 'offline_unverified':
      return "bu pincode hech qachon online tekshirilmagan";
    case 'not_manager':
      return "manager/admin emas";
    case 'verification_failed':
      return "tekshiruv muvaffaqiyatsiz";
    default:
      return reason;
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard();

  @override
  Widget build(BuildContext context) {
    final auditLog = inject<PrivilegedActionAuditLogService>();
    final colors = context.colors;
    return ValueListenableBuilder<Box<PrivilegedActionAuditEntry>>(
      valueListenable: auditLog.listenable,
      builder: (context, box, _) {
        // Newest-first, capped — this is a glance-back list, not a full
        // export/review tool (no backend endpoint exists yet to submit
        // these for real off-device review — see the service's own doc
        // comment).
        final items = auditLog.entries.take(10).toList();
        return SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icons.fact_check_outlined,
                iconColor: colors.buttonBrand,
                title: 'Imtiyozli amallar jurnali',
                subtitle: items.isEmpty
                    ? "Hali hech qanday urinish qayd etilmagan"
                    : '${auditLog.entries.length} ta yozuv (oxirgi ${items.length} tasi)',
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(color: colors.border, height: 1),
                const SizedBox(height: 10),
                ...items.map((e) => _AuditLogRow(entry: e)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  final PrivilegedActionAuditEntry entry;
  const _AuditLogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = entry.approved ? colors.systemSuccess : colors.systemError;
    final denialLabel = _denialReasonLabel(entry.reason);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            entry.approved ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 16,
            color: statusColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_actionLabel(entry.action)} · ${entry.timestamp.timeAgo}'
                  '${entry.verifiedOffline ? ' · offline' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.approved
                      ? "Tasdiqladi: ${entry.approverName ?? '—'}"
                          "${entry.requestedByName != null ? ' (so\'ragan: ${entry.requestedByName})' : ''}"
                      : "Rad etildi${denialLabel != null ? ' — $denialLabel' : ''}"
                          "${entry.requestedByName != null ? ' (so\'ragan: ${entry.requestedByName})' : ''}",
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
