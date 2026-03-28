import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bgSecondary,
      body: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => inject<PaymentBloc>()
              ..add(PaymentEvent.started(tableId: tableId, orderId: orderId)),
          ),
          BlocProvider(
            create: (_) => inject<HourPriceBloc>()
              ..add(HourPriceEvent.started(orderId: tableId)),
          ),
        ],
        child: BlocBuilder<PaymentBloc, PaymentState>(
          builder: (context, state) {
            if (state.detail == null && state.status == Status.LOADING) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (state.detail == null) {
              return const Center(
                child: Text("To'lov ma'lumotlari topilmadi"),
              );
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
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: state.detail!.goods.length,
                                  separatorBuilder: (context, i) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final g = state.detail!.goods[i];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        spacing: 10,
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8F9FA),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                g.name.isNotEmpty
                                                    ? g.name[0].toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF19160B),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  g.name,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: Color(0xFF19160B),
                                                    fontFamily: 'Inter',
                                                  ),
                                                ),
                                                Text(
                                                  'x${g.quantity}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        colors.textSecondary,
                                                    fontFamily: 'Inter',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            g.price.formatN,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF19160B),
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
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
                                      int discountAmt =
                                          int.tryParse(state.discountAmount) ??
                                              0;
                                      int total =
                                          state.detail!.grandTotal.toInt();
                                      if (state.discountType ==
                                          DiscountType.money) {
                                        total -= discountAmt;
                                      } else {
                                        total -=
                                            (total * (discountAmt / 100))
                                                .round();
                                      }
                                      if (total < 0) total = 0;

                                      return Column(
                                        spacing: 8,
                                        children: [
                                          _TotalRow(
                                            label: 'Jami',
                                            value: state
                                                .detail!.grandTotal
                                                .toInt()
                                                .formatN,
                                          ),
                                          _TotalRow(
                                            label: 'Xizmat (5%)',
                                            value: state
                                                .detail!.serviceAmount
                                                .toInt()
                                                .formatN,
                                          ),
                                          if (discountAmt > 0)
                                            _TotalRow(
                                              label: 'Chegirma',
                                              value:
                                                  '- $discountAmt ${state.discountType == DiscountType.money ? "so'm" : "%"}',
                                              valueColor: const Color(
                                                0xFF13AF1B,
                                              ),
                                            ),
                                          Divider(
                                            color: colors.border,
                                            height: 1,
                                          ),
                                          _TotalRow(
                                            label: "To'lov",
                                            value: (total +
                                                    state.hourPrice.toInt())
                                                .formatN,
                                            isBold: true,
                                            valueColor:
                                                const Color(0xFFFB6633),
                                          ),
                                          // Discount controls
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

class _DiscountRow extends StatelessWidget {
  final PaymentState state;
  const _DiscountRow({required this.state});

  @override
  Widget build(BuildContext context) {
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
        _DiscountTypeBtn(
          label: '%',
          isActive: state.discountType == DiscountType.percent,
          onTap: () => context.read<PaymentBloc>().add(
            const PaymentEvent.updateDiscountType(
              dicountType: DiscountType.percent,
            ),
          ),
        ),
        _DiscountTypeBtn(
          label: "so'm",
          isActive: state.discountType == DiscountType.money,
          onTap: () => context.read<PaymentBloc>().add(
            const PaymentEvent.updateDiscountType(
              dicountType: DiscountType.money,
            ),
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
