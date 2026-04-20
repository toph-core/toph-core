import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/hour_price/hour_price_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_right_side_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_top_bar.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final args =
      ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
  late final String? tableId = args['table_id'];
  late final String? orderId = args['order_id'];
  late final double _passedHourAmount = () {
    final raw = args['hour_amount'] as String?;
    if (raw == null) return 0.0;
    // Strip decimal point too — backend sends e.g. "530.28" meaning 53028 so'm
    return double.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
  }();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bgSecondary,
      body: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) {
              final bloc = inject<PaymentBloc>()
                ..add(PaymentEvent.started(tableId: tableId, orderId: orderId));
              if (_passedHourAmount > 0) {
                bloc.add(PaymentEvent.upadeHourPrice(hourPrice: _passedHourAmount));
              }
              return bloc;
            },
          ),
          BlocProvider(
            create: (_) => inject<HourPriceBloc>(),
          ),
        ],
        child: BlocBuilder<PaymentBloc, PaymentState>(
          builder: (context, state) {
            if (state.detail == null) {
              if (state.detailStatus == Status.ERROR) {
                return const Center(
                  child: Text("To'lov ma'lumotlari topilmadi"),
                );
              }
              return const Center(child: CircularProgressIndicator.adaptive());
            }

            return Column(
              children: [
                const PaymentTopBar(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left: order summary
                      SizedBox(
                        width: 380,
                        child: Container(
                          color: Colors.white,
                          child: Column(
                            children: [
                              // Header
                              Container(
                                height: 52,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: colors.border),
                                  ),
                                ),
                                alignment: Alignment.centerLeft,
                                child: const Text(
                                  'Buyurtma',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF19160B),
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                              // Items
                              Expanded(
                                child: Builder(builder: (context) {
                                  // Group active items by name
                                  final Map<String, _PayItem> grouped = {};
                                  final List<_PayItem> cancelled = [];
                                  for (final g in state.detail!.goods) {
                                    if (g.status == 'cancelled') {
                                      cancelled.add(_PayItem(name: g.name, price: g.price.toDouble(), qty: g.quantity, isPending: false, isCancelled: true));
                                      continue;
                                    }
                                    if (grouped.containsKey(g.name)) {
                                      grouped[g.name] = grouped[g.name]!.withQty(grouped[g.name]!.qty + g.quantity);
                                    } else {
                                      grouped[g.name] = _PayItem(name: g.name, price: g.price.toDouble(), qty: g.quantity, isPending: false, isCancelled: false);
                                    }
                                  }
                                  // Offline pending items
                                  if (tableId != null) {
                                    final cachedGoods = inject<CacheService>().getGoods();
                                    for (final op in inject<OfflineQueueService>().pending.where(
                                      (o) => o.tableId == tableId && o.type == PendingOperationType.addItems,
                                    )) {
                                      try {
                                        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
                                        final items = payload['items'] as List<dynamic>;
                                        for (final item in items) {
                                          final goodId = item['good_id'] as String;
                                          final qty = (item['quantity'] as num).toInt();
                                          final goodJson = cachedGoods.firstWhere((g) => g['id'] == goodId, orElse: () => <String, dynamic>{});
                                          if (goodJson.isEmpty) continue;
                                          final name = goodJson['name'] as String? ?? goodId;
                                          final price = double.tryParse(goodJson['price']?.toString() ?? '0') ?? 0.0;
                                          final key = '⏳$name';
                                          if (grouped.containsKey(key)) {
                                            grouped[key] = grouped[key]!.withQty(grouped[key]!.qty + qty);
                                          } else {
                                            grouped[key] = _PayItem(name: '⏳ $name', price: price, qty: qty, isPending: true, isCancelled: false);
                                          }
                                        }
                                      } catch (_) {}
                                    }
                                  }
                                  final allItems = [...grouped.values, ...cancelled];
                                  return ListView.separated(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: allItems.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final g = allItems[i];
                                      final nameColor = g.isCancelled
                                          ? const Color(0xFFBBBBBB)
                                          : g.isPending
                                              ? const Color(0xFFFF9800)
                                              : const Color(0xFF19160B);
                                      return Opacity(
                                        opacity: g.isCancelled ? 0.6 : 1.0,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          child: Row(
                                            spacing: 10,
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: g.isCancelled
                                                      ? const Color(0xFFFFF0F0)
                                                      : g.isPending
                                                          ? const Color(0xFFFFF3E0)
                                                          : const Color(0xFFF8F9FA),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    g.isPending ? '⏳' : (g.name.isNotEmpty ? g.name[0].toUpperCase() : '?'),
                                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: nameColor),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      g.name,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w500,
                                                        color: nameColor,
                                                        fontFamily: 'Inter',
                                                        decoration: g.isCancelled ? TextDecoration.lineThrough : null,
                                                        decorationColor: const Color(0xFFBBBBBB),
                                                      ),
                                                    ),
                                                    if (g.isCancelled)
                                                      const Text('Bekor qilindi', style: TextStyle(fontSize: 10, color: Color(0xFFEB295B), fontFamily: 'Inter'))
                                                    else if (g.isPending)
                                                      const Text('Yuborilmoqda...', style: TextStyle(fontSize: 10, color: Color(0xFFFF9800), fontFamily: 'Inter'))
                                                    else
                                                      Text('x${g.qty}', style: TextStyle(fontSize: 12, color: colors.textSecondary, fontFamily: 'Inter')),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                (g.price * g.qty).formatN,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: nameColor,
                                                  fontFamily: 'Inter',
                                                  decoration: g.isCancelled ? TextDecoration.lineThrough : null,
                                                  decorationColor: const Color(0xFFBBBBBB),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ),
                              // Totals
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: colors.border),
                                  ),
                                ),
                                child: BlocListener<HourPriceBloc,
                                    HourPriceState>(
                                  listenWhen: (p, v) =>
                                      p.price?.totalPrice !=
                                      v.price?.totalPrice,
                                  listener: (context, hState) {
                                    if (hState.price != null) {
                                      context.read<PaymentBloc>().add(
                                        PaymentEvent.upadeHourPrice(
                                          hourPrice:
                                              hState.price!.totalPrice,
                                        ),
                                      );
                                    }
                                  },
                                  child: BlocBuilder<PaymentBloc,
                                      PaymentState>(
                                    builder: (context, state) {
                                      final effective = PaymentBloc.effectiveTotal(state.detail!);
                                      int discountAmt =
                                          int.tryParse(state.discountAmount) ?? 0;
                                      int toPay = effective;
                                      if (state.discountType == DiscountType.money) {
                                        toPay -= discountAmt;
                                      } else {
                                        toPay -= (toPay * (discountAmt / 100)).round();
                                      }
                                      if (toPay < 0) toPay = 0;
                                      final serviceAmt = state.detail!.serviceAmount.toInt();

                                      return Column(
                                        spacing: 8,
                                        children: [
                                          _TotalRow(
                                            label: 'Jami',
                                            value: effective.formatN,
                                          ),
                                          if (serviceAmt > 0)
                                            _TotalRow(
                                              label: state.detail!.servicePercent > 0
                                                  ? 'Xizmat (${state.detail!.servicePercent.toInt()}%)'
                                                  : 'Xizmat',
                                              value: serviceAmt.formatN,
                                            ),
                                          if (state.hourPrice > 0)
                                            _TotalRow(
                                              label: "Soatlik to'lov",
                                              value: state.hourPrice.toInt().formatN,
                                              valueColor: const Color(0xFF6366F1),
                                            ),
                                          if (discountAmt > 0)
                                            _TotalRow(
                                              label: 'Chegirma',
                                              value: "- $discountAmt ${state.discountType == DiscountType.money ? "so'm" : "%"}",
                                              valueColor: const Color(0xFF13AF1B),
                                            ),
                                          Divider(color: colors.border, height: 1),
                                          _TotalRow(
                                            label: "To'lov",
                                            value: (toPay + state.hourPrice.toInt()).formatN,
                                            isBold: true,
                                            valueColor: const Color(0xFFFB6633),
                                          ),
                                          const SizedBox(height: 4),
                                          _DiscountRow(state: state),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Right: payment panel
                      Expanded(
                        child: PaymentRightSideBar(detail: state.detail!),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            color: const Color(0xFF888888),
            fontFamily: 'Inter',
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? const Color(0xFF19160B),
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

class _DiscountRow extends StatefulWidget {
  final PaymentState state;
  const _DiscountRow({required this.state});

  @override
  State<_DiscountRow> createState() => _DiscountRowState();
}

class _DiscountRowState extends State<_DiscountRow> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final amt = widget.state.discountAmount;
    _ctrl = TextEditingController(text: amt == '0' ? '' : amt);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Row(
      spacing: 8,
      children: [
        const Text(
          'Chegirma:',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF888888),
            fontFamily: 'Inter',
          ),
        ),
        SizedBox(
          width: 90,
          height: 32,
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'Inter',
              color: Color(0xFF19160B),
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
              hintText: '0',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEBEFF2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFEBEFF2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFB6633)),
              ),
            ),
            onChanged: (v) => context.read<PaymentBloc>().add(
              PaymentEvent.updateDiscountAmount(amount: v.isEmpty ? '0' : v),
            ),
          ),
        ),
        _DiscountTypeBtn(
          label: '%',
          isActive: state.discountType == DiscountType.percent,
          onTap: () => context.read<PaymentBloc>().add(
            const PaymentEvent.updateDiscountType(dicountType: DiscountType.percent),
          ),
        ),
        _DiscountTypeBtn(
          label: "so'm",
          isActive: state.discountType == DiscountType.money,
          onTap: () => context.read<PaymentBloc>().add(
            const PaymentEvent.updateDiscountType(dicountType: DiscountType.money),
          ),
        ),
      ],
    );
  }
}

class _DiscountTypeBtn extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DiscountTypeBtn({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFB6633)
              : const Color(0xFFF8F9FA),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFB6633)
                : const Color(0xFFEBEFF2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : const Color(0xFF19160B),
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

class _PayItem {
  final String name;
  final double price;
  final int qty;
  final bool isPending;
  final bool isCancelled;

  const _PayItem({
    required this.name,
    required this.price,
    required this.qty,
    required this.isPending,
    required this.isCancelled,
  });

  _PayItem withQty(int newQty) => _PayItem(
        name: name,
        price: price,
        qty: newQty,
        isPending: isPending,
        isCancelled: isCancelled,
      );
}
