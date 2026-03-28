import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/archive/widgets/archive_right_sider_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      activeRoute: AppRoutes.archiveScreen,
      body: BlocProvider(
        create: (context) =>
            inject<ArchivesBloc>()..add(const ArchivesEvent.started()),
        child: const _ArchiveBody(),
      ),
    );
  }
}

class _ArchiveBody extends StatelessWidget {
  const _ArchiveBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MainHeader(title: 'Arxiv'),
        Expanded(
          child: BlocBuilder<ArchivesBloc, ArchivesState>(
            builder: (context, state) {
              final archives = state.archives?.archives ?? [];

              // Stats derived from loaded data
              final openCount = archives
                  .where(
                    (a) =>
                        a.status == OrderStatus.open ||
                        a.status == OrderStatus.opened,
                  )
                  .length;
              final closedCount = archives
                  .where(
                    (a) =>
                        a.status == OrderStatus.closed ||
                        a.status == OrderStatus.paid,
                  )
                  .length;
              final revenue = archives.fold<int>(
                0,
                (sum, a) => sum + a.totalPrice,
              );
              final avgCheck =
                  archives.isNotEmpty ? revenue ~/ archives.length : 0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Row(
                      spacing: 16,
                      children: [
                        _StatCard(
                          label: 'Ochiq hisoblar',
                          value: '$openCount',
                          sub: 'Hozir aktiv',
                          valueColor: const Color(0xFFFB6633),
                        ),
                        _StatCard(
                          label: "Bugungi tushum",
                          value: revenue.formatNWithoutS,
                          sub: "so'm",
                        ),
                        _StatCard(
                          label: 'Bugun yopildi',
                          value: '$closedCount',
                          sub: 'hisob',
                          valueColor: const Color(0xFF13AF1B),
                        ),
                        _StatCard(
                          label: "O'rtacha chek",
                          value: avgCheck.formatNWithoutS,
                          sub: "so'm",
                        ),
                      ],
                    ),
                  ),

                  // Filter bar
                  _ArchiveFilterBar(state: state),

                  // Table + optional detail sidebar
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 16,
                        children: [
                          // Table
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFEBEFF2),
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Table header
                                  Container(
                                    height: 40,
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Color(0xFFEBEFF2),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        _ThCell(label: '#', flex: 2),
                                        _ThCell(label: 'Stol', flex: 1),
                                        _ThCell(label: 'Holat', flex: 2),
                                        _ThCell(label: 'Taomlar', flex: 1),
                                        _ThCell(label: 'Summa', flex: 3),
                                        _ThCell(label: 'Vaqt', flex: 2),
                                        _ThCell(label: 'Amallar', flex: 2),
                                      ],
                                    ),
                                  ),
                                  // Table body
                                  Expanded(
                                    child: state.status == Status.LOADING &&
                                            archives.isEmpty
                                        ? const Center(
                                            child: CircularProgressIndicator
                                                .adaptive(),
                                          )
                                        : archives.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Arxiv topilmadi',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFF888888),
                                                fontFamily: 'Inter',
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: archives.length,
                                            itemBuilder: (context, i) =>
                                                _ArchiveRow(
                                                  archive: archives[i],
                                                  isSelected:
                                                      state.selectArchive
                                                          ?.id ==
                                                      archives[i].id,
                                                  onTap: () =>
                                                      context
                                                          .read<ArchivesBloc>()
                                                          .add(
                                                            ArchivesEvent
                                                                .selectArchive(
                                                                  id: archives[i]
                                                                      .id,
                                                                ),
                                                          ),
                                                ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Right sidebar (shown when archive selected)
                          if (state.selectArchive != null)
                            const SizedBox(
                              width: 300,
                              child: ArchiveRightSiderBar(),
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

class _ArchiveFilterBar extends StatelessWidget {
  final ArchivesState state;
  const _ArchiveFilterBar({required this.state});

  static const _filterLabels = ['Hammasi', 'Bugun', 'Hafta', 'Oy'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        spacing: 10,
        children: [
          // Search
          SizedBox(
            width: 260,
            height: 36,
            child: TextField(
              controller: state.textController,
              decoration: InputDecoration(
                hintText: 'Stol, chek raqami...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFAAAAAA),
                  fontFamily: 'Inter',
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFFAAAAAA),
                ),
                filled: true,
                fillColor: const Color(0xFFF5F4F2),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFB6633)),
                ),
              ),
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'Inter',
                color: Color(0xFF19160B),
              ),
              onChanged: (v) => context.read<ArchivesBloc>().add(
                ArchivesEvent.searchByArchiveNum(v),
              ),
            ),
          ),

          // Filter tabs
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F4F2),
              borderRadius: BorderRadius.circular(10),
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
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isActive
                            ? const Color(0xFF19160B)
                            : const Color(0xFF888888),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const Spacer(),

          // Date range picker
          GestureDetector(
            onTap: () async {
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
                builder: (context, child) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 400,
                      maxHeight: 600,
                    ),
                    child: child,
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
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: state.filterType == ArchivesFilterType.date
                    ? const Color(0xFFFFF3EE)
                    : Colors.white,
                border: Border.all(
                  color: state.filterType == ArchivesFilterType.date
                      ? const Color(0xFFFB6633)
                      : const Color(0xFFEBEBEB),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                spacing: 8,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: state.filterType == ArchivesFilterType.date
                        ? const Color(0xFFFB6633)
                        : const Color(0xFF888888),
                  ),
                  Text(
                    state.filterType == ArchivesFilterType.date &&
                            state.startFilterDate != null
                        ? '${state.startFilterDate!.day}.${state.startFilterDate!.month.toString().padLeft(2, '0')}'
                        : 'Sana',
                    style: TextStyle(
                      fontSize: 13,
                      color: state.filterType == ArchivesFilterType.date
                          ? const Color(0xFFFB6633)
                          : const Color(0xFF888888),
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Total count
          Text(
            "Jami: ${state.archives?.pagination.total ?? 0} ta",
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF888888),
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEBEBEB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF888888),
                fontFamily: 'Inter',
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF19160B),
                fontFamily: 'Inter',
              ),
            ),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFAAAAAA),
                fontFamily: 'Inter',
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888888),
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  final ArchiveEntity archive;
  final bool isSelected;
  final VoidCallback onTap;

  const _ArchiveRow({
    required this.archive,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final time = archive.opened != null
        ? '${archive.opened!.hour.toString().padLeft(2, '0')}:${archive.opened!.minute.toString().padLeft(2, '0')}'
        : '-';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF3EE) : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFF5F4F2)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '#${archive.bilNumber}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFAAAAAA),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F4F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${archive.tableNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF19160B),
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _StatusBadge(status: archive.status),
              ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '${archive.goodsQuantity}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  archive.totalPrice.formatN,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  time,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFEBEBEB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      size: 14,
                      color: Color(0xFF888888),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
    String label;

    switch (status) {
      case OrderStatus.open:
      case OrderStatus.opened:
      case OrderStatus.pending:
        bg = const Color(0xFFFFF3EE);
        fg = const Color(0xFFFB6633);
        label = '● Ochiq';
      case OrderStatus.closed:
      case OrderStatus.paid:
        bg = const Color(0xFFE8F9E9);
        fg = const Color(0xFF13AF1B);
        label = '● Yopildi';
      case OrderStatus.deleted:
        bg = const Color(0xFFFFF0F3);
        fg = const Color(0xFFEB295B);
        label = '● Bekor';
      default:
        bg = const Color(0xFFF5F4F2);
        fg = const Color(0xFF888888);
        label = '● Noma\'lum';
    }

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
