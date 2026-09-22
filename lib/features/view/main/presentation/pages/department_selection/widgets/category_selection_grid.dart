import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/design_system/pos_grid_metrics.dart';
import 'package:mary_ai_pos/core/design_system/pos_text_tile.dart';
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
                  final categoryGrid = PosGridMetrics.forTextTileGrid(
                    constraints.maxWidth,
                  );
                  final categoryGridDelegate =
                      SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: categoryGrid.columns,
                        crossAxisSpacing: categoryGrid.spacing,
                        mainAxisSpacing: categoryGrid.spacing,
                        mainAxisExtent: categoryGrid.cardHeight,
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
                            gridDelegate: categoryGridDelegate,
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

class _CategoryCard extends StatelessWidget {
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

  Color? get _accentColor {
    if (colorCode == null || colorCode!.isEmpty) return null;
    final hex = colorCode!.replaceAll('#', '');
    final val = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return val != null ? Color(val) : null;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor ?? context.colors.textBrand;
    return PosTextTile(
      title: name,
      accent: accent,
      onTap: onTap,
      leading: isAllCard
          ? Icon(Icons.grid_view_rounded, size: 20, color: accent)
          : null,
    );
  }
}
