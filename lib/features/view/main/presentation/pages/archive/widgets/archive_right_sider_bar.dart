import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/extension/date_time_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/utils/order_localizations.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
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
                  status: archive.status,
                  isPrintEnabled: role.canPrintReceipt,
                  onPrint: () async {
                    await inject<PrinterService>().printCashierReceiptFromDetail(
                      detail: detail,
                      hourAmount: detail.tableAmount,
                      timerStartedAt: detail.opened,
                      timerPauses: detail.pausePeriods,
                    );
                  },
                ),
                8.hBox,
                _MetaCard(
                  tableNumber: archive.tableNumber,
                  cashierName: detail.cashierName,
                  opened: archive.opened,
                  paymentType: detail.paymentType,
                  tableAmount: detail.tableAmount.round(),
                ),
                if (detail.pausePeriods.isNotEmpty) ...[
                  8.hBox,
                  _PauseHistoryDropdown(pauses: detail.pausePeriods),
                ],
                12.hBox,
                Text(
                  S.current.strOrderDetails,
                  style: context.textStyles.bold16.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                8.hBox,
                _ItemsList(goods: detail.goods),
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
  final OrderStatus status;
  final bool isPrintEnabled;
  final VoidCallback onPrint;

  const _HeaderRow({
    required this.bilNumber,
    required this.status,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$bilNumber',
                  style: context.textStyles.bold20.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                6.hBox,
                _ArchiveStatusBadge(status: status),
              ],
            ),
          ),
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
  final String cashierName;
  final DateTime? opened;
  final String paymentType;
  final int tableAmount;

  const _MetaCard({
    required this.tableNumber,
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

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: context.textStyles.bodySm),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: context.textStyles.bold16.copyWith(
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _PauseHistoryDropdown extends StatefulWidget {
  final List<PauseInterval> pauses;
  const _PauseHistoryDropdown({required this.pauses});

  @override
  State<_PauseHistoryDropdown> createState() => _PauseHistoryDropdownState();
}

class _PauseHistoryDropdownState extends State<_PauseHistoryDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final pauses = widget.pauses;
    final totalSec = pauses.fold<int>(0, (s, p) => s + p.durationSec);
    const accentColor = Color(0xFFF59E0B);

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
                    const Icon(
                      Icons.pause_circle_outline_rounded,
                      size: 16,
                      color: accentColor,
                    ),
                    8.wBox,
                    Expanded(
                      child: Text(
                        '${S.current.strPauseHistory} · ${pauses.length}x',
                        style: context.textStyles.bodySm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${S.current.strTotalPause} ${_fmtPauseDuration(totalSec)}',
                      style: context.textStyles.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accentColor,
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
              secondChild: _PauseHistoryList(pauses: pauses),
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

class _PauseHistoryList extends StatelessWidget {
  final List<PauseInterval> pauses;
  const _PauseHistoryList({required this.pauses});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(pauses.length, (i) {
        final p = pauses[i];
        final isLast = i == pauses.length - 1;
        final range = p.endedAt != null
            ? '${p.startedAt.toHourMinute} – ${p.endedAt!.toHourMinute}'
            : '${p.startedAt.toHourMinute} – …';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    top: BorderSide(
                      color: context.colors.textSecondary.withValues(
                        alpha: 0.12,
                      ),
                    ),
                  ),
          ),
          child: Row(
            children: [
              Text(range, style: context.textStyles.bodySm),
              const Spacer(),
              Text(
                _fmtPauseDuration(p.durationSec),
                style: context.textStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _ItemsList extends StatelessWidget {
  final List<OrderFoodEntity> goods;
  const _ItemsList({required this.goods});

  bool _isCancelled(OrderFoodEntity g) {
    final s = g.status.toLowerCase().trim();
    return s == 'cancelled' || s == 'canceled';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 6,
      children: List.generate(
        goods.length,
        (index) {
          final g = goods[index];
          final cancelled = _isCancelled(g);
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
                            if (cancelled) ...[
                              8.wBox,
                              _CancelledBadge(),
                            ],
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
                      decoration:
                          cancelled ? TextDecoration.lineThrough : TextDecoration.none,
                    ),
                  ),
                ],
              ).paddingSymmetric(horizontal: 14, vertical: 10),
            ),
          );
        },
      ),
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
            _MetaRow(label: 'Subtotal', value: subtotal.formatN),
            8.hBox,
            _MetaRow(label: 'Service Fee', value: serviceFee.formatN),
            8.hBox,
            _MetaRow(label: 'Discount', value: discount.formatN),
            8.hBox,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: context.textStyles.bodySm),
                Text(
                  total.formatN,
                  style: context.textStyles.bold18.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.colors.bgBrand,
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

String _fmtPauseDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}min';
  return '${m}min';
}
