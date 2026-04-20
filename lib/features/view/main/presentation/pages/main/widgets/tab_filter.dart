import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/common/custom_shimmer_container.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';

class TabFilter extends StatelessWidget {
  final String? selectedHallId;
  final List<HallModel> halls;
  final bool isLoading;
  const TabFilter({
    super.key,
    required this.halls,
    this.selectedHallId,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: isLoading
                  ? List.generate(4, (index) {
                      return CustomShimmerBox(
                        h: 36,
                        w: 96,
                        borderRadius: BorderRadius.circular(8),
                      );
                    })
                  : halls
                        .map(
                          (hall) => _TabButton(
                            hall: hall,
                            isActive: hall.id == selectedHallId,
                          ),
                        )
                        .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatefulWidget {
  final HallModel hall;
  final bool isActive;

  const _TabButton({required this.hall, required this.isActive});

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Color backgroundColor;
    Color textColor;
    if (widget.isActive) {
      backgroundColor = colors.textBrand;
      textColor = Colors.white;
    } else {
      backgroundColor = _isHovered
          ? colors.border
          : Colors.transparent;
      textColor = colors.textSecondary;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => inject<MainCubit>().setSelectedHallId(widget.hall.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.hall.name,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

