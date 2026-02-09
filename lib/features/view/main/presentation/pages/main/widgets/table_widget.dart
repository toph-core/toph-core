import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/main/data/models/restaurant_table.dart';

class TableWidget extends StatelessWidget {
  final RestaurantTable table;
  final VoidCallback? onTap;

  const TableWidget({super.key, required this.table, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: table.posX,
      top: table.posY,
      child: Transform.rotate(
        angle: table.rotation * (math.pi / 180),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: table.width > 0 ? table.width : 100,
            height: table.height > 0 ? table.height : 100,
            decoration: BoxDecoration(
              color: _getStatusColor(),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: Colors.black.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${table.number}',
                  style: context.textStyles.bodyLg.copyWith(
                    fontWeight: FontWeight.bold,
                    color: table.status == TableStatus.free
                        ? const Color(0xFF2D2D2D)
                        : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${table.capacity} kishi',
                  style: context.textStyles.bodySm.copyWith(
                    color: table.status == TableStatus.free
                        ? const Color(0xFF7B7B7B)
                        : Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (table.status) {
      case TableStatus.free:
        return Colors.white;
      case TableStatus.busy:
        return const Color(0xFF2D2D2D);
    }
  }
}
