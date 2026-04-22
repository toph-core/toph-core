import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/core/utils/app_formatter.dart';
import 'package:mary_ai_pos/core/utils/order_localizations.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/archive/widgets/archive_right_sider_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:number_paginator/number_paginator.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.select((UserBloc b) => b.state.userMOdel?.role);
    return AppScaffold(
      activeRoute: AppRoutes.archiveScreen,
      body: role.canViewAllOrders
          ? const _AdminOrdersArchiveBody()
          : BlocProvider(
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
              final avgCheck = archives.isNotEmpty
                  ? revenue ~/ archives.length
                  : 0;

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
                          valueColor: const Color(0xFF16A34A),
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
                                  color: const Color(0xFFE2E8F0),
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
                                          color: Color(0xFFE2E8F0),
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
                                    child:
                                        state.status == Status.LOADING &&
                                            archives.isEmpty
                                        ? const Center(
                                            child:
                                                CircularProgressIndicator.adaptive(),
                                          )
                                        : archives.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Arxiv topilmadi',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFF64748B),
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
                                                      state.selectArchive?.id ==
                                                      archives[i].id,
                                                  onTap: () => context
                                                      .read<ArchivesBloc>()
                                                      .add(
                                                        ArchivesEvent.selectArchive(
                                                          id: archives[i].id,
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
                  color: Color(0xFF94A3B8),
                  fontFamily: 'Inter',
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFB6633)),
                ),
              ),
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'Inter',
                color: Color(0xFF0F172A),
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
              color: const Color(0xFFF8FAFC),
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
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF64748B),
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
                      : const Color(0xFFE2E8F0),
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
                        : const Color(0xFF64748B),
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
                          : const Color(0xFF64748B),
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
              color: Color(0xFF64748B),
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
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
                color: Color(0xFF64748B),
                fontFamily: 'Inter',
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF0F172A),
                fontFamily: 'Inter',
              ),
            ),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
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
            color: Color(0xFF64748B),
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
          border: const Border(bottom: BorderSide(color: Color(0xFFF8FAFC))),
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
                    color: Color(0xFF94A3B8),
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
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${archive.tableNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
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
                    color: Color(0xFF0F172A),
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
                    color: Color(0xFF0F172A),
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
                    color: Color(0xFF0F172A),
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
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      size: 14,
                      color: Color(0xFF64748B),
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

class _AdminOrdersArchiveBody extends StatefulWidget {
  const _AdminOrdersArchiveBody();

  @override
  State<_AdminOrdersArchiveBody> createState() =>
      _AdminOrdersArchiveBodyState();
}

class _AdminOrdersArchiveBodyState extends State<_AdminOrdersArchiveBody> {
  static const List<int> _pageSizeOptions = [20, 50, 100];
  int _pageSize = 20;
  final NumberPaginatorController _paginatorController =
      NumberPaginatorController();
  static const List<String> _statuses = [
    'open',
    'cooking',
    'ready',
    'served',
    'paid',
    'cancelled',
    'reserved',
    'rescheduled',
  ];
  static const List<String> _orderTypes = ['dine_in', 'takeaway'];

  final DioClient _client = inject<DioClient>();
  final ScrollController _scrollCtrl = ScrollController();

  List<_AdminOrderItem> _orders = const [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int? _totalCount;
  String? _statusFilter;
  String? _orderTypeFilter;

  // id → displayName (waiter va kassir uchun)
  Map<String, String> _userNames = {};
  // tableId → {number, hallName}
  Map<String, _TableMeta> _tableMeta = {};

  int get _totalPages {
    final total = _totalCount;
    if (total == null || total <= 0) return 1;
    final pages = (total + _pageSize - 1) ~/ _pageSize;
    return pages > 0 ? pages : 1;
  }

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _load(page: 1);
  }

  @override
  void dispose() {
    _paginatorController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final results = await Future.wait([
        _client.get(ListAPI.users, queryParameters: {'limit': 1000}),
        _client.get(ListAPI.halls),
        _client.get(ListAPI.cafeTables, queryParameters: {'limit': 1000}),
      ]);

      // Users: id → displayName
      final usersRaw = results[0].data;
      final usersList = usersRaw is Map && usersRaw['data'] is List
          ? usersRaw['data'] as List
          : usersRaw is List
          ? usersRaw
          : const [];
      final userNames = <String, String>{};
      for (final u in usersList) {
        if (u is! Map<String, dynamic>) continue;
        final id = (u['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final name = (u['full_name'] ?? u['username'] ?? '').toString().trim();
        if (name.isNotEmpty) userNames[id] = name;
      }

      // Halls: id → name
      final hallsRaw = results[1].data;
      final hallsList = hallsRaw is Map && hallsRaw['data'] is List
          ? hallsRaw['data'] as List
          : hallsRaw is List
          ? hallsRaw
          : const [];
      final hallNames = <String, String>{};
      for (final h in hallsList) {
        if (h is! Map) continue;
        final id = (h['id'] ?? '').toString();
        final name = (h['name'] ?? '').toString();
        if (id.isNotEmpty && name.isNotEmpty) hallNames[id] = name;
      }

      // Tables: tableId → _TableMeta
      final tablesRaw = results[2].data;
      final tablesList = tablesRaw is Map && tablesRaw['data'] is List
          ? tablesRaw['data'] as List
          : tablesRaw is List
          ? tablesRaw
          : const [];
      final tableMeta = <String, _TableMeta>{};
      for (final t in tablesList) {
        if (t is! Map) continue;
        final id = (t['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final number = (t['number'] as num?)?.toInt() ?? 0;
        final hallId = (t['hall_id'] ?? '').toString();
        tableMeta[id] = _TableMeta(
          number: number,
          hallName: hallNames[hallId] ?? '',
        );
      }

      if (!mounted) return;
      setState(() {
        _userNames = userNames;
        _tableMeta = tableMeta;
      });
    } catch (_) {
      // meta yuklanmasa ham ro'yxat ko'rinadi
    }
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{
        'lang': 'uz',
        'sort_by': 'created_at',
        'sort_order': 'desc',
        'limit': _pageSize,
        'offset': (page - 1) * _pageSize,
        if (_statusFilter != null) 'status': _statusFilter,
        if (_orderTypeFilter != null) 'type': _orderTypeFilter,
      };
      final res = await _client.get(ListAPI.orders, queryParameters: query);
      final data = res.data is Map<String, dynamic>
          ? res.data as Map<String, dynamic>
          : <String, dynamic>{};
      final list = data['data'] is List ? data['data'] as List : const [];
      final parsed = list
          .whereType<Map<String, dynamic>>()
          .map(_AdminOrderItem.fromJson)
          .toList();
      final total = _extractTotalCount(data);

      if (!mounted) return;
      setState(() {
        _orders = parsed;
        _page = page;
        _totalCount = total;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.data is Map
            ? (e.response!.data['message']?.toString() ?? 'Yuklashda xatolik')
            : 'Yuklashda xatolik';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Buyurtmalarni yuklab bo\'lmadi';
      });
    }
  }

  int? _extractTotalCount(Map<String, dynamic> raw) {
    final candidates = [
      raw['total'],
      raw['count'],
      raw['meta'] is Map ? (raw['meta'] as Map)['total'] : null,
      raw['meta'] is Map ? (raw['meta'] as Map)['count'] : null,
      raw['pagination'] is Map ? (raw['pagination'] as Map)['total'] : null,
    ];
    for (final c in candidates) {
      if (c is num) return c.toInt();
      if (c is String) {
        final parsed = int.tryParse(c);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  void _applyFilters({String? status, String? type}) {
    setState(() {
      _statusFilter = status;
      _orderTypeFilter = type;
    });
    _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MainHeader(title: 'Barcha buyurtmalar'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Row(
            children: [
              SizedBox(
                width: 220,
                child: _filterDropdown(
                  label: 'Status',
                  value: _statusFilter,
                  items: _statuses,
                  labelFor: (e) => localizedOrderStatus(context, e),
                  onChanged: (v) =>
                      _applyFilters(status: v, type: _orderTypeFilter),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 180,
                child: _filterDropdown(
                  label: 'Order type',
                  value: _orderTypeFilter,
                  items: _orderTypes,
                  labelFor: (e) => localizedOrderType(context, e),
                  onChanged: (v) =>
                      _applyFilters(status: _statusFilter, type: v),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _load(page: 1),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Yangilash'),
              ),
              const Spacer(),
              Text(
                'Jami: ${_totalCount ?? _orders.length}',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _loading && _orders.isEmpty
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(color: colors.systemError),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => _load(page: _page),
                          child: const Text('Qayta urinish'),
                        ),
                      ],
                    ),
                  )
                : _orders.isEmpty
                ? Center(
                    child: Text(
                      'Buyurtmalar topilmadi',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollCtrl,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 8,
                    radius: const Radius.circular(4),
                    interactive: true,
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _orders.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.border,
                      ),
                      itemBuilder: (context, i) {
                        final o = _orders[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Builder(
                            builder: (context) {
                              final meta = _tableMeta[o.tableId];
                              final hallName = meta?.hallName ?? '';
                              final tableNum = meta?.number ?? 0;
                              final waiterName = _userNames[o.waiterId] ?? '';
                              final cashierName = _userNames[o.cashierId] ?? '';
                              final staffName = waiterName.isNotEmpty
                                  ? waiterName
                                  : cashierName.isNotEmpty
                                  ? cashierName
                                  : '—';
                              final isWaiter = waiterName.isNotEmpty;
                              return Row(
                                children: [
                                  // Zal
                                  Expanded(
                                    flex: 3,
                                    child: o.orderType == 'takeaway'
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF3EE),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFFFB6633,
                                                ).withOpacity(0.3),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              spacing: 4,
                                              children: [
                                                Icon(
                                                  Icons.shopping_bag_outlined,
                                                  size: 12,
                                                  color: Color(0xFFFB6633),
                                                ),
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
                                          )
                                        : Text(
                                            hallName.isNotEmpty
                                                ? hallName
                                                : '—',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: colors.textDefault,
                                            ),
                                          ),
                                  ),
                                  // Stol
                                  Expanded(
                                    flex: 2,
                                    child: o.orderType == 'takeaway'
                                        ? Text(
                                            '—',
                                            style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          )
                                        : tableNum > 0
                                        ? Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FAFC),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              '$tableNum',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: colors.textDefault,
                                              ),
                                            ),
                                          )
                                        : Text(
                                            '—',
                                            style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                  ),
                                  // Ofitsiant / Kassir
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          staffName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: colors.textDefault,
                                          ),
                                        ),
                                        if (staffName != '—')
                                          Text(
                                            isWaiter ? 'Ofitsiant' : 'Kassir',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Vaqt
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      o.createdAtLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  // Summa
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      AppFormatter.formatAmountWithSpaces(
                                        o.totalAmount,
                                      ),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textBrand,
                                      ),
                                    ),
                                  ),
                                  // Holat
                                  Expanded(
                                    flex: 3,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: _orderStatusBadge(
                                        status: o.status,
                                        secondaryTextColor:
                                            colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
        _buildPaginationBar(colors),
      ],
    );
  }

  Widget _buildPaginationBar(ThemeColors colors) {
    final totalPages = _totalPages;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                secondary: colors.buttonBrand,
                onSecondary: colors.textOnBrand,
              ),
            ),
            child: SizedBox(
              width: 372,
              height: 44,
              child: NumberPaginator(
                controller: _paginatorController,
                numberPages: totalPages,
                initialPage: (_page - 1).clamp(0, totalPages - 1),
                onPageChange: (pageIndex) {
                  if (_loading) return;
                  _load(page: pageIndex + 1);
                },
                child: const SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      PrevButton(),
                      Expanded(child: NumberContent()),
                      NextButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _pageSize,
                isDense: true,
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: colors.textSecondary,
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textDefault,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                ),
                items: _pageSizeOptions
                    .map(
                      (size) => DropdownMenuItem<int>(
                        value: size,
                        child: Text('$size / sahifa'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == _pageSize || _loading) return;
                  setState(() {
                    _pageSize = value;
                    final newTotal = _totalCount == null
                        ? 1
                        : ((_totalCount! + value - 1) ~/ value).clamp(
                            1,
                            999999,
                          );
                    if (_page > newTotal) _page = newTotal;
                  });
                  _load(page: _page);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String Function(String)? labelFor,
  }) {
    return DropdownButtonFormField<String?>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Hammasi')),
        ...items.map(
          (e) => DropdownMenuItem<String?>(
            value: e,
            child: Text(labelFor?.call(e) ?? e),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _orderStatusBadge({
    required String status,
    required Color secondaryTextColor,
  }) {
    final s = status.toLowerCase();
    final isOpen =
        s == 'open' || s == 'cooking' || s == 'ready' || s == 'served';
    final isPaid = s == 'paid';
    final bg = isOpen
        ? const Color(0xFFFFF3EE)
        : isPaid
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFF2F3F5);
    final fg = isOpen
        ? const Color(0xFFFB6633)
        : isPaid
        ? const Color(0xFF16A34A)
        : secondaryTextColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        localizedOrderStatus(context, status),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _TableMeta {
  final int number;
  final String hallName;
  const _TableMeta({required this.number, required this.hallName});
}

class _AdminOrderItem {
  final String id;
  final String tableId;
  final String waiterId;
  final String cashierId;
  final String status;
  final String orderType;
  final String totalAmount;
  final DateTime? createdAt;

  const _AdminOrderItem({
    required this.id,
    required this.tableId,
    required this.waiterId,
    required this.cashierId,
    required this.status,
    required this.orderType,
    required this.totalAmount,
    required this.createdAt,
  });

  factory _AdminOrderItem.fromJson(Map<String, dynamic> json) {
    return _AdminOrderItem(
      id: (json['id'] ?? '').toString(),
      tableId: (json['table_id'] ?? '').toString(),
      waiterId: (json['waiter_id'] ?? '').toString(),
      cashierId: (json['cashier_id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      orderType: (json['order_type'] ?? '').toString(),
      totalAmount: (json['total_amount'] ?? '0').toString(),
      createdAt: DateTime.tryParse(
        (json['created_at'] ?? '').toString(),
      )?.toLocal(),
    );
  }

  String get createdAtLabel {
    if (createdAt == null) return '-';
    final d = createdAt!;
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$day.$month $hour:$minute';
  }
}
