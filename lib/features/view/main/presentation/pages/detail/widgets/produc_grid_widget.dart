import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_network_image.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/detail_tab_widget.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class ProductGridWidget extends StatelessWidget {
  const ProductGridWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        // Category tabs
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: const DetailTabFilter(),
        ),
        // Product grid
        Expanded(
          child: BlocBuilder<DetailBloc, DetailState>(
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
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) =>
                    _ProductCard(product: products[index]),
              );
            },
          ),
        ),
      ],
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
              // Image area
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: Container(
                    width: double.infinity,
                    color: const Color(0xFFF8F9FA),
                    child: widget.product.pictureUrl == null
                        ? Center(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    width: 4,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  widget.product.name.isNotEmpty
                                      ? widget.product.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                    color: colors.emptyValueColor,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
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
              ),
              // Info
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF19160B),
                        fontFamily: 'Inter',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      num.parse(widget.product.price).formatN,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFB6633),
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3EE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.add,
                          size: 16,
                          color: Color(0xFFFB6633),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
