import 'dart:math' as math;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:mary_ai_pos/core/pricing/order_totals.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_esc_pos_helper.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_notice_lines.dart';
import 'package:mary_ai_pos/core/service/printer/receipt/receipt_som_format.dart';
import 'package:mary_ai_pos/core/service/receipt/receipt_info_storage.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

/// One consolidated receipt line — same menu item (by `good_id`, or by name
/// when `good_id` isn't known) merged across every order line that produced
/// it, with every distinct comment preserved (never dropped or merged into
/// one string — printed as separate indented rows under the item).
class _MergedLine {
  _MergedLine({required this.name});

  final String name;
  int quantity = 0;
  double lineTotal = 0;
  final List<String> comments = [];
}

/// Kassir cheki — narxlar, jami summa, xizmat to'lovi bilan to'liq chek.
class CashierReceiptBuilder {
  CashierReceiptBuilder._();

  static String _fmt(num value) => ReceiptSomFormat.formatInt(value);

  static String _fmtClock(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtDuration(int totalSec) {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0 && m > 0) return '${h}h ${m}min';
    if (h > 0) return '${h}h 0min';
    if (m > 0) return '${m}min ${s}s';
    return '${s}s';
  }

  /// The service fee for a bill, charged on **items only**.
  ///
  /// The table charge is never serviced. That is the venue's rule, it is what
  /// `OrderTotals.compute` has always implemented, and it is what the backend
  /// re-derives at pay time — but this path added `hourAmount` into the base,
  /// so the waiter's close receipt billed service on the hourly charge as well.
  /// The amount actually taken came from `WaiterCubit._payAmountSom`, which
  /// prices through `OrderTotals`, so the paper said one number and the till
  /// took another — and the cashier's receipt for the same bill said a third.
  ///
  /// When a table charge is present the fee is recomputed from the percent
  /// rather than read from the row: the API's `service_amount` on an unpaid
  /// order is not yet the settled figure.
  static double _servicePart(OpenOrderModel order, double subtotal, {double hourAmount = 0}) {
    final sp = order.servicePercent;
    if (hourAmount > 0.0001) {
      if (sp != null && sp > 0) return subtotal * sp / 100.0;
      return 0;
    }
    final explicit = order.serviceAmountValue;
    if (explicit > 0.0001) return explicit;
    if (sp != null && sp > 0) return subtotal * sp / 100.0;
    final tot = order.totalAmountValue;
    if (tot > subtotal + 0.01) return tot - subtotal;
    return 0;
  }

  static String _serviceLabel(OpenOrderModel order, double subtotal, double service) {
    final sp = order.servicePercent;
    if (sp != null && sp > 0) {
      final ps = sp == sp.roundToDouble() ? '${sp.round()}' : '$sp';
      return 'Обслужение ($ps%):';
    }
    if (subtotal > 0.01 && service > 0.01) {
      final approx = (service / subtotal * 100).round();
      return 'Обслужение (~$approx%):';
    }
    return 'Обслужение:';
  }

  static double _discountValue(double preDiscount, double discountPercent, double discountAmount) {
    if (discountPercent > 0) {
      final v = preDiscount * discountPercent / 100.0;
      if (v > 0.0001) return v;
    }
    if (discountAmount > 0.0001) return math.min(discountAmount, preDiscount);
    return 0;
  }

  /// Pause tarixi bloki — ikkala `build` metodida qayta ishlatiladi.
  static void _appendTimerSection({
    required Generator gen,
    required List<int> bytes,
    required DateTime? timerStartedAt,
    required List<PauseInterval> timerPauses,
    required int timerTotalSec,
    required String? timerPricePerHour,
  }) {
    final hasData = timerStartedAt != null || timerTotalSec > 0 || timerPauses.isNotEmpty;
    if (!hasData) return;

    bytes.addAll(gen.hr());
    bytes.addAll(gen.text(
      'SOATLIK JADVAL',
      styles: const PosStyles(bold: false, align: PosAlign.center),
    ));

    if (timerStartedAt != null) {
      bytes.addAll(gen.row([
        PosColumn(text: 'Ochildi:', width: 6),
        PosColumn(text: _fmtClock(timerStartedAt), width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]));
    }

    // Pause tarixi
    for (int i = 0; i < timerPauses.length; i++) {
      final p = timerPauses[i];
      final num = i + 1;
      bytes.addAll(gen.row([
        PosColumn(text: 'Pause $num bo\'ldi:', width: 7),
        PosColumn(text: _fmtClock(p.startedAt), width: 5,
            styles: const PosStyles(align: PosAlign.right)),
      ]));
      if (p.endedAt != null) {
        bytes.addAll(gen.row([
          PosColumn(text: 'To\'xtatildi:', width: 7),
          PosColumn(text: _fmtClock(p.endedAt!), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      }
      if (p.durationSec > 0) {
        bytes.addAll(gen.row([
          PosColumn(text: 'Pause vaqti:', width: 7),
          PosColumn(text: _fmtDuration(p.durationSec), width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      }
    }

    if (timerTotalSec > 0) {
      bytes.addAll(gen.row([
        PosColumn(text: 'Faol vaqt:', width: 7),
        PosColumn(text: _fmtDuration(timerTotalSec), width: 5,
            styles: const PosStyles(align: PosAlign.right)),
      ]));
    }

    // Umumiy pauza vaqti
    final totalPauseSec = timerPauses.fold(0, (s, p) => s + p.durationSec);
    if (totalPauseSec > 0) {
      bytes.addAll(gen.row([
        PosColumn(text: 'Umumiy pauza:', width: 7),
        PosColumn(text: _fmtDuration(totalPauseSec), width: 5,
            styles: const PosStyles(align: PosAlign.right)),
      ]));
    }

    if (timerPricePerHour != null && timerPricePerHour.isNotEmpty) {
      final ph = int.tryParse(timerPricePerHour.replaceAll(RegExp(r'[^0-9]'), ''));
      if (ph != null && ph > 0) {
        bytes.addAll(gen.row([
          PosColumn(text: 'Soatlik narx:', width: 7),
          PosColumn(text: '${_fmt(ph)} sum', width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
      }
    }
  }

  // ── Department grouping (buildFromDetail) ────────────────────────────────

  /// Groups [items] by department id (via [departmentIdOf], empty string for
  /// unknown/unresolved) and, within each department, merges lines that
  /// share the same menu item (`good_id`, falling back to name) into one
  /// row with a summed quantity — while keeping every comment from every
  /// merged line (never lost, never collapsed into the others).
  static Map<String, List<_MergedLine>> _groupByDepartment(
    List<OrderFoodEntity> items,
    String Function(OrderFoodEntity)? departmentIdOf,
  ) {
    final byDept = <String, Map<String, _MergedLine>>{};
    for (final g in items) {
      final deptId = departmentIdOf?.call(g) ?? '';
      final deptLines = byDept.putIfAbsent(deptId, () => {});
      final key = g.goodId.isNotEmpty ? g.goodId : g.name;
      final line = deptLines.putIfAbsent(key, () => _MergedLine(name: g.name));
      line.quantity += g.quantity;
      line.lineTotal += g.price * g.quantity;
      final note = g.comment.trim();
      if (note.isNotEmpty) line.comments.add(note);
    }
    return {for (final e in byDept.entries) e.key: e.value.values.toList()};
  }

  /// Departments are printed only if they have items, in [departmentOrder]
  /// (a fixed, session-stable order from the department list), then any
  /// department id not present there (still a real id, just not fetched into
  /// the order list), and finally the unresolved/"no department" bucket.
  static List<String> _departmentPrintOrder(
    Map<String, List<_MergedLine>> byDept,
    List<String> departmentOrder,
  ) {
    final keys = <String>[];
    for (final id in departmentOrder) {
      if (byDept.containsKey(id)) keys.add(id);
    }
    for (final id in byDept.keys) {
      if (!keys.contains(id)) keys.add(id);
    }
    if (keys.remove('')) keys.add('');
    return keys;
  }

  static void _appendDepartmentItemLines({
    required Generator gen,
    required List<int> bytes,
    required Map<String, List<_MergedLine>> byDept,
    required Map<String, String> departmentNames,
    required List<String> departmentOrder,
  }) {
    final keys = _departmentPrintOrder(byDept, departmentOrder);
    for (final id in keys) {
      final lines = byDept[id];
      if (lines == null || lines.isEmpty) continue;
      final name = departmentNames[id];
      final label = (name != null && name.isNotEmpty) ? name : 'ДРУГОЕ';
      // Black text on white, bold only — no inverted/reverse-video headers
      // (thermal paper is white; reverse print looks muddy and wastes ink).
      bytes.addAll(gen.text(
        label.toUpperCase(),
        styles: const PosStyles(bold: true),
      ));
      for (final line in lines) {
        final displayName = line.name.length > 20
            ? '${line.name.substring(0, 18)}..'
            : line.name;
        bytes.addAll(gen.row([
          PosColumn(text: displayName, width: 6),
          PosColumn(text: '${line.quantity}x', width: 2,
              styles: const PosStyles(align: PosAlign.center)),
          PosColumn(text: _fmt(line.lineTotal), width: 4,
              styles: const PosStyles(align: PosAlign.right)),
        ]));
        for (final c in line.comments) {
          bytes.addAll(gen.text('  - $c'));
        }
      }
    }
  }

  static void _appendCancelledSection({
    required Generator gen,
    required List<int> bytes,
    required List<OrderFoodEntity> cancelledGoods,
    required Map<String, String> departmentNames,
    required List<String> departmentOrder,
    required String Function(OrderFoodEntity)? departmentIdOf,
  }) {
    if (cancelledGoods.isEmpty) return;
    bytes.addAll(gen.hr());
    bytes.addAll(gen.text(
      'ОТМЕНЁННЫЕ ПОЗИЦИИ',
      styles: const PosStyles(bold: true, align: PosAlign.center),
      linesAfter: 1,
    ));
    final byDept = _groupByDepartment(cancelledGoods, departmentIdOf);
    _appendDepartmentItemLines(
      gen: gen,
      bytes: bytes,
      byDept: byDept,
      departmentNames: departmentNames,
      departmentOrder: departmentOrder,
    );
  }

  // ── Table usage (Room-by-room) — buildFromDetail only ────────────────────

  static double _segmentAmount(TableSegment s, double fallbackPricePerHour) {
    final amt = double.tryParse(s.amount ?? '');
    if (amt != null) return amt;
    return fallbackPricePerHour * (s.activeSeconds / 3600.0);
  }

  static double _segmentPrice(TableSegment s) =>
      double.tryParse(s.pricePerHour ?? '') ?? 0;

  /// "X ч Y мин" — always both parts, rounded to the nearest minute from raw
  /// seconds (a single rounding step, so per-line and summed totals never
  /// disagree by a minute the way summing already-rounded lines would).
  static String _fmtHoursMinutesRu(int totalSec) {
    final totalMin = (totalSec / 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    return '$h ч $m мин';
  }

  /// Transparent room-by-room breakdown of the time-based table charge —
  /// every segment (a room may be entered/left/re-entered several times),
  /// every active interval within it, and a clean hours × rate result (no
  /// intermediate formula spelled out). Silently omitted when there's
  /// nothing to show. All totals are derived from raw seconds, never by
  /// re-summing already-rounded per-line minute values, so the room and
  /// grand totals can never mismatch what's shown per interval.
  static void _appendTableUsageSection({
    required Generator gen,
    required List<int> bytes,
    required ArchiveDetailEntity detail,
  }) {
    final segments = detail.activePeriods;
    if (segments.isEmpty) return;

    bytes.addAll(gen.hr());
    bytes.addAll(gen.text(
      'ИСПОЛЬЗОВАНИЕ СТОЛА',
      styles: const PosStyles(bold: true, align: PosAlign.center),
    ));
    if (detail.tableNumber > 0) {
      bytes.addAll(gen.text('Стол: ${detail.tableNumber.toInt()}'));
    }
    if (detail.opened != null) {
      bytes.addAll(gen.text('Открыт: ${_fmtClock(detail.opened!)}'));
    }

    // Group segments by room (table number; falls back to table id for the
    // rare case a segment's number wasn't frozen).
    final byRoom = <String, List<TableSegment>>{};
    final roomOrder = <String>[];
    for (final s in segments) {
      final key = s.tableNumber != null ? 'n${s.tableNumber}' : 't${s.tableId ?? ''}';
      if (!byRoom.containsKey(key)) roomOrder.add(key);
      byRoom.putIfAbsent(key, () => []).add(s);
    }

    int totalActiveSec = 0;
    int totalCost = 0;

    for (var i = 0; i < roomOrder.length; i++) {
      final segs = byRoom[roomOrder[i]]!;
      final roomNumber = segs.firstWhere(
        (s) => s.tableNumber != null,
        orElse: () => segs.first,
      ).tableNumber;
      // Most recent known rate for this room (rate may have changed between
      // segments — each segment's own frozen amount is still authoritative
      // if rates actually differ, see fallback below).
      final price = segs.map(_segmentPrice).lastWhere((p) => p > 0, orElse: () => 0);
      final pricesDiffer = segs.map(_segmentPrice).where((p) => p > 0).toSet().length > 1;

      bytes.addAll(gen.text(''));
      bytes.addAll(gen.text(
        'Комната ${roomNumber ?? '?'}   ${_fmt(price)} сум/час',
        styles: const PosStyles(bold: true),
      ));

      final intervals = <ActiveInterval>[];
      for (final s in segs) {
        intervals.addAll(s.activeIntervals);
      }
      intervals.sort((a, b) => a.start.compareTo(b.start));

      for (final iv in intervals) {
        final endLabel = iv.end != null ? _fmtClock(iv.end!) : 'сейчас';
        bytes.addAll(gen.text(
          '${_fmtClock(iv.start)} -> $endLabel   ${_fmtHoursMinutesRu(iv.durationSec)}',
        ));
      }

      final roomActiveSec = segs.fold<int>(0, (s, seg) => s + seg.activeSeconds);
      final roomHours = roomActiveSec / 3600.0;
      // Rate changed mid-room (rare) — the clean hours×rate formula doesn't
      // apply to a single displayed rate, so fall back to summing each
      // segment's own authoritative frozen amount.
      final roomCost = pricesDiffer
          ? segs.fold<double>(0, (s, seg) => s + _segmentAmount(seg, _segmentPrice(seg))).round()
          : (roomHours * price).round();

      if (intervals.isNotEmpty) {
        bytes.addAll(gen.text(
          'Итого по комнате: ${roomHours.toStringAsFixed(2)} ч x ${_fmt(price)} = ${_fmt(roomCost)} сум',
        ));
      }

      totalActiveSec += roomActiveSec;
      totalCost += roomCost;

      if (i < roomOrder.length - 1) bytes.addAll(gen.hr(ch: '-'));
    }

    bytes.addAll(gen.hr());
    bytes.addAll(gen.text('Общее время: ${_fmtHoursMinutesRu(totalActiveSec)}'));
    bytes.addAll(gen.text(
      'Общая стоимость стола: ${_fmt(totalCost)} сум',
      styles: const PosStyles(bold: true),
    ));
  }

  /// To'liq kassir cheki — [OpenOrderModel] asosida.
  static Future<List<int>> build({
    required OpenOrderModel order,
    required List<OrderItem> items,
    PaperSize paperSize = PaperSize.mm80,
    double discountPercent = 0,
    double discountAmount = 0,
    double hourAmount = 0,
    DateTime? timerStartedAt,
    List<PauseInterval> timerPauses = const [],
    int timerTotalSec = 0,
    String? timerPricePerHour,
    Map<String, String> departmentNames = const {},
    List<String> departmentOrder = const [],
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = receiptGenerator(paperSize, profile);
    final now = DateTime.now();
    final timeFmt = DateFormat('dd.MM.yyyy  HH:mm');

    List<int> bytes = [];
    bytes += receiptEncodingPreamble(gen);

    bytes += gen.text(
      'КАССИРСКИЙ ЧЕК',
      styles: const PosStyles(
        align: PosAlign.center, bold: true,
        height: PosTextSize.size2, width: PosTextSize.size1,
      ),
      linesAfter: 1,
    );

    bytes += gen.text(timeFmt.format(now));
    bytes += gen.row([
      PosColumn(text: 'Зал:', width: 4),
      PosColumn(text: order.hallName, width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Стол:', width: 4),
      PosColumn(text: '${order.tableNumber}', width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Гости:', width: 4),
      PosColumn(text: '${order.guestCount}', width: 8),
    ]);

    _appendTimerSection(
      gen: gen, bytes: bytes,
      timerStartedAt: timerStartedAt,
      timerPauses: timerPauses,
      timerTotalSec: timerTotalSec,
      timerPricePerHour: timerPricePerHour,
    );

    bytes += gen.hr();

    // Items — grouped by department (empty dept id → "ДРУГОЕ" bucket), each
    // menu item merged into one line with a summed quantity, no comment lost.
    final byDept = <String, Map<String, _MergedLine>>{};
    double subtotal = 0;
    for (final item in items) {
      final price = double.tryParse(item.goods.price) ?? 0;
      final lineTotal = price * item.quantity;
      subtotal += lineTotal;
      final deptId = item.goods.departmentId;
      final deptLines = byDept.putIfAbsent(deptId, () => {});
      final key = item.goods.id.isNotEmpty ? item.goods.id : item.goods.name;
      final line = deptLines.putIfAbsent(key, () => _MergedLine(name: item.goods.name));
      line.quantity += item.quantity;
      line.lineTotal += lineTotal;
      // Waiter flow stores the note in `commet` (status field repurposed as
      // comment for this print-only list); DetailBloc flow uses `comment`.
      final note = (item.commet.isNotEmpty ? item.commet : item.comment).trim();
      if (note.isNotEmpty) line.comments.add(note);
    }
    final byDeptLines = {
      for (final e in byDept.entries) e.key: e.value.values.toList(),
    };
    _appendDepartmentItemLines(
      gen: gen,
      bytes: bytes,
      byDept: byDeptLines,
      departmentNames: departmentNames,
      departmentOrder: departmentOrder,
    );

    bytes += gen.hr();

    bytes += gen.row([
      PosColumn(text: 'Товары:', width: 8, styles: const PosStyles(bold: false)),
      PosColumn(text: _fmt(subtotal), width: 4,
          styles: const PosStyles(bold: false, align: PosAlign.right)),
    ]);

    if (hourAmount > 0.0001) {
      bytes += gen.row([
        PosColumn(text: 'Плата за стол:', width: 8),
        PosColumn(text: _fmt(hourAmount), width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    final serviceRaw = _servicePart(order, subtotal, hourAmount: hourAmount);
    final serviceAmt = serviceRaw > 0.0001 ? serviceRaw : 0.0;
    if (serviceAmt > 0) {
      bytes += gen.row([
        PosColumn(text: _serviceLabel(order, subtotal, serviceAmt), width: 8),
        PosColumn(text: _fmt(serviceAmt), width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    final preDiscount = subtotal + hourAmount + serviceAmt;
    final discountVal = _discountValue(preDiscount, discountPercent, discountAmount);
    if (discountVal > 0.0001) {
      final discLabel = discountPercent > 0
          ? 'Скидка (${discountPercent == discountPercent.roundToDouble() ? discountPercent.round().toString() : discountPercent.toStringAsFixed(1)}%):'
          : 'Скидка:';
      bytes += gen.row([
        PosColumn(text: discLabel, width: 8),
        PosColumn(text: _fmt(discountVal), width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    final toPay = (preDiscount - discountVal).clamp(0.0, double.infinity);

    bytes += gen.hr();
    bytes += gen.row([
      PosColumn(text: 'ИТОГО:', width: 8,
          styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size1)),
      PosColumn(text: _fmt(toPay.round()), width: 4,
          styles: const PosStyles(bold: true, align: PosAlign.right,
              height: PosTextSize.size2, width: PosTextSize.size1)),
    ]);

    appendReceiptNoReprepNotice(gen, bytes);
    bytes += gen.feed(1);
    bytes += gen.text('Спасибо!', styles: const PosStyles(align: PosAlign.center, bold: true), linesAfter: 1);
    bytes += gen.cut();

    return bytes;
  }

  /// Ismdan qisqa format ("Ali Valiyev" → "Ali V.")
  /// `—` emas — CP866 kod jadvalida yo'q, printer uni `?` ga almashtiradi.
  static String _shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'Неизвестно';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts[1][0].toUpperCase()}.';
  }

  /// Chekni kim yopgani — hech qachon "?" yoki bo'sh chiqmasligi kerak.
  /// `detail.cashierName` bo'sh bo'lsa (masalan admin tomonidan yopilganda
  /// backend uni to'ldirmagan holatlar), hozir tizimga kirgan foydalanuvchi
  /// ([closerName]) ishlatiladi — u chekni chop etayotgan aynan shu kishi.
  static String _resolveCloserName(ArchiveDetailEntity detail, String closerName) {
    final primary = detail.cashierName.trim();
    if (primary.isNotEmpty) return primary;
    final fallback = closerName.trim();
    if (fallback.isNotEmpty) return fallback;
    return 'Неизвестно';
  }

  /// To'lov ekranidan keyin chek — [ArchiveDetailEntity] asosida. This is the
  /// **closing check**: items grouped by department (duplicates merged, every
  /// comment kept), a transparent room-by-room table-usage breakdown, and
  /// cancelled items in their own section at the very end.
  /// Preview modal (`ReceiptPreviewModal`) bilan bir xil ko'rinishda chop etiladi.
  static Future<List<int>> buildFromDetail({
    required ArchiveDetailEntity detail,
    PaperSize paperSize = PaperSize.mm80,
    double hourAmount = 0,
    double discountPercent = 0,
    double discountAmount = 0,
    // Kept for call-site compatibility; the printed table-usage breakdown
    // now comes from `detail.activePeriods` (room-by-room, see
    // `_appendTableUsageSection`) rather than this flat pause list.
    DateTime? timerStartedAt,
    List<PauseInterval> timerPauses = const [],
    int timerTotalSec = 0,
    String? timerPricePerHour,
    String Function(OrderFoodEntity)? departmentIdOf,
    Map<String, String> departmentNames = const {},
    List<String> departmentOrder = const [],
    // Hozir tizimga kirgan foydalanuvchi — `detail.cashierName` bo'sh bo'lsa
    // shu ko'rsatiladi (hech qachon "?" yoki bo'sh emas).
    String closerName = '',
    // The figures the cashier was shown and the customer was charged.
    //
    // Without them this method re-derives the service fee from the order row,
    // and on the close-check path that row is the *unpaid* bill: the backend
    // fills `service_amount` when it settles the payment, so at print time it
    // is still 0 and the fee silently vanished from the receipt — while the
    // same bill reprinted from the checks history, by then a settled row,
    // showed it. Two formulas over two versions of one bill.
    //
    // So the payment screen hands over the `OrderTotals` it charged, and the
    // receipt prints that. The derivation below stays for the reprint paths,
    // which have no live payment state and a settled row that carries the
    // right numbers already.
    OrderTotals? totals,
    // Only for the service line's "(N%)" label, when [totals] carries a fee
    // the order row cannot name a percent for.
    double servicePercent = 0,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = receiptGenerator(paperSize, profile);
    final now = DateTime.now();
    final dateStr = DateFormat('dd.MM.yyyy  HH:mm').format(now);

    // Restoran ma'lumotlari
    final info = inject<ReceiptInfoStorage>().effective;
    final companyName = info.companyName.toUpperCase();

    List<int> bytes = [];
    bytes += receiptEncodingPreamble(gen);

    // ─── 1) Restoran sarlavhasi ──────────────────────────────────────────
    bytes += gen.text(
      companyName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    if (info.address.isNotEmpty) {
      bytes += gen.text(
        info.address,
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (info.phone.isNotEmpty) {
      bytes += gen.text(
        'Tel: ${info.phone}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    bytes += gen.hr(ch: '-');

    // ─── 2) Meta info ────────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(text: 'Чек №:', width: 6),
      PosColumn(
        text: 'A-${detail.bilNumber}',
        width: 6,
        styles: const PosStyles(align: PosAlign.right, bold: false),
      ),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Дата:', width: 4),
      PosColumn(
        text: dateStr,
        width: 8,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    final tableNum = detail.tableNumber.toInt();
    if (tableNum > 0) {
      final guests = detail.guestCount > 0
          ? ' · ${detail.guestCount.toInt()} гостей'
          : '';
      bytes += gen.row([
        PosColumn(text: 'Стол:', width: 4),
        PosColumn(
          text: '№$tableNum$guests',
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }
    bytes += gen.row([
      PosColumn(text: 'Кассир:', width: 5),
      PosColumn(
        text: _shortName(_resolveCloserName(detail, closerName)),
        width: 7,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);

    bytes += gen.hr(ch: '-');

    // ─── 3) Ordered items — grouped by department, duplicates merged ─────
    final purchasedGoods = detail.goods.where((g) => g.status != 'cancelled').toList();
    final cancelledGoods = detail.goods.where((g) => g.status == 'cancelled').toList();

    double subtotal = 0;
    for (final g in purchasedGoods) {
      subtotal += g.price * g.quantity;
    }

    final byDept = _groupByDepartment(purchasedGoods, departmentIdOf);
    _appendDepartmentItemLines(
      gen: gen,
      bytes: bytes,
      byDept: byDept,
      departmentNames: departmentNames,
      departmentOrder: departmentOrder,
    );

    // ─── 4) Cancelled items — right after ordered items, own section ─────
    _appendCancelledSection(
      gen: gen,
      bytes: bytes,
      cancelledGoods: cancelledGoods,
      departmentNames: departmentNames,
      departmentOrder: departmentOrder,
      departmentIdOf: departmentIdOf,
    );

    // ─── 5) Table usage — transparent room-by-room breakdown ─────────────
    _appendTableUsageSection(gen: gen, bytes: bytes, detail: detail);

    // ─── 6) Totals ─────────────────────────────────────────────────────
    bytes += gen.hr(ch: '-');
    bytes += gen.row([
      PosColumn(text: 'Товары:', width: 7),
      PosColumn(
        text: _fmt(subtotal),
        width: 5,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (hourAmount > 0.0001) {
      bytes += gen.row([
        PosColumn(text: 'Плата за стол:', width: 7),
        PosColumn(
          text: _fmt(hourAmount),
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // Service applies to items only — table_charge is not serviced.
    // When table charge is present, ignore API service_amount (read path omits it on table).
    final baseForService = subtotal;
    final serviceAmt = totals != null
        // `serviceCharged`, not `serviceAmount`: a cashier who switched the
        // service toggle off must not see the fee on the customer's receipt.
        ? totals.serviceCharged.toDouble()
        : hourAmount > 0.0001
        ? (detail.servicePercent > 0
              ? baseForService * detail.servicePercent / 100
              : 0.0)
        : (detail.serviceAmount > 0.0001
              ? detail.serviceAmount
              : (detail.servicePercent > 0
                    ? baseForService * detail.servicePercent / 100
                    : 0.0));
    if (serviceAmt > 0.0001) {
      final pct = detail.servicePercent > 0
          ? detail.servicePercent
          : servicePercent;
      final servicePct = pct.toInt();
      final label = servicePct > 0 ? 'Обслуживание ($servicePct%)' : 'Обслуживание';
      bytes += gen.row([
        PosColumn(text: label, width: 7),
        PosColumn(
          text: _fmt(serviceAmt),
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    final preDiscount = totals != null
        ? totals.baseTotal.toDouble()
        : subtotal + hourAmount + serviceAmt;
    final discVal = totals != null
        ? totals.discountValue.toDouble()
        : _discountValue(preDiscount, discountPercent, discountAmount);
    if (discVal > 0.0001) {
      final discLabel = discountPercent > 0
          ? 'Скидка (${discountPercent.toInt()}%)'
          : 'Скидка';
      bytes += gen.row([
        PosColumn(text: discLabel, width: 7),
        PosColumn(
          text: '-${_fmt(discVal)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += gen.hr(ch: '-');

    // The absolute total: items + table charge + service - discount, taken
    // from the charged figures when the caller has them rather than re-added
    // here from parts that may not include the fee.
    final toPay = totals != null
        ? totals.grandTotal.toDouble()
        : (preDiscount - discVal).clamp(0.0, double.infinity);
    // ─── ИТОГО (big, bold) ────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(
        text: 'ИТОГО',
        width: 5,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      ),
      PosColumn(
        text: '${_fmt(toPay.round())} сум',
        width: 7,
        styles: const PosStyles(
          bold: true,
          align: PosAlign.right,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      ),
    ]);

    // ─── 7) Footer notes ───────────────────────────────────────────────
    appendReceiptNoReprepNotice(gen, bytes);
    bytes += gen.feed(1);
    bytes += gen.text(
      'Спасибо!',
      styles: const PosStyles(align: PosAlign.center, bold: true),
      linesAfter: 1,
    );
    bytes += gen.cut();

    return bytes;
  }
}
