import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/common/custom_shimmer_container.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 3,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: isLoading
                ? List.generate(4, (index) {
                    return CustomShimmerBox(
                      h: 52,
                      w: 106,
                      borderRadius: context.radius.buttonLg,
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
        Expanded(
          flex: 1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.detailScreen,
                    arguments: {"guest_count": 1},
                  );
                },
                child: SizedBox(
                  height: 52,
                  width: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.buttonBrand,
                      borderRadius: context.radius.buttonLg,
                    ),
                    child: SvgPicture.asset(
                      Assets.icons.icAddCircle.path,
                    ).paddingAll(10),
                  ),
                ),
              ),
            ],
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
    Color backgroundColor;
    if (widget.isActive) {
      backgroundColor = const Color(0xFF2D2D2D);
    } else {
      backgroundColor = _isHovered
          ? const Color(0xFFE5E7EB)
          : const Color(0xFFF6F7F9);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => inject<MainCubit>().setSelectedHallId(widget.hall.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16.50),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            widget.hall.name,
            style: TextStyle(
              color: widget.isActive ? Colors.white : const Color(0xFF2D2D2D),
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}


// ...[
// const SizedBox(width: 16),
// Row(
//   mainAxisSize: MainAxisSize.min,
//   spacing: 12,
//   children: [
//     Container(
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: const Color(0xFF2D2D2D),
//         borderRadius: BorderRadius.circular(16),
//       ),
//       child: const Icon(Icons.add, size: 24, color: Colors.white),
//     ),
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
// ],
// ),
// ],