import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';

const _kS900 = Color(0xFF0F172A);
const _kS500 = Color(0xFF64748B);
const _kS200 = Color(0xFFE2E8F0);
const _kS50 = Color(0xFFF8FAFC);

class PaymentTopBar extends StatelessWidget {
  const PaymentTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kS50,
                border: Border.all(color: _kS200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: _kS900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          BlocBuilder<PaymentBloc, PaymentState>(
            builder: (context, state) {
              final tableNumber = state.detail?.tableNumber;
              final orderId = state.detail?.id;
              final tableLabel = (tableNumber != null && tableNumber > 0)
                  ? 'Stol №${tableNumber.toInt()}'
                  : 'Takeaway';
              final codeShort = (orderId != null && orderId.length > 6)
                  ? orderId.substring(orderId.length - 6).toUpperCase()
                  : orderId?.toUpperCase();
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Buyurtma',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kS900,
                      fontFamily: 'Inter',
                      height: 1.1,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    codeShort != null && codeShort.isNotEmpty
                        ? '$tableLabel · #$codeShort'
                        : tableLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _kS500,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
