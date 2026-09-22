import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/design_system/pos_grid_metrics.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/department_selection/department_selection_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/department_selection/widgets/department_tab_filter.dart';
import 'package:mary_ai_pos/features/view/main/presentation/widgets/product_grid_card.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// Grid of categories for the selected department, plus an "All Categories" card.
class CategorySelectionGrid extends StatelessWidget {
  final ValueChanged<CategoryModel> onCategorySelected;

  const CategorySelectionGrid({super.key, required this.onCategorySelected});

  static const String allCategoriesId = 'all';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: const DepartmentTabFilter(),
        ),
        Expanded(
          child: BlocBuilder<DepartmentSelectionCubit, DepartmentSelectionState>(
            builder: (context, state) {
              if (state.status == Status.LOADING) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }

              final categories = state.filteredCategories;
              final isSearching = state.searchQuery.isNotEmpty;
              final matchedGoods = state.matchedGoods;

              if (state.status == Status.ERROR &&
                  categories.isEmpty &&
                  !isSearching) {
                return Center(
                  child: Text(
                    S.current.strFoodsCategoriesNotFound.trim(),
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                );
              }

              if (isSearching && categories.isEmpty && matchedGoods.isEmpty) {
                return Center(
                  child: Text(
                    'Hech narsa topilmadi',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final categoryGrid = PosGridMetrics.forCategoryTextGrid(
                    constraints.maxWidth,
                  );
                  final categoryGridDelegate =
                      SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: categoryGrid.columns,
                        crossAxisSpacing: categoryGrid.spacing,
                        mainAxisSpacing: categoryGrid.spacing,
                        mainAxisExtent: categoryGrid.cardHeight,
                      );

                  final goodsGrid = PosGridMetrics.forOrderGrid(
                    constraints.maxWidth,
                  );
                  final goodsGridDelegate =
                      SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: goodsGrid.columns,
                        crossAxisSpacing: goodsGrid.spacing,
                        mainAxisSpacing: goodsGrid.spacing,
                        childAspectRatio: goodsGrid.aspectRatio,
                      );

                  if (!isSearching) {
                    // First card is always "All Categories"
                    final itemCount = categories.length + 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      gridDelegate: categoryGridDelegate,
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _CategoryCard(
                            name: S.current.strAllCategories,
                            colorCode: null,
                            isAllCard: true,
                            onTap: () => onCategorySelected(
                              CategoryModel(
                                id: allCategoriesId,
                                name: S.current.strAllCategories,
                              ),
                            ),
                          );
                        }
                        final category = categories[index - 1];
                        return _CategoryCard(
                          name: category.name,
                          colorCode: category.colorCode,
                          onTap: () => onCategorySelected(category),
                        );
                      },
                    );
                  }

                  return CustomScrollView(
                    slivers: [
                      if (categories.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: _SectionHeader(title: 'Kategoriyalar'),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          sliver: SliverGrid(
                            gridDelegate: categoryGridDelegate,
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final category = categories[index];
                              return _CategoryCard(
                                name: category.name,
                                colorCode: category.colorCode,
                                onTap: () => onCategorySelected(category),
                              );
                            }, childCount: categories.length),
                          ),
                        ),
                      ],
                      if (matchedGoods.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _SectionHeader(
                            title: S.current.strFoodsColumn,
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          sliver: SliverGrid(
                            gridDelegate: goodsGridDelegate,
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  _MatchedGoodCard(good: matchedGoods[index]),
                              childCount: matchedGoods.length,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: context.colors.textDefault,
          fontFamily: PosTypography.family,
        ),
      ),
    );
  }
}

class _MatchedGoodCard extends StatelessWidget {
  final GoodsModel good;
  const _MatchedGoodCard({required this.good});

  @override
  Widget build(BuildContext context) {
    final cartQty = context.select<DetailBloc, int>((b) {
      final s = b.state;
      final selected = s.selectedGoods
          .where((g) => g.goods.id == good.id)
          .fold<int>(0, (sum, g) => sum + g.quantity);
      final existing = s.existingGoods
          .where((g) => g.goods.id == good.id && g.commet != 'cancelled')
          .fold<int>(0, (sum, g) => sum + g.quantity);
      return selected + existing;
    });

    return ProductGridCard(
      good: good,
      onTap: () =>
          context.read<DetailBloc>().add(DetailEvent.selectGood(good: good)),
      topRightBadge: cartQty > 0 ? ProductCartQtyBadge(qty: cartQty) : null,
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final String name;
  final String? colorCode;
  final bool isAllCard;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.colorCode,
    required this.onTap,
    this.isAllCard = false,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  Color? get _accentColor {
    if (widget.colorCode == null || widget.colorCode!.isEmpty) return null;
    final hex = widget.colorCode!.replaceAll('#', '');
    final val = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return val != null ? Color(val) : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = _accentColor ?? c.textBrand;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          // So the accent bar below can be a plain rectangle: the clip gives it
          // the card's own left corners, which is one radius to keep in step
          // instead of two.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.bgDefault,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? c.textBrand.withOpacity(0.4) : c.border,
              width: _hovered ? 1.2 : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: c.textBrand.withOpacity(0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          // A row, not a column with a picture above the name.
          //
          // The tile used to give four fifths of its height to the category's
          // image, and — since almost no category has one — that space was
          // filled by a single giant initial, with the name clipped to one or
          // two lines underneath. The initial told the operator nothing the
          // name did not, and it was the reason the name had no room.
          //
          // So the picture and the initial are both gone. `colorCode` is what
          // survives of the visual identity, as a bar down the leading edge:
          // it is the one thing on the old card that distinguished categories
          // at a glance without costing the name any width.
          child: Row(
            children: [
              Container(width: 6, color: accent),
              const SizedBox(width: 12),
              if (widget.isAllCard) ...[
                Icon(
                  Icons.grid_view_rounded,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textDefault,
                      fontFamily: PosTypography.family,
                      height: 1.2,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
