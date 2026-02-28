import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_network_image.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen_mixin.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/show_food_additional.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class ProductGridWidget extends StatelessWidget {
  const ProductGridWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bgDefault,
        borderRadius: context.radius.card24,
      ),
      child: BlocBuilder<DetailBloc, DetailState>(
        buildWhen: (previous, current) => previous.goods != current.goods,
        builder: (context, state) {
          final products = state.goods;
          final bool isLoading = state.status == Status.LOADING;

          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (products?.isEmpty ?? false) {
            return Center(child: Text(S.current.strProductNotFound));
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: ((constraints.maxWidth / 3) * 0.7) + 100,
                  // childAspectRatio: 0.9,
                ),
                itemCount: products?.length ?? 0,
                itemBuilder: (context, index) =>
                    _ProductCard(product: products![index]),
              );
            },
          );
        },
      ).paddingAll(16),
    );
  }
}

class _ProductCard extends StatelessWidget with DetailScreenMixin {
  final GoodsModel product;

  _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Material(
          color: context.colors.bgSecondary,
          borderRadius: context.radius.card,
          child: InkWell(
            onTap: () {
              context.read<DetailBloc>().add(
                DetailEvent.selectGood(good: product),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: context.radius.card,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxWidth * 0.7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.bgDefault,
                          border: Border(
                            left: BorderSide(
                              width: 5,
                              color: product.colorCode != null
                                  ? Color(int.parse(product.colorCode!))
                                  : context.colors.bgBrand,
                            ),
                          ),
                        ),

                        child: product.pictureUrl == null
                            ? Center(
                                child: Text(
                                  product.name.substring(0, 1),
                                  style: context.textStyles.bodyLg.copyWith(
                                    fontSize: 56,
                                    color: context.colors.emptyValueColor,
                                  ),
                                ),
                              )
                            : CustomCachedNetworkImage(
                                height: 160,
                                width: double.infinity,
                                minioObjectName: product.pictureUrl,
                                fit: BoxFit.contain,
                              ).paddingSymmetric(
                                horizontal: constraints.maxWidth * 0.15,
                                vertical: (constraints.maxWidth * 0.7) * 0.15,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    product.name,
                    style: context.textStyles.title14.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    num.parse(product.price).formatN,
                    style: context.textStyles.bodyMd.copyWith(
                      color: context.colors.textBrand,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
