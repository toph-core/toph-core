import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
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
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _paginatorController.dispose();
    _scrollCtrl.dispose();
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
                    child: Scrollbar(
                      controller: _scrollCtrl,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 6,
                      radius: const Radius.circular(4),
                      child: GridView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 20,
                          childAspectRatio: 0.88,
                        ),
                        itemCount: pageItems.length,
                        itemBuilder: (context, index) =>
                            _ProductCard(product: pageItems[index]),
                      ),
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
              width: 280,
              height: 36,
              child: NumberPaginator(
                key: ValueKey('paginator-$totalPages-$_pageSize'),
                controller: _paginatorController,
                numberPages: totalPages,
                initialPage: (_page - 1).clamp(0, totalPages - 1),
                onPageChange: (pageIndex) {
                  setState(() => _page = pageIndex + 1);
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.jumpTo(0);
                  }
                },
                child: const SizedBox(
                  height: 36,
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
            height: 36,
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
    // Cart quantity for this product (selected + existing).
    final cartQty = context.select<DetailBloc, int>((b) {
      final s = b.state;
      final selected = s.selectedGoods
          .where((g) => g.goods.id == widget.product.id)
          .fold<int>(0, (sum, g) => sum + g.quantity);
      final existing = s.existingGoods
          .where(
            (g) =>
                g.goods.id == widget.product.id && g.commet != 'cancelled',
          )
          .fold<int>(0, (sum, g) => sum + g.quantity);
      return selected + existing;
    });

    final letter = widget.product.name.isNotEmpty
        ? widget.product.name[0].toUpperCase()
        : '?';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.read<DetailBloc>().add(
          DetailEvent.selectGood(good: widget.product),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Circle avatar with cart badge overlay
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4D4),
                    shape: BoxShape.circle,
                    boxShadow: _hovered
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFB6633).withOpacity(0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    letter,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFB6633),
                      fontFamily: 'Inter',
                      height: 1,
                    ),
                  ),
                ),
                if (cartQty > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _CartQtyBadge(qty: cartQty),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Product name
            Text(
              widget.product.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
                fontFamily: 'Inter',
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            // Price
            Text(
              num.parse(widget.product.price).formatN,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFB6633),
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartQtyBadge extends StatelessWidget {
  final int qty;
  const _CartQtyBadge({required this.qty});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFB6633),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$qty',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontFamily: 'Inter',
          height: 1,
        ),
      ),
    );
  }
}
