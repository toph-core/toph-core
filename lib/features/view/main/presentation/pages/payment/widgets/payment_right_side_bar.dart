import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/payment_screen_mixin.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';

class PaymentRightSideBar extends StatelessWidget with PaymentScreenMixin {
  final ArchiveDetailEntity detail;
  PaymentRightSideBar({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: context.colors.border),
        ),
      ),
      child: BlocBuilder<PaymentBloc, PaymentState>(
        builder: (context, state) {
          final int discountAmt = int.tryParse(state.discountAmount) ?? 0;
          int finalTotal = detail.grandTotal.toInt();
          if (state.discountType == DiscountType.money) {
            finalTotal -= discountAmt;
          } else {
            finalTotal -= (finalTotal * (discountAmt / 100)).round();
          }
          if (finalTotal < 0) finalTotal = 0;
          finalTotal += state.hourPrice.toInt();

          final int entered = int.tryParse(state.enterSum) ?? 0;
          final int change = entered > finalTotal ? entered - finalTotal : 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total display
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.colors.border),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      "Jami to'lov",
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      finalTotal.formatN,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF19160B),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),

              // Payment method selector
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    const Text(
                      "To'lov usuli",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF19160B),
                        fontFamily: 'Inter',
                      ),
                    ),
                    Row(
                      spacing: 10,
                      children: [
                        _PayMethod(
                          label: 'Naqd',
                          icon: SvgPicture.asset(
                            Assets.icons.icCash.path,
                            width: 24,
                            height: 24,
                          ),
                          isActive: state.paymentType == PaymentType.cash,
                          onTap: () => context.read<PaymentBloc>().add(
                            const PaymentEvent.updatePaymentType(
                              paymentType: PaymentType.cash,
                            ),
                          ),
                        ),
                        _PayMethod(
                          label: 'Karta',
                          icon: SvgPicture.asset(
                            Assets.icons.icCard.path,
                            width: 24,
                            height: 24,
                          ),
                          isActive: state.paymentType == PaymentType.card,
                          onTap: () => context.read<PaymentBloc>().add(
                            const PaymentEvent.updatePaymentType(
                              paymentType: PaymentType.card,
                            ),
                          ),
                        ),
                        _PayMethod(
                          label: 'QR',
                          icon: SvgPicture.asset(
                            Assets.icons.icQr.path,
                            width: 24,
                            height: 24,
                          ),
                          isActive: state.paymentType == PaymentType.qr,
                          onTap: () => context.read<PaymentBloc>().add(
                            const PaymentEvent.updatePaymentType(
                              paymentType: PaymentType.qr,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Amount display (cash only)
              if (state.paymentType == PaymentType.cash) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      border: Border.all(color: const Color(0xFFEBEFF2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          'Berilayotgan summa',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        Text(
                          entered > 0 ? entered.formatN : '0',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF19160B),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Numpad
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            mainAxisExtent: 52,
                          ),
                      itemCount: keyboardKeys.length,
                      itemBuilder: (context, index) {
                        final key = keyboardKeys[index];
                        final isDelete = key == 'delete';
                        return GestureDetector(
                          onTap: () => context.read<PaymentBloc>().add(
                            PaymentEvent.updateEnterSum(symbol: key),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDelete
                                  ? const Color(0xFFFFF0F3)
                                  : const Color(0xFFF8F9FA),
                              border: Border.all(
                                color: isDelete
                                    ? const Color(0xFFFBCDD8)
                                    : const Color(0xFFEBEFF2),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: isDelete
                                  ? const Icon(
                                      Icons.backspace_outlined,
                                      size: 20,
                                      color: Color(0xFFEB295B),
                                    )
                                  : Text(
                                      key,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF19160B),
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],

              // Card / QR confirmation message
              if (state.paymentType != PaymentType.cash)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        state.paymentType == PaymentType.card
                            ? "Mijoz to'lovni karta orqali amalga oshirganini tasdiqlang"
                            : "Mijoz to'lovni QR kod orqali amalga oshirganini tasdiqlang",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ),

              // Change row (only when cash and entered > total)
              if (state.paymentType == PaymentType.cash && change > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1FAF1),
                      border: Border.all(color: const Color(0xFF13AF1B)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Qaytim',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF13AF1B),
                            fontFamily: 'Inter',
                          ),
                        ),
                        Text(
                          change.formatN,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF13AF1B),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Footer: print + confirm
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.colors.border),
                  ),
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        border: Border.all(color: const Color(0xFFEBEFF2)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          Assets.icons.icPrinter.path,
                          width: 22,
                          height: 22,
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (state.status != Status.LOADING) {
                            context.read<PaymentBloc>().add(
                              const PaymentEvent.payment(),
                            );
                          }
                        },
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFB6633),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: state.status == Status.LOADING
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator.adaptive(
                                      strokeWidth: 2,
                                      backgroundColor: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Tasdiqlash',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
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
            ],
          );
        },
      ),
    );
  }
}

class _PayMethod extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool isActive;
  final VoidCallback onTap;

  const _PayMethod({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFFFF3EE) : Colors.white,
            border: Border.all(
              color: isActive
                  ? const Color(0xFFFB6633)
                  : const Color(0xFFEBEFF2),
              width: isActive ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              icon,
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isActive
                      ? const Color(0xFFFB6633)
                      : const Color(0xFF19160B),
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
