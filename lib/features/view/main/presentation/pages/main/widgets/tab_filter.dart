import 'package:flutter/material.dart';

class TabFilter extends StatelessWidget {
  const TabFilter({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 600;
        final isMediumScreen = constraints.maxWidth < 900;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildTabButton('Barchasi', true),
                  _buildTabButton('Asosiy zal', false),
                  if (!isSmallScreen) _buildTabButton('VIP xonalar', false),
                  if (!isMediumScreen) _buildTabButton('Terassa', false),
                ],
              ),
            ),
            if (!isSmallScreen) ...[
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.add, size: 24, color: Colors.white),
                  ),
                  // Container(
                  //   padding: const EdgeInsets.symmetric(
                  //     horizontal: 16,
                  //     vertical: 7,
                  //   ),
                  //   decoration: BoxDecoration(
                  //     color: const Color(0xFFF6F7F9),
                  //     borderRadius: BorderRadius.circular(16),
                  //   ),
                  //   child: const Row(
                  //     mainAxisSize: MainAxisSize.min,
                  //     spacing: 8,
                  //     children: [
                  //       Column(
                  //         mainAxisSize: MainAxisSize.min,
                  //         crossAxisAlignment: CrossAxisAlignment.start,
                  //         spacing: 4,
                  //         children: [
                  //           Text(
                  //             'Buyurtmaga qaytish',
                  //             style: TextStyle(
                  //               color: Color(0xFF2D2D2D),
                  //               fontSize: 16,
                  //               fontFamily: 'Inter',
                  //               fontWeight: FontWeight.w400,
                  //             ),
                  //           ),
                  //           Text(
                  //             '16-stol 4x burger, 4x lava... ',
                  //             style: TextStyle(
                  //               color: Color(0xFF7B7B7B),
                  //               fontSize: 12,
                  //               fontFamily: 'Inter',
                  //               fontWeight: FontWeight.w400,
                  //             ),
                  //           ),
                  //         ],
                  //       ),
                  //       Icon(
                  //         Icons.arrow_forward_ios,
                  //         size: 16,
                  //         color: Color(0xFF7B7B7B),
                  //       ),
                  //     ],
                  //   ),
                  // ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTabButton(String text, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16.50),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF2D2D2D) : const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isActive ? Colors.white : const Color(0xFF2D2D2D),
          fontSize: 16,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
