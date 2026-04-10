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
                final closing = state.shift != null;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final maxH = constraints.maxHeight;
                    final compactW = maxW < 1100;
                    final shortH = maxH < 720;
                    final edge = compactW ? 12.0 : 20.0;
                    final gap = compactW ? 12.0 : 20.0;
                    final rightW = compactW ? 300.0 : 380.0;
                    final keyExtent = shortH ? 48.0 : 56.0;
                    final keyGap = shortH ? 6.0 : 8.0;

                    if (closing) {
                      return Padding(
                        padding: EdgeInsets.all(edge),
                        child: Row(
                          spacing: gap,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Column(
                                spacing: compactW ? 12 : 16,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _ShiftInfoCard(state: state),
                                  Expanded(
                                    child: Center(
                                      child: SingleChildScrollView(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 16,
                                          ),
                                          child: Text(
                                            'Smenani yopish uchun pastdagi tugmani bosing.\n\n'
                                            'Yakuniy naqd/terminal summasini kiritish shart emas.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: compactW ? 14 : 15,
                                              height: 1.5,
                                              color: const Color(0xFF666666),
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: rightW,
                              child: const Align(
                                alignment: Alignment.bottomCenter,
                                child: WShiftBottom(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Padding(
                      padding: EdgeInsets.all(edge),
                      child: Row(
                        spacing: gap,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              spacing: compactW ? 12 : 16,
                              children: [
                                _ShiftInfoCard(state: state),
                                _StatsRow(
                                  cashAmount: cashAmount,
                                  cardAmount: cardAmount,
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: _PaymentBreakdownCard(
                                      cashAmount: cashAmount,
                                      cardAmount: cardAmount,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: rightW,
                            child: Column(
                              spacing: compactW ? 12 : 16,
                              children: [
                                Row(
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
                                        title: "Naqd (boshlang'ich)",
                                        value: state.cashSum,
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
                                        title: "Terminal (boshlang'ich)",
                                        value: cardAmount.toString(),
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, g) {
                                      final cellW =
                                          (g.maxWidth - 2 * keyGap) / 3;
                                      final ar = cellW / keyExtent;
                                      return GridView.builder(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          crossAxisSpacing: keyGap,
                                          mainAxisSpacing: keyGap,
                                          childAspectRatio: ar > 0 ? ar : 1,
                                        ),
                                        itemCount: keyboardKeys.length,
                                        itemBuilder: (context, index) {
                                          final String key =
                                              keyboardKeys[index];
                                          return _keyboardKey(
                                            context,
                                            key,
                                            state.sum,
                                          );
                                        },
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          Column(
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
          const SizedBox(width: 32),
          Container(width: 1, height: 36, color: const Color(0xFFEBEBEB)),
          const SizedBox(width: 32),
          Column(
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
          const SizedBox(width: 32),
          Container(width: 1, height: 36, color: const Color(0xFFEBEBEB)),
          const SizedBox(width: 32),
          const Column(
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
          const SizedBox(width: 24),
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
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int cashAmount;
  final int cardAmount;

  const _StatsRow({
    required this.cashAmount,
    required this.cardAmount,
  });

  @override
  Widget build(BuildContext context) {
    const w = 168.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 12,
        children: [
          SizedBox(
            width: w,
            child: _StatCard(
              label: "Kassa (boshlang'ich)",
              value: cashAmount.toString(),
              sub: "so'm",
              bgColor: const Color(0xFFE8F9E9),
              valueColor: const Color(0xFF13AF1B),
            ),
          ),
          SizedBox(
            width: w,
            child: _StatCard(
              label: "Terminal (boshlang'ich)",
              value: cardAmount.toString(),
              sub: "so'm",
              bgColor: const Color(0xFFEEF2FF),
              valueColor: const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(
            width: w,
            child: _StatCard(
              label: 'Smena',
              value: '#',
              sub: 'joriy',
              bgColor: Color(0xFFF5F4F2),
              valueColor: Color(0xFF19160B),
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
    return Container(
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    );
  }
}

class _PaymentBreakdownCard extends StatelessWidget {
  final int cashAmount;
  final int cardAmount;

  const _PaymentBreakdownCard({
    required this.cashAmount,
    required this.cardAmount,
  });

  @override
  Widget build(BuildContext context) {
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
            "Boshlang'ich qoldiq",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF19160B),
              fontFamily: 'Inter',
            ),
          ),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF13AF1B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Naqd',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
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
                        'Terminal',
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
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  value: 1,
                  minHeight: 8,
                  backgroundColor: Color(0xFFF5F4F2),
                  valueColor: AlwaysStoppedAnimation<Color>(
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
