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
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/send_to_kitchen_dialog.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/show_food_additional.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class OrderSidebar extends StatelessWidget with DetailScreenMixin {
  final String? tableId;
  final int guestCount;
  final TableStatus tableStatus;
  final String? orderId;
  final CafeTableModel? cafeTable;

  OrderSidebar({
    super.key,
    this.tableId,
    required this.guestCount,
    required this.tableStatus,
    this.orderId,
    this.cafeTable,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocBuilder<DetailBloc, DetailState>(
      buildWhen: (p, c) => p.selectedGoods != c.selectedGoods,
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
                    const Text(
                      'Buyurtmalar',
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
                        child: const Text(
                          'Tozalash',
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
                child: state.selectedGoods.isEmpty
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
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: state.selectedGoods.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _OrderItem(item: state.selectedGoods[i]),
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
                    _SummaryRow(
                      label: 'Jami:',
                      value: calculateTotalPrice(state.selectedGoods).formatN,
                      isTotal: false,
                    ),
                    Divider(color: colors.border, height: 1),
                    _SummaryRow(
                      label: 'To\'lov:',
                      value: calculateTotalPrice(state.selectedGoods).formatN,
                      isTotal: true,
                    ),
                    const SizedBox(height: 4),
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
                              // Add order to SavedOrdersBloc
                              print('DEBUG: Saving order - selectedGoods count: ${state.selectedGoods.length}');
                              print('DEBUG: cafeTable: $cafeTable');
                              print('DEBUG: createState.tableId: ${createState.tableId}');

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
                                print('DEBUG: Order added to SavedOrdersBloc');
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
                              label: 'Saqlash',
                              bgColor: const Color(0xFFFB6633),
                              textColor: Colors.white,
                              isLoading: createState.status == Status.LOADING,
                              onTap: state.selectedGoods.isNotEmpty
                                  ? () async {
                                      final bloc = context.read<CreateOrderBloc>();
                                      final goods = state.selectedGoods;
                                      final result = await showDialog<bool>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) =>
                                            const SendToKitchenDialog(),
                                      );
                                      if (result == true) {
                                        bloc.add(
                                          CreateOrderEvent.createOrder(
                                            orders: goods,
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                    // Payment button (for occupied tables)
                    if (tableId != null && tableStatus != TableStatus.free)
                      BlocProvider(
                        create: (_) => inject<CreateOrderBloc>()
                          ..add(CreateOrderEvent.started(
                            tableId: tableId,
                            guestCount: guestCount,
                            tableStatus: tableStatus,
                          )),
                        child: BlocBuilder<CreateOrderBloc, CreateOrderState>(
                          builder: (context, createState) {
                            return _ActionButton(
                              label: 'To\'lov',
                              bgColor: const Color(0xFFFB6633),
                              textColor: Colors.white,
                              isLoading: createState.status == Status.LOADING,
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.paymentScreen,
                                  arguments: {'table_id': tableId},
                                );
                              },
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
