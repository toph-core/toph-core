import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen_mixin.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/show_food_additional.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/table_timer/table_timer_cubit.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

const _indigo = Color(0xFF6366F1);

class OrderSidebar extends StatefulWidget {
  final String? tableId;
  final CafeTableModel? cafeTable;

  const OrderSidebar({
    super.key,
    this.tableId,
    this.cafeTable,
  });

  @override
  State<OrderSidebar> createState() => _OrderSidebarState();
}

class _OrderSidebarState extends State<OrderSidebar> with DetailScreenMixin {
  final ScrollController _itemsCtrl = ScrollController();

  @override
  void dispose() {
    _itemsCtrl.dispose();
    super.dispose();
  }

  String? get tableId => widget.tableId;
  CafeTableModel? get cafeTable => widget.cafeTable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocListener<DetailBloc, DetailState>(
      listenWhen: (p, c) =>
          p.activeOrderId != c.activeOrderId && c.activeOrderId != null,
      listener: (ctx, s) {
        if (cafeTable?.tableType == 'time_based') {
          final timerCubit = ctx.read<TableTimerCubit>();
          timerCubit.fetchTimer(orderId: s.activeOrderId!);
        }
      },
      child: BlocBuilder<DetailBloc, DetailState>(
        buildWhen: (p, c) =>
            p.selectedGoods != c.selectedGoods ||
            p.existingGoods != c.existingGoods,
        builder: (context, state) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: colors.border)),
            ),
            child: Column(
              children: [
                // Items list (sidebar = faqat itemlar)
                Expanded(
                  child: (state.existingGoods.isEmpty &&
                          state.selectedGoods.isEmpty)
                      ? _SidebarEmptyState(colors: colors)
                      : Scrollbar(
                          controller: _itemsCtrl,
                          thumbVisibility: true,
                          thickness: 4,
                          radius: const Radius.circular(8),
                          child: ListView(
                            controller: _itemsCtrl,
                            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                            children: [
                              if (state.existingGoods.isNotEmpty) ...[
                                _SectionLabel(
                                  label: S.current.strExistingOrders,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(height: 6),
                                ...state.existingGoods.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ReadonlyOrderItem(
                                      item: item,
                                      tableId: cafeTable?.id,
                                    ),
                                  ),
                                ),
                                if (state.selectedGoods.isNotEmpty)
                                  const SizedBox(height: 4),
                              ],
                              if (state.selectedGoods.isNotEmpty) ...[
                                if (state.existingGoods.isNotEmpty)
                                  _SectionLabel(
                                    label: S.current.strExtras,
                                    color: const Color(0xFFFB6633),
                                  ),
                                if (state.existingGoods.isNotEmpty)
                                  const SizedBox(height: 6),
                                ...state.selectedGoods.asMap().entries.map(
                                  (e) => Padding(
                                    padding: EdgeInsets.only(
                                      bottom: e.key <
                                              state.selectedGoods.length - 1
                                          ? 8
                                          : 0,
                                    ),
                                    child: _OrderItem(item: e.value),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),

              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Order Item Card
// ─────────────────────────────────────────────
class _OrderItem extends StatelessWidget with DetailScreenMixin {
  final OrderItem item;
  _OrderItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () async {
        List<FoodAdditionalModel> selectedAdditional = List.from(additionals);
        for (int i = 0; i < additionals.length; i++) {
          if (item.goods.additionals.any(
            (v) =>
                v.price == additionals[i].price &&
                v.title == additionals[i].title,
          )) {
            selectedAdditional[i].selected = true;
          }
        }
        final bloc = context.read<DetailBloc>();
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ShowFoodAdditional(
            additionals: selectedAdditional,
            goods: item.goods,
            comment: item.comment,
          ),
        );
        if (result != null) {
          bloc.add(
            DetailEvent.addFoodAdditional(
              additionals: result['additional'],
              orderId: item.uniqueId,
              comment: result['comment'],
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 7, 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Initial badge (kichik)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: colors.border),
              ),
              child: Center(
                child: Text(
                  item.goods.name.isNotEmpty
                      ? item.goods.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            // Nom + jami narx (column)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.goods.name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      fontFamily: 'Inter',
                      height: 1.2,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ((item.goods.additionals.isNotEmpty
                                ? item.goods.additionals
                                        .map((v) => v.price)
                                        .reduce((a, b) => a + b) +
                                    double.parse(item.goods.price)
                                : double.parse(item.goods.price)) *
                            item.quantity)
                        .formatN,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFB6633),
                      fontFamily: 'Inter',
                      letterSpacing: -0.1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _QtyControl(
              quantity: item.quantity,
              onDecrement: () => context.read<DetailBloc>().add(
                DetailEvent.decrementQuantity(goodsId: item.goods.id),
              ),
              onIncrement: () => context.read<DetailBloc>().add(
                DetailEvent.incrementQuantity(goodsId: item.goods.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _QtyControl({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        _QtyBtn(icon: Icons.remove, onTap: onDecrement),
        SizedBox(
          width: 18,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              fontFamily: 'Inter',
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _QtyBtn(icon: Icons.add, onTap: onIncrement),
      ],
    );
  }
}

class _QtyBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  State<_QtyBtn> createState() => _QtyBtnState();
}

class _QtyBtnState extends State<_QtyBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFFFB6633) : Colors.white,
          border: Border.all(
            color: _pressed ? const Color(0xFFFB6633) : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          widget.icon,
          size: 14,
          color: _pressed ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

// ─── Sidebar empty state (premium) ──────────────────────────────────────────
class _SidebarEmptyState extends StatelessWidget {
  final dynamic colors;
  const _SidebarEmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decorative ring with icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFB6633).withOpacity(0.06),
                border: Border.all(
                  color: const Color(0xFFFB6633).withOpacity(0.15),
                ),
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFB6633).withOpacity(0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.restaurant_menu_rounded,
                    size: 26,
                    color: Color(0xFFFB6633),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              S.current.strSidebarEmptyTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                fontFamily: 'Inter',
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.current.strSelectFoodsNotFound,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
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

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        fontFamily: 'Inter',
        letterSpacing: 0.3,
      ),
    );
  }
}

class _ReadonlyOrderItem extends StatelessWidget {
  final OrderItem item;
  final String? tableId;
  const _ReadonlyOrderItem({required this.item, this.tableId});

  void _showCommentDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(
          item.goods.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            fontFamily: 'Inter',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.current.strSpecialNote,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
                fontFamily: 'Inter',
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.comment,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F172A),
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.current.strClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = item.commet == 'cancelled';
    final isOfflinePending = item.commet == 'pending_offline';
    final hasComment = item.comment.trim().isNotEmpty;
    final textColor = isCancelled
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF0F172A);
    Color bgColor = const Color(0xFFF8FAFC);
    if (isCancelled) bgColor = const Color(0xFFFEE2E2);
    if (isOfflinePending) bgColor = const Color(0xFFF5F3FF);
    return Opacity(
      opacity: isCancelled ? 0.6 : 1.0,
      child: GestureDetector(
        onTap: hasComment ? () => _showCommentDialog(context) : null,
        child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: isOfflinePending
              ? Border.all(color: const Color(0xFFFB6633).withOpacity(0.4))
              : null,
        ),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  item.goods.name.isNotEmpty
                      ? item.goods.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isCancelled
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF64748B),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.goods.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      fontFamily: 'Inter',
                      decoration: isCancelled
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: const Color(0xFFCBD5E1),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (isCancelled)
                    const Text(
                      'Bekor qilindi',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFDC2626),
                        fontFamily: 'Inter',
                      ),
                    )
                  else if (isOfflinePending)
                    const Text(
                      '⏳ Yuborilmoqda...',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFFB6633),
                        fontFamily: 'Inter',
                      ),
                    )
                  else ...[
                    Text(
                      (double.tryParse(item.goods.price) ?? 0).formatN,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (item.createdAt != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        _fmtHm(item.createdAt!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                          fontFamily: 'Inter',
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (hasComment) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 11,
                            color: Color(0xFFFB6633),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.comment.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFFFB6633),
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            Text(
              'x${item.quantity}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isCancelled
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFF64748B),
                fontFamily: 'Inter',
                decoration: isCancelled ? TextDecoration.lineThrough : null,
                decorationColor: const Color(0xFFCBD5E1),
              ),
            ),
            Text(
              ((double.tryParse(item.goods.price) ?? 0) * item.quantity)
                  .formatN,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFamily: 'Inter',
                decoration: isCancelled ? TextDecoration.lineThrough : null,
                decorationColor: const Color(0xFFCBD5E1),
              ),
            ),
            if (tableId != null && !isOfflinePending && !isCancelled)
              GestureDetector(
                onTap: () async {
                  final bloc = context.read<DetailBloc>();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(
                        S.current.strConfirmDelete,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      content: Text(
                        S.current.strConfirmDeleteItem(item.goods.name),
                        style: const TextStyle(fontSize: 14),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(S.current.strNo),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            S.current.strYes,
                            style: const TextStyle(color: Color(0xFFDC2626)),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    bloc.add(
                      DetailEvent.cancelOrderItem(
                        itemId: item.uniqueId,
                        tableId: tableId!,
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Color(0xFFDC2626),
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

class _TimerBadgeRow extends StatefulWidget {
  final TableTimerState timerState;
  const _TimerBadgeRow({required this.timerState});

  @override
  State<_TimerBadgeRow> createState() => _TimerBadgeRowState();
}

class _TimerBadgeRowState extends State<_TimerBadgeRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.timerState.timer;
    final displaySec =
        widget.timerState.displayActiveSec ?? t?.totalActiveSec ?? 0;
    final isRunning = t?.stateNormalized == 'running';
    final isPaused = t?.stateNormalized == 'paused';
    final isNone = t == null || t.stateNormalized == 'none';
    // effectiveCurrentAmount: timer API currentAmount yoki hisoblangan summa
    final rawAmt = widget.timerState.effectiveCurrentAmount ?? '';
    final amountStr = rawAmt.isNotEmpty ? '${_fmtAmount(rawAmt)} so\'m' : '';
    final startedAtStr = t?.startedAt != null ? _fmtClock(t!.startedAt!) : null;
    // billPauses — bill API dan (pause_periods), bo'lmasa timer API dan
    final pauses = widget.timerState.billPauses.isNotEmpty
        ? widget.timerState.billPauses
        : (t?.pauses ?? const []);

    final accentColor = isPaused
        ? const Color(0xFFF59E0B)
        : isRunning
        ? _indigo
        : _indigo.withOpacity(0.5);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          // ── Main row ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                // State dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isRunning
                        ? const Color(0xFF22C55E)
                        : isPaused
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFCBD5E1),
                    shape: BoxShape.circle,
                    boxShadow: isRunning
                        ? [
                            BoxShadow(
                              color: const Color(0xFF22C55E).withOpacity(0.5),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),

                // Elapsed time + amount stacked
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmtTime(displaySec),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                          fontFamily: 'Inter',
                          letterSpacing: 0.4,
                          height: 1.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (amountStr.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            amountStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentColor.withOpacity(0.75),
                              fontFamily: 'Inter',
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Pause/Resume button
                if (isRunning || isPaused || isNone)
                  GestureDetector(
                    onTap: widget.timerState.isMutating
                        ? null
                        : () => isRunning
                              ? context.read<TableTimerCubit>().pauseTimer()
                              : context.read<TableTimerCubit>().resumeTimer(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isRunning
                            ? _indigo.withOpacity(0.10)
                            : const Color(0xFF22C55E).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isRunning
                              ? _indigo.withOpacity(0.20)
                              : const Color(0xFF22C55E).withOpacity(0.20),
                        ),
                      ),
                      child: Center(
                        child: widget.timerState.isMutating
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: isRunning
                                      ? _indigo
                                      : const Color(0xFF22C55E),
                                ),
                              )
                            : Icon(
                                isRunning
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 20,
                                color: isRunning
                                    ? _indigo
                                    : const Color(0xFF22C55E),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Meta row: opened + pause history toggle ───────────
          GestureDetector(
            onTap: pauses.isNotEmpty
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border(
                  top: BorderSide(color: accentColor.withOpacity(0.15)),
                ),
              ),
              child: Row(
                children: [
                  if (startedAtStr != null) ...[
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: accentColor.withOpacity(0.6),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Ochildi: $startedAtStr',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: accentColor.withOpacity(0.7),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                  if (pauses.isNotEmpty) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 5,
                        children: [
                          const Icon(
                            Icons.pause_circle_outline_rounded,
                            size: 15,
                            color: Color(0xFFF59E0B),
                          ),
                          Text(
                            '${pauses.length}x pause',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF59E0B),
                              fontFamily: 'Inter',
                            ),
                          ),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 17,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (startedAtStr == null)
                    const Spacer(),
                ],
              ),
            ),
          ),

          // ── Expandable pause history ──────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _PauseHistoryPanel(pauses: pauses),
            crossFadeState: _expanded && pauses.isNotEmpty
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  static String _fmtTime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2, '0')}:$mm:$ss';
    return '$mm:$ss';
  }

  static String _fmtClock(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _fmtAmount(String raw) {
    // Backend "4436.39" formatida decimal qaytaradi. Nuqtani saqlab olib,
    // double ga parse qilib, yaxlitlaymiz.
    final d = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (d == null) return raw;
    final n = d.round();
    return n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }
}

// ─── Pause history dropdown panel ────────────────────────────────────────────

class _PauseHistoryPanel extends StatelessWidget {
  final List<PauseInterval> pauses;
  const _PauseHistoryPanel({required this.pauses});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: List.generate(pauses.length, (i) {
          final p = pauses[i];
          final isLast = i == pauses.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                // Index badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Paused at
                _PauseChip(
                  icon: Icons.pause_rounded,
                  label: _fmtClock(p.startedAt),
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),

                // Arrow
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: Color(0xFFCBD5E1),
                ),
                const SizedBox(width: 8),

                // Resumed at
                _PauseChip(
                  icon: Icons.play_arrow_rounded,
                  label: p.endedAt != null ? _fmtClock(p.endedAt!) : '—',
                  color: const Color(0xFF22C55E),
                ),
                const Spacer(),

                // Duration
                Text(
                  p.durationSec > 0
                      ? _fmtDuration(p.durationSec)
                      : p.endedAt != null
                      ? _fmtDuration(
                          p.endedAt!.difference(p.startedAt).inSeconds.abs(),
                        )
                      : '—',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                    fontFamily: 'Inter',
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  static String _fmtClock(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtDuration(int sec) {
    if (sec < 60) return '${sec}s';
    final m = sec ~/ 60;
    final s = sec % 60;
    if (s == 0) return '${m}min';
    return '${m}m ${s}s';
  }
}

class _PauseChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _PauseChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Icon(icon, size: 13, color: color),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
            fontFamily: 'Inter',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// HH:mm formatida sanadan vaqt chiqaradi (lokal zona).
String _fmtHm(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
