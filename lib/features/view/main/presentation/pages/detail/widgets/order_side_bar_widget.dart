import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/save_order/save_order_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/create_order/create_order_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen_mixin.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/clear_dialog.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/show_food_additional.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/table_timer/table_timer_cubit.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

const _indigo = Color(0xFF6366F1);

class OrderSidebar extends StatefulWidget {
  final String? tableId;
  final int guestCount;
  final TableStatus tableStatus;
  final String? orderId;
  final CafeTableModel? cafeTable;

  const OrderSidebar({
    super.key,
    this.tableId,
    required this.guestCount,
    required this.tableStatus,
    this.orderId,
    this.cafeTable,
  });

  @override
  State<OrderSidebar> createState() => _OrderSidebarState();
}

class _OrderSidebarState extends State<OrderSidebar> with DetailScreenMixin {
  bool _includeService = true;

  String? get tableId => widget.tableId;
  int get guestCount => widget.guestCount;
  TableStatus get tableStatus => widget.tableStatus;
  String? get orderId => widget.orderId;
  CafeTableModel? get cafeTable => widget.cafeTable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocListener<DetailBloc, DetailState>(
      listenWhen: (p, c) =>
          p.activeOrderId != c.activeOrderId && c.activeOrderId != null,
      listener: (ctx, s) {
        if (cafeTable?.tableType == 'time_based') {
          ctx.read<TableTimerCubit>().fetchTimer(orderId: s.activeOrderId!);
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
              // Header
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Text(
                      S.current.strOrders,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF19160B),
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (state.selectedGoods.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${state.selectedGoods.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (state.selectedGoods.isNotEmpty)
                      GestureDetector(
                        onTap: () async {
                          await showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => ClearDialog(
                              onSuccess: () => context
                                  .read<DetailBloc>()
                                  .add(const DetailEvent.clearGoods()),
                            ),
                          );
                        },
                        child: Text(
                          S.current.strClear,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFEB295B),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Items list
              Expanded(
                child: (state.existingGoods.isEmpty &&
                        state.selectedGoods.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 40,
                              color: colors.border,
                            ),
                            Text(
                              S.current.strSelectFoodsNotFound,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
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
                                color: Color(0xFFFB6633),
                              ),
                            if (state.existingGoods.isNotEmpty)
                              const SizedBox(height: 6),
                            ...state.selectedGoods.asMap().entries.map(
                              (e) => Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      e.key < state.selectedGoods.length - 1
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

              // Footer
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: colors.border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      offset: const Offset(0, -4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  spacing: 8,
                  children: [
                    BlocBuilder<TableTimerCubit, TableTimerState>(
                      builder: (ctx, timerState) {
                        final existingTotal = calculateTotalPrice(
                            state.existingGoods
                                .where((g) => g.commet != 'cancelled')
                                .toList());
                        final foodTotal = existingTotal +
                            calculateTotalPrice(state.selectedGoods);
                        final rawAmt =
                            timerState.timer?.currentAmount ?? '';
                        final timerAmt = int.tryParse(
                              rawAmt.replaceAll(RegExp(r'[^0-9]'), ''),
                            ) ??
                            0;
                        final detail = context.read<DetailBloc>().lastDetail;
                        final servicePercent = detail?.servicePercent ?? 0;
                        final serviceAmt = _includeService && servicePercent > 0
                            ? (foodTotal * servicePercent / 100).round()
                            : 0;
                        final total = foodTotal + timerAmt + serviceAmt;
                        return Column(
                          spacing: 8,
                          children: [
                            _SummaryRow(
                              label: S.current.strTotalLabel,
                              value: foodTotal.formatN,
                              isTotal: false,
                            ),
                            if (servicePercent > 0)
                              _ServiceRow(
                                percent: servicePercent,
                                amount: serviceAmt,
                                included: _includeService,
                                onToggle: (v) => setState(() => _includeService = v),
                              ),
                            if (timerState.shouldShow)
                              _TimerBadgeRow(timerState: timerState),
                            Divider(color: colors.border, height: 1),
                            _SummaryRow(
                              label: S.current.strPaymentLabel,
                              value: total.formatN,
                              isTotal: true,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    // Takeaway: create order → payment directly
                    if (tableId == null)
                      BlocProvider(
                        create: (_) => inject<CreateOrderBloc>()
                          ..add(CreateOrderEvent.started(
                            tableId: null,
                            guestCount: 1,
                            tableStatus: TableStatus.free,
                          )),
                        child: BlocBuilder<CreateOrderBloc, CreateOrderState>(
                          builder: (context, createState) {
                            return _ActionButton(
                              label: S.current.strPayment,
                              bgColor: const Color(0xFFFB6633),
                              textColor: Colors.white,
                              isLoading: createState.status == Status.LOADING,
                              onTap: state.selectedGoods.isNotEmpty
                                  ? () => context
                                      .read<CreateOrderBloc>()
                                      .add(CreateOrderEvent.createOrder(
                                        orders: state.selectedGoods,
                                      ))
                                  : null,
                            );
                          },
                        ),
                      ),
                    // Save button (for free tables)
                    if (tableId != null && tableStatus == TableStatus.free)
                      BlocProvider(
                        create: (_) => inject<CreateOrderBloc>()
                          ..add(CreateOrderEvent.started(
                            tableId: tableId,
                            guestCount: guestCount,
                            tableStatus: tableStatus,
                          )),
                        child: BlocConsumer<CreateOrderBloc, CreateOrderState>(
                          listener: (context, createState) {
                            if (createState.status != Status.LOADING &&
                                createState.success) {
                              if (cafeTable != null) {
                                context.read<SavedOrdersBloc>().add(
                                  SavedOrdersEvent.addNewOrder(
                                    order: SaveOrderModel(
                                      cafeTable: cafeTable!,
                                      createOrderRequest: CreateOrderRequestModel(
                                        tableId: createState.tableId,
                                        foods: state.selectedGoods,
                                        guestCount: guestCount,
                                        tableStatus: TableStatus.busy,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              context.read<MainCubit>().updateTableStatus(
                                createState.tableId,
                                TableStatus.busy,
                              );
                              showSuccessMessage(
                                context,
                                S.current.strOrderSuccessCreated,
                              );
                              Navigator.pop(context);
                            }
                          },
                          builder: (context, createState) {
                            return _ActionButton(
                              label: S.current.strSave,
                              bgColor: const Color(0xFFFB6633),
                              textColor: Colors.white,
                              isLoading: createState.status == Status.LOADING,
                              onTap: state.selectedGoods.isNotEmpty
                                  ? () {
                                      context.read<CreateOrderBloc>().add(
                                        CreateOrderEvent.createOrder(
                                          orders: state.selectedGoods,
                                        ),
                                      );
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                    // Busy table: add items + payment buttons
                    if (tableId != null && tableStatus != TableStatus.free)
                      BlocProvider(
                        create: (_) => inject<CreateOrderBloc>()
                          ..add(CreateOrderEvent.started(
                            tableId: tableId,
                            guestCount: guestCount,
                            tableStatus: tableStatus,
                          )),
                        child: BlocConsumer<CreateOrderBloc, CreateOrderState>(
                          listener: (context, createState) {
                            if (createState.status != Status.LOADING &&
                                createState.success) {
                              showSuccessMessage(
                                context,
                                S.current.strOrderSuccessCreated,
                              );
                              context
                                  .read<DetailBloc>()
                                  .add(DetailEvent.fetchBillOrders(
                                    billId: cafeTable!.id,
                                  ));
                              context
                                  .read<DetailBloc>()
                                  .add(const DetailEvent.clearGoods());
                            }
                          },
                          builder: (context, createState) {
                            return Column(
                              spacing: 8,
                              children: [
                                if (state.selectedGoods.isNotEmpty)
                                  _ActionButton(
                                    label: S.current.strAddItems,
                                    bgColor: const Color(0xFF13AF1B),
                                    textColor: Colors.white,
                                    isLoading:
                                        createState.status == Status.LOADING,
                                    onTap: () {
                                      context.read<CreateOrderBloc>().add(
                                        CreateOrderEvent.createOrder(
                                          orders: state.selectedGoods,
                                        ),
                                      );
                                    },
                                  ),
                                _ActionButton(
                                  label: S.current.strPayment,
                                  bgColor: const Color(0xFFFB6633),
                                  textColor: Colors.white,
                                  isLoading: false,
                                  onTap: () {
                                    final timerCubit = context.read<TableTimerCubit>();
                                    final currentAmt = timerCubit.state.timer?.currentAmount;
                                    if (cafeTable?.tableType == 'time_based' &&
                                        timerCubit.state.timer?.isRunning == true) {
                                      timerCubit.pauseTimer();
                                    }
                                    Navigator.pushNamed(
                                      context,
                                      AppRoutes.paymentScreen,
                                      arguments: {
                                        'table_id': tableId,
                                        'table_type': cafeTable?.tableType ?? 'simple',
                                        'hour_amount': currentAmt,
                                      },
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
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
            (v) => v.price == additionals[i].price && v.title == additionals[i].title,
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
            comment: item.commet,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          spacing: 12,
          children: [
            // Item color indicator
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Center(
                child: Text(
                  item.goods.name.isNotEmpty
                      ? item.goods.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            // Name + price
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.goods.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF19160B),
                      fontFamily: 'Inter',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    double.parse(item.goods.price).formatN,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            // Qty control
            _QtyControl(
              quantity: item.quantity,
              onDecrement: () => context.read<DetailBloc>().add(
                DetailEvent.decrementQuantity(goodsId: item.goods.id),
              ),
              onIncrement: () => context.read<DetailBloc>().add(
                DetailEvent.incrementQuantity(goodsId: item.goods.id),
              ),
            ),
            // Total
            SizedBox(
              width: 72,
              child: Text(
                (item.goods.additionals.isNotEmpty
                        ? (item.goods.additionals
                                    .map((v) => v.price)
                                    .reduce((a, b) => a + b) +
                                double.parse(item.goods.price)) *
                            item.quantity
                        : double.parse(item.goods.price) * item.quantity)
                    .formatN,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF19160B),
                  fontFamily: 'Inter',
                ),
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
      spacing: 6,
      children: [
        _QtyBtn(icon: Icons.remove, onTap: onDecrement),
        Text(
          '$quantity',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF19160B),
            fontFamily: 'Inter',
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
            color: _pressed
                ? const Color(0xFFFB6633)
                : const Color(0xFFEBEFF2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          widget.icon,
          size: 14,
          color: _pressed ? Colors.white : const Color(0xFF19160B),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.isTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
            color: isTotal
                ? const Color(0xFF19160B)
                : const Color(0xFF888888),
            fontFamily: 'Inter',
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal
                ? const Color(0xFFFB6633)
                : const Color(0xFF19160B),
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.isLoading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: onTap != null ? bgColor : bgColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator.adaptive(
                    strokeWidth: 2,
                    backgroundColor: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    fontFamily: 'Inter',
                  ),
                ),
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

  @override
  Widget build(BuildContext context) {
    final isCancelled = item.commet == 'cancelled';
    final isOfflinePending = item.commet == 'pending_offline';
    final textColor = isCancelled ? const Color(0xFFBBBBBB) : const Color(0xFF19160B);
    Color bgColor = const Color(0xFFF5F4F2);
    if (isCancelled) bgColor = const Color(0xFFFFF0F0);
    if (isOfflinePending) bgColor = const Color(0xFFFFF8F0);
    return Opacity(
      opacity: isCancelled ? 0.6 : 1.0,
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
                  color: isCancelled ? const Color(0xFFBBBBBB) : const Color(0xFF888888),
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
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                    decorationColor: const Color(0xFFBBBBBB),
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
                      color: Color(0xFFEB295B),
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
                else
                  Text(
                    (double.tryParse(item.goods.price) ?? 0).formatN,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF888888),
                      fontFamily: 'Inter',
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'x${item.quantity}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isCancelled ? const Color(0xFFBBBBBB) : const Color(0xFF888888),
              fontFamily: 'Inter',
              decoration: isCancelled ? TextDecoration.lineThrough : null,
              decorationColor: const Color(0xFFBBBBBB),
            ),
          ),
          Text(
            ((double.tryParse(item.goods.price) ?? 0) * item.quantity).formatN,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor,
              fontFamily: 'Inter',
              decoration: isCancelled ? TextDecoration.lineThrough : null,
              decorationColor: const Color(0xFFBBBBBB),
            ),
          ),
          if (tableId != null && !isOfflinePending && !isCancelled)
            GestureDetector(
              onTap: () async {
                final bloc = context.read<DetailBloc>();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text(
                      "O'chirishni tasdiqlang",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    content: Text(
                      "'${item.goods.name}' ni o'chirmoqchimisiz?",
                      style: const TextStyle(fontSize: 14),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Yo'q"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'Ha',
                          style: TextStyle(color: Color(0xFFEB295B)),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  bloc.add(DetailEvent.cancelOrderItem(
                    itemId: item.uniqueId,
                    tableId: tableId!,
                  ));
                }
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: Color(0xFFEB295B),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

class _TimerBadgeRow extends StatelessWidget {
  final TableTimerState timerState;
  const _TimerBadgeRow({required this.timerState});

  @override
  Widget build(BuildContext context) {
    final t = timerState.timer!;
    final displaySec = timerState.displayActiveSec ?? t.totalActiveSec;
    final isRunning = t.stateNormalized == 'running';
    final isPaused = t.stateNormalized == 'paused';
    final rawAmt = t.currentAmount ?? '';
    final amountStr = rawAmt.isNotEmpty
        ? '${_fmtAmount(rawAmt)} so\'m'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _indigo.withOpacity(0.15),
            _indigo.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _indigo.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Icon(
            isRunning ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 13,
            color: _indigo,
          ),
          const SizedBox(width: 5),
          Text(
            _fmtTime(displaySec),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _indigo,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          if (amountStr.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                amountStr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _indigo.withOpacity(0.80),
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (isRunning || isPaused) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: timerState.isMutating
                  ? null
                  : () => isRunning
                      ? context.read<TableTimerCubit>().pauseTimer()
                      : context.read<TableTimerCubit>().resumeTimer(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isRunning
                      ? const Color(0xFFFB6633).withOpacity(0.12)
                      : const Color(0xFF13AF1B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: timerState.isMutating
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isRunning
                                ? const Color(0xFFFB6633)
                                : const Color(0xFF13AF1B),
                          ),
                        )
                      : Icon(
                          isRunning
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                          color: isRunning
                              ? const Color(0xFFFB6633)
                              : const Color(0xFF13AF1B),
                        ),
                ),
              ),
            ),
          ],
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

  static String _fmtAmount(String raw) {
    final n = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n == null) return raw;
    return n
        .toString()
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
  }
}

class _ServiceRow extends StatelessWidget {
  final double percent;
  final int amount;
  final bool included;
  final ValueChanged<bool> onToggle;

  const _ServiceRow({
    required this.percent,
    required this.amount,
    required this.included,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: included,
          onChanged: (v) => onToggle(v ?? false),
          activeColor: const Color(0xFFFB6633),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: Text(
            'Xizmat (${percent.toInt()}%)',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF888888),
              fontFamily: 'Inter',
            ),
          ),
        ),
        Text(
          included ? amount.formatN : '0',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF19160B),
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}
