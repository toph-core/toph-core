import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

// ─────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────

const _kS900 = Color(0xFF0F172A);
const _kS700 = Color(0xFF334155);
const _kS500 = Color(0xFF64748B);
const _kS400 = Color(0xFF94A3B8);
const _kS300 = Color(0xFFCBD5E1);
const _kS200 = Color(0xFFE2E8F0);
const _kS50 = Color(0xFFF8FAFC);

const _kBrand = Color(0xFFFB6633);
const _kBrandTint = Color(0xFFFFF3EE);
const _kRed = Color(0xFFEF4444);
const _kGreen = Color(0xFF16A34A);
const _kGreenTint = Color(0xFFDCFCE7);
const _kGrowth = Color(0xFF22C55E);

class CloseShiftScreen extends StatefulWidget {
  const CloseShiftScreen({super.key});

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => inject<ArchivesBloc>()
        ..add(const ArchivesEvent.started()),
      child: AppScaffold(
        activeRoute: AppRoutes.closeShiftScreen,
        body: Column(
          children: [
            MainHeader(title: S.current.strTerminal),
            Expanded(
              child: BlocBuilder<ShiftBloc, ShiftState>(
                builder: (context, state) {
                  return state.shift != null
                      ? _ShiftDashboard(state: state)
                      : const _OpenShiftBody();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// OPEN SHIFT — empty-state, existing flow preserved
// ─────────────────────────────────────────────

class _OpenShiftBody extends StatelessWidget {
  const _OpenShiftBody();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = _dateLabel(now);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _kBrandTint,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.storefront_outlined,
                    color: _kBrand,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                S.current.strOpenShift,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _kS900,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                S.current.strStartWorkInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: _kS500,
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: _kS50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: _kS500,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: _kS900,
                            fontFamily: 'Inter',
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kS500,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              BlocBuilder<ShiftBloc, ShiftState>(
                builder: (context, state) {
                  final loading = state.status == Status.LOADING;
                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: loading
                          ? null
                          : () => context
                              .read<ShiftBloc>()
                              .add(const ShiftEvent.openShift()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrand,
                        disabledBackgroundColor: _kBrand.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                                backgroundColor: Colors.white,
                              ),
                            )
                          : Text(
                              S.current.strOpenShift,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontFamily: 'Inter',
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateLabel(DateTime d) {
    final months = [
      '',
      S.current.strJanuary,
      S.current.strFebruary,
      S.current.strMarch,
      S.current.strApril,
      S.current.strMay,
      S.current.strJune,
      S.current.strJuly,
      S.current.strAugust,
      S.current.strSeptember,
      S.current.strOctober,
      S.current.strNovember,
      S.current.strDecember,
    ];
    final days = [
      S.current.strMonday,
      S.current.strTuesday,
      S.current.strWednesday,
      S.current.strThursday,
      S.current.strFriday,
      S.current.strSaturday,
      S.current.strSunday,
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month]} ${d.year}';
  }
}

// ─────────────────────────────────────────────
// SHIFT DASHBOARD — full report view
// ─────────────────────────────────────────────

class _ShiftDashboard extends StatelessWidget {
  final ShiftState state;
  const _ShiftDashboard({required this.state});

  @override
  Widget build(BuildContext context) {
    final shift = state.shift!;
    final archives = context.select<ArchivesBloc, List<ArchiveEntity>>(
      (b) => b.state.archives?.archives ?? const [],
    );
    final cashierName = context.select<UserBloc, String>(
      (b) => b.state.userMOdel?.fullName ?? shift.cashierId,
    );
    final openedAt = shift.openedAt ?? DateTime.now();

    // Aggregate today's archives opened during current shift.
    final shiftArchives = archives
        .where((a) => a.opened != null && !a.opened!.isBefore(openedAt))
        .toList();

    final revenue =
        shiftArchives.fold<int>(0, (sum, a) => sum + a.totalPrice);
    final serviceTotal = shiftArchives.fold<int>(
      0,
      (sum, a) => sum + a.serviceAmount,
    );
    final orderCount = shiftArchives.length;
    final itemsCount = shiftArchives.fold<int>(
      0,
      (sum, a) => sum + a.goodsQuantity,
    );
    final avgCheck = orderCount > 0 ? revenue ~/ orderCount : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(
            openedAt: openedAt,
            cashierName: cashierName,
            shiftId: shift.id,
          ),
          const SizedBox(height: 20),
          _StatsRow(
            revenue: revenue,
            serviceTotal: serviceTotal,
            orderCount: orderCount,
            itemsCount: itemsCount,
            avgCheck: avgCheck,
            openedAt: openedAt,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 1100;
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HourlyChartPanel(
                      archives: shiftArchives,
                      openedAt: openedAt,
                    ),
                    const SizedBox(height: 16),
                    _CashBalancePanel(
                      openingCash: shift.openingCash,
                      cashReceived: revenue,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _HourlyChartPanel(
                      archives: shiftArchives,
                      openedAt: openedAt,
                    ),
                  ),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 340,
                    child: _CashBalancePanel(
                      openingCash: shift.openingCash,
                      cashReceived: revenue,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const _CloseShiftCTA(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Page header (date + status pill + cashier + actions)
// ─────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final DateTime openedAt;
  final String cashierName;
  final String shiftId;

  const _PageHeader({
    required this.openedAt,
    required this.cashierName,
    required this.shiftId,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = _dateLabel(now);
    final openedClock = _clock(openedAt);
    final shortId = shiftId.length > 6
        ? shiftId.substring(shiftId.length - 6).toUpperCase()
        : shiftId.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Smena hisoboti',
          style: TextStyle(
            fontSize: 13,
            color: _kS500,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _kS900,
                      fontFamily: 'Inter',
                      letterSpacing: -0.3,
                    ),
                  ),
                  _OpenShiftPill(openedClock: openedClock),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _OutlinedIconButton(
                  icon: Icons.file_download_outlined,
                  label: 'Eksport',
                  onTap: () {},
                ),
                const SizedBox(width: 8),
                _OutlinedIconButton(
                  icon: Icons.print_outlined,
                  label: 'Chop etish',
                  onTap: () => context
                      .read<ShiftBloc>()
                      .add(const ShiftEvent.printShiftReport()),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          shortId.isEmpty
              ? 'Kassir: $cashierName'
              : 'Kassir: $cashierName · Smena #$shortId',
          style: const TextStyle(
            fontSize: 14,
            color: _kS500,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  static String _clock(DateTime d) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _dateLabel(DateTime d) {
    final months = [
      '',
      S.current.strJanuary,
      S.current.strFebruary,
      S.current.strMarch,
      S.current.strApril,
      S.current.strMay,
      S.current.strJune,
      S.current.strJuly,
      S.current.strAugust,
      S.current.strSeptember,
      S.current.strOctober,
      S.current.strNovember,
      S.current.strDecember,
    ];
    final days = [
      S.current.strMonday,
      S.current.strTuesday,
      S.current.strWednesday,
      S.current.strThursday,
      S.current.strFriday,
      S.current.strSaturday,
      S.current.strSunday,
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month]} ${d.year}';
  }
}

class _OpenShiftPill extends StatelessWidget {
  final String openedClock;
  const _OpenShiftPill({required this.openedClock});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _kGreenTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _kGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Smena ochiq · $openedClock',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kGreen,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedIconButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlinedIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_OutlinedIconButton> createState() => _OutlinedIconButtonState();
}

class _OutlinedIconButtonState extends State<_OutlinedIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _hovered ? _kS50 : Colors.white,
            border: Border.all(color: _kS200),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: _kS500),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _kS900,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Stats row (4 cards)
// ─────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int revenue;
  final int serviceTotal;
  final int orderCount;
  final int itemsCount;
  final int avgCheck;
  final DateTime openedAt;

  const _StatsRow({
    required this.revenue,
    required this.serviceTotal,
    required this.orderCount,
    required this.itemsCount,
    required this.avgCheck,
    required this.openedAt,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1000;
        final cols = isNarrow ? 2 : 4;
        const gap = 16.0;
        final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: w,
              child: _DarkStatCard(
                label: 'Umumiy savdo',
                value: revenue.formatN,
                suffix: "so'm",
              ),
            ),
            SizedBox(
              width: w,
              child: _LightStatCard(
                icon: Icons.receipt_long_outlined,
                iconBg: _kBrandTint,
                iconColor: _kBrand,
                label: 'Buyurtmalar',
                value: '$orderCount ta',
                sub: orderCount > 0
                    ? "$itemsCount taom · o'rt. ${avgCheck.formatN}"
                    : 'Hali yo\'q',
              ),
            ),
            SizedBox(
              width: w,
              child: _LightStatCard(
                icon: Icons.spa_outlined,
                iconBg: _kGreenTint,
                iconColor: _kGreen,
                label: 'Xizmat haqi',
                value: '${serviceTotal.formatN} so\'m',
                sub: orderCount > 0
                    ? '$orderCount ta buyurtma'
                    : '—',
              ),
            ),
            SizedBox(
              width: w,
              child: _DurationStatCard(openedAt: openedAt),
            ),
          ],
        );
      },
    );
  }
}

class _DarkStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;

  const _DarkStatCard({
    required this.label,
    required this.value,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kS900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
              fontFamily: 'Inter',
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'Inter',
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                suffix,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                size: 14,
                color: _kGrowth,
              ),
              const SizedBox(width: 4),
              Text(
                'Joriy smena',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _kGrowth,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LightStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;

  const _LightStatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kS500,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _kS900,
                fontFamily: 'Inter',
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
          ),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 12,
              color: _kS500,
              fontFamily: 'Inter',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DurationStatCard extends StatefulWidget {
  final DateTime openedAt;
  const _DurationStatCard({required this.openedAt});

  @override
  State<_DurationStatCard> createState() => _DurationStatCardState();
}

class _DurationStatCardState extends State<_DurationStatCard> {
  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(widget.openedAt);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final value = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    final startedAt =
        '${widget.openedAt.hour.toString().padLeft(2, '0')}:${widget.openedAt.minute.toString().padLeft(2, '0')}';

    return Container(
      height: 128,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _kBrandTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: _kBrand,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Davomiyligi',
                  style: TextStyle(
                    fontSize: 13,
                    color: _kS500,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kS900,
              fontFamily: 'Inter',
              letterSpacing: 1,
              height: 1.1,
            ),
          ),
          Text(
            'Ochildi $startedAt',
            style: const TextStyle(
              fontSize: 12,
              color: _kS500,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Hourly chart panel
// ─────────────────────────────────────────────

class _HourlyChartPanel extends StatelessWidget {
  final List<ArchiveEntity> archives;
  final DateTime openedAt;

  const _HourlyChartPanel({
    required this.archives,
    required this.openedAt,
  });

  @override
  Widget build(BuildContext context) {
    // Group by hour from shift start to current hour.
    final now = DateTime.now();
    final startHour = openedAt.hour;
    final endHour = now.hour;
    final hourRange = <int>[
      for (int h = startHour; h <= endHour; h++) h,
    ];

    final hourlySums = <int, int>{for (final h in hourRange) h: 0};
    for (final a in archives) {
      final o = a.opened;
      if (o == null) continue;
      final h = o.hour;
      if (hourlySums.containsKey(h)) {
        hourlySums[h] = (hourlySums[h] ?? 0) + a.totalPrice;
      }
    }

    int maxValue = 0;
    int peakHour = startHour;
    int peakValue = 0;
    hourlySums.forEach((h, v) {
      if (v > maxValue) maxValue = v;
      if (v > peakValue) {
        peakValue = v;
        peakHour = h;
      }
    });

    return Container(
      height: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Soatlik savdo dinamikasi',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _kS900,
              fontFamily: 'Inter',
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            peakValue > 0
                ? 'Eng gavjum vaqt: ${peakHour.toString().padLeft(2, '0')}:00 — ${peakValue.formatN} so\'m'
                : "Hali savdo ma'lumoti yo'q",
            style: const TextStyle(
              fontSize: 12,
              color: _kS500,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _HourlyChart(
              hourRange: hourRange,
              hourlySums: hourlySums,
              maxValue: maxValue,
              currentHour: now.hour,
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  final List<int> hourRange;
  final Map<int, int> hourlySums;
  final int maxValue;
  final int currentHour;

  const _HourlyChart({
    required this.hourRange,
    required this.hourlySums,
    required this.maxValue,
    required this.currentHour,
  });

  @override
  Widget build(BuildContext context) {
    if (hourRange.isEmpty) {
      return const Center(
        child: Text(
          "Smena hozirgina boshlandi",
          style: TextStyle(
            fontSize: 13,
            color: _kS400,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelHeight = 24.0;
        final chartH = constraints.maxHeight - labelHeight;
        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: hourRange.map((h) {
                  final v = hourlySums[h] ?? 0;
                  final ratio = maxValue > 0 ? v / maxValue : 0.0;
                  final isCurrent = h == currentHour;
                  final barColor = isCurrent ? _kBrand : _kS300;
                  return Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isCurrent && v > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: _kBrandTint,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'hozir',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: _kBrand,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: (chartH - 30) * ratio + 4,
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            SizedBox(
              height: labelHeight,
              child: Row(
                children: hourRange.map((h) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _kS500,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Cash balance panel
// ─────────────────────────────────────────────

class _CashBalancePanel extends StatelessWidget {
  final int openingCash;
  final int cashReceived;

  const _CashBalancePanel({
    required this.openingCash,
    required this.cashReceived,
  });

  @override
  Widget build(BuildContext context) {
    final expected = openingCash + cashReceived;
    return Container(
      height: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kS200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kassa balansi',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _kS900,
              fontFamily: 'Inter',
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 16),
          _BalanceRow(
            label: "Boshlang'ich qoldiq",
            value: openingCash,
            valueColor: _kS900,
          ),
          const SizedBox(height: 12),
          _BalanceRow(
            label: 'Smena tushumi',
            value: cashReceived,
            valueColor: _kGreen,
            prefix: '+',
          ),
          const Spacer(),
          const Divider(color: _kS200, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Kutilayotgan qoldiq',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kS900,
                  fontFamily: 'Inter',
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    expected.formatN,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _kBrand,
                      fontFamily: 'Inter',
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    "so'm",
                    style: TextStyle(
                      fontSize: 11,
                      color: _kS500,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final String label;
  final int value;
  final Color valueColor;
  final String prefix;

  const _BalanceRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.prefix = '',
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
            color: _kS700,
            fontFamily: 'Inter',
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$prefix${value.formatN}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(width: 3),
            const Text(
              "so'm",
              style: TextStyle(
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

// ─────────────────────────────────────────────
// Close shift CTA (full-width red)
// ─────────────────────────────────────────────

class _CloseShiftCTA extends StatelessWidget {
  const _CloseShiftCTA();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShiftBloc, ShiftState>(
      builder: (context, state) {
        final loading = state.status == Status.LOADING;
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: GestureDetector(
            onTap: loading
                ? null
                : () => context
                    .read<ShiftBloc>()
                    .add(const ShiftEvent.closeShift()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: loading ? _kRed.withOpacity(0.6) : _kRed,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          backgroundColor: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Smenani yopish',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontFamily: 'Inter',
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
