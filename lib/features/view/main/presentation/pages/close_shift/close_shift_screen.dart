import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/close_shift/widgets/w_shift_bottom.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

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
    return AppScaffold(
      activeRoute: AppRoutes.closeShiftScreen,
      body: Column(
        children: [
          MainHeader(title: S.current.strTerminal),
          Expanded(
            child: BlocBuilder<ShiftBloc, ShiftState>(
              builder: (context, state) {
                return state.shift != null
                    ? _CloseShiftBody(state: state)
                    : const _OpenShiftBody();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Open Shift ────────────────────────────────────────────────────────────────

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
                  color: Color(0xFFFFF3EE),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.storefront_outlined,
                    color: Color(0xFFFB6633),
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
                  color: Color(0xFF19160B),
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                S.current.strStartWorkInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888888),
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // Time card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F4F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: Color(0xFF888888),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF19160B),
                            fontFamily: 'Inter',
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Open button
              BlocBuilder<ShiftBloc, ShiftState>(
                builder: (context, state) {
                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: state.status == Status.LOADING
                          ? null
                          : () => context.read<ShiftBloc>().add(
                                const ShiftEvent.openShift(),
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ffFB6633,
                        disabledBackgroundColor:
                            AppColors.ffFB6633.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: state.status == Status.LOADING
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

// ── Close Shift ───────────────────────────────────────────────────────────────

class _CloseShiftBody extends StatelessWidget {
  final ShiftState state;

  const _CloseShiftBody({required this.state});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;
        final edge = compact ? 12.0 : 24.0;
        final gap = compact ? 12.0 : 20.0;
        final rightW = compact ? 300.0 : 360.0;

        return Padding(
          padding: EdgeInsets.all(edge),
          child: Row(
            spacing: gap,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  spacing: compact ? 12 : 16,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ShiftInfoCard(state: state),
                    Expanded(child: _CloseShiftHint(compact: compact)),
                  ],
                ),
              ),
              SizedBox(
                width: rightW,
                child: const Align(
                  alignment: Alignment.bottomCenter,
                  child: WShiftBottom(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CloseShiftHint extends StatelessWidget {
  final bool compact;
  const _CloseShiftHint({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEBEBEB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF3EE),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.lock_clock_outlined,
                color: Color(0xFFFB6633),
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.current.strCloseShift,
            style: TextStyle(
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF19160B),
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            S.current.strCloseShiftInstruction,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              height: 1.5,
              color: const Color(0xFF888888),
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _ShiftInfoCard extends StatelessWidget {
  final ShiftState state;
  const _ShiftInfoCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final openTime = state.shift?.openedAt;
    final dur =
        openTime != null ? DateTime.now().difference(openTime) : Duration.zero;
    final h = dur.inHours;
    final m = dur.inMinutes % 60;
    final durationStr =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

    final openStr = openTime != null
        ? '${openTime.day.toString().padLeft(2, '0')}.${openTime.month.toString().padLeft(2, '0')}  '
            '${openTime.hour.toString().padLeft(2, '0')}:${openTime.minute.toString().padLeft(2, '0')}'
        : '--';

    final cashierName = context.select(
      (UserBloc b) => b.state.userMOdel?.fullName ?? state.shift?.cashierId ?? '',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEBEBEB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _InfoItem(label: S.current.strCashierRole, value: cashierName.isEmpty ? '--' : cashierName),
            _divider(),
            _InfoItem(label: S.current.strShiftOpened, value: openStr),
            _divider(),
            _InfoItem(
              label: S.current.strTerminal,
              value: S.current.strConnected,
              valueColor: const Color(0xFF13AF1B),
              prefix: const Icon(Icons.circle, size: 7, color: Color(0xFF13AF1B)),
            ),
            const SizedBox(width: 20),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3EE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                spacing: 3,
                children: [
                  Text(
                    S.current.strDuration,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFFB6633),
                      fontFamily: 'Inter',
                    ),
                  ),
                  Text(
                    durationStr,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFB6633),
                      fontFamily: 'Inter',
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Row(
        children: [
          const SizedBox(width: 28),
          Container(width: 1, height: 36, color: const Color(0xFFEBEBEB)),
          const SizedBox(width: 28),
        ],
      );
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? prefix;

  const _InfoItem({
    required this.label,
    required this.value,
    this.valueColor,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF888888),
            fontFamily: 'Inter',
          ),
        ),
        Row(
          spacing: 5,
          children: [
            if (prefix != null) prefix!,
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF19160B),
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
