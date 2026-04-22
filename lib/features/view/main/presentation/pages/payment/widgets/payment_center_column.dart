import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/payment_screen_mixin.dart';

const _kS900 = Color(0xFF0F172A);
const _kS700 = Color(0xFF334155);
const _kS500 = Color(0xFF64748B);
const _kS200 = Color(0xFFE2E8F0);
const _kS100 = Color(0xFFF1F5F9);
const _kS50 = Color(0xFFF8FAFC);
const _kGreen = Color(0xFF16A34A);
const _kGreenBg = Color(0xFFDCFCE7);
const _kRed = Color(0xFFDC2626);
const _kRedBg = Color(0xFFFEE2E2);

class PaymentCenterColumn extends StatelessWidget with PaymentScreenMixin {
  final int finalTotal;
  PaymentCenterColumn({super.key, required this.finalTotal});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kS50,
      padding: const EdgeInsets.all(20),
      child: BlocBuilder<PaymentBloc, PaymentState>(
        builder: (context, state) {
          final entered = int.tryParse(state.enterSum) ?? 0;
          final change = entered > finalTotal ? entered - finalTotal : 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Payment type tabs (2 wide pills: Naqd / Karta)
              _PayTypeTabs(state: state),
              const SizedBox(height: 18),

              // Amount entry block
              _AmountEntry(
                entered: entered,
                change: change,
                showChange:
                    state.paymentType == PaymentType.cash && change > 0,
              ),
              const SizedBox(height: 14),

              // Quick amount pills
              if (state.paymentType == PaymentType.cash)
                _QuickAmountPills(
                  currentEntered: entered,
                  finalTotal: finalTotal,
                ),

              if (state.paymentType == PaymentType.cash) ...[
                const SizedBox(height: 14),
                // Numpad (large buttons)
                Expanded(child: _Numpad()),
              ] else
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        "Mijoz to'lovni karta orqali amalga oshirganini tasdiqlang",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _kS500,
                          fontFamily: 'Inter',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PayTypeTabs extends StatelessWidget {
  final PaymentState state;
  const _PayTypeTabs({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PayTypePill(
            label: 'Naqd',
            icon: Icons.payments_outlined,
            isActive: state.paymentType == PaymentType.cash,
            onTap: () => context.read<PaymentBloc>().add(
              const PaymentEvent.updatePaymentType(
                paymentType: PaymentType.cash,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PayTypePill(
            label: 'Karta',
            icon: Icons.credit_card_outlined,
            isActive: state.paymentType == PaymentType.card,
            onTap: () => context.read<PaymentBloc>().add(
              const PaymentEvent.updatePaymentType(
                paymentType: PaymentType.card,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PayTypePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _PayTypePill({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: isActive ? _kBrand : Colors.white,
          border: Border.all(color: isActive ? _kBrand : _kS200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.white : _kS700,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.white : _kS900,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _kBrand = Color(0xFFFB6633);

class _AmountEntry extends StatelessWidget {
  final int entered;
  final int change;
  final bool showChange;

  const _AmountEntry({
    required this.entered,
    required this.change,
    required this.showChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Qabul qilingan',
            style: TextStyle(
              fontSize: 13,
              color: _kS500,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                entered > 0 ? entered.formatN : '0',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: _kS900,
                  fontFamily: 'Inter',
                  height: 1.1,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "so'm",
                style: TextStyle(
                  fontSize: 14,
                  color: _kS500,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          if (showChange) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _kGreenBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Qaytim',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _kGreen,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${change.formatN} so\'m',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kGreen,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAmountPills extends StatelessWidget {
  final int currentEntered;
  final int finalTotal;

  const _QuickAmountPills({
    required this.currentEntered,
    required this.finalTotal,
  });

  @override
  Widget build(BuildContext context) {
    final options = <({String label, int? amount})>[
      (label: 'Aniq summa', amount: finalTotal),
      (label: '100 000', amount: 100000),
      (label: '200 000', amount: 200000),
      (label: '500 000', amount: 500000),
      (label: '1 000 000', amount: 1000000),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final opt = options[i];
          final isActive = opt.amount != null &&
              currentEntered == opt.amount &&
              opt.amount != 0;
          return _QuickPill(
            label: opt.label,
            isActive: isActive,
            onTap: () => context.read<PaymentBloc>().add(
              PaymentEvent.updateEnterSum(symbol: 'set:${opt.amount ?? 0}'),
            ),
          );
        },
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? _kBrand : Colors.white,
          border: Border.all(color: isActive ? _kBrand : _kS200),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? Colors.white : _kS700,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

class _Numpad extends StatelessWidget with PaymentScreenMixin {
  _Numpad();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const cols = 3;
        const spacing = 10.0;
        final cellW = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        final maxCellH = (constraints.maxHeight - spacing * 3) / 4;
        final cellH = maxCellH.clamp(56.0, 80.0);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: keyboardKeys.map((key) {
            final isDelete = key == 'delete';
            return SizedBox(
              width: cellW,
              height: cellH,
              child: _NumpadButton(
                keyLabel: key,
                isDelete: isDelete,
                onTap: () => context.read<PaymentBloc>().add(
                  PaymentEvent.updateEnterSum(symbol: key),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _NumpadButton extends StatefulWidget {
  final String keyLabel;
  final bool isDelete;
  final VoidCallback onTap;

  const _NumpadButton({
    required this.keyLabel,
    required this.isDelete,
    required this.onTap,
  });

  @override
  State<_NumpadButton> createState() => _NumpadButtonState();
}

class _NumpadButtonState extends State<_NumpadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDelete
        ? (_pressed ? const Color(0xFFFBCDD8) : _kRedBg)
        : (_pressed ? _kS200 : _kS100);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: widget.isDelete
              ? const Icon(
                  Icons.backspace_outlined,
                  size: 22,
                  color: _kRed,
                )
              : Text(
                  widget.keyLabel,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: _kS900,
                    fontFamily: 'Inter',
                  ),
                ),
        ),
      ),
    );
  }
}
