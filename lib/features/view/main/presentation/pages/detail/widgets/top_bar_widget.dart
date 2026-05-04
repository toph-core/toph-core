import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/leave_from_detail_screen_dialog.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

const _kS900 = Color(0xFF0F172A);
const _kS500 = Color(0xFF64748B);
const _kS200 = Color(0xFFE2E8F0);
const _kS50 = Color(0xFFF8FAFC);

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
    // Compact ekranlarda kichikroq padding — joy tejash uchun
    final hPad = PosBreakpoints.pick<double>(
      context,
      compact: PosDimensions.l, // 16
      comfortable: PosDimensions.xl, // 20
    );
    return Container(
      height: PosDimensions.appBarHeight, // 64
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: BlocBuilder<DetailBloc, DetailState>(
        builder: (context, state) {
          final itemCount =
              state.selectedGoods.length + state.existingGoods.length;
          final qtyTotal = [
            ...state.selectedGoods,
            ...state.existingGoods,
          ].fold<int>(0, (sum, g) => sum + g.quantity);
          final orderCode = state.activeOrderId;

          return Row(
            children: [
              _BackButton(
                cafeTable: cafeTable,
                guestCount: guestCount,
                hasSelection: state.selectedGoods.isNotEmpty,
              ),
              const SizedBox(width: PosDimensions.m),
              if (cafeTable != null)
                _TableHeader(
                  table: cafeTable!,
                  guestCount: guestCount,
                  orderCode: orderCode,
                )
              else
                _TakeawayHeader(),
              const Spacer(),
              // Search input — compact'da kengligi kichikroq
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: PosBreakpoints.pick<double>(
                      context,
                      compact: 140,
                      comfortable: 160,
                    ),
                    maxWidth: PosBreakpoints.pick<double>(
                      context,
                      compact: 220,
                      comfortable: 280,
                    ),
                  ),
                  child: _SearchInput(
                    controller: textEditingController,
                    showKeyboard: showKeyboard,
                  ),
                ),
              ),
              const SizedBox(width: PosDimensions.m),
              // Right-side order summary
              if (itemCount > 0)
                _OrderSummaryChip(
                  itemCount: itemCount,
                  qtyTotal: qtyTotal,
                ),
              if (state.selectedGoods.isNotEmpty) ...[
                const SizedBox(width: PosDimensions.s),
                _TrashIconButton(
                  onTap: () => context.read<DetailBloc>().add(
                    const DetailEvent.clearGoods(),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final CafeTableModel? cafeTable;
  final int guestCount;
  final bool hasSelection;

  const _BackButton({
    required this.cafeTable,
    required this.guestCount,
    required this.hasSelection,
  });

  Future<void> _onTap(BuildContext context) async {
    if (hasSelection && cafeTable != null) {
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
          savedOrdersBloc.add(SavedOrdersEvent.addNewOrder(order: saved));
          navigator.pop();
        }
      } else if (value == false) {
        savedOrdersBloc.add(
          SavedOrdersEvent.removeOrder(tableId: cafeTable?.id ?? ''),
        );
        navigator.pop();
      }
    } else {
      if (cafeTable != null) {
        context.read<SavedOrdersBloc>().add(
          SavedOrdersEvent.removeOrder(tableId: cafeTable!.id),
        );
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTap(context),
      child: Container(
        // POS minimum touch target — barmoqqa qulay
        width: PosDimensions.touchTargetMin, // 56
        height: PosDimensions.touchTargetMin,
        decoration: BoxDecoration(
          color: _kS50,
          border: Border.all(color: _kS200),
          borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: _kS900,
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final CafeTableModel table;
  final int guestCount;
  final String? orderCode;

  const _TableHeader({
    required this.table,
    required this.guestCount,
    required this.orderCode,
  });

  @override
  Widget build(BuildContext context) {
    final hallName = context.select<MainCubit, String?>(
      (c) => c.state.halls
          ?.where((h) => h.id == table.hallId)
          .map((h) => h.name)
          .firstOrNull,
    );
    final subtitleParts = <String>[
      '$guestCount ${S.current.strGuestsSuffix}',
      if (orderCode != null && orderCode!.isNotEmpty)
        '#${_shortCode(orderCode!)}',
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${S.current.strTable} ${table.number}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _kS900,
                    fontFamily: 'Inter',
                    height: 1.1,
                    letterSpacing: -0.3,
                  ),
                ),
                if (hallName != null && hallName.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _HallBadge(label: hallName),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitleParts.join(' · '),
              style: const TextStyle(
                fontSize: 13,
                color: _kS500,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _shortCode(String id) {
    if (id.length <= 6) return id.toUpperCase();
    return id.substring(id.length - 6).toUpperCase();
  }
}

class _HallBadge extends StatelessWidget {
  final String label;
  const _HallBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kS50,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _kS500,
          fontFamily: 'Inter',
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _TakeawayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.shopping_bag_outlined, size: 20, color: _kS900),
        const SizedBox(width: 8),
        Text(
          S.current.strTakeaway,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _kS900,
            fontFamily: 'Inter',
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _SearchInput extends StatefulWidget {
  final TextEditingController controller;
  final ValueNotifier<bool> showKeyboard;

  const _SearchInput({required this.controller, required this.showKeyboard});

  @override
  State<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<_SearchInput> {
  String _last = '';

  @override
  void initState() {
    super.initState();
    _last = widget.controller.text;
    // Virtual keyboard `controller.value` ni dasturiy o'zgartiradi.
    // TextField.onChanged bunday o'zgarishlarni TUTMAYDI — shuning uchun
    // controller.addListener orqali kuzatamiz (ham fizik, ham virtual
    // klaviatura orqali yozilgan matnni).
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final current = widget.controller.text;
    if (current == _last) return;
    _last = current;
    if (!mounted) return;
    context.read<DetailBloc>().add(
      DetailEvent.searchTextChanged(text: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Touch target ≥ 48 dp
      height: 48,
      decoration: BoxDecoration(
        color: _kS50,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
      ),
      child: TextField(
        controller: widget.controller,
        onTap: () => widget.showKeyboard.value = true,
        style: const TextStyle(
          fontSize: PosTypography.bodyMd, // 15
          color: _kS900,
          fontFamily: PosTypography.family,
        ),
        decoration: InputDecoration(
          hintText: S.current.strSearchHint,
          hintStyle: const TextStyle(
            fontSize: PosTypography.bodyMd,
            color: _kS500,
            fontFamily: PosTypography.family,
          ),
          prefixIcon: const Icon(Icons.search, size: 20, color: _kS500),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: PosDimensions.s),
          isDense: true,
        ),
      ),
    );
  }
}

class _OrderSummaryChip extends StatelessWidget {
  final int itemCount;
  final int qtyTotal;

  const _OrderSummaryChip({required this.itemCount, required this.qtyTotal});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Joriy buyurtma',
          style: TextStyle(
            fontSize: 11,
            color: _kS500,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$itemCount taom · $qtyTotal dona',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _kS900,
            fontFamily: 'Inter',
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _TrashIconButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TrashIconButton({required this.onTap});

  @override
  State<_TrashIconButton> createState() => _TrashIconButtonState();
}

class _TrashIconButtonState extends State<_TrashIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          // POS minimum touch target
          width: PosDimensions.touchTargetMin, // 56
          height: PosDimensions.touchTargetMin,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFFEE2E2) : _kS50,
            border: Border.all(
              color: _hovered ? const Color(0xFFFBCDD8) : _kS200,
            ),
            borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 20,
            color: _hovered ? const Color(0xFFDC2626) : _kS500,
          ),
        ),
      ),
    );
  }
}
