import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/color_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/create_order/create_order_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/create_order/create_order_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen_mixin.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/clear_dialog.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/send_to_kitchen_dialog.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/show_food_additional.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class OrderSidebar extends StatelessWidget with DetailScreenMixin {
  final String? tableId;
  final int guestCount;
  final TableStatus tableStatus;
  final String? orderId;
  OrderSidebar({
    super.key,
    this.tableId,
    required this.guestCount,
    required this.tableStatus,
    this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailBloc, DetailState>(
      buildWhen: (previous, current) =>
          previous.selectedGoods != current.selectedGoods,
      builder: (context, state) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.bgDefault,
            borderRadius: context.radius.card24,
          ),
          child: Column(
            children: [
              Row(
                spacing: 12,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Buyurtmalar',
                    style: context.textStyles.bold24.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 22,
                    ),
                  ),
                  CustomHoverEffectWidget(
                    bgColor: AppColors.ffDB2020.withOpacity(.1),
                    onTap: state.selectedGoods.isNotEmpty
                        ? () async {
                            await showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => ClearDialog(
                                onSuccess: () => context.read<DetailBloc>().add(
                                  const DetailEvent.clearGoods(),
                                ),
                              ),
                            ).then(
                              (value) => value != null && value is bool && value
                                  ? context.read<DetailBloc>().add(
                                      const DetailEvent.clearGoods(),
                                    )
                                  : () {},
                            );
                          }
                        : () {},
                    borderRadius: context.radius.buttonLg,
                    child: Text(
                      "Tozalash",
                      style: context.textStyles.semibold16.copyWith(
                        color: AppColors.ffDB2020,
                      ),
                    ).paddingSymmetric(horizontal: 16, vertical: 12.5),
                  ),
                ],
              ).paddingAll(16),
              if (state.selectedGoods.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      S.current.strSelectFoodsNotFound,
                      textAlign: TextAlign.center,
                    ).paddingSymmetric(horizontal: 20),
                  ),
                ),
              if (state.selectedGoods.isNotEmpty)
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) =>
                        _OrderCard(orderItem: state.selectedGoods[index]),
                    separatorBuilder: (context, index) => 12.hBox,
                    itemCount: state.selectedGoods.length,
                  ).paddingSymmetric(horizontal: 16),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.bgDefault,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.newWithOpacity(.07),
                      offset: const Offset(0, -4),
                      blurRadius: 12,
                    ),
                  ],
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
                          calculateTotalPrice(state.selectedGoods).formatN,
                          style: context.textStyles.semibold16,
                        ),
                      ],
                    ),
                    Column(
                      spacing: 8,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (tableId != null)
                          BlocProvider(
                            create: (context) => inject<CreateOrderBloc>()
                              ..add(
                                CreateOrderEvent.started(
                                  tableId: tableId,
                                  guestCount: guestCount,
                                  tableStatus: tableStatus,
                                ),
                              ),
                            child:
                                BlocConsumer<CreateOrderBloc, CreateOrderState>(
                                  listener: (context, state) {
                                    if (state.status != Status.LOADING &&
                                        state.success) {
                                      context
                                          .read<MainCubit>()
                                          .updateTableStatus(
                                            state.tableId,
                                            TableStatus.busy,
                                          );

                                      showSuccessMessage(
                                        context,
                                        S.current.strOrderSuccessCreated,
                                      );
                                      Navigator.pop(context);
                                    }
                                  },
                                  builder: (context, createOrderState) {
                                    return CustomHoverEffectWidget(
                                      bgColor: context.colors.buttonBrand,
                                      onTap: () async {
                                        if (state.selectedGoods.isNotEmpty &&
                                            createOrderState.status !=
                                                Status.LOADING) {
                                          await showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (context) =>
                                                const SendToKitchenDialog(),
                                          ).then((value) {
                                            if (value != null &&
                                                value is bool &&
                                                value) {
                                              context
                                                  .read<CreateOrderBloc>()
                                                  .add(
                                                    CreateOrderEvent.createOrder(
                                                      orders:
                                                          state.selectedGoods,
                                                    ),
                                                  );
                                            }
                                          });
                                        }
                                      },
                                      borderRadius: context.radius.buttonLg,
                                      child: state.status == Status.LOADING
                                          ? CircularProgressIndicator.adaptive(
                                              backgroundColor:
                                                  context.colors.iconOnBrand,
                                            ).paddingSymmetric(vertical: 12.5)
                                          : Text(
                                              "Oshxonaga yuborish",
                                              textAlign: TextAlign.center,
                                              style: context
                                                  .textStyles
                                                  .semibold16
                                                  .copyWith(
                                                    color: Colors.white,
                                                  ),
                                            ).paddingSymmetric(
                                              horizontal: 16,
                                              vertical: 12.5,
                                            ),
                                    );
                                  },
                                ),
                          ),
                        BlocProvider(
                          create: (context) => inject<CreateOrderBloc>()
                            ..add(
                              CreateOrderEvent.started(
                                guestCount: guestCount,
                                tableStatus: tableStatus,
                              ),
                            ),
                          child: BlocBuilder<CreateOrderBloc, CreateOrderState>(
                            builder: (context, createOrderState) {
                              return SizedBox(
                                height: 56,
                                child: CustomHoverEffectWidget(
                                  bgColor: AppColors.ffFB6633,
                                  onTap: () {
                                    if (tableId == null &&
                                        state.selectedGoods.isNotEmpty) {
                                      context.read<CreateOrderBloc>().add(
                                        CreateOrderEvent.createOrder(
                                          orders: state.selectedGoods,
                                        ),
                                      );
                                    } else if (tableId != null) {
                                      if (tableStatus != TableStatus.free) {
                                        Navigator.pushNamed(
                                          context,
                                          AppRoutes.paymentScreen,
                                          arguments: {"table_id": tableId},
                                        );
                                      }
                                    }
                                  },
                                  borderRadius: context.radius.buttonLg,
                                  child:
                                      createOrderState.status == Status.LOADING
                                      ? const CircularProgressIndicator.adaptive()
                                      : Text(
                                          "To’lovga o’tish",
                                          textAlign: TextAlign.center,
                                          style: context.textStyles.semibold16
                                              .copyWith(color: Colors.white),
                                        ).paddingSymmetric(
                                          horizontal: 16,
                                          vertical: 12.5,
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ).paddingAll(16),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget with DetailScreenMixin {
  final OrderItem orderItem;
  _OrderCard({required this.orderItem});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        List<FoodAdditionalModel> selectedAdditional = additionals;
        additionals.asMap().forEach((index, value) {
          if (orderItem.goods.additionals.indexWhere(
                (v) => v.price == value.price && v.title == value.title,
              ) !=
              -1) {
            selectedAdditional[index].selected = true;
          }
        });
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ShowFoodAdditional(
            additionals: selectedAdditional,
            goods: orderItem.goods,
            comment: orderItem.commet,
          ),
        ).then((value) {
          if (value != null && value is Map<String, dynamic>) {
            context.read<DetailBloc>().add(
              DetailEvent.addFoodAdditional(
                additionals: value['additional'],
                orderId: orderItem.uniqueId,
                comment: value['comment'],
              ),
            );
          }
        });
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.bgTritary,
          borderRadius: context.radius.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              orderItem.goods.name,
              style: context.textStyles.headingSm.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                orderItem.goods.additionals.length,
                (index) =>
                    _TagChip(text: orderItem.goods.additionals[index].title),
              ),
              // children: [
              //   _TagChip(text: "Qo'shimcha achchiq"),
              //   _TagChip(text: 'Tuz kam'),
              //   _TagChip(text: 'Ketchup kamroq'),
              //   _TagChip(text: 'Sirsiz'),
              // ],
            ).paddingSymmetric(vertical: 16),
            Text(
              'Izoh: ${orderItem.commet}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            16.hBox,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _QuantitySelector(
                  quantity: orderItem.quantity,
                  onDecrement: () => context.read<DetailBloc>().add(
                    DetailEvent.decrementQuantity(goodsId: orderItem.goods.id),
                  ),
                  onIncrement: () => context.read<DetailBloc>().add(
                    DetailEvent.incrementQuantity(goodsId: orderItem.goods.id),
                  ),
                ),
                Text(
                  (orderItem.goods.additionals.isNotEmpty
                          ? (orderItem.goods.additionals
                                        .map((v) => v.price)
                                        .reduce((a, b) => a + b) +
                                    double.parse(orderItem.goods.price)) *
                                orderItem.quantity
                          : double.parse(orderItem.goods.price) *
                                orderItem.quantity)
                      .formatN,
                  style: context.textStyles.headingSm.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ).paddingAll(12),
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
        color: context.colors.bgDefault,
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
    return Row(
      children: [
        InkWell(
          onTap: onDecrement,
          child: SizedBox(
            height: 44,
            width: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: context.radius.buttonMd,
                color: context.colors.iconOnBrand,
              ),
              child: const Icon(Icons.remove, size: 18),
            ),
          ),
        ),
        Text(
          '$quantity',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ).paddingSymmetric(horizontal: 16),
        InkWell(
          onTap: onIncrement,
          child: SizedBox(
            height: 44,
            width: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: context.radius.buttonMd,
                color: context.colors.iconOnBrand,
              ),
              child: const Icon(Icons.add, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}
