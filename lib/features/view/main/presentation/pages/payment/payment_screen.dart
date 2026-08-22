import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/pricing/order_totals.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/hour_price/hour_price_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/payment/payment_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_center_column.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_right_side_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/payment/widgets/payment_top_bar.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

const _kS900 = Color(0xFF0F172A);
const _kS500 = Color(0xFF64748B);
const _kS400 = Color(0xFF94A3B8);
const _kBrand = Color(0xFFFB6633);
const _kRed = Color(0xFFDC2626);
const _kIndigo = Color(0xFF6366F1);
const _kIndigoBg = Color(0xFFEEF2FF);
const _kIndigoBorder = Color(0xFFC7D2FE);
const _kS50 = Color(0xFFF8FAFC);
const _kS200 = Color(0xFFE2E8F0);

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _discountFocused = ValueNotifier<bool>(false);

  late final args =
      ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
  late final String? tableId = args['table_id'];
  late final String? orderId = args['order_id'];
  late final double _passedHourAmount = () {
    final raw = args['hour_amount'] as String?;
    if (raw == null) return 0.0;
    return double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  }();
  late final DateTime? _timerStartedAt = args['timer_started_at'] as DateTime?;
  late final List<PauseInterval> _timerPauses =
      (args['timer_pauses'] as List<PauseInterval>?) ?? const [];
  late final int _timerTotalSec = (args['timer_total_sec'] as int?) ?? 0;
  late final String? _timerPricePerHour =
      args['timer_price_per_hour'] as String?;
  // Navigatsiyadan kelgan service_percent (bills endpoint qaytarmasa fallback)
  late final double _servicePercent =
      (args['service_percent'] as num?)?.toDouble() ?? 0.0;

  @override
  void dispose() {
    _discountFocused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bgSecondary,
      body: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) {
              final bloc = inject<PaymentBloc>()
                ..setServicePercent(_servicePercent)
                ..add(PaymentEvent.started(tableId: tableId, orderId: orderId));
              if (_passedHourAmount > 0) {
                bloc.add(
                  PaymentEvent.upadeHourPrice(hourPrice: _passedHourAmount),
                );
              }
              if (_timerStartedAt != null ||
                  _timerTotalSec > 0 ||
                  _timerPauses.isNotEmpty) {
                bloc.setTimerInfo(
                  startedAt: _timerStartedAt,
                  pauses: _timerPauses,
                  totalSec: _timerTotalSec,
                  pricePerHour: _timerPricePerHour,
                );
              }
              return bloc;
            },
          ),
          BlocProvider(create: (_) => inject<HourPriceBloc>()),
        ],
        child: Builder(
          builder: (paymentContext) {
            return PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) return;
            // Leaving payment without success — resume paused timer.
            try {
              final bloc = paymentContext.read<PaymentBloc>();
              if (!bloc.paymentSucceeded) {
                bloc.resumeTimerAfterFailedPay();
              }
            } catch (_) {}
          },
          child: BlocListener<HourPriceBloc, HourPriceState>(
          listenWhen: (p, v) => p.price?.totalPrice != v.price?.totalPrice,
          listener: (context, hState) {
            if (hState.price != null) {
              context.read<PaymentBloc>().add(
                PaymentEvent.upadeHourPrice(
                  hourPrice: hState.price!.totalPrice,
                ),
              );
            }
          },
          child: BlocBuilder<PaymentBloc, PaymentState>(
            builder: (context, state) {
              if (state.detail == null) {
                if (state.detailStatus == Status.ERROR) {
                  return Center(
                    child: Text(S.current.strPaymentInfoNotFound),
                  );
                }
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }

              // Phase 3: the displayed total and the charged total are now the
              // same call on the same state — the screen no longer assembles
              // its own inputs. See `PaymentBloc.totals`.
              final totals = context.read<PaymentBloc>().totals();
              final finalTotal = totals.grandTotal;
              final serviceToggleAmt = totals.serviceAmount;

              // Compact (1024–1366): kichikroq side panellar — numpad uchun joy
              final sidePanelW = PosBreakpoints.pick<double>(
                context,
                compact: 240,
                comfortable: 300,
              );
              return Column(
                children: [
                  const PaymentTopBar(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left column — order summary
                        SizedBox(
                          width: sidePanelW,
                          child: _OrderSummaryColumn(
                            detail: state.detail!,
                            servicePercentFallback: _servicePercent,
                            includeService: state.applyService,
                            onToggleService: (v) {
                              final bloc = context.read<PaymentBloc>();
                              final entered =
                                  int.tryParse(bloc.state.enterSum) ?? 0;
                              // Toggle direction: adding or removing service
                              final delta =
                                  v ? serviceToggleAmt : -serviceToggleAmt;
                              final newTotal =
                                  (finalTotal + delta).clamp(0, 999999999);
                              // `state.applyService` is the only copy of this
                              // flag now; the BlocBuilder above rebuilds off
                              // it, so there is no screen-local mirror to keep
                              // in sync (and none to fall out of sync).
                              bloc.add(PaymentEvent.updateApplyService(
                                applyService: v,
                              ));
                              // Sync numpad only if it still shows the exact total
                              if (entered == 0 || entered == finalTotal) {
                                bloc.add(PaymentEvent.updateEnterSum(
                                  symbol: 'set:$newTotal',
                                ));
                              }
                            },
                          ),
                        ),
                        // Center column (flex) — payment + numpad
                        Expanded(
                          child: PaymentCenterColumn(
                            finalTotal: finalTotal,
                            discountFocused: _discountFocused,
                          ),
                        ),
                        // Right column — discount + total + actions
                        SizedBox(
                          width: sidePanelW,
                          child: PaymentRightSideBar(
                            detail: state.detail!,
                            finalTotal: finalTotal,
                            discountFocused: _discountFocused,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Left column — order items + totals footer
// ─────────────────────────────────────────────

class _OrderSummaryColumn extends StatelessWidget {
  final dynamic detail;
  final double servicePercentFallback;
  final bool includeService;
  final ValueChanged<bool> onToggleService;

  const _OrderSummaryColumn({
    required this.detail,
    this.servicePercentFallback = 0,
    this.includeService = true,
    required this.onToggleService,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          // Section header
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Text(
              S.current.strOrder,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _kS900,
                fontFamily: 'Inter',
              ),
            ),
          ),
          // Items list
          Expanded(
            child: _ItemsList(detail: detail),
          ),
          // Totals footer: Oraliq jami + Xizmat haqi (simplified per spec)
          _SummaryFooter(
            detail: detail,
            servicePercentFallback: servicePercentFallback,
            includeService: includeService,
            onToggleService: onToggleService,
          ),
        ],
      ),
    );
  }
}

class _ItemsList extends StatelessWidget {
  final dynamic detail;

  const _ItemsList({required this.detail});

  @override
  Widget build(BuildContext context) {
    // PaymentBloc.state.itemTimestamps — `/order-items/order/{id}` dan
    // olingan name->earliestCreatedAt mapping (bills javobida yo'q).
    final timestamps = context.select<PaymentBloc, Map<String, DateTime>>(
      (b) => b.state.itemTimestamps,
    );
    final Map<String, _PayItem> grouped = {};
    final List<_PayItem> cancelled = [];
    for (final g in detail.goods) {
      final ts = (g.createdAt as DateTime?) ?? timestamps[g.name];
      if (g.status == 'cancelled') {
        cancelled.add(
          _PayItem(
            name: g.name,
            price: g.price.toDouble(),
            qty: (g.quantity as num).toInt(),
            isPending: false,
            isCancelled: true,
            createdAt: ts,
          ),
        );
        continue;
      }
      final int qty = (g.quantity as num).toInt();
      if (grouped.containsKey(g.name)) {
        grouped[g.name] = grouped[g.name]!.withQty(
          grouped[g.name]!.qty + qty,
          earliestAt: ts,
        );
      } else {
        grouped[g.name] = _PayItem(
          name: g.name,
          price: g.price.toDouble(),
          qty: qty,
          isPending: false,
          isCancelled: false,
          createdAt: ts,
        );
      }
    }
    // Offline-added items are real replica rows now (order flow §6/§7), so they
    // arrive in `detail.goods` above and are grouped like any other line. The
    // old supplement here read the legacy OfflineQueueService, which no longer
    // carries addItems — it added nothing and is gone.

    final allItems = [...grouped.values, ...cancelled];

    if (allItems.isEmpty) {
      return Center(
        child: Text(
          S.current.strOrderNotFound,
          style: const TextStyle(fontSize: 13, color: _kS500, fontFamily: 'Inter'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: allItems.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
      itemBuilder: (_, i) => _OrderLineRow(item: allItems[i]),
    );
  }
}

class _OrderLineRow extends StatelessWidget {
  final _PayItem item;
  const _OrderLineRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final nameColor = item.isCancelled
        ? _kS400
        : item.isPending
        ? _kBrand
        : _kS900;
    final total = item.price * item.qty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quantity × chip
          SizedBox(
            width: 32,
            child: Text(
              '${item.qty}×',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: item.isCancelled ? _kS400 : _kS500,
                fontFamily: 'Inter',
                decoration: item.isCancelled
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          // Name + per-unit price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: nameColor,
                    fontFamily: 'Inter',
                    decoration: item.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: _kS400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (item.isCancelled)
                  const Text(
                    'Bekor qilindi',
                    style: TextStyle(
                      fontSize: 10,
                      color: _kRed,
                      fontFamily: 'Inter',
                    ),
                  )
                else if (item.isPending)
                  const Text(
                    'Yuborilmoqda...',
                    style: TextStyle(
                      fontSize: 10,
                      color: _kBrand,
                      fontFamily: 'Inter',
                    ),
                  )
                else ...[
                  Text(
                    item.price.formatN,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _kS500,
                      fontFamily: 'Inter',
                    ),
                  ),
                  if (item.createdAt != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      _fmtHm(item.createdAt!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                        fontFamily: 'Inter',
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          // Line total (right aligned)
          Text(
            total.formatN,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: item.isCancelled ? _kS400 : _kS900,
              fontFamily: 'Inter',
              decoration: item.isCancelled ? TextDecoration.lineThrough : null,
              decorationColor: _kS400,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryFooter extends StatelessWidget {
  final dynamic detail;
  final double servicePercentFallback;
  final bool includeService;
  final ValueChanged<bool> onToggleService;

  const _SummaryFooter({
    required this.detail,
    this.servicePercentFallback = 0,
    this.includeService = true,
    required this.onToggleService,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: BlocBuilder<PaymentBloc, PaymentState>(
        builder: (context, state) {
          final detail = state.detail!;
          // API servicePercent 0 qaytarsa — navigatsiyadan kelgan fallback ishlatiladi
          final servicePct = detail.servicePercent > 0
              ? detail.servicePercent
              : servicePercentFallback;
          final totals = OrderTotals.fromDetail(
            detail,
            tableCharge: state.hourPrice,
            servicePercentFallback: servicePercentFallback,
          );
          final serviceAmt = totals.serviceAmount;
          final foodOnly = totals.itemsAmount;
          final pctLabel = servicePct > 0
              ? '${S.current.strServiceCharge} (${servicePct.toInt()}%)'
              : S.current.strServiceCharge;

          return Column(
            children: [
              _SummaryLine(
                label: S.current.strSubtotal,
                value: foodOnly.formatNWithoutS,
              ),
              if (serviceAmt > 0) ...[
                const SizedBox(height: 8),
                // Tappable service toggle row
                GestureDetector(
                  onTap: () => onToggleService(!includeService),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: includeService ? _kIndigoBg : _kS50,
                      border: Border.all(
                        color:
                            includeService ? _kIndigoBorder : _kS200,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          includeService
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 14,
                          color: includeService ? _kIndigo : _kS500,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            pctLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: includeService ? _kIndigo : _kS500,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        Text(
                          serviceAmt.formatNWithoutS,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: includeService ? _kIndigo : _kS900,
                            fontFamily: 'Inter',
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          S.current.strSom,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kS500,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (state.hourPrice > 0) ...[
                const SizedBox(height: 8),
                _SummaryLine(
                  label: S.current.strHourlyPayment,
                  value: state.hourPrice.toInt().formatNWithoutS,
                  valueColor: _kBrand,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: _kS500,
            fontFamily: 'Inter',
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _kS900,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(width: 3),
            Text(
              S.current.strSom,
              style: const TextStyle(
                fontSize: 11,
                color: _kS500,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PayItem {
  final String name;
  final double price;
  final int qty;
  final bool isPending;
  final bool isCancelled;
  final DateTime? createdAt;

  const _PayItem({
    required this.name,
    required this.price,
    required this.qty,
    required this.isPending,
    required this.isCancelled,
    this.createdAt,
  });

  _PayItem withQty(int newQty, {DateTime? earliestAt}) => _PayItem(
    name: name,
    price: price,
    qty: newQty,
    isPending: isPending,
    isCancelled: isCancelled,
    createdAt: _earliest(createdAt, earliestAt),
  );
}

DateTime? _earliest(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}

String _fmtHm(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
