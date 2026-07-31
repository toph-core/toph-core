import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/date_time_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/utils/order_localizations.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/widgets/active_periods_view.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class ArchiveRightSiderBar extends StatelessWidget {
  final UserRole? role;
  const ArchiveRightSiderBar({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.w,
      height: context.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.textOnBrand,
          borderRadius: context.radius.card24,
        ),
        child: BlocBuilder<ArchivesBloc, ArchivesState>(
          builder: (context, state) {
            final archive = state.selectArchive;
            final detail = state.selectArchiveDetail;

            if (archive == null) {
              return _EmptyDetailsState();
            }

            final isLoading =
                state.archiveStatus == Status.LOADING && detail == null;
            if (isLoading) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }

            if (detail == null) {
              return Center(
                child: Text(
                  S.current.strCheckNotFound,
                  style: context.textStyles.bodyMd,
                ),
              );
            }

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              children: [
                _HeaderRow(
                  bilNumber: archive.bilNumber,
                  checkId: archive.id,
                  status: archive.status,
                  showPrint: !_isOpenOrderStatus(archive.status),
                  isPrintEnabled: role.canPrintReceipt,
                  onPrint: () async {
                    await inject<PrinterService>()
                        .printCashierReceiptFromDetail(
                          detail: detail,
                          hourAmount: detail.tableAmount,
                          timerStartedAt: detail.opened,
                          timerPauses: detail.pausePeriods,
                        );
                  },
                ),
                if (_isOpenOrderStatus(archive.status)) ...[
                  10.hBox,
                  _OpenOrderActionsRow(
                    onPay: () => Navigator.pushNamed(
                      context,
                      AppRoutes.paymentScreen,
                      arguments: {'order_id': archive.id},
                    ),
                    onAddItems: () => _openOrderInCategories(context, detail),
                  ),
                ],
                8.hBox,
                _MetaCard(
                  tableNumber: archive.tableNumber,
                  hallName: detail.hallName,
                  cashierName: detail.cashierName,
                  opened: archive.opened,
                  paymentType: detail.paymentType,
                  tableAmount: detail.tableAmount.round(),
                ),
                if (detail.activePeriods.isNotEmpty) ...[
                  8.hBox,
                  ActivePeriodsSection(segments: detail.activePeriods),
                ],
                12.hBox,
                _OrderDetailsAccordion(
                  goods: detail.goods,
                  itemsTotal: detail.foodTotal.round(),
                ),
                12.hBox,
                _TotalsCard(
                  subtotal: detail.foodTotal.round(),
                  serviceFee: detail.serviceAmount.round(),
                  discount: detail.discountAmount.round(),
                  total: detail.grandTotal.round(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _shortCheckId(String id) {
  final clean = id.replaceAll('-', '');
  if (clean.isEmpty) return '';
  return clean.length > 8
      ? clean.substring(0, 8).toUpperCase()
      : clean.toUpperCase();
}

void _openOrderInCategories(BuildContext context, ArchiveDetailEntity detail) {
  final table = CafeTableModel(
    id: detail.tableId,
    hallId: '',
    number: detail.tableNumber.toInt(),
    posX: 0,
    posY: 0,
    width: 0,
    height: 0,
    rotation: 0,
    capacity: detail.guestCount.toInt(),
    status: TableStatus.busy,
  );
  Navigator.pushNamed(
    context,
    AppRoutes.departmentSelectionScreen,
    arguments: {
      'table': table,
      'guest_count': detail.guestCount.toInt(),
      'table_status': TableStatus.busy,
      'saved_orders': null,
    },
  );
}

class _EmptyDetailsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select an order to view its details.',
        style: context.textStyles.bodyMd,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final int bilNumber;
  final String checkId;
  final OrderStatus status;
  final bool showPrint;
  final bool isPrintEnabled;
  final VoidCallback onPrint;

  const _HeaderRow({
    required this.bilNumber,
    required this.checkId,
    required this.status,
    required this.showPrint,
    required this.isPrintEnabled,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.w,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  '#$bilNumber',
                  style: context.textStyles.bold20.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (checkId.isNotEmpty) ...[
                  8.wBox,
                  Text(
                    '•',
                    style: context.textStyles.bold20.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  8.wBox,
                  Flexible(
                    child: Text(
                      _shortCheckId(checkId),
                      style: context.textStyles.bodySm.copyWith(
                        color: context.colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                _ArchiveStatusBadge(status: status),
              ],
            ),
          ),
          if (showPrint) ...[
            8.wBox,
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: IgnorePointer(
                  ignoring: !isPrintEnabled,
                  child: Opacity(
                    opacity: isPrintEnabled ? 1 : 0.6,
                    child: CustomHoverEffectWidget(
                      onTap: onPrint,
                      borderRadius: context.radius.buttonMd,
                      bgColor: isPrintEnabled
                          ? context.colors.bgBrand
                          : context.colors.bgTritary,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            Assets.icons.icPrinter.path,
                            width: 16,
                            height: 16,
                            color: isPrintEnabled
                                ? AppColors.white
                                : context.colors.textSecondary,
                          ),
                          6.wBox,
                          Flexible(
                            child: Text(
                              S.current.strPrint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.title14.copyWith(
                                fontSize: 13,
                                color: isPrintEnabled
                                    ? context.colors.textOnBrand
                                    : context.colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ).paddingSymmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpenOrderActionsRow extends StatelessWidget {
  final VoidCallback onPay;
  final VoidCallback onAddItems;

  const _OpenOrderActionsRow({required this.onPay, required this.onAddItems});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CompactActionButton(
            onTap: onPay,
            bgColor: context.colors.bgBrand,
            icon: Icons.payments_outlined,
            iconColor: AppColors.white,
            label: S.current.strGoToPayment,
            labelColor: context.colors.textOnBrand,
          ),
        ),
        8.wBox,
        Expanded(
          child: _CompactActionButton(
            onTap: onAddItems,
            bgColor: context.colors.bgTritary,
            icon: Icons.add_circle_outline_rounded,
            iconColor: context.colors.textDefault,
            label: S.current.strAddItems,
            labelColor: context.colors.textDefault,
          ),
        ),
      ],
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color bgColor;
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;

  const _CompactActionButton({
    required this.onTap,
    required this.bgColor,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: CustomHoverEffectWidget(
        onTap: onTap,
        borderRadius: context.radius.buttonMd,
        bgColor: bgColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            6.wBox,
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.title14.copyWith(
                  fontSize: 13,
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveStatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _ArchiveStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String key;

    switch (status) {
      case OrderStatus.open:
      case OrderStatus.opened:
      case OrderStatus.pending:
        bg = const Color(0xFFFFF3EE);
        fg = const Color(0xFFFB6633);
        key = 'open';
      case OrderStatus.closed:
      case OrderStatus.paid:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        key = status == OrderStatus.paid ? 'paid' : 'closed';
      case OrderStatus.deleted:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        key = 'cancelled';
      default:
        bg = const Color(0xFFF8FAFC);
        fg = const Color(0xFF64748B);
        key = '';
    }

    final label = key.isEmpty ? '—' : localizedOrderStatus(context, key);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  final int tableNumber;
  final String hallName;
  final String cashierName;
  final DateTime? opened;
  final String paymentType;
  final int tableAmount;

  const _MetaCard({
    required this.tableNumber,
    required this.hallName,
    required this.cashierName,
    required this.opened,
    required this.paymentType,
    required this.tableAmount,
  });

  String _paymentLabel() {
    final v = paymentType.toLowerCase().trim();
    if (v == 'card') return S.current.strCard;
    if (v == 'qr') return 'QR';
    return S.current.strCash;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: context.radius.buttonLg,
          color: context.colors.bgTritary,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetaRow(
              label: S.current.strTableLabel,
              value: tableNumber == 0 ? '—' : tableNumber.toString(),
            ),
            if (tableNumber != 0 && hallName.trim().isNotEmpty) ...[
              6.hBox,
              _MetaRow(label: S.current.strHall, value: hallName.trim()),
            ],
            6.hBox,
            _MetaRow(
              label: S.current.strCashierLabel,
              value: cashierName.isEmpty ? '—' : cashierName,
            ),
            6.hBox,
            _MetaRow(
              label: S.current.strDateLabel,
              value: opened?.toYyyyMmDd ?? '—',
            ),
            6.hBox,
            _MetaRow(
              label: S.current.strPaymentMethodLabel,
              value: _paymentLabel(),
            ),
            if (tableAmount > 0) ...[
              6.hBox,
              _MetaRow(
                label: S.current.strHourlyPayment,
                value: tableAmount.formatN,
              ),
            ],
          ],
        ).paddingSymmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

const double _kMetaLabelWidth = 132;

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _kMetaLabelWidth,
          child: Text(label, style: context.textStyles.bodySm),
        ),
        Expanded(
          child: Text(
            value,
            style: context.textStyles.bold16.copyWith(
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
          ),
        ),
      ],
    );
  }
}

bool _isCancelledGood(OrderFoodEntity g) {
  final s = g.status.toLowerCase().trim();
  return s == 'cancelled' || s == 'canceled';
}

class _OrderDetailsAccordion extends StatefulWidget {
  final List<OrderFoodEntity> goods;
  final int itemsTotal;

  const _OrderDetailsAccordion({required this.goods, required this.itemsTotal});

  @override
  State<_OrderDetailsAccordion> createState() => _OrderDetailsAccordionState();
}

class _OrderDetailsAccordionState extends State<_OrderDetailsAccordion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final goods = widget.goods;
    final itemCount = goods
        .where((g) => !_isCancelledGood(g))
        .fold<int>(0, (s, g) => s + g.quantity);

    return SizedBox(
      width: context.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: context.radius.buttonLg,
          color: context.colors.bgTritary,
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 16,
                      color: context.colors.bgBrand,
                    ),
                    8.wBox,
                    Expanded(
                      child: Text(
                        '${S.current.strOrderDetails} · ${itemCount}x',
                        style: context.textStyles.bodySm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      widget.itemsTotal.formatN,
                      style: context.textStyles.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.colors.bgBrand,
                      ),
                    ),
                    4.wBox,
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: _ItemsList(goods: goods),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemsList extends StatelessWidget {
  final List<OrderFoodEntity> goods;
  const _ItemsList({required this.goods});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 6,
      children: List.generate(goods.length, (index) {
        final g = goods[index];
        final cancelled = _isCancelledGood(g);
        return SizedBox(
          width: context.w,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: context.radius.buttonLg,
              color: context.colors.bgTritary,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              g.name,
                              style: context.textStyles.bold16.copyWith(
                                fontWeight: FontWeight.w500,
                                color: cancelled
                                    ? context.colors.textSecondary
                                    : context.colors.textDefault,
                                decoration: cancelled
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (cancelled) ...[8.wBox, _CancelledBadge()],
                        ],
                      ),
                      4.hBox,
                      Text(
                        '${g.quantity} x ${g.price.formatN}',
                        style: context.textStyles.bodySm.copyWith(
                          color: cancelled
                              ? context.colors.textSecondary
                              : context.colors.textSecondary,
                          decoration: cancelled
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                12.wBox,
                Text(
                  g.price.formatN,
                  style: context.textStyles.bold16.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cancelled
                        ? context.colors.textSecondary
                        : context.colors.textDefault,
                    decoration: cancelled
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ],
            ).paddingSymmetric(horizontal: 14, vertical: 10),
          ),
        );
      }),
    );
  }
}

class _CancelledBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.systemError.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: context.colors.systemError.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        'Cancelled',
        style: context.textStyles.bodySm.copyWith(
          color: context.colors.systemError,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final int subtotal;
  final int serviceFee;
  final int discount;
  final int total;

  const _TotalsCard({
    required this.subtotal,
    required this.serviceFee,
    required this.discount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: context.radius.buttonLg,
          color: context.colors.bgTritary,
        ),
        child: Column(
          children: [
            _MetaRow(label: S.current.strSubtotal, value: subtotal.formatN),
            8.hBox,
            _MetaRow(
              label: S.current.strServiceCharge,
              value: serviceFee.formatN,
            ),
            8.hBox,
            _MetaRow(label: S.current.strDiscount, value: discount.formatN),
            8.hBox,
            Row(
              children: [
                SizedBox(
                  width: _kMetaLabelWidth,
                  child: Text(
                    S.current.strTotal,
                    style: context.textStyles.bodySm,
                  ),
                ),
                Expanded(
                  child: Text(
                    total.formatN,
                    style: context.textStyles.bold18.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.colors.bgBrand,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ).paddingSymmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

bool _isOpenOrderStatus(OrderStatus status) {
  return status == OrderStatus.open ||
      status == OrderStatus.opened ||
      status == OrderStatus.pending;
}
