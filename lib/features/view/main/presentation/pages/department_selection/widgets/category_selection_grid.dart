import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_network_image.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
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

  const CategorySelectionGrid({
    super.key,
    required this.onCategorySelected,
  });

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

              if (state.status == Status.ERROR && categories.isEmpty && !isSearching) {
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
                  const maxCardWidth = 180.0;
                  const maxCardHeight = 200.0;
                  const spacing = 12.0;
                  const padding = 40.0;
                  final available = constraints.maxWidth - padding;
                  final crossCount =
                      (available / (maxCardWidth + spacing)).floor().clamp(2, 8);
                  final cardWidth =
                      (available - spacing * (crossCount - 1)) / crossCount;
                  final cardHeight =
                      (cardWidth / 0.92).clamp(1.0, maxCardHeight);
                  final aspectRatio = cardWidth / cardHeight;

                  final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: aspectRatio,
                  );

                  if (!isSearching) {
                    // First card is always "All Categories"
                    final itemCount = categories.length + 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      gridDelegate: gridDelegate,
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _CategoryCard(
                            name: S.current.strAllCategories,
                            pictureUrl: null,
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
                          pictureUrl: category.pictureUrl,
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
                            gridDelegate: gridDelegate,
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final category = categories[index];
                                return _CategoryCard(
                                  name: category.name,
                                  pictureUrl: category.pictureUrl,
                                  colorCode: category.colorCode,
                                  onTap: () => onCategorySelected(category),
                                );
                              },
                              childCount: categories.length,
                            ),
                          ),
                        ),
                      ],
                      if (matchedGoods.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _SectionHeader(title: S.current.strFoodsColumn),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          sliver: SliverGrid(
                            gridDelegate: gridDelegate,
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
      onTap: () => context.read<DetailBloc>().add(
        DetailEvent.selectGood(good: good),
      ),
      topRightBadge: cartQty > 0 ? ProductCartQtyBadge(qty: cartQty) : null,
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final String name;
  final String? pictureUrl;
  final String? colorCode;
  final bool isAllCard;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.pictureUrl,
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
    final pic = widget.pictureUrl;
    final hasImage = pic != null && pic.isNotEmpty;
    final initial =
        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '•';
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11),
                  ),
                  child: widget.isAllCard
                      ? _AllCategoriesPlaceholder(accent: accent)
                      : hasImage
                          ? CustomCachedNetworkImage(
                              minioObjectName: pic,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorWidget: _InitialPlaceholder(
                                initial: initial,
                                accent: accent,
                              ),
                            )
                          : _InitialPlaceholder(
                              initial: initial,
                              accent: accent,
                            ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PosDimensions.m,
                  PosDimensions.s + 2,
                  PosDimensions.m,
                  PosDimensions.m,
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _AllCategoriesPlaceholder extends StatelessWidget {
  final Color accent;

  const _AllCategoriesPlaceholder({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.08),
            accent.withOpacity(0.18),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.grid_view_rounded,
        size: 42,
        color: accent.withOpacity(0.7),
      ),
    );
  }
}

class _InitialPlaceholder extends StatelessWidget {
  final String initial;
  final Color accent;

  const _InitialPlaceholder({
    required this.initial,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.05),
            accent.withOpacity(0.12),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.w700,
          color: accent.withOpacity(0.55),
          fontFamily: 'Inter',
          letterSpacing: -1,
        ),
      ),
    );
  }
}
