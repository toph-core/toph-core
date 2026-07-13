import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/offline_queue_service.dart';
import 'package:mary_ai_pos/core/services/offline_queue/pending_operation.dart';
import 'package:mary_ai_pos/core/utils/order_totals.dart';
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
  bool _includeService = true;

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
                ..add(PaymentEvent.started(
                  tableId: tableId,
                  orderId: orderId,
                  servicePercent: _servicePercent,
                ));
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
          BlocProvider(
            create: (_) {
              final bloc = inject<HourPriceBloc>();
              // Time-based stol — jonli stol haqini serverdan olamiz
              // (guide §4: GET /orders/{id}/table-price), shunda ekran va
              // /pay dagi table_charge server bilan aynan mos bo'ladi.
              // Offline'da fetch xato bo'lsa nav-arg'dagi lokal taymer
              // qiymati o'z kuchida qoladi.
              final isTimeBased =
                  args['table_type'] == 'time_based' || _passedHourAmount > 0;
              final id = tableId ?? orderId;
              if (isTimeBased && id != null) {
                bloc.add(HourPriceEvent.started(orderId: id));
              }
              return bloc;
            },
          ),
        ],
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

              // Yagona hisob — backend /pay formulasi (`OrderTotals`):
              // xizmat (mahsulot + stol haqi) ustidan, chegirma to'liq
              // base_total dan (guide §1/§7).
              final discountAmt =
                  (int.tryParse(state.discountAmount) ?? 0).toDouble();
              OrderTotals totalsFor({required bool withService}) =>
                  OrderTotals.fromDetail(
                    state.detail!,
                    tableCharge: state.hourPrice,
                    offlineExtra: PaymentBloc.pendingOfflineExtra(
                      state.tableId,
                    ).toDouble(),
                    servicePercentFallback: _servicePercent,
                    discountPercent: state.discountType == DiscountType.percent
                        ? discountAmt
                        : 0,
                    discountAmount: state.discountType == DiscountType.money
                        ? discountAmt
                        : 0,
                    includeService: withService,
                  );
              final totalsWithService = totalsFor(withService: true);
              final grandWithService = totalsWithService.grandTotal;
              final grandWithoutService =
                  totalsFor(withService: false).grandTotal;
              final finalTotal =
                  _includeService ? grandWithService : grandWithoutService;

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
                            tableId: tableId,
                            subtotal: totalsWithService.itemsAmount,
                            serviceAmount: totalsWithService.serviceAmount,
                            servicePercentFallback: _servicePercent,
                            includeService: _includeService,
                            onToggleService: (v) {
                              final bloc = context.read<PaymentBloc>();
                              final entered =
                                  int.tryParse(bloc.state.enterSum) ?? 0;
                              final newTotal = v
                                  ? grandWithService
                                  : grandWithoutService;
                              setState(() => _includeService = v);
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
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Left column — order items + totals footer
// ─────────────────────────────────────────────

class _OrderSummaryColumn extends StatelessWidget {
  final dynamic detail;
  final String? tableId;
  final int subtotal;
  final int serviceAmount;
  final double servicePercentFallback;
  final bool includeService;
  final ValueChanged<bool> onToggleService;

  const _OrderSummaryColumn({
    required this.detail,
    required this.tableId,
    required this.subtotal,
    required this.serviceAmount,
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
            child: _ItemsList(detail: detail, tableId: tableId),
          ),
          // Totals footer: Oraliq jami + Xizmat haqi (simplified per spec)
          _SummaryFooter(
            subtotal: subtotal,
            serviceAmount: serviceAmount,
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
  final String? tableId;

  const _ItemsList({required this.detail, required this.tableId});

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
    // Offline pending items (same behavior as before)
    if (tableId != null) {
      final cachedGoods = inject<CacheService>().getGoods();
      for (final op in inject<OfflineQueueService>().pending.where(
        (o) => o.tableId == tableId && o.type == PendingOperationType.addItems,
      )) {
        try {
          final payload = jsonDecode(op.payload) as Map<String, dynamic>;
          final items = payload['items'] as List<dynamic>;
          for (final item in items) {
            final goodId = item['good_id'] as String;
            final qty = (item['quantity'] as num).toInt();
            final goodJson = cachedGoods.firstWhere(
              (g) => g['id'] == goodId,
              orElse: () => <String, dynamic>{},
            );
            if (goodJson.isEmpty) continue;
            final name = goodJson['name'] as String? ?? goodId;
            final price =
                double.tryParse(goodJson['price']?.toString() ?? '0') ?? 0.0;
            final key = '⏳$name';
            if (grouped.containsKey(key)) {
              grouped[key] = grouped[key]!.withQty(
                grouped[key]!.qty + qty,
                earliestAt: op.createdAt,
              );
            } else {
              grouped[key] = _PayItem(
                name: '⏳ $name',
                price: price,
                qty: qty,
                isPending: true,
                isCancelled: false,
                createdAt: op.createdAt,
              );
            }
          }
        } catch (_) {}
      }
    }

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
  final int subtotal;
  final int serviceAmount;
  final double servicePercentFallback;
  final bool includeService;
  final ValueChanged<bool> onToggleService;

  const _SummaryFooter({
    required this.subtotal,
    required this.serviceAmount,
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
          // Summalar yuqorida `OrderTotals` orqali hisoblangan — bu yerda
          // qayta hisoblamaymiz (xizmat stol haqini ham o'z ichiga oladi).
          final serviceAmt = serviceAmount;
          final pctLabel = servicePct > 0
              ? '${S.current.strServiceCharge} (${servicePct.toInt()}%)'
              : S.current.strServiceCharge;

          return Column(
            children: [
              _SummaryLine(
                label: S.current.strSubtotal,
                value: subtotal.formatNWithoutS,
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
