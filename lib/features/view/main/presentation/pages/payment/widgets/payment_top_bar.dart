import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';

class PaymentTopBar extends StatelessWidget {
  const PaymentTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        spacing: 12,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 15,
                color: Color(0xFF19160B),
              ),
            ),
          ),
          const Text(
            "To'lov",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF19160B),
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
