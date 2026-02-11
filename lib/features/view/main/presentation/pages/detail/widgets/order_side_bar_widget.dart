import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_cubit.dart';

class OrderSidebar extends StatelessWidget {
  const OrderSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailCubit, DetailState>(
      builder: (context, state) {
        final totalPrice = state.selectedGoods.fold<double>(
          0,
          (sum, item) =>
              sum + (double.tryParse(item.goods.price) ?? 0) * item.quantity,
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.bgDefault,
            borderRadius: context.radius.card24,
          ),
          child: Column(
            spacing: 16,
            children: [
              Row(
                spacing: 12,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Buyurtmalar', style: context.textStyles.bold24),
                  CustomHoverEffectWidget(
                    bgColor: AppColors.ffDB2020.withOpacity(.1),
                    onTap: () => context.read<DetailCubit>().clearGoods(),
                    borderRadius: context.radius.buttonLg,
                    child: Text(
                      "Tozalash",
                      style: context.textStyles.semibold16.copyWith(
                        color: AppColors.ffDB2020,
                      ),
                    ).paddingSymmetric(horizontal: 16, vertical: 12.5),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: state.selectedGoods
                      .map((item) => _OrderCard(orderItem: item))
                      .toList(),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.bgDefault,
                  borderRadius: BorderRadius.only(
                    bottomLeft: context.radius.card.bottomLeft,
                    bottomRight: context.radius.card.bottomRight,
                  ),
                ),
                child: Column(
                  spacing: 16,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Jami:',
                          style: context.textStyles.semibold16.copyWith(
                            color: context.colors.textTertiary,
                          ),
                        ),
                        Text(
                          totalPrice.formatN,
                          style: context.textStyles.semibold16,
                        ),
                      ],
                    ),
                    Column(
                      spacing: 8,
                      crossAxisAlignment: .stretch,
                      children: [
                        CustomHoverEffectWidget(
                          bgColor: context.colors.buttonBrand,
                          onTap: () {
                            showSuccessMessage(
                              context,
                              "Buyurtmalar oshxonaga yuborildi",
                            );
                          },
                          borderRadius: context.radius.buttonLg,
                          child: Text(
                            "Oshxonaga yuborish",
                            textAlign: .center,
                            style: context.textStyles.semibold16.copyWith(
                              color: Colors.white,
                            ),
                          ).paddingSymmetric(horizontal: 16, vertical: 12.5),
                        ),
                        CustomHoverEffectWidget(
                          bgColor: AppColors.ffFB6633,
                          onTap: () {},
                          borderRadius: context.radius.buttonLg,
                          child: Text(
                            "To’lovga o’tish",
                            textAlign: .center,
                            style: context.textStyles.semibold16.copyWith(
                              color: Colors.white,
                            ),
                          ).paddingSymmetric(horizontal: 16, vertical: 12.5),
                        ),
                      ],
                    ),
                  ],
                ).paddingAll(16),
              ),
            ],
          ).paddingAll(16),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderItem orderItem;
  const _OrderCard({required this.orderItem});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            orderItem.goods.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagChip(text: "Qo'shimcha achchiq"),
              _TagChip(text: 'Tuz kam'),
              _TagChip(text: 'Ketchup kamroq'),
              _TagChip(text: 'Sirsiz'),
            ],
          ),
          const Text(
            'Izoh: Mijoz qandaydir izoh aytsa qo\'shib qo\'yilgani shu yerda ko\'rinadi',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _QuantitySelector(
                quantity: orderItem.quantity,
                onDecrement: () => context
                    .read<DetailCubit>()
                    .decrementQuantity(orderItem.goods.id),
                onIncrement: () => context
                    .read<DetailCubit>()
                    .incrementQuantity(orderItem.goods.id),
              ),
              Text(
                (double.tryParse(orderItem.goods.price) ?? 0).formatN,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  const _TagChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _QuantitySelector extends StatelessWidget {
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _QuantitySelector({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onDecrement,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Icon(Icons.remove, size: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$quantity',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          InkWell(
            onTap: onIncrement,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Icon(Icons.add, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
