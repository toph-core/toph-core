import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
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
  final ValueChanged<String> onSearchChanged;
  final bool hadInitialDraft;

  const TopBarWidget({
    super.key,
    this.cafeTable,
    required this.showKeyboard,
    required this.textEditingController,
    required this.guestCount,
    required this.onSearchChanged,
    this.hadInitialDraft = false,
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
                hadInitialDraft: hadInitialDraft,
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
              // Search input — o'ng tomonga taqalgan, fixed width
              SizedBox(
                width: PosBreakpoints.pick<double>(
                  context,
                  compact: 280,
                  comfortable: 340,
                ),
                child: _SearchInput(
                  controller: textEditingController,
                  showKeyboard: showKeyboard,
                  onChanged: onSearchChanged,
                ),
              ),
              if (itemCount > 0) ...[
                const SizedBox(width: PosDimensions.m),
                _OrderSummaryChip(
                  itemCount: itemCount,
                  qtyTotal: qtyTotal,
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
  final bool hadInitialDraft;

  const _BackButton({
    required this.cafeTable,
    required this.guestCount,
    required this.hadInitialDraft,
  });

  // Leaves silently — no confirmation dialog. If there are uncommitted
  // items, they're auto-saved as a local draft (per table) so the user
  // finds them ready to add when they come back. Only clears the draft
  // when this same screen instance started with one and the user emptied
  // it here — a bare empty `selectedGoods` doesn't mean "no draft exists",
  // since department_selection_screen and detail_screen each hold their
  // own DetailBloc instance and one may simply never have seen the items
  // the other screen saved.
  void _onTap(BuildContext context) {
    if (cafeTable != null) {
      final detailBloc = context.read<DetailBloc>();
      final savedOrdersBloc = context.read<SavedOrdersBloc>();
      final entity = detailBloc.saveOrder(cafeTable!, guestCount);
      if (entity != null) {
        savedOrdersBloc.add(SavedOrdersEvent.addNewOrder(order: entity));
      } else if (hadInitialDraft) {
        savedOrdersBloc.add(
          SavedOrdersEvent.removeOrder(tableId: cafeTable!.id),
        );
      }
    }
    Navigator.pop(context);
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
                fontSize: 15,
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
          fontSize: 13,
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
  final ValueChanged<String> onChanged;

  const _SearchInput({
    required this.controller,
    required this.showKeyboard,
    required this.onChanged,
  });

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
    widget.onChanged(current);
    setState(() {});
  }

  void _onClear() {
    widget.controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: _kS50,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: _kS500),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              onTap: () => widget.showKeyboard.value = true,
              style: const TextStyle(
                fontSize: PosTypography.bodyMd,
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
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onClear,
              child: const Icon(Icons.close, size: 22, color: _kS500),
            ),
          ],
        ],
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
            fontSize: 13,
            color: _kS500,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$itemCount taom · $qtyTotal dona',
          style: const TextStyle(
            fontSize: 16,
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

