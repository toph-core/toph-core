import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/date_time_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/utils/order_localizations.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/archive/widgets/archive_right_sider_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

// Open bills haven't been paid yet, so their persisted `grand_total`
// doesn't include the running table charge (only finalized at payment) —
// add it back in for display. Closed/paid bills already have it baked in.
int _archiveDisplayTotal(ArchiveEntity a) {
  final isOpen =
      a.status == OrderStatus.open ||
      a.status == OrderStatus.opened ||
      a.status == OrderStatus.pending;
  return isOpen ? a.totalPrice + a.tableAmount : a.totalPrice;
}

String _fmtHm(DateTime? dt) => dt != null
    ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
    : '-';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  late final ArchivesBloc _bloc;

  @override
  void initState() {
    super.initState();
    // §8 Phase 6/V8 — no `Timer.periodic` silent refresh here, and no fetch:
    // `ArchivesBloc` subscribes to the replica and re-queries it whenever
    // replication changes a row (see `archives_bloc.dart`).
    _bloc = inject<ArchivesBloc>()..add(const ArchivesEvent.started());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select((UserBloc b) => b.state.userMOdel?.role);
    return AppScaffold(
      activeRoute: AppRoutes.archiveScreen,
      body: BlocProvider.value(
        value: _bloc,
        child: _ArchiveBody(role: role),
      ),
    );
  }
}

class _ArchiveBody extends StatelessWidget {
  final UserRole? role;
  const _ArchiveBody({required this.role});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MainHeader(title: S.current.strArchive),
        Expanded(
          child: BlocBuilder<ArchivesBloc, ArchivesState>(
            builder: (context, state) {
              final archives = state.archives?.archives ?? [];

              // Straight off `ArchivesQuery.summary`, which aggregates the
              // whole filtered window in SQL. These used to be folded out of
              // `archives` — the rows the list happened to be holding — so a
              // shift with more bills than one page reported the count and
              // revenue of a page, and the number a cashier reconciles a till
              // against moved as they scrolled.
              final summary = state.summary;

              final horizontal = PosBreakpoints.pick<double>(
                context,
                compact: PosDimensions.l,
                comfortable: PosDimensions.xxl,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ArchiveFilterBar(state: state, role: role),
                  Padding(
                    padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 14),
                    child: _InlineStatsRow(
                      count: summary.count,
                      revenue: summary.revenue,
                      openCount: summary.openCount,
                      avgCheck: summary.avgCheck,
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        12,
                        horizontal,
                        PosDimensions.l,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 16,
                        children: [
                          Expanded(
                            child: _ArchiveTable(
                              archives: archives,
                              selectedId: state.selectArchive?.id,
                              isLoading: state.status == Status.LOADING,
                              hasMore: state.hasMore,
                              isLoadingMore: state.isLoadingMore,
                              onSelect: (id) => context
                                  .read<ArchivesBloc>()
                                  .add(ArchivesEvent.selectArchive(id: id)),
                              onLoadMore: () => context
                                  .read<ArchivesBloc>()
                                  .add(const ArchivesEvent.loadMore()),
                            ),
                          ),
                          SizedBox(
                            width: 420,
                            child: ArchiveRightSiderBar(role: role),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InlineStatsRow extends StatelessWidget {
  final int count;
  final int revenue;
  final int openCount;
  final int avgCheck;

  const _InlineStatsRow({
    required this.count,
    required this.revenue,
    required this.openCount,
    required this.avgCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Metric(
          label: S.current.strOrders,
          value: '$count',
          unit: 'ta',
          valueColor: const Color(0xFF0F172A),
        ),
        const _MetricDivider(),
        _Metric(
          label: S.current.strUmumiySumma,
          value: revenue.formatNWithoutS,
          unit: "so'm",
          valueColor: const Color(0xFF16A34A),
        ),
        const _MetricDivider(),
        _Metric(
          label: S.current.strOpenBills,
          value: '$openCount',
          unit: 'aktiv',
          valueColor: const Color(0xFFFB6633),
        ),
        const _MetricDivider(),
        _Metric(
          label: S.current.strAverageCheck,
          value: avgCheck.formatNWithoutS,
          unit: "so'm",
          valueColor: const Color(0xFF2563EB),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color valueColor;

  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                    fontFamily: 'Inter',
                    letterSpacing: -0.5,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFE2E8F0),
    );
  }
}

class _ArchiveTable extends StatefulWidget {
  final List<ArchiveEntity> archives;
  final String? selectedId;
  final bool isLoading;

  /// The window holds bills this list has not asked for yet.
  final bool hasMore;

  /// A load is in flight — the footer shows it, and [onLoadMore] is not
  /// dispatched again until it lands.
  final bool isLoadingMore;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;

  const _ArchiveTable({
    required this.archives,
    required this.selectedId,
    required this.isLoading,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onSelect,
    required this.onLoadMore,
  });

  @override
  State<_ArchiveTable> createState() => _ArchiveTableState();
}

class _ArchiveTableState extends State<_ArchiveTable> {
  final _controller = ScrollController();

  /// How close to the end counts as "reached the end". A few rows' worth, so
  /// the next page is already loading by the time the operator gets there.
  static const _prefetchExtent = 400.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.hasMore || widget.isLoadingMore) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - _prefetchExtent) {
      widget.onLoadMore();
    }
  }

  /// A window short enough not to scroll still has to be able to grow —
  /// otherwise a filter whose first page happens to fit on screen would strand
  /// the rest of its bills with no gesture to reach them.
  void _loadMoreIfNotScrollable() {
    if (!widget.hasMore || widget.isLoadingMore) return;
    if (!_controller.hasClients) return;
    if (_controller.position.maxScrollExtent == 0) widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final archives = widget.archives;
    final isLoading = widget.isLoading;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadMoreIfNotScrollable(),
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const _ThCell(label: '#', flex: 2),
                _ThCell(label: S.current.strTimeColumnHeader, flex: 2),
                _ThCell(label: S.current.strClosedColumnHeader, flex: 2),
                _ThCell(label: S.current.strTypeColumnHeader, flex: 2),
                const _ThCell(label: 'Stol', flex: 2),
                _ThCell(label: S.current.strAmountColumnHeader, flex: 3),
                _ThCell(label: S.current.strStatusColumnHeader, flex: 2),
              ],
            ),
          ),
          Expanded(
            child: isLoading && archives.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : archives.isEmpty
                ? _EmptyState()
                : ListView.separated(
                    controller: _controller,
                    // One extra slot for the footer: the "loading more"
                    // indicator while the window grows, and nothing once
                    // every bill in the window is on screen.
                    itemCount: archives.length + (widget.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF1F5F9),
                    ),
                    itemBuilder: (context, i) {
                      if (i >= archives.length) return const _LoadingMoreRow();
                      return _ArchiveRow(
                        key: ValueKey(archives[i].id),
                        archive: archives[i],
                        isSelected: widget.selectedId == archives[i].id,
                        onTap: () => widget.onSelect(archives[i].id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The list's footer while the next page of bills is being read.
class _LoadingMoreRow extends StatelessWidget {
  const _LoadingMoreRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 26,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            S.current.strArchiveEmpty,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tanlangan davrda buyurtmalar topilmadi',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveFilterBar extends StatelessWidget {
  final ArchivesState state;
  final UserRole? role;
  const _ArchiveFilterBar({required this.state, required this.role});

  @override
  Widget build(BuildContext context) {
    final horizontal = PosBreakpoints.pick<double>(
      context,
      compact: PosDimensions.l,
      comfortable: PosDimensions.xxl,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 12),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: PosBreakpoints.pick<double>(
              context,
              compact: 220,
              comfortable: 260,
            ),
            height: 48,
            child: TextField(
              controller: state.textController,
              onTap: () => AppScaffold.open(
                state.textController!,
                onChanged: (v) => context.read<ArchivesBloc>().add(
                  ArchivesEvent.searchByArchiveNum(v),
                ),
              ),
              decoration: InputDecoration(
                hintText: S.current.strSearchTableOrCheck,
                hintStyle: const TextStyle(
                  fontSize: PosTypography.bodyMd,
                  color: Color(0xFF94A3B8),
                  fontFamily: PosTypography.family,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Color(0xFF94A3B8),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
                  borderSide: const BorderSide(color: Color(0xFFFB6633)),
                ),
              ),
              style: const TextStyle(
                fontSize: PosTypography.bodyMd,
                fontFamily: PosTypography.family,
                color: Color(0xFF0F172A),
              ),
              onChanged: (v) => context.read<ArchivesBloc>().add(
                ArchivesEvent.searchByArchiveNum(v),
              ),
            ),
          ),
          _PeriodFilterBar(state: state),
          _StatusFilterRow(state: state),
          const Spacer(),
          if (role.canViewAllOrders)
            _ExportCsvButton(count: state.summary.count),
        ],
      ),
    );
  }
}

/// Bill-status filter rendered as a row of selectable chips (not a
/// dropdown) — every option is visible and reachable in one tap.
class _StatusFilterRow extends StatelessWidget {
  final ArchivesState state;
  const _StatusFilterRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String)>[
      (null, S.current.all),
      ('opened', localizedOrderStatus(context, 'opened')),
      ('closed', localizedOrderStatus(context, 'closed')),
      ('paid', localizedOrderStatus(context, 'paid')),
    ];

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 0,
        children: options.map((o) {
          final isActive = state.statusFilter == o.$1;
          return GestureDetector(
            onTap: () => context.read<ArchivesBloc>().add(
              ArchivesEvent.updateStatusFilter(status: o.$1),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                o.$2,
                style: TextStyle(
                  fontSize: PosTypography.bodyMd,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF64748B),
                  fontFamily: PosTypography.family,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Compact "FROM … → TO …" range display (tap opens the calendar — no
/// icon, since the tap target itself is the affordance) paired with a
/// D/W/M/Y quick-range toggle.
class _PeriodFilterBar extends StatelessWidget {
  final ArchivesState state;
  const _PeriodFilterBar({required this.state});

  DateTimeRange get _range {
    final now = DateTime.now();
    switch (state.filterType) {
      case ArchivesFilterType.Today:
        return DateTimeRange(
          start: now.subtract(const Duration(hours: 24)),
          end: now,
        );
      case ArchivesFilterType.Week:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case ArchivesFilterType.month:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
      case ArchivesFilterType.Year:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 365)),
          end: now,
        );
      case ArchivesFilterType.date:
      case ArchivesFilterType.All:
        return DateTimeRange(
          start: state.startFilterDate ?? now,
          end: state.endFilterDate ?? now,
        );
    }
  }

  Future<void> _pick(BuildContext context) async {
    final bloc = context.read<ArchivesBloc>();
    final current = _range;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: current.start, end: current.end),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: const Color(0xFFFB6633),
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFB6633),
            ),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 580),
            child: child,
          ),
        ),
      ),
    );
    if (picked != null) {
      bloc.add(
        ArchivesEvent.updateFilterDateRange(
          startDate: picked.start,
          endDate: picked.end,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final presets = <(ArchivesFilterType, String)>[
      (ArchivesFilterType.Today, S.current.strPeriodDay),
      (ArchivesFilterType.Week, S.current.strPeriodWeek),
      (ArchivesFilterType.month, S.current.strPeriodMonth),
      (ArchivesFilterType.Year, S.current.strPeriodYear),
    ];
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pick(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  _DateChunk(label: S.current.strFrom, date: range.start),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  _DateChunk(label: S.current.strTo, date: range.end),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFFE2E8F0),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: presets.map((p) {
              final isActive = state.filterType == p.$1;
              return GestureDetector(
                onTap: () => context.read<ArchivesBloc>().add(
                  ArchivesEvent.updateFilterType(type: p.$1),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFFB6633)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    p.$2,
                    style: TextStyle(
                      fontSize: PosTypography.bodyMd,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : const Color(0xFF64748B),
                      fontFamily: PosTypography.family,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DateChunk extends StatelessWidget {
  final String label;
  final DateTime date;
  const _DateChunk({required this.label, required this.date});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
            fontFamily: PosTypography.family,
            letterSpacing: 0.4,
          ),
        ),
        Text(
          date.toYyyyMmDd,
          style: const TextStyle(
            fontSize: PosTypography.bodySm,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
            fontFamily: PosTypography.family,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ExportCsvButton extends StatelessWidget {
  /// Only used to decide whether the button is live — the rows themselves are
  /// read from the bloc at press time, so the file holds the whole window and
  /// not just the part that has been scrolled into the list.
  final int count;
  const _ExportCsvButton({required this.count});

  Future<void> _export(BuildContext context) async {
    final archives = await context.read<ArchivesBloc>().archivesInWindow();
    if (!context.mounted || archives.isEmpty) return;
    final buffer = StringBuffer()..writeln('#,Stol,Holat,Taomlar,Summa,Vaqt');
    for (final a in archives) {
      final time = a.opened != null
          ? '${a.opened!.year}-${a.opened!.month.toString().padLeft(2, '0')}-${a.opened!.day.toString().padLeft(2, '0')} '
                '${a.opened!.hour.toString().padLeft(2, '0')}:${a.opened!.minute.toString().padLeft(2, '0')}'
          : '';
      buffer.writeln(
        '${a.bilNumber},${a.tableNumber},${a.status.name},${a.goodsQuantity},${_archiveDisplayTotal(a)},$time',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    showInfoMessage(
      context,
      'CSV clipboard\'ga nusxalandi · ${archives.length} ta',
      duration: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    return GestureDetector(
      onTap: enabled ? () => _export(context) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: PosDimensions.l),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.file_download_outlined,
              size: 18,
              color: enabled
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Text(
              'Eksport CSV',
              style: TextStyle(
                fontSize: PosTypography.bodyMd,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF94A3B8),
                fontFamily: PosTypography.family,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThCell extends StatelessWidget {
  final String label;
  final int flex;
  const _ThCell({required this.label, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            fontFamily: 'Inter',
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _ArchiveRow extends StatefulWidget {
  final ArchiveEntity archive;
  final bool isSelected;
  final VoidCallback onTap;

  const _ArchiveRow({
    super.key,
    required this.archive,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final archive = widget.archive;
    final time = _fmtHm(archive.opened);
    final closedTime = _fmtHm(archive.closed);
    final isTakeaway = archive.tableNumber == 0;

    final bg = widget.isSelected
        ? const Color(0xFFFFF3EE)
        : _hover
        ? const Color(0xFFF8FAFC)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            border: widget.isSelected
                ? const Border(
                    left: BorderSide(color: Color(0xFFFB6633), width: 4),
                  )
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '#${archive.bilNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.isSelected
                          ? const Color(0xFFFB6633)
                          : const Color(0xFF0F172A),
                      fontFamily: 'Inter',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontFamily: 'Inter',
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    closedTime,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontFamily: 'Inter',
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _TypeChip(isTakeaway: isTakeaway),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: isTakeaway
                      ? const Text(
                          '—',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                            fontFamily: 'Inter',
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${archive.tableNumber}',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                            if (archive.hallName.trim().isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  archive.hallName.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    _archiveDisplayTotal(archive).formatN,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      fontFamily: 'Inter',
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(status: archive.status),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final bool isTakeaway;
  const _TypeChip({required this.isTakeaway});

  @override
  Widget build(BuildContext context) {
    if (isTakeaway) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3EE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFB6633).withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 13,
              color: Color(0xFFFB6633),
            ),
            SizedBox(width: 6),
            Text(
              'Olib ketish',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFB6633),
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_outlined, size: 13, color: Color(0xFF475569)),
          SizedBox(width: 6),
          Text(
            'Zalda',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String key;

    switch (status) {
      case OrderStatus.open:
      case OrderStatus.opened:
      case OrderStatus.pending:
        bg = const Color(0xFFFFF3EE);
        fg = const Color(0xFFFB6633);
        key = 'open';
      case OrderStatus.closed:
      case OrderStatus.paid:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        key = status == OrderStatus.paid ? 'paid' : 'closed';
      case OrderStatus.deleted:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        key = 'cancelled';
      default:
        bg = const Color(0xFFF8FAFC);
        fg = const Color(0xFF64748B);
        key = '';
    }
    final label = '● ${key.isEmpty ? '—' : localizedOrderStatus(context, key)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}
