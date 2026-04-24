import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/create_order/create_order_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen_mixin.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/clear_dialog.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/show_food_additional.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
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
  late TableStatus _tableStatus;

  @override
  void initState() {
    super.initState();
    _tableStatus = widget.tableStatus;
  }

  @override
  void didUpdateWidget(OrderSidebar old) {
    super.didUpdateWidget(old);
    if (old.tableStatus != widget.tableStatus) {
      _tableStatus = widget.tableStatus;
    }
  }

  String? get tableId => widget.tableId;
  int get guestCount => widget.guestCount;
  TableStatus get tableStatus => _tableStatus;
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
                // Header — "Joriy buyurtma / N taom · M dona" + trash icon
                _OrderPanelHeader(
                  itemCount:
                      state.selectedGoods.length + state.existingGoods.length,
                  qtyTotal: [
                    ...state.selectedGoods,
                    ...state.existingGoods,
                  ].fold<int>(0, (sum, g) => sum + g.quantity),
                  canClear: state.selectedGoods.isNotEmpty,
                  onClear: () async {
                    await showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ClearDialog(
                        onSuccess: () => context.read<DetailBloc>().add(
                          const DetailEvent.clearGoods(),
                        ),
                      ),
                    );
                  },
                ),

                // Items list
                Expanded(
                  child:
                      (state.existingGoods.isEmpty &&
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
                                  color: const Color(0xFFFB6633),
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
                  child: BlocBuilder<TableTimerCubit, TableTimerState>(
                    builder: (ctx, timerState) {
                      final existingTotal = calculateTotalPrice(
                        state.existingGoods
                            .where((g) => g.commet != 'cancelled')
                            .toList(),
                      );
                      final foodTotal =
                          existingTotal +
                          calculateTotalPrice(state.selectedGoods);
                      final rawAmt = timerState.timer?.currentAmount ?? '';
                      // "4436.39" — backend decimal qaytaradi; . ni saqlash kerak
                      final timerAmt =
                          (double.tryParse(
                                rawAmt.replaceAll(RegExp(r'[^0-9.]'), ''),
                              ) ??
                              0)
                              .round();
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
                              onToggle: (v) =>
                                  setState(() => _includeService = v),
                            ),
                          if (timerState.shouldShow)
                            BlocListener<TableTimerCubit, TableTimerState>(
                              listenWhen: (p, c) =>
                                  p.isMutating && !c.isMutating,
                              listener: (ctx, _) {
                                if (cafeTable != null) {
                                  ctx.read<DetailBloc>().add(
                                    DetailEvent.fetchBillOrders(
                                      billId: cafeTable!.id,
                                      force: true,
                                    ),
                                  );
                                }
                              },
                              child: _TimerBadgeRow(timerState: timerState),
                            ),
                          Divider(color: colors.border, height: 1),
                          _SummaryRow(
                            label: S.current.strPaymentLabel,
                            value: total.formatN,
                            isTotal: true,
                          ),
                          const SizedBox(height: 4),
                          // Takeaway: create order → payment directly
                          if (tableId == null)
                            BlocProvider(
                              create: (_) => inject<CreateOrderBloc>()
                                ..add(
                                  const CreateOrderEvent.started(
                                    tableId: null,
                                    guestCount: 1,
                                    tableStatus: TableStatus.free,
                                  ),
                                ),
                              child:
                                  BlocBuilder<
                                    CreateOrderBloc,
                                    CreateOrderState
                                  >(
                                    builder: (context, createState) {
                                      return _ActionButton(
                                        label: S.current.strPayment,
                                        bgColor: const Color(0xFFFB6633),
                                        textColor: Colors.white,
                                        isLoading:
                                            createState.status ==
                                            Status.LOADING,
                                        trailingAmount: total.formatN,
                                        onTap: state.selectedGoods.isNotEmpty
                                            ? () => context
                                                  .read<CreateOrderBloc>()
                                                  .add(
                                                    CreateOrderEvent.createOrder(
                                                      orders:
                                                          state.selectedGoods,
                                                    ),
                                                  )
                                            : null,
                                      );
                                    },
                                  ),
                            ),
                          // Save button (for free tables)
                          if (tableId != null &&
                              tableStatus == TableStatus.free)
                            BlocProvider(
                              create: (_) => inject<CreateOrderBloc>()
                                ..add(
                                  CreateOrderEvent.started(
                                    tableId: tableId,
                                    guestCount: guestCount,
                                    tableStatus: tableStatus,
                                  ),
                                ),
                              child:
                                  BlocConsumer<
                                    CreateOrderBloc,
                                    CreateOrderState
                                  >(
                                    listener: (context, createState) {
                                      if (createState.status !=
                                              Status.LOADING &&
                                          createState.success) {
                                        if (createState.tableId.isNotEmpty) {
                                          context.read<SavedOrdersBloc>().add(
                                            SavedOrdersEvent.removeOrder(
                                              tableId: createState.tableId,
                                            ),
                                          );
                                        }
                                        context
                                            .read<MainCubit>()
                                            .updateTableStatus(
                                              createState.tableId,
                                              TableStatus.busy,
                                            );
                                        if (cafeTable != null) {
                                          context.read<DetailBloc>().add(
                                            DetailEvent.fetchBillOrders(
                                              billId: cafeTable!.id,
                                              force: true,
                                            ),
                                          );
                                        }
                                        context.read<DetailBloc>().add(
                                          const DetailEvent.clearGoods(),
                                        );
                                        showSuccessMessage(
                                          navigatorKey.currentContext!,
                                          S.current.strOrderSuccessCreated,
                                        );
                                        setState(
                                          () => _tableStatus = TableStatus.busy,
                                        );
                                      }
                                    },
                                    builder: (context, createState) {
                                      return _ActionButton(
                                        label: S.current.strSave,
                                        bgColor: const Color(0xFFFB6633),
                                        textColor: Colors.white,
                                        isLoading:
                                            createState.status ==
                                            Status.LOADING,
                                        onTap: state.selectedGoods.isNotEmpty
                                            ? () {
                                                final createBloc = context
                                                    .read<CreateOrderBloc>();
                                                // Just-in-time bind: agar
                                                // backend'da mavjud buyurtma
                                                // bor bo'lsa (stale UI) —
                                                // POST /order-items ga tushamiz.
                                                final activeId = context
                                                    .read<DetailBloc>()
                                                    .state
                                                    .activeOrderId;
                                                if (activeId != null) {
                                                  createBloc.bindActiveOrder(
                                                    activeId,
                                                  );
                                                }
                                                createBloc.add(
                                                  CreateOrderEvent.createOrder(
                                                    orders:
                                                        state.selectedGoods,
                                                  ),
                                                );
                                              }
                                            : null,
                                      );
                                    },
                                  ),
                            ),
                          // Busy table: add items + payment buttons
                          if (tableId != null &&
                              tableStatus != TableStatus.free)
                            BlocProvider(
                              create: (ctx) {
                                final bloc = inject<CreateOrderBloc>()
                                  ..add(
                                    CreateOrderEvent.started(
                                      tableId: tableId,
                                      guestCount: guestCount,
                                      tableStatus: tableStatus,
                                    ),
                                  );
                                // Bind active order immediately if already known
                                final activeId = ctx
                                    .read<DetailBloc>()
                                    .state
                                    .activeOrderId;
                                if (activeId != null) {
                                  bloc.bindActiveOrder(activeId);
                                }
                                return bloc;
                              },
                              child: MultiBlocListener(
                                listeners: [
                                  // Keep activeOrderId in sync when DetailBloc updates it
                                  BlocListener<DetailBloc, DetailState>(
                                    listenWhen: (p, c) =>
                                        p.activeOrderId != c.activeOrderId &&
                                        c.activeOrderId != null,
                                    listener: (ctx, s) {
                                      ctx
                                          .read<CreateOrderBloc>()
                                          .bindActiveOrder(s.activeOrderId!);
                                    },
                                  ),
                                ],
                                child:
                                    BlocConsumer<
                                      CreateOrderBloc,
                                      CreateOrderState
                                    >(
                                      listener: (context, createState) {
                                        if (createState.status !=
                                                Status.LOADING &&
                                            createState.success) {
                                          showSuccessMessage(
                                            context,
                                            S.current.strOrderSuccessCreated,
                                          );
                                          context.read<DetailBloc>().add(
                                            DetailEvent.fetchBillOrders(
                                              billId: cafeTable!.id,
                                              force: true,
                                            ),
                                          );
                                          context.read<DetailBloc>().add(
                                            const DetailEvent.clearGoods(),
                                          );
                                        }
                                      },
                                      builder: (context, createState) {
                                        return Column(
                                          spacing: 8,
                                          children: [
                                            if (state.selectedGoods.isNotEmpty)
                                              _ActionButton(
                                                label: S.current.strAddItems,
                                                bgColor: const Color(
                                                  0xFF16A34A,
                                                ),
                                                textColor: Colors.white,
                                                isLoading:
                                                    createState.status ==
                                                    Status.LOADING,
                                                onTap: () {
                                                  final createBloc = context
                                                      .read<CreateOrderBloc>();
                                                  // Just-in-time bind: agar
                                                  // BlocProvider.create
                                                  // setActiveOrderId'dan oldin
                                                  // ishga tushgan bo'lsa,
                                                  // activeOrderId hali null
                                                  // bo'lishi mumkin. Bu yerda
                                                  // DetailBloc dan so'nggi
                                                  // qiymatni o'qib beramiz —
                                                  // shunda busy shoxi POST
                                                  // /order-items ga tushadi
                                                  // (POST /orders emas).
                                                  final activeId = context
                                                      .read<DetailBloc>()
                                                      .state
                                                      .activeOrderId;
                                                  if (activeId != null) {
                                                    createBloc.bindActiveOrder(
                                                      activeId,
                                                    );
                                                  }
                                                  createBloc.add(
                                                    CreateOrderEvent.createOrder(
                                                      orders: state
                                                          .selectedGoods,
                                                    ),
                                                  );
                                                },
                                              ),
                                            _ActionButton(
                                              label: S.current.strPayment,
                                              bgColor: const Color(0xFFFB6633),
                                              textColor: Colors.white,
                                              isLoading: false,
                                              trailingAmount: total.formatN,
                                              onTap: () async {
                                                final timerCubit = context
                                                    .read<TableTimerCubit>();
                                                // Ishlab turgan bo'lsa — await bilan to'xtatamiz
                                                if (cafeTable?.tableType ==
                                                        'time_based' &&
                                                    timerCubit
                                                            .state
                                                            .timer
                                                            ?.isRunning ==
                                                        true) {
                                                  await timerCubit.pauseTimer();
                                                }
                                                // Pause so'ngra yangilangan state-dan olamiz
                                                final timerState =
                                                    timerCubit.state;
                                                final timerData =
                                                    timerState.timer;
                                                // currentAmount yo'q bo'lsa — pricePerHour × sec hisoblaymiz
                                                final hourAmt =
                                                    timerState
                                                        .effectiveCurrentAmount;
                                                if (!context.mounted) return;
                                                Navigator.pushNamed(
                                                  context,
                                                  AppRoutes.paymentScreen,
                                                  arguments: {
                                                    'table_id': tableId,
                                                    'table_type':
                                                        cafeTable?.tableType ??
                                                        'simple',
                                                    'hour_amount': hourAmt,
                                                    'timer_started_at':
                                                        timerData?.startedAt,
                                                    'timer_pauses':
                                                        timerState.billPauses
                                                            .isNotEmpty
                                                        ? timerState.billPauses
                                                        : (timerData?.pauses ??
                                                              const <PauseInterval>[]),
                                                    'timer_total_sec':
                                                        timerState
                                                                .displayActiveSec ??
                                                            timerData
                                                                ?.totalActiveSec ??
                                                            0,
                                                    'timer_price_per_hour':
                                                        timerData?.pricePerHour,
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                              ),
                            ),
                        ],
                      );
                    },
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
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Yuqori qator: ikon + nom + jami ───
            Row(
              children: [
                // Item color indicator (kichraytirildi)
                Container(
                  width: 36,
                  height: 36,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Nomi (to'liq joy oladi)
                Expanded(
                  child: Text(
                    item.goods.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      fontFamily: 'Inter',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Jami narx (o'ng tomonda)
                Text(
                  (item.goods.additionals.isNotEmpty
                          ? (item.goods.additionals
                                        .map((v) => v.price)
                                        .reduce((a, b) => a + b) +
                                    double.parse(item.goods.price)) *
                                item.quantity
                          : double.parse(item.goods.price) * item.quantity)
                      .formatN,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ─── Pastki qator: dona narxi + miqdor boshqaruvi ───
            Row(
              children: [
                Expanded(
                  child: Text(
                    double.parse(item.goods.price).formatN,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
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
            color: Color(0xFF0F172A),
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
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFFFB6633) : Colors.white,
          border: Border.all(
            color: _pressed ? const Color(0xFFFB6633) : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          widget.icon,
          size: 18,
          color: _pressed ? Colors.white : const Color(0xFF0F172A),
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
            color: isTotal ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            fontFamily: 'Inter',
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal ? const Color(0xFFFB6633) : const Color(0xFF0F172A),
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
  final String? trailingAmount;

  const _ActionButton({
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.isLoading,
    this.onTap,
    this.trailingAmount,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrailing = trailingAmount != null && trailingAmount!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        padding: hasTrailing
            ? const EdgeInsets.symmetric(horizontal: 16)
            : null,
        decoration: BoxDecoration(
          color: onTap != null ? bgColor : bgColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator.adaptive(
                    strokeWidth: 2,
                    backgroundColor: Colors.white,
                  ),
                ),
              )
            : hasTrailing
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      fontFamily: 'Inter',
                      letterSpacing: -0.1,
                    ),
                  ),
                  Text(
                    '$trailingAmount',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      fontFamily: 'Inter',
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              )
            : Center(
                child: Text(
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

class _OrderPanelHeader extends StatelessWidget {
  final int itemCount;
  final int qtyTotal;
  final bool canClear;
  final Future<void> Function() onClear;

  const _OrderPanelHeader({
    required this.itemCount,
    required this.qtyTotal,
    required this.canClear,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Joriy buyurtma',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  itemCount == 0
                      ? S.current.strSelectFoodsNotFound
                      : '$itemCount taom · $qtyTotal dona',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    fontFamily: 'Inter',
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canClear) _TrashButton(onTap: () async => await onClear()),
        ],
      ),
    );
  }
}

class _TrashButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TrashButton({required this.onTap});

  @override
  State<_TrashButton> createState() => _TrashButtonState();
}

class _TrashButtonState extends State<_TrashButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFFEE2E2) : const Color(0xFFF8FAFC),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFFFBCDD8)
                  : const Color(0xFFE2E8F0),
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 18,
            color: _hovered ? const Color(0xFFDC2626) : const Color(0xFF64748B),
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
    final textColor = isCancelled
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF0F172A);
    Color bgColor = const Color(0xFFF8FAFC);
    if (isCancelled) bgColor = const Color(0xFFFEE2E2);
    if (isOfflinePending) bgColor = const Color(0xFFF5F3FF);
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
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (double.tryParse(item.goods.price) ?? 0).formatN,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                            fontFamily: 'Inter',
                          ),
                        ),
                        if (item.createdAt != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              color: Color(0xFFCBD5E1),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _fmtHm(item.createdAt!),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                              fontFamily: 'Inter',
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
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
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                // State dot
                Container(
                  width: 8,
                  height: 8,
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
                const SizedBox(width: 8),

                // Elapsed time
                Text(
                  _fmtTime(displaySec),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    fontFamily: 'Inter',
                    letterSpacing: 0.8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),

                // Amount
                if (amountStr.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      amountStr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accentColor.withOpacity(0.85),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),

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
              color: Color(0xFF64748B),
              fontFamily: 'Inter',
            ),
          ),
        ),
        Text(
          included ? amount.formatN : '0',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0F172A),
            fontFamily: 'Inter',
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
