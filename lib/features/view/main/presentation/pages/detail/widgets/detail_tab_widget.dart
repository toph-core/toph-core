import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_shimmer_container.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class DetailTabFilter extends StatelessWidget {
  const DetailTabFilter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailBloc, DetailState>(
      builder: (context, state) {
        if (state.status == Status.LOADING && state.categories == null) {
          return SizedBox(
            height: 55,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) => CustomShimmerBox(
                h: 52,
                w: 106,
                borderRadius: context.radius.buttonLg,
              ),
              separatorBuilder: (context, index) => 8.wBox,
              itemCount: 10,
            ),
          );
        }

        if (state.status != Status.LOADING && state.categories == null) {
          return Center(
            child: Text(S.current.strFoodsCategoriesNotFound.trim()),
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SizedBox(
                height: 55,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) => _TabButton(
                    category: state.categories![index],
                    isActive:
                        state.categories![index].id == state.selectedCategoryId,
                  ),
                  separatorBuilder: (context, index) => 8.wBox,
                  itemCount: state.categories?.length ?? 0,
                ),
              ),
            ),
            // Expanded(
            //   child: Wrap(
            //     spacing: 8,
            //     runSpacing: 8,
            //     children: state.status == Status.LOADING
            //         ? List.generate(4, (index) {
            // return CustomShimmerBox(
            //   h: 52,
            //   w: 106,
            //   borderRadius: context.radius.buttonLg,
            // );
            //           })
            //         : state.categories != null
            //         ? state.categories!
            //               .map(
            //                 (category) => _TabButton(
            //                   category: category,
            //                   isActive: category.id == state.selectedCategoryId,
            //                 ),
            //               )
            //               .toList()
            //         : [],
            //   ),
            // ),
          ],
        );
      },
    );
  }
}

class _TabButton extends StatefulWidget {
  final CategoryModel category;
  final bool isActive;

  const _TabButton({required this.category, required this.isActive});

  @override
  State<_TabButton> createState() => __TabButtonState();
}

class __TabButtonState extends State<_TabButton> {
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
        onTap: () => context.read<DetailBloc>().add(
          DetailEvent.setSelectedCategoryId(id: widget.category.id),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16.50),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            widget.category.name,
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
