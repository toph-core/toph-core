import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
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

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  static const _bgRefreshInterval = Duration(seconds: 30);

  late final ArchivesBloc _bloc;
  Timer? _bgRefreshTimer;

  @override
  void initState() {
    super.initState();
    _bloc = inject<ArchivesBloc>()..add(const ArchivesEvent.started());
    _bgRefreshTimer = Timer.periodic(_bgRefreshInterval, (_) {
      if (inject<ConnectivityCubit>().isOnline && mounted) {
        _bloc.add(const ArchivesEvent.getArchived(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _bgRefreshTimer?.cancel();
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

              final openCount = archives
                  .where(
                    (a) =>
                        a.status == OrderStatus.open ||
                        a.status == OrderStatus.opened,
                  )
                  .length;
              final revenue = archives.fold<int>(
                0,
                (sum, a) => sum + a.totalPrice,
              );
              final avgCheck = archives.isNotEmpty
                  ? revenue ~/ archives.length
                  : 0;

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
                      count: archives.length,
                      revenue: revenue,
                      openCount: openCount,
                      avgCheck: avgCheck,
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
                              onSelect: (id) => context
                                  .read<ArchivesBloc>()
                                  .add(ArchivesEvent.selectArchive(id: id)),
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

class _ArchiveTable extends StatelessWidget {
  final List<ArchiveEntity> archives;
  final String? selectedId;
  final bool isLoading;
  final ValueChanged<String> onSelect;

  const _ArchiveTable({
    required this.archives,
    required this.selectedId,
    required this.isLoading,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
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
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                const _ThCell(label: '#', flex: 2),
                _ThCell(label: S.current.strTimeColumnHeader, flex: 2),
                _ThCell(label: S.current.strTypeColumnHeader, flex: 2),
                const _ThCell(label: 'Stol', flex: 1),
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
                    itemCount: archives.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF1F5F9),
                    ),
                    itemBuilder: (context, i) => _ArchiveRow(
                      key: ValueKey(archives[i].id),
                      archive: archives[i],
                      isSelected: selectedId == archives[i].id,
                      onTap: () => onSelect(archives[i].id),
                    ),
                  ),
          ),
        ],
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

  static const _filterLabels = ['Hammasi', 'Bugun', 'Hafta', 'Oy'];

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
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              spacing: 0,
              children: List.generate(state.filters.length, (i) {
                final isActive = state.filterType == state.filters[i];
                return GestureDetector(
                  onTap: () => context.read<ArchivesBloc>().add(
                    ArchivesEvent.updateFilterType(type: state.filters[i]),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                      _filterLabels[i],
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
              }),
            ),
          ),
          const Spacer(),
          _DateRangeButton(state: state),
          if (role.canViewAllOrders)
            _ExportCsvButton(archives: state.archives?.archives ?? const []),
        ],
      ),
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  final ArchivesState state;
  const _DateRangeButton({required this.state});

  bool get _isActive => state.filterType == ArchivesFilterType.date;

  String get _label {
    if (!_isActive || state.startFilterDate == null) return 'Sana';
    final s = state.startFilterDate!;
    final e = state.endFilterDate;
    final start =
        '${s.day.toString().padLeft(2, '0')}.${s.month.toString().padLeft(2, '0')}';
    if (e == null || (e.day == s.day && e.month == s.month && e.year == s.year)) {
      return start;
    }
    final end =
        '${e.day.toString().padLeft(2, '0')}.${e.month.toString().padLeft(2, '0')}';
    return '$start — $end';
  }

  Future<void> _pick(BuildContext context) async {
    final bloc = context.read<ArchivesBloc>();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: state.startFilterDate ?? DateTime.now(),
        end: state.endFilterDate ?? DateTime.now(),
      ),
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

  void _clear(BuildContext context) {
    context.read<ArchivesBloc>().add(
          const ArchivesEvent.updateFilterType(type: ArchivesFilterType.All),
        );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 48,
      decoration: BoxDecoration(
        color: _isActive ? const Color(0xFFFFF3EE) : Colors.white,
        border: Border.all(
          color: _isActive ? const Color(0xFFFB6633) : const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _pick(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: _isActive
                        ? const Color(0xFFFB6633)
                        : const Color(0xFF64748B),
                  ),
                  Text(
                    _label,
                    style: TextStyle(
                      fontSize: PosTypography.bodyMd,
                      fontWeight: _isActive ? FontWeight.w600 : FontWeight.w400,
                      color: _isActive
                          ? const Color(0xFFFB6633)
                          : const Color(0xFF64748B),
                      fontFamily: PosTypography.family,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isActive) ...[
            Container(
              width: 1,
              height: 18,
              color: const Color(0xFFFB6633).withValues(alpha: 0.3),
            ),
            GestureDetector(
              onTap: () => _clear(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFFB6633),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExportCsvButton extends StatelessWidget {
  final List<ArchiveEntity> archives;
  const _ExportCsvButton({required this.archives});

  void _export(BuildContext context) {
    final buffer = StringBuffer()..writeln('#,Stol,Holat,Taomlar,Summa,Vaqt');
    for (final a in archives) {
      final time = a.opened != null
          ? '${a.opened!.year}-${a.opened!.month.toString().padLeft(2, '0')}-${a.opened!.day.toString().padLeft(2, '0')} '
                '${a.opened!.hour.toString().padLeft(2, '0')}:${a.opened!.minute.toString().padLeft(2, '0')}'
          : '';
      buffer.writeln(
        '${a.bilNumber},${a.tableNumber},${a.status.name},${a.goodsQuantity},${a.totalPrice},$time',
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
    final enabled = archives.isNotEmpty;
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
    final time = archive.opened != null
        ? '${archive.opened!.hour.toString().padLeft(2, '0')}:${archive.opened!.minute.toString().padLeft(2, '0')}'
        : '-';
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _TypeChip(isTakeaway: isTakeaway),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
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
                      : Container(
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
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    archive.totalPrice.formatN,
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
          Icon(
            Icons.restaurant_outlined,
            size: 13,
            color: Color(0xFF475569),
          ),
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
