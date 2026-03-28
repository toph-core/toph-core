import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/notification/notification_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          NotificationBloc()..add(const NotificationEvent.started()),
      child: const AppScaffold(
        activeRoute: AppRoutes.notificationsScreen,
        body: _NotificationBody(),
      ),
    );
  }
}

class _NotificationBody extends StatefulWidget {
  const _NotificationBody();

  @override
  State<_NotificationBody> createState() => _NotificationBodyState();
}

class _NotificationBodyState extends State<_NotificationBody> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocBuilder<NotificationBloc, NotificationState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MainHeader(title: 'Bildirishnomalar'),
            // Filter bar
            Container(
              height: 56,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                spacing: 12,
                children: [
                  // Search field
                  SizedBox(
                    width: 260,
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Qidirish...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFEBEFF2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFEBEFF2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFFB6633),
                          ),
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'Inter',
                        color: Color(0xFF19160B),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const Spacer(),
                  // Filter tabs
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      spacing: 4,
                      children: [
                        _FilterTab(
                          label: 'Bugun',
                          isActive:
                              state.filterType == ArchivesFilterType.Today,
                          onTap: () => context.read<NotificationBloc>().add(
                            const NotificationEvent.updateFilterType(
                              filterType: ArchivesFilterType.Today,
                            ),
                          ),
                        ),
                        _FilterTab(
                          label: 'Hafta',
                          isActive:
                              state.filterType == ArchivesFilterType.Week,
                          onTap: () => context.read<NotificationBloc>().add(
                            const NotificationEvent.updateFilterType(
                              filterType: ArchivesFilterType.Week,
                            ),
                          ),
                        ),
                        _FilterTab(
                          label: 'Oy',
                          isActive:
                              state.filterType == ArchivesFilterType.month,
                          onTap: () => context.read<NotificationBloc>().add(
                            const NotificationEvent.updateFilterType(
                              filterType: ArchivesFilterType.month,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Date range picker
                  GestureDetector(
                    onTap: () async {
                      final notifBloc = context.read<NotificationBloc>();
                      final picked = await showDateRangePicker(
                        context: context,
                        initialDateRange: DateTimeRange(
                          start: state.start ?? DateTime.now(),
                          end: state.end ?? DateTime.now(),
                        ),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365),
                        ),
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
                        notifBloc.add(
                          NotificationEvent.updateDateFilterEvent(
                            start: picked.start,
                            end: picked.end,
                          ),
                        );
                      }
                    },
                    child: Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                        color: state.filterType == ArchivesFilterType.date
                            ? const Color(0xFFFB6633)
                            : const Color(0xFFF8F9FA),
                        border: Border.all(color: const Color(0xFFEBEFF2)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: state.filterType == ArchivesFilterType.date
                            ? Colors.white
                            : const Color(0xFF19160B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            // Content
            Expanded(
              child: Container(
                color: colors.bgSecondary,
                child: state.status == Status.LOADING
                    ? const Center(
                        child: CircularProgressIndicator.adaptive(),
                      )
                    : _NotificationGrid(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NotificationGrid extends StatelessWidget {
  // Dummy data for now
  static final List<_NotificationItem> _items = List.generate(
    18,
    (i) => _NotificationItem(
      orderNumber: '#${1020 + i}',
      tableName: '${i + 1}-stol',
      description: '${i + 1}-stol buyurtmasi yetkazildi.',
      time: '${(8 + i % 14).toString().padLeft(2, '0')}:${(i * 3 % 60).toString().padLeft(2, '0')}',
    ),
  );

  _NotificationGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 820
            ? 1
            : constraints.maxWidth < 1280
            ? 2
            : 3;
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: _items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 100,
          ),
          itemBuilder: (context, index) =>
              _NotificationCard(item: _items[index]),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final _NotificationItem item;
  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEBEFF2)),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3EE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(
                Icons.notifications_rounded,
                size: 20,
                color: Color(0xFFFB6633),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 4,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.orderNumber,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF19160B),
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      item.time,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
                Text(
                  item.tableName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFFB6633),
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888888),
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

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFB6633) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : const Color(0xFF888888),
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

class _NotificationItem {
  final String orderNumber;
  final String tableName;
  final String description;
  final String time;

  const _NotificationItem({
    required this.orderNumber,
    required this.tableName,
    required this.description,
    required this.time,
  });
}
