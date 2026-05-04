import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// Buyurtmani boshqa stolga ko'chirish dialogi.
///
/// `MainCubit`'dagi mavjud `halls` va `tables`'ni qayta ishlatadi (sozlamalardan
/// kelgan, "Barchasi" rejimida yuklangan). Faqat `free` statusli stollar
/// tanlanadi.
Future<bool?> showTransferTableDialog(
  BuildContext context, {
  required String orderId,
  required String sourceTableId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _TransferTableDialog(
      orderId: orderId,
      sourceTableId: sourceTableId,
    ),
  );
}

class _TransferTableDialog extends StatefulWidget {
  final String orderId;
  final String sourceTableId;

  const _TransferTableDialog({
    required this.orderId,
    required this.sourceTableId,
  });

  @override
  State<_TransferTableDialog> createState() => _TransferTableDialogState();
}

class _TransferTableDialogState extends State<_TransferTableDialog> {
  String? _selectedHallId;
  String? _selectedTableId;
  bool _submitting = false;
  final ScrollController _gridCtrl = ScrollController();

  @override
  void dispose() {
    _gridCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final targetId = _selectedTableId;
    if (targetId == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final dio = inject<DioClient>().dio;
      await dio.post(
        ListAPI.orderTransfer(widget.orderId),
        data: {'target_table_id': targetId},
      );
      if (!mounted) return;
      // Stol holatlarini darhol yangilab, broadcast qilamiz —
      // boshqa POS qurilmalari ham real-time ko'rishi uchun.
      final main = context.read<MainCubit>();
      main.broadcastTableStatus(widget.sourceTableId, TableStatus.free);
      main.broadcastTableStatus(targetId, TableStatus.busy);
      Navigator.of(context).pop(true);
      showInfoMessage(context, S.current.strOrderTransferred);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final code = e.response?.statusCode;
      final detail = e.response?.data is Map
          ? (e.response?.data['details']?.toString() ??
              e.response?.data['message']?.toString())
          : null;
      final msg = switch (code) {
        409 => S.current.strSelectedTableIsBusy,
        404 => S.current.strOrderOrTableNotFound,
        400 => detail ?? S.current.strCannotTransfer,
        _ => detail ?? e.message ?? S.current.strErrorOccurred,
      };
      showErrorMessage(context, msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showErrorMessage(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MainCubit, MainState>(
      builder: (context, state) {
        final halls = state.halls ?? const <HallModel>[];
        final tables = state.tables ?? const <CafeTableModel>[];
        final hallId =
            _selectedHallId ?? (halls.isNotEmpty ? halls.first.id : null);

        // Tanlangan zaldagi stollar (joriy stol istisno qilinadi)
        final hallTables = tables
            .where((t) => t.hallId == hallId && t.id != widget.sourceTableId)
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.current.strChangeTable,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                fontFamily: 'Inter',
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              S.current.strSelectFreeTableForTransfer,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: const Color(0xFF64748B),
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Hall chips
                if (halls.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: halls.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final h = halls[i];
                          final selected = h.id == hallId;
                          return _HallChip(
                            label: h.name,
                            isActive: selected,
                            onTap: () => setState(() {
                              _selectedHallId = h.id;
                              _selectedTableId = null;
                            }),
                          );
                        },
                      ),
                    ),
                  ),

                // Tables grid
                Expanded(
                  child: hallTables.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFFB6633)
                                      .withOpacity(0.06),
                                ),
                                child: const Icon(
                                  Icons.table_restaurant_outlined,
                                  size: 24,
                                  color: Color(0xFFFB6633),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                S.current.strNoOtherTablesInHall,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF94A3B8),
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                          ),
                        )
                      : Scrollbar(
                          controller: _gridCtrl,
                          thumbVisibility: true,
                          thickness: 4,
                          radius: const Radius.circular(8),
                          child: GridView.builder(
                            controller: _gridCtrl,
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 20, 12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: hallTables.length,
                            itemBuilder: (_, i) {
                              final t = hallTables[i];
                              final isFree = t.status == TableStatus.free;
                              final isSelected = _selectedTableId == t.id;
                              return _TableTile(
                                number: t.number,
                                status: t.status,
                                tableType: t.tableType,
                                isSelected: isSelected,
                                onTap: isFree
                                    ? () => setState(
                                          () => _selectedTableId = t.id,
                                        )
                                    : null,
                              );
                            },
                          ),
                        ),
                ),

                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(S.current.strCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFB6633),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onPressed: (_selectedTableId == null || _submitting)
                            ? null
                            : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(S.current.strTransfer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HallChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _HallChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFB6633).withOpacity(0.1)
              : const Color(0xFFF8FAFC),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFB6633).withOpacity(0.4)
                : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive
                ? const Color(0xFFFB6633)
                : const Color(0xFF64748B),
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  final int number;
  final TableStatus status;
  final String? tableType;
  final bool isSelected;
  final VoidCallback? onTap;

  const _TableTile({
    required this.number,
    required this.status,
    required this.tableType,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = status == TableStatus.free;
    final isTimeBased = tableType?.toLowerCase() == 'time_based';
    final Color bg, border, text;
    if (isSelected) {
      bg = const Color(0xFFFB6633);
      border = const Color(0xFFFB6633);
      text = Colors.white;
    } else if (!isFree) {
      bg = const Color(0xFFF1F5F9);
      border = const Color(0xFFE2E8F0);
      text = const Color(0xFFCBD5E1);
    } else {
      bg = Colors.white;
      border = const Color(0xFFE2E8F0);
      text = const Color(0xFF0F172A);
    }
    // Indigo tint — time-based stol indikatori (yuqori-o'ngda kichik soat)
    final timerIconColor = isSelected
        ? Colors.white.withOpacity(0.9)
        : (isFree ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1));
    return Opacity(
      opacity: isFree || isSelected ? 1 : 0.6,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: isSelected ? 2 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              if (isTimeBased)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Tooltip(
                    message: 'Soatlik xona',
                    child: Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: timerIconColor,
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: text,
                        fontFamily: 'Inter',
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (!isFree && !isSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          S.current.strBusyShort,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF94A3B8),
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
