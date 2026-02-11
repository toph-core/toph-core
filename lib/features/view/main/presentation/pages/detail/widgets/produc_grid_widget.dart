import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_network_image.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_cubit.dart';

class ProductGridWidget extends StatelessWidget {
  const ProductGridWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bgDefault,
        borderRadius: context.radius.card24,
      ),
      child: BlocBuilder<DetailCubit, DetailState>(
        builder: (context, state) {
          final products = state.goods;
          final bool isLoading = state.status == Status.LOADING;

          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (products?.isEmpty ?? false) {
            return const Center(child: Text('Mahsulot topilmadi'));
          }

          return GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            itemCount: products?.length ?? 0,
            itemBuilder: (context, index) =>
                _ProductCard(product: products![index]),
          );
        },
      ).paddingAll(16),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final GoodsModel product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.bgSecondary,
      borderRadius: context.radius.card,
      child: InkWell(
        borderRadius: context.radius.card,
        onTap: () {
          context.read<DetailCubit>().selectGood(product);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: context.radius.card,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(color: context.colors.bgDefault),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 4,
                          color: product.colorCode != null
                              ? Color(int.parse(product.colorCode!))
                              : context.colors.borderBrand,
                        ),
                      ),
                      product.pictureUrl != null
                          ? CustomCachedNetworkImage(
                              height: 160,
                              width: double.infinity,
                              minioObjectName: product.pictureUrl,
                              fit: .contain,
                            )
                          : Center(
                              child: Icon(
                                Icons.fastfood,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(product.name, style: context.textStyles.headingSm),
              const SizedBox(height: 8),
              Text(
                num.parse(product.price).formatN,
                style: context.textStyles.bodyMd.copyWith(
                  color: context.colors.textBrand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
