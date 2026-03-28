import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/leave_from_detail_screen_dialog.dart';

class TopBarWidget extends StatelessWidget {
  final CafeTableModel? cafeTable;
  final ValueNotifier<bool> showKeyboard;
  final TextEditingController textEditingController;
  final int guestCount;

  const TopBarWidget({
    super.key,
    this.cafeTable,
    required this.showKeyboard,
    required this.textEditingController,
    required this.guestCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: BlocBuilder<DetailBloc, DetailState>(
        builder: (context, state) {
          return Row(
            spacing: 12,
            children: [
              // Back button
              GestureDetector(
                onTap: state.selectedGoods.isNotEmpty && cafeTable != null
                    ? () async {
                        final detailBloc = context.read<DetailBloc>();
                        final savedOrdersBloc = context.read<SavedOrdersBloc>();
                        final navigator = Navigator.of(context);
                        final value = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const LeaveFromDetailScreenDialog(),
                        );
                        if (value == true) {
                          final saved = detailBloc.saveOrder(cafeTable!, guestCount);
                          if (saved != null) {
                            savedOrdersBloc.add(
                              SavedOrdersEvent.addNewOrder(order: saved),
                            );
                            navigator.pop();
                          }
                        } else if (value == false) {
                          savedOrdersBloc.add(
                            SavedOrdersEvent.removeOrder(
                              tableId: cafeTable?.id ?? '',
                            ),
                          );
                          navigator.pop();
                        }
                      }
                    : () {
                        if (cafeTable != null) {
                          context.read<SavedOrdersBloc>().add(
                            SavedOrdersEvent.removeOrder(
                              tableId: cafeTable!.id,
                            ),
                          );
                        }
                        Navigator.pop(context);
                      },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 15,
                    color: Color(0xFF19160B),
                  ),
                ),
              ),
              // Title & subtitle
              if (cafeTable != null)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cafeTable!.number}-stol',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF19160B),
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      '$guestCount mehmon',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              // Search field
              Container(
                width: 220,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: textEditingController,
                  onTap: () => showKeyboard.value = true,
                  onChanged: (v) => context.read<DetailBloc>().add(
                    DetailEvent.searchTextChanged(text: v),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF19160B),
                    fontFamily: 'Inter',
                  ),
                  decoration: InputDecoration(
                    hintText: 'Qidirish...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
              // Clear button
              if (state.selectedGoods.isNotEmpty)
                _HeaderButton(
                  label: 'Tozalash',
                  color: const Color(0xFFEB295B),
                  bgColor: const Color(0xFFFFF0F3),
                  borderColor: const Color(0xFFFBCDD8),
                  onTap: () => context.read<DetailBloc>().add(
                    const DetailEvent.clearGoods(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.label,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}
