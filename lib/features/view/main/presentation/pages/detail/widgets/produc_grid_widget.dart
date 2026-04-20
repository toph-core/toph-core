import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_network_image.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/ui_prefs/ui_prefs_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/detail_tab_widget.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:number_paginator/number_paginator.dart';

class ProductGridWidget extends StatefulWidget {
  const ProductGridWidget({super.key});

  @override
  State<ProductGridWidget> createState() => _ProductGridWidgetState();
}

class _ProductGridWidgetState extends State<ProductGridWidget> {
  static const List<int> _pageSizeOptions = [20, 50, 100];
  int _pageSize = 20;
  int _page = 1;
  final NumberPaginatorController _paginatorController =
      NumberPaginatorController();

  @override
  void dispose() {
    _paginatorController.dispose();
    super.dispose();
  }

  int _totalPagesFor(int total) {
    if (total <= 0) return 1;
    final pages = (total + _pageSize - 1) ~/ _pageSize;
    return pages > 0 ? pages : 1;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: const DetailTabFilter(),
        ),
        Expanded(
          child: BlocConsumer<DetailBloc, DetailState>(
            listenWhen: (p, c) => p.goods != c.goods,
            listener: (context, state) {
              if (_page != 1) {
                setState(() => _page = 1);
              }
            },
            buildWhen: (p, c) => p.goods != c.goods || p.status != c.status,
            builder: (context, state) {
              if (state.status == Status.LOADING) {
                return const Center(child: CircularProgressIndicator.adaptive());
              }
              final products = state.goods;
              if (products == null || products.isEmpty) {
                return Center(
                  child: Text(
                    S.current.strProductNotFound,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                );
              }
              final totalPages = _totalPagesFor(products.length);
              final safePage = _page.clamp(1, totalPages);
              final start = (safePage - 1) * _pageSize;
              final end = (start + _pageSize).clamp(0, products.length);
              final pageItems = products.sublist(start, end);
              return Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final cols = w >= 1300
                            ? 5
                            : w >= 1000
                            ? 4
                            : w >= 750
                            ? 3
                            : 2;
                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.92,
                          ),
                          itemCount: pageItems.length,
                          itemBuilder: (context, index) =>
                              _ProductCard(product: pageItems[index]),
                        );
                      },
                    ),
                  ),
                  _buildPaginationBar(colors, products.length, totalPages),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPaginationBar(
      ThemeColors colors, int totalItems, int totalPages) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    secondary: colors.buttonBrand,
                    onSecondary: colors.textOnBrand,
                  ),
            ),
            child: SizedBox(
              width: 372,
              height: 44,
              child: NumberPaginator(
                key: ValueKey('paginator-$totalPages-$_pageSize'),
                controller: _paginatorController,
                numberPages: totalPages,
                initialPage: (_page - 1).clamp(0, totalPages - 1),
                onPageChange: (pageIndex) {
                  setState(() => _page = pageIndex + 1);
                },
                child: const SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      PrevButton(),
                      Expanded(child: NumberContent()),
                      NextButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _pageSize,
                isDense: true,
                icon: Icon(Icons.expand_more_rounded,
                    color: colors.textSecondary),
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textDefault,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                ),
                items: _pageSizeOptions
                    .map(
                      (size) => DropdownMenuItem<int>(
                        value: size,
                        child: Text('$size / sahifa'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == _pageSize) return;
                  setState(() {
                    _pageSize = value;
                    _page = 1;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  final GoodsModel product;
  const _ProductCard({required this.product});

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = widget.product.colorCode != null
        ? Color(int.parse(widget.product.colorCode!))
        : colors.bgBrand;
    final showImages =
        context.select((UiPrefsCubit c) => c.state.menuShowImages);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.read<DetailBloc>().add(
          DetailEvent.selectGood(good: widget.product),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: _hovered ? colors.textBrand : colors.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showImages)
                AspectRatio(
                  aspectRatio: 1.3,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(11),
                    ),
                    child: widget.product.pictureUrl == null
                        ? Container(
                            color: statusColor.withOpacity(0.08),
                            child: Row(
                              children: [
                                Container(width: 3, color: statusColor),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      widget.product.name.isNotEmpty
                                          ? widget.product.name[0]
                                              .toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor.withOpacity(0.6),
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : CustomCachedNetworkImage(
                            height: double.infinity,
                            width: double.infinity,
                            minioObjectName: widget.product.pictureUrl,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF19160B),
                          fontFamily: 'Inter',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        num.parse(widget.product.price).formatN,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFB6633),
                          fontFamily: 'Inter',
                        ),
                      ),
                      const Spacer(),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: double.infinity,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _hovered
                              ? const Color(0xFFFB6633)
                              : const Color(0xFFFFF3EE),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.add,
                            size: 14,
                            color: _hovered
                                ? Colors.white
                                : const Color(0xFFFB6633),
                          ),
                        ),
                      ),
                    ],
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
