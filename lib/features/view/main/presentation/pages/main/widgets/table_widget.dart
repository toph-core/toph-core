import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'dart:math' as math;
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';

class TableWidget extends StatelessWidget {
  final CafeTableModel table;
  final VoidCallback? onTap;

  const TableWidget({super.key, required this.table, this.onTap});

  @override
  Widget build(BuildContext context) {
    final height = table.height
        .clamp(60, table.height < 60 ? 60 : table.height)
        .toDouble();
    final width =
        table.width.clamp(80, table.width < 80 ? 80 : table.width).toDouble() *
        2;
    final statusColor = _getStatusColor();
    final isFree = table.status == TableStatus.free;

    return Positioned(
      left: table.posX,
      top: table.posY,
      child: Transform.rotate(
        angle: table.rotation * (math.pi / 180),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ..._buildSeats(width, height),

            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 12, color: statusColor),
                      ),
                      // Content
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${table.number}',
                              style: context.textStyles.bodyLg.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                                color: const Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isFree ? "Bo'sh" : "To'lov kutilmoqda",
                              style: context.textStyles.bodySm.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSeats(double width, double height) {
    final List<Widget> seats = [];
    const seatSize = 35.0;
    final seatColor = _getStatusColor().withOpacity(.4);

    int seatsPerSide = (table.capacity / 2).ceil();

    for (int i = 0; i < seatsPerSide; i++) {
      double offsetX = (width / (seatsPerSide + 1)) * (i + 1) - (seatSize / 2);
      seats.add(
        Positioned(
          top: -seatSize / 2,
          left: offsetX,
          child: _SeatCircle(size: seatSize, color: seatColor),
        ),
      );

      if (i + seatsPerSide < table.capacity) {
        seats.add(
          Positioned(
            bottom: -seatSize / 2,
            left: offsetX,
            child: _SeatCircle(size: seatSize, color: seatColor),
          ),
        );
      }
    }

    return seats;
  }

  Color _getStatusColor() {
    switch (table.status) {
      case TableStatus.free:
        return const Color(0xFF13AF1B);
      case TableStatus.busy:
        return const Color(0xFFFB6633);
      default:
        return Colors.black;
    }
  }
}

class _SeatCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _SeatCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
