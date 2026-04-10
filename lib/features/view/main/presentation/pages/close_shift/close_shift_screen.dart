import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/w_shift_bottom.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/w_shift_input_sum_container.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';

class CloseShiftScreen extends StatefulWidget {
  const CloseShiftScreen({super.key});

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  late final DateTime enterDate = DateTime.now();
  Timer? _ticker;
  final List<String> keyboardKeys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'delete',
    '0',
    '00',
  ];

  @override
  void initState() {
    super.initState();
    // Make the UI (duration, time) update even without backend.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      activeRoute: AppRoutes.closeShiftScreen,
      body: Column(
        children: [
          const MainHeader(title: 'Kasir'),
          Expanded(
            child: BlocBuilder<ShiftBloc, ShiftState>(
              builder: (context, state) {
                final cashAmount = int.tryParse(state.cashSum) ?? 0;
                final cardAmount = int.tryParse(state.cardSum) ?? 0;
                final totalAmount = cashAmount + cardAmount;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final maxH = constraints.maxHeight;
                    // ~1024×768 POS: chap panel uchun joy saqlash
                    final compactW = maxW < 1100;
                    final shortH = maxH < 720;
                    final edge = compactW ? 12.0 : 20.0;
                    final gap = compactW ? 12.0 : 20.0;
                    final rightW = compactW ? 300.0 : 380.0;
                    final keyExtent = shortH ? 48.0 : 56.0;
                    final keyGap = shortH ? 6.0 : 8.0;

                    return Padding(
                      padding: EdgeInsets.all(edge),
                      child: Row(
                        spacing: gap,
                        children: [
                          // LEFT PANEL — Dashboard
                          Expanded(
                            flex: 3,
                            child: Column(
                              spacing: compactW ? 12 : 16,
                              children: [
                                _ShiftInfoCard(state: state),
                                _StatsRow(
                                  cashAmount: cashAmount,
                                  cardAmount: cardAmount,
                                  totalAmount: totalAmount,
                                ),
                                Expanded(
                                  child: _PaymentBreakdownCard(
                                    cashAmount: cashAmount,
                                    cardAmount: cardAmount,
                                    totalAmount: totalAmount,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // RIGHT PANEL — Numpad
                          SizedBox(
                            width: rightW,
                            child: Column(
                              spacing: compactW ? 12 : 16,
                              children: [
                                Expanded(
                                  flex: 0,
                                  child: Row(
                                    spacing: compactW ? 8 : 12,
                                    children: [
                                      Expanded(
                                        child: WShiftInputSumContainer(
                                          onTap: () => context
                                              .read<ShiftBloc>()
                                              .add(
                                                const ShiftEvent.updateSumType(
                                                  type: ShiftSumType.cash,
                                                ),
                                              ),
                                          selected:
                                              state.sum == ShiftSumType.cash,
                                          title: "Naqt summani kiriting",
                                          value: cashAmount.toString(),
                                        ),
                                      ),
                                      Expanded(
                                        child: WShiftInputSumContainer(
                                          onTap: () => context
                                              .read<ShiftBloc>()
                                              .add(
                                                const ShiftEvent.updateSumType(
                                                  type: ShiftSumType.card,
                                                ),
                                              ),
                                          selected:
                                              state.sum == ShiftSumType.card,
                                          title: "Terminal summani kiriting",
                                          value: cardAmount.toString(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: keyGap,
                                      mainAxisSpacing: keyGap,
                                      mainAxisExtent: keyExtent,
                                    ),
                                    itemCount: keyboardKeys.length,
                                    itemBuilder: (context, index) {
                                      final String key = keyboardKeys[index];
                                      return _keyboardKey(
                                        context,
                                        key,
                                        state.sum,
                                      );
                                    },
                                  ),
                                ),
                                const WShiftBottom(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyboardKey(BuildContext context, String key, ShiftSumType type) {
    final bool isDelete = key == 'delete';
    return CustomHoverEffectWidget(
      onTap: () {
        if (type == ShiftSumType.card) {
          context.read<ShiftBloc>().add(ShiftEvent.updateCardSum(value: key));
        } else {
          context.read<ShiftBloc>().add(ShiftEvent.updateCashSum(value: key));
        }
      },
      bgColor: isDelete
          ? AppColors.ffDB2020.withOpacity(.10)
          : const Color(0xFFF8F9FA),
      borderRadius: BorderRadius.circular(10),
      child: Center(
        child: isDelete
            ? const Icon(
                Icons.backspace_outlined,
                color: AppColors.ffDB2020,
                size: 26,
              )
            : Text(
                key,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF19160B),
                  fontFamily: 'Inter',
                ),
              ),
      ),
    );
  }
}

class _ShiftInfoCard extends StatelessWidget {
  final ShiftState state;
  const _ShiftInfoCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final openTime = state.shift?.openedAt;
    final durationMinutes = openTime != null
        ? DateTime.now().difference(openTime).inMinutes
        : 0;
    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;
    final durationStr =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEBEBEB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                const Text(
                  'Kasir',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF888888),
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  state.shift?.cashierId ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Container(width: 1, height: 36, color: const Color(0xFFEBEBEB)),
          const SizedBox(width: 32),
          Expanded(
            flex: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                const Text(
                  'Smena ochildi',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF888888),
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  openTime != null
                      ? '${openTime.hour.toString().padLeft(2, '0')}:${openTime.minute.toString().padLeft(2, '0')}'
                      : '--:--',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Container(width: 1, height: 36, color: const Color(0xFFEBEBEB)),
          const SizedBox(width: 32),
          const Expanded(
            flex: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  'Terminal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF888888),
                    fontFamily: 'Inter',
                  ),
                ),
                Row(
                  spacing: 4,
                  children: [
                    Icon(Icons.circle, size: 6, color: Color(0xFF13AF1B)),
                    Text(
                      'Ulangan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF13AF1B),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3EE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              spacing: 3,
              children: [
                const Text(
                  'Davomiyligi',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFFB6633),
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  durationStr,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFB6633),
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

class _StatsRow extends StatelessWidget {
  final int cashAmount;
  final int cardAmount;
  final int totalAmount;

  const _StatsRow({
    required this.cashAmount,
    required this.cardAmount,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 16,
      children: [
        _StatCard(
          label: 'Kassadagi naqd',
          value: cashAmount.toString(),
          sub: "so'm",
          bgColor: const Color(0xFFE8F9E9),
          valueColor: const Color(0xFF13AF1B),
        ),
        _StatCard(
          label: "Karta bo'yicha",
          value: cardAmount.toString(),
          sub: "so'm",
          bgColor: const Color(0xFFEEF2FF),
          valueColor: const Color(0xFF3B82F6),
        ),
        _StatCard(
          label: 'Umumiy tushum',
          value: totalAmount.toString(),
          sub: "so'm",
          bgColor: const Color(0xFFFFF3EE),
          valueColor: const Color(0xFFFB6633),
        ),
        const _StatCard(
          label: 'Smena raqami',
          value: 'Smena #',
          sub: 'joriy',
          bgColor: Color(0xFFF5F4F2),
          valueColor: Color(0xFF19160B),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color bgColor;
  final Color valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.bgColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFEBEBEB)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: valueColor,
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

class _PaymentBreakdownCard extends StatelessWidget {
  final int cashAmount;
  final int cardAmount;
  final int totalAmount;

  const _PaymentBreakdownCard({
    required this.cashAmount,
    required this.cardAmount,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    final cashPct = totalAmount > 0
        ? (cashAmount / totalAmount * 100).toInt()
        : 0;
    final cardPct = totalAmount > 0
        ? (cardAmount / totalAmount * 100).toInt()
        : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEBEBEB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: [
          const Text(
            'To\'lov usullari',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF19160B),
              fontFamily: 'Inter',
            ),
          ),
          // Naqd
          Column(
            spacing: 6,
            children: [
              Row(
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF13AF1B),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Text(
                        'Naqd',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF19160B),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    spacing: 8,
                    children: [
                      Text(
                        '$cashPct%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF888888),
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        '$cashAmount so\'m',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF19160B),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: totalAmount > 0 ? cashAmount / totalAmount : 0,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF5F4F2),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF13AF1B),
                  ),
                ),
              ),
            ],
          ),
          // Karta
          Column(
            spacing: 6,
            children: [
              Row(
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3B82F6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Text(
                        'Karta',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF19160B),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    spacing: 8,
                    children: [
                      Text(
                        '$cardPct%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF888888),
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        '$cardAmount so\'m',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF19160B),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: totalAmount > 0 ? cardAmount / totalAmount : 0,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF5F4F2),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
