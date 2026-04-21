import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/list_extension.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/admin_floor_plan_canvas.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/show_table_guest_count.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/tab_filter.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

enum _ViewMode { floorPlan, grid }

/// Waiter va cashier uchun floor plan ekrani.
/// Canvas (floor plan) yoki karta grid ko'rinishda almashish mumkin.
class WaiterFloorPlanScreen extends StatefulWidget {
  const WaiterFloorPlanScreen({super.key});

  @override
  State<WaiterFloorPlanScreen> createState() => _WaiterFloorPlanScreenState();
}

class _WaiterFloorPlanScreenState extends State<WaiterFloorPlanScreen> {
  _ViewMode _viewMode = _ViewMode.floorPlan;

  void _toggleView() {
    setState(() {
      _viewMode = _viewMode == _ViewMode.floorPlan
          ? _ViewMode.grid
          : _ViewMode.floorPlan;
    });
  }

  Future<void> _refresh() async {
    await context.read<MainCubit>().refreshTables();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppScaffold(
      activeRoute: AppRoutes.mainScreen,
      body: BlocBuilder<MainCubit, MainState>(
        builder: (context, state) {
          final hall = state.halls?.firstWhereOrNull(
            (h) => h.id == state.selectedHallId,
          );
          final tables = state.tables ?? [];

          // Saved order table IDs
          final savedIds = context
              .watch<SavedOrdersBloc>()
              .state
              .order
              .map((o) => o.createOrderRequest.tableId)
              .toSet();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MainHeader(
                title: S.current.strFloorMap,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TakeawayButton(),
                    const SizedBox(width: 6),
                    // Refresh
                    _HeaderIconBtn(
                      icon: Icons.refresh_rounded,
                      tooltip: S.current.strRefresh,
                      loading: state.status == Status.LOADING,
                      onTap: _refresh,
                    ),
                    const SizedBox(width: 6),
                    // View toggle
                    _ViewToggle(mode: _viewMode, onToggle: _toggleView),
                  ],
                ),
              ),
              if ((state.halls ?? []).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: TabFilter(
                    halls: state.halls ?? [],
                    selectedHallId: state.selectedHallId,
                    isLoading: state.status == Status.OTHER_LOADING,
                  ),
                ),
              Expanded(
                child: state.status == Status.LOADING
                    ? Center(
                        child: CircularProgressIndicator.adaptive(
                          valueColor: AlwaysStoppedAnimation(colors.textBrand),
                        ),
                      )
                    : _viewMode == _ViewMode.floorPlan
                    ? AdminFloorPlanCanvas(
                        tables: tables,
                        hall: hall,
                        isEditMode: false,
                        savedTableIds: savedIds,
                        onTableTap: (table) => _handleTableTap(context, table),
                      )
                    : _GridView(
                        tables: tables,
                        savedIds: savedIds,
                        onTap: (table) => _handleTableTap(context, table),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleTableTap(
    BuildContext context,
    CafeTableModel table,
  ) async {
    if (table.status == TableStatus.free) {
      final savedOrdersBloc = context.read<SavedOrdersBloc>();
      final navigator = Navigator.of(context);

      final guestCount = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShowTableGuestCount(tableNumber: table.number),
      );
      if (guestCount == null) return;

      final index = savedOrdersBloc.state.order.indexWhere(
        (v) => v.createOrderRequest.tableId == table.id,
      );

      Future.delayed(
        const Duration(milliseconds: 300),
        () => navigator.pushNamed(
          AppRoutes.detailScreen,
          arguments: {
            'table': table,
            'guest_count': guestCount,
            'table_status': table.status,
            'saved_orders': index != -1
                ? savedOrdersBloc.state.order[index]
                : null,
          },
        ),
      );
    } else {
      final savedOrdersBloc = context.read<SavedOrdersBloc>();
      final index = savedOrdersBloc.state.order.indexWhere(
        (v) => v.createOrderRequest.tableId == table.id,
      );

      Navigator.pushNamed(
        context,
        AppRoutes.detailScreen,
        arguments: {
          'table': table,
          'table_status': TableStatus.busy,
          'saved_orders': index != -1
              ? savedOrdersBloc.state.order[index]
              : null,
        },
      );
    }
  }
}

// ─────────────────────────────────────────────
// Header tugmalar
// ─────────────────────────────────────────────

class _TakeawayButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.detailScreen,
        arguments: {
          'table': null,
          'table_status': TableStatus.none,
          'guest_count': 1,
        },
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.bgSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 15, color: c.textSecondary),
            Text(
              S.current.strTakeaway,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool loading;
  final VoidCallback onTap;
  const _HeaderIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
  });

  @override
  State<_HeaderIconBtn> createState() => _HeaderIconBtnState();
}

class _HeaderIconBtnState extends State<_HeaderIconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _hovered ? c.bgSecondary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? c.border : Colors.transparent,
              ),
            ),
            child: widget.loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(c.textBrand),
                    ),
                  )
                : Icon(widget.icon, size: 18, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final _ViewMode mode;
  final VoidCallback onToggle;
  const _ViewToggle({required this.mode, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isFloorPlan = mode == _ViewMode.floorPlan;
    return Tooltip(
      message: isFloorPlan ? S.current.strGridView : S.current.strMapView,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.bgSecondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Icon(
                isFloorPlan ? Icons.grid_view_rounded : Icons.map_outlined,
                size: 15,
                color: c.textSecondary,
              ),
              Text(
                isFloorPlan ? S.current.strGrid : S.current.strMap,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Grid ko'rinish
// ─────────────────────────────────────────────

class _GridView extends StatelessWidget {
  final List<CafeTableModel> tables;
  final Set<String> savedIds;
  final void Function(CafeTableModel) onTap;

  const _GridView({
    required this.tables,
    required this.savedIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (tables.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(Icons.table_restaurant_outlined, size: 48, color: c.border),
            Text(
              S.current.strNoTables,
              style: TextStyle(
                fontSize: 14,
                color: c.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: tables
            .map(
              (t) => _WaiterTableCard(
                table: t,
                isSaved: savedIds.contains(t.id),
                onTap: () => onTap(t),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WaiterTableCard extends StatefulWidget {
  final CafeTableModel table;
  final bool isSaved;
  final VoidCallback onTap;

  const _WaiterTableCard({
    required this.table,
    required this.isSaved,
    required this.onTap,
  });

  @override
  State<_WaiterTableCard> createState() => _WaiterTableCardState();
}

class _WaiterTableCardState extends State<_WaiterTableCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = widget.table.status;

    final Color borderColor;
    final Color bgColor;
    final Color statusColor;
    final String statusLabel;

    switch (status) {
      case TableStatus.busy:
        borderColor = const Color(0xFFFB6633);
        bgColor = const Color(0xFFFFF3EE);
        statusColor = const Color(0xFFFB6633);
        statusLabel = S.current.strBusy;
      case TableStatus.away:
        borderColor = const Color(0xFF3B82F6);
        bgColor = const Color(0xFFEEF2FF);
        statusColor = const Color(0xFF3B82F6);
        statusLabel = S.current.strReserved;
      default:
        borderColor = c.border;
        bgColor = c.bgDefault;
        statusColor = const Color(0xFF22C55E);
        statusLabel = S.current.strFree;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 160,
          height: 120,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovered ? bgColor.withOpacity(0.75) : bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? borderColor : borderColor.withOpacity(0.6),
              width: status == TableStatus.busy ? 2 : 1.5,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: borderColor.withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row: table number + saved badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${S.current.strTable} ${widget.table.number}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.textDefault,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                  if (widget.isSaved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFB6633).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        S.current.strSavedBadge,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFB6633),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Capacity
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  Icon(Icons.people_outline, size: 13, color: c.textTertiary),
                  Text(
                    '${widget.table.capacity} ${S.current.strPersonsSuffix}',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
