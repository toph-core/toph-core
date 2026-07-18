import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_shimmer_container.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

const _kS900 = Color(0xFF0F172A);
const _kS200 = Color(0xFFE2E8F0);
const _kS100 = Color(0xFFF1F5F9);
const _kExpandBg = Color(0xFF2563EB);
const _kExpandBgHover = Color(0xFF1D4ED8);

const _kBarHeight = 56.0;
const _kChipHPad = 18.0;
const _kChipVPad = 12.0;
const _kChipFontSize = 17.0;
const _kChipRadius = 12.0;
const _kChipGap = 8.0;
const _kExpandGap = 10.0;
const _kExpandIconSize = 24.0;

class DetailTabFilter extends StatefulWidget {
  const DetailTabFilter({super.key});

  @override
  State<DetailTabFilter> createState() => _DetailTabFilterState();
}

class _DetailTabFilterState extends State<DetailTabFilter> {
  bool _isExpanded = false;

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  double _chipWidth(String name) {
    final painter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          fontSize: _kChipFontSize,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + (_kChipHPad * 2) + 2;
  }

  bool _needsExpandButton(List<CategoryModel> categories, double maxWidth) {
    if (_isExpanded) return true;
    var used = 0.0;
    for (var i = 0; i < categories.length; i++) {
      final width = _chipWidth(categories[i].name);
      final needed = i == 0 ? width : width + _kChipGap;
      used += needed;
      if (used > maxWidth) return true;
    }
    return false;
  }

  Widget _chipFor(
    BuildContext context,
    CategoryModel category,
    String? selectedCategoryId,
  ) {
    return _CategoryChip(
      key: ValueKey(category.id),
      category: category,
      isActive: category.id == selectedCategoryId,
      onTap: () {
        if (category.id == selectedCategoryId) return;
        context.read<DetailBloc>().add(
          DetailEvent.setSelectedCategoryId(id: category.id),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailBloc, DetailState>(
      builder: (context, state) {
        if (state.status == Status.LOADING && state.categories == null) {
          return SizedBox(
            height: _kBarHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) => CustomShimmerBox(
                h: _kBarHeight,
                w: 140,
                borderRadius: context.radius.buttonLg,
              ),
              separatorBuilder: (context, index) => _kChipGap.toInt().wBox,
              itemCount: 10,
            ),
          );
        }

        if (state.status != Status.LOADING && state.categories == null) {
          return Center(
            child: Text(S.current.strFoodsCategoriesNotFound.trim()),
          );
        }

        final categories = state.categories ?? [];
        if (categories.isEmpty) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final showExpandButton =
                _needsExpandButton(categories, constraints.maxWidth);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topLeft,
                    child: _isExpanded
                        ? Wrap(
                            spacing: _kChipGap,
                            runSpacing: _kChipGap,
                            children: [
                              for (final category in categories)
                                _chipFor(
                                  context,
                                  category,
                                  state.selectedCategoryId,
                                ),
                            ],
                          )
                        : SizedBox(
                            height: _kBarHeight,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: categories.length,
                              separatorBuilder: (_, __) =>
                                  _kChipGap.toInt().wBox,
                              itemBuilder: (context, index) => _chipFor(
                                context,
                                categories[index],
                                state.selectedCategoryId,
                              ),
                            ),
                          ),
                  ),
                ),
                if (showExpandButton) ...[
                  const SizedBox(width: _kExpandGap),
                  _ExpandButton(
                    isExpanded: _isExpanded,
                    onTap: _toggleExpanded,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CategoryChip extends StatefulWidget {
  final CategoryModel category;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryChip({
    super.key,
    required this.category,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final Color bg;
    final Color borderColor;
    if (active) {
      bg = _kS900;
      borderColor = _kS900;
    } else if (_hovered) {
      bg = _kS100;
      borderColor = _kS200;
    } else {
      bg = Colors.white;
      borderColor = _kS200;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: _kChipHPad,
            vertical: _kChipVPad,
          ),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(_kChipRadius),
          ),
          child: Text(
            widget.category.name,
            style: TextStyle(
              color: active ? Colors.white : _kS900,
              fontSize: _kChipFontSize,
              fontFamily: 'Inter',
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandButton extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _ExpandButton({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_ExpandButton> createState() => _ExpandButtonState();
}

class _ExpandButtonState extends State<_ExpandButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg =
        _hovered || widget.isExpanded ? _kExpandBgHover : _kExpandBg;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: _kChipHPad,
            vertical: _kChipVPad,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_kChipRadius),
          ),
          child: Icon(
            widget.isExpanded
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            color: Colors.white,
            size: _kExpandIconSize,
          ),
        ),
      ),
    );
  }
}
