import 'dart:ffi';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:win32/win32.dart';

import 'package:mary_ai_pos/core/db/order_detail_query.dart' as replica;
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

import 'printer_config.dart';
import 'printer_config_storage.dart';
import 'receipt/cashier_receipt_builder.dart';
import 'receipt/kitchen_receipt_builder.dart';
import 'receipt/receipt_esc_pos_helper.dart';
import 'receipt/shift_close_receipt_builder.dart';

class PrinterService {
  PrinterService(this._storage);

  final PrinterConfigStorage _storage;

  /// Wired by `di.dart` once `PrintQueueService` exists — routes a
  /// fully-rendered close-check-family receipt through the print-job queue
  /// (local-print-vs-relay decision, claim/lease tracking, Phase 5) instead
  /// of blasting bytes straight to the transport layer. Kept as a plain
  /// function reference rather than a constructor dependency so this file
  /// never has to import `print_queue_service.dart` — `PrintQueueService`
  /// already depends on *this* class (for [printRenderedBytes]), and a
  /// two-way import between them would be a real circular dependency, not
  /// just an inconvenient one. Mirrors `LanAuthValidator`/`LanRelayHandler`'s
  /// existing typedef-callback pattern for the same reason. `null` until
  /// `di.dart` finishes wiring (nothing prints during `initDi()` itself, so
  /// this is never actually called unset in practice) — falls back to
  /// direct printing regardless, so a receipt can never silently vanish due
  /// to wiring order.
  Future<({bool ok, String? error})> Function(
    PrinterConfig config,
    List<int> bytes, {
    required String jobType,
    required bool beep,
  })? _dispatchViaQueue;

  void attachPrintQueue(
    Future<({bool ok, String? error})> Function(
      PrinterConfig config,
      List<int> bytes, {
      required String jobType,
      required bool beep,
    }) dispatch,
  ) {
    _dispatchViaQueue = dispatch;
  }

  Future<({bool ok, String? error})> _dispatchOrPrint(
    PrinterConfig config,
    List<int> bytes, {
    required String jobType,
    bool beep = true,
  }) {
    final dispatch = _dispatchViaQueue;
    if (dispatch != null) {
      return dispatch(config, bytes, jobType: jobType, beep: beep);
    }
    return _connectAndPrint(config, bytes, beep: beep);
  }

  /// Hozir tizimga kirgan foydalanuvchi (buyurtmani qabul qilgan/qo'shgan kishi) — cheklarda ko'rsatish uchun.
  String get _waiterName => inject<UserBloc>().state.userMOdel?.fullName ?? '';

  /// categoryId -> nom — oshxona chekida pozitsiyalarni kategoriya bo'yicha
  /// guruhlab sarlavha chiqarish uchun. Replikadan sinxron o'qiladi.
  Map<String, String> get _categoryNames => {
        for (final c in inject<MenuRepository>().getCategories()) c.id: c.name,
      };

  /// goodId -> departmentId. Prefers the good's own `department_id`; falls
  /// back to its category's department when that's empty (older/denormalized
  /// records). Used to group closing-check items by department.
  Map<String, String> get _goodDepartmentId {
    final menu = inject<MenuRepository>();
    final categoryDept = <String, String>{
      for (final c in menu.getCategories()) c.id: c.departmentId ?? '',
    };
    final map = <String, String>{};
    for (final g in menu.getGoodsForCategory('all')) {
      if (g.id.isEmpty) continue;
      var deptId = g.departmentId;
      if (deptId.isEmpty) deptId = categoryDept[g.categoryId] ?? '';
      map[g.id] = deptId;
    }
    return map;
  }

  /// departmentId -> name, plus a fixed print order — the replica's own
  /// `name COLLATE NOCASE, id` ordering, so a check groups its departments
  /// the same way on every terminal and every reprint.
  ///
  /// This used to fetch from the network when the local cache happened to be
  /// empty (app never navigated to the menu screen this session), which put a
  /// round-trip on the kitchen-print path. The replica is populated by the
  /// change feed, not by a screen having been visited, so there is nothing
  /// left to fall back to.
  ({Map<String, String> names, List<String> order}) _resolveDepartments() {
    final names = <String, String>{};
    final order = <String>[];
    for (final d in inject<MenuRepository>().getDepartments()) {
      if (d.id.isEmpty) continue;
      order.add(d.id);
      names[d.id] = d.name;
    }
    return (names: names, order: order);
  }

  /// Archive/bill items don't always carry `good_id` (older backend
  /// responses), and department grouping needs one per line.
  ///
  /// This used to ask `/api/v1/order-items/order/{id}` for it, which put an
  /// awaited round-trip on the receipt path: offline the cashier waited out
  /// Dio's timeout before the check printed, and the grouping degraded to
  /// "Other" anyway. `order_items` replicates — `good_id` is a promoted
  /// column on it — so the same answer is a local join, which is what
  /// `DetailBloc` already moved to when it dropped its own `getOrderItemsRaw`
  /// fetch. Same map, no socket, and it is correct offline rather than merely
  /// tolerable.
  Map<String, String> _goodIdsByName(String orderId) {
    try {
      final map = <String, String>{};
      for (final item in inject<replica.OrderDetailQuery>().itemsForOrder(orderId)) {
        final name = (item['good_name'] ?? item['name'] ?? '').toString();
        final goodId = (item['good_id'] ?? '').toString();
        if (name.isNotEmpty && goodId.isNotEmpty) {
          map.putIfAbsent(name, () => goodId);
        }
      }
      return map;
    } catch (e) {
      debugPrint('[PrinterService] good_id enrichment xatosi: $e');
      return const {};
    }
  }

  /// TCP orqali yuborish; juda kichik bo‘laklar ESC/raster oqimini sindirishi mumkin.
  static const _socketChunkBytes = 8192;
  static const List<int> _buzzerBytes = [0x1B, 0x42, 0x02, 0x03];

  static List<List<int>> _socketSendChunks(List<int> bytes) {
    if (bytes.isEmpty) return [bytes];
    if (bytes.length <= _socketChunkBytes) return [bytes];
    return bytes.splitByLength(_socketChunkBytes);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// `type: close_check` printer — to’liq kassir cheki.
  Future<void> printCashierReceipt({
    required OpenOrderModel order,
    required List<OrderItem> items,
    double discountPercent = 0,
    double discountAmount = 0,
    double hourAmount = 0,
    DateTime? timerStartedAt,
    List<PauseInterval> timerPauses = const [],
    int timerTotalSec = 0,
    String? timerPricePerHour,
  }) async {
    // Summa 0 / barcha pozitsiyalar bekor — yopilgan schyot uchun bo’sh chek ham chop etiladi.
    try {
      final config = _storage.closeCheckConfigOrFallback();
      final deptInfo = _resolveDepartments();
      final bytes = await CashierReceiptBuilder.build(
        order: order,
        items: items,
        paperSize: config.paperSize,
        discountPercent: discountPercent,
        discountAmount: discountAmount,
        hourAmount: hourAmount,
        timerStartedAt: timerStartedAt,
        timerPauses: timerPauses,
        timerTotalSec: timerTotalSec,
        timerPricePerHour: timerPricePerHour,
        departmentNames: deptInfo.names,
        departmentOrder: deptInfo.order,
      );
      final r = await _dispatchOrPrint(config, bytes, jobType: 'cashier');
      if (!r.ok) {
        _notifyPrinterFailed(
          config,
          title: 'Kassir cheki chop etilmadi',
          printerRole: 'close_check printer (backend)',
          detail: r.error,
        );
      }
    } catch (e, st) {
      debugPrint('[PrinterService] Kassir cheki xatosi: $e\n$st');
      final config = _storage.closeCheckConfigOrFallback();
      _notifyPrinterFailed(
        config,
        title: 'Kassir cheki tayyorlashda xato',
        printerRole: 'close_check printer (backend)',
        detail: e.toString(),
      );
    }
  }

  /// To'lov ekranidan keyin chek — [ArchiveDetailEntity] asosida.
  Future<void> printCashierReceiptFromDetail({
    required ArchiveDetailEntity detail,
    double hourAmount = 0,
    double discountPercent = 0,
    double discountAmount = 0,
    DateTime? timerStartedAt,
    List<PauseInterval> timerPauses = const [],
    int timerTotalSec = 0,
    String? timerPricePerHour,
  }) async {
    try {
      final config = _storage.closeCheckConfigOrFallback();

      // good_id yo'q bo'lgan qatorlar bo'lsa — nom bo'yicha to'ldiramiz
      // (bo'lim/departament guruhlash uchun kerak).
      Map<String, String> nameToGoodId = const {};
      if (detail.goods.any((g) => g.goodId.isEmpty) && detail.id.isNotEmpty) {
        nameToGoodId = _goodIdsByName(detail.id);
      }
      final goodDept = _goodDepartmentId;
      final deptInfo = _resolveDepartments();
      String departmentIdOf(OrderFoodEntity g) {
        final gid = g.goodId.isNotEmpty ? g.goodId : (nameToGoodId[g.name] ?? '');
        return gid.isNotEmpty ? (goodDept[gid] ?? '') : '';
      }

      final bytes = await CashierReceiptBuilder.buildFromDetail(
        detail: detail,
        paperSize: config.paperSize,
        hourAmount: hourAmount,
        discountPercent: discountPercent,
        discountAmount: discountAmount,
        timerStartedAt: timerStartedAt,
        timerPauses: timerPauses,
        timerTotalSec: timerTotalSec,
        timerPricePerHour: timerPricePerHour,
        departmentIdOf: departmentIdOf,
        departmentNames: deptInfo.names,
        departmentOrder: deptInfo.order,
        // Chekni kim yopayotgani — hozir tizimga kirgan foydalanuvchi
        // (kassir yoki admin). `detail.cashierName` bo'sh bo'lsa shu ishlatiladi,
        // hech qachon "?" yoki bo'sh qator chiqmasligi uchun.
        closerName: _waiterName,
      );
      final r = await _dispatchOrPrint(config, bytes, jobType: 'cashier');
      if (!r.ok) {
        _notifyPrinterFailed(
          config,
          title: 'Kassir cheki chop etilmadi',
          printerRole: 'close_check printer',
          detail: r.error,
        );
      }
    } catch (e, st) {
      debugPrint('[PrinterService] Kassir cheki xatosi: $e\n$st');
      final config = _storage.closeCheckConfigOrFallback();
      _notifyPrinterFailed(
        config,
        title: 'Kassir cheki tayyorlashda xato',
        printerRole: 'close_check printer',
        detail: e.toString(),
      );
    }
  }

  /// Smena yopilishi — `close_check` printer.
  Future<void> printShiftCloseReceipt({
    required String shiftId,
    required DateTime? openedAt,
    required int closingCard,
    required String cashierLabel,
  }) async {
    try {
      final config = _storage.closeCheckConfigOrFallback();
      final bytes = await ShiftCloseReceiptBuilder.build(
        shiftId: shiftId,
        openedAt: openedAt,
        closingCard: closingCard,
        cashierLabel: cashierLabel,
        paperSize: config.paperSize,
      );
      final r = await _dispatchOrPrint(config, bytes, jobType: 'shiftClose');
      if (!r.ok) {
        _notifyPrinterFailed(
          config,
          title: 'Smena yopilish cheki chop etilmadi',
          printerRole: 'close_check printer (backend)',
          detail: r.error,
        );
      }
    } catch (e, st) {
      debugPrint('[PrinterService] Smena yopilish cheki: $e\n$st');
      final config = _storage.closeCheckConfigOrFallback();
      _notifyPrinterFailed(
        config,
        title: 'Smena cheki tayyorlashda xato',
        printerRole: 'close_check printer (backend)',
        detail: e.toString(),
      );
    }
  }

  /// Printer sozlamalari formasidagi "Test Printer" tugmasi uchun — bitta
  /// diagnostik chek chop etadi (IP/port/tur, oddiy/qalin/tagiga chizilgan
  /// matn, uchta tekislash). Hali saqlanmagan qiymatlarni ham sinash mumkin —
  /// `PrinterConfigStorage`ga bog'liq emas, chaqiruvchi istalgan
  /// ip/port/connectionType/paperSize kombinatsiyasini uzatishi mumkin.
  /// `connectionType: 'usb'` bo'lsa [windowsPrinterName] talab qilinadi,
  /// ip/port e'tiborga olinmaydi. Muvaffaqiyat/xato natijasini
  /// to'g'ridan-to'g'ri qaytaradi — UI o'zi qanday ko'rsatishni hal qiladi
  /// (bu yerda global xato overlay chiqarilmaydi).
  Future<({bool ok, String? error})> testPrint({
    String ip = '',
    int port = 0,
    String connectionType = 'wlan',
    PaperSize paperSize = PaperSize.mm80,
    int timeoutMs = 6000,
    String? windowsPrinterName,
  }) async {
    final config = PrinterConfig(
      ip: ip,
      port: port,
      connectionType: connectionType,
      paperSize: paperSize,
      timeoutMs: timeoutMs,
      windowsPrinterName: windowsPrinterName,
    );
    try {
      final bytes = await _buildTestTicket(config);
      // Tez javob uchun bitta urinish + bitta qayta urinish — Save tugmasidan
      // farqli o'laroq, foydalanuvchi "Test" bosgach uzoq kutmasligi kerak.
      return await _connectAndPrint(config, bytes, beep: true, maxRetries: 1);
    } catch (e, st) {
      debugPrint('[PrinterService] Test print xatosi: $e\n$st');
      return (ok: false, error: e.toString());
    }
  }

  Future<List<int>> _buildTestTicket(PrinterConfig config) async {
    final profile = await CapabilityProfile.load();
    final gen = receiptGenerator(config.paperSize, profile);

    List<int> bytes = [];
    bytes += receiptEncodingPreamble(gen);

    bytes += gen.text(
      'ТЕСТОВАЯ ПЕЧАТЬ',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
      linesAfter: 1,
    );
    bytes += gen.hr();
    bytes += gen.row([
      PosColumn(text: 'IP:', width: 4),
      PosColumn(text: config.ip, width: 8, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Порт:', width: 4),
      PosColumn(text: '${config.port}', width: 8, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Тип:', width: 4),
      PosColumn(text: config.connectionType, width: 8, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.text('Время: ${DateFormat('dd.MM.yyyy HH:mm:ss').format(DateTime.now())}');
    bytes += gen.hr();
    bytes += gen.text('Обычный текст');
    bytes += gen.text('Жирный текст', styles: const PosStyles(bold: true));
    bytes += gen.text('Подчёркнутый текст', styles: const PosStyles(underline: true));
    bytes += gen.text('По левому краю', styles: const PosStyles(align: PosAlign.left));
    bytes += gen.text('По центру', styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('По правому краю', styles: const PosStyles(align: PosAlign.right));
    bytes += gen.hr();
    bytes += gen.text(
      'Принтер настроен верно!',
      styles: const PosStyles(align: PosAlign.center, bold: true),
      linesAfter: 1,
    );
    bytes += gen.feed(2);
    bytes += gen.cut();

    return bytes;
  }

  /// `type: category` bo‘yicha guruhlab, har bir printerga alohida oshxona cheki.
  /// Printeri sozlanmagan kategoriya pozitsiyalari o‘tkaziladi (boshqa printerga qo‘shilmaydi).
  Future<void> printKitchenReceipt({
    required OpenOrderModel order,
    required List<OrderItem> items,
    bool cancelled = false,
  }) =>
      printKitchenReceiptFor(
        tableLine: 'Стол: ${order.tableNumber}',
        hallName: order.hallName,
        guestCount: order.guestCount,
        items: items,
        orderId: order.id,
        cancelled: cancelled,
      );

  /// [printKitchenReceipt] bilan bir xil, lekin to'liq [OpenOrderModel] talab
  /// qilmaydi — kassir oqimlari (CreateOrderBloc/DetailBloc) uchun.
  Future<void> printKitchenReceiptFor({
    required String tableLine,
    required List<OrderItem> items,
    String hallName = '',
    int guestCount = 0,
    String? orderNumber,
    String? orderId,
    // See KitchenReceiptBuilder.buildWithHeader — template-only, no call
    // site passes true yet (design doc §12/§13, open question 5).
    bool cancelled = false,
  }) async {
    if (items.isEmpty) return;
    final byKey = <String, List<OrderItem>>{};
    final cfgByKey = <String, PrinterConfig>{};
    for (final item in items) {
      final cfg = _storage.categoryPrinterForOrNull(
        item.goods.categoryId,
        goodId: item.goods.id,
      );
      if (cfg == null) {
        debugPrint(
          '[PrinterService] Oshxona printeri yo\'q, o\'tkazildi: ${item.goods.name} '
          '(category_id=${item.goods.categoryId}, good_id=${item.goods.id})',
        );
        continue;
      }
      final k = '${cfg.ip}:${cfg.port}';
      cfgByKey[k] = cfg;
      byKey.putIfAbsent(k, () => []).add(item);
    }
    if (byKey.isEmpty) {
      // Bu pozitsiyalarning kategoriyasi printer sozlamalarida yo'q — kutilgan
      // holat (masalan ichimliklar uchun oshxona printeri sozlanmagan bo'lishi
      // mumkin). Foydalanuvchiga xato ko'rsatilmaydi, faqat log yoziladi.
      debugPrint(
        '[PrinterService] Oshxona cheki: barcha pozitsiyalar uchun printer topilmadi — chop etilmadi.',
      );
      return;
    }
    try {
      final categoryNames = _categoryNames;
      final configsInOrder = <PrinterConfig>[];
      final dispatches = <Future<({bool ok, String? error})>>[];
      for (final k in byKey.keys) {
        final config = cfgByKey[k]!;
        final sub = byKey[k]!;
        final bytes = await KitchenReceiptBuilder.buildWithHeader(
          tableLine: tableLine,
          hallName: hallName,
          guestCount: guestCount,
          items: sub,
          paperSize: config.paperSize,
          waiterName: _waiterName,
          orderNumber: orderNumber,
          orderId: orderId,
          categoryNames: categoryNames,
          cancelled: cancelled,
        );
        configsInOrder.add(config);
        dispatches.add(
          _dispatchOrPrint(config, bytes, jobType: 'kitchen', beep: false),
        );
      }
      // Barchasi bir vaqtda yuboriladi — birinchi xatoda to'xtab qolmaydi.
      // Relay orqali yuborilgan job (Phase 5) ~26s gacha davom etishi mumkin;
      // ketma-ket kutish boshqa (relay kerak bo'lmagan) printerlarning
      // cheklarini ham sababsiz kechiktirar edi — oshxona cheklari shoshilinch.
      final results = await Future.wait(dispatches);
      for (var i = 0; i < results.length; i++) {
        if (!results[i].ok) {
          _notifyPrinterFailed(
            configsInOrder[i],
            title: 'Oshxona cheki chop etilmadi',
            printerRole: 'category printer (backend) ${configsInOrder[i].ip}',
            detail: results[i].error,
          );
        }
      }
    } catch (e, st) {
      debugPrint('[PrinterService] Oshxona cheki xatosi: $e\n$st');
      PrinterConfig? config;
      for (final item in items) {
        config = _storage.categoryPrinterForOrNull(
          item.goods.categoryId,
          goodId: item.goods.id,
        );
        if (config != null) break;
      }
      if (config != null) {
        _notifyPrinterFailed(
          config,
          title: 'Oshxona cheki tayyorlashda xato',
          printerRole: 'category printer (backend)',
          detail: e.toString(),
        );
      }
    }
  }

  /// Sends already-rendered ESC/POS bytes straight to a printer — no receipt
  /// building or config lookup. Used by `PrintQueueService` (Phase 5) both
  /// when this terminal executes its own locally-owned print and when it's
  /// executing a job relayed here from another terminal — the receipt was
  /// already rendered wherever the job originated, so only the transport
  /// step happens here.
  Future<({bool ok, String? error})> printRenderedBytes(
    PrinterConfig config,
    List<int> bytes, {
    bool beep = true,
  }) => _connectAndPrint(config, bytes, beep: beep);

  // ── Internal ──────────────────────────────────────────────────────────────

  void _notifyPrinterFailed(
    PrinterConfig config, {
    required String title,
    required String printerRole,
    String? detail,
  }) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final timeoutSec = config.timeoutMs ~/ 1000;
    final paragraphs = <String>[
      printerRole,
      'Manzil: ${config.ip}:${config.port}  •  timeout: ${timeoutSec}s',
      if (detail != null && detail.trim().isNotEmpty) detail.trim(),
      'Tarmoq, printer yoqilishi va IP/port (odatda 9100)ni tekshiring.',
    ];

    showStructuredErrorDismissible(
      ctx,
      title: title,
      icon: Icons.print_disabled_rounded,
      paragraphs: paragraphs,
    );
  }

  /// Printer’ga ulanib bytes yuboradi: cable → Windows USB API, wlan/wifi → TCP.
  Future<({bool ok, String? error})> _connectAndPrint(
    PrinterConfig config,
    List<int> bytes, {
    int maxRetries = 2,
    bool beep = false,
  }) async {
    // Signal oxirida — boshida yuborilsa, printer hali ESC @ bilan
    // ishga tushmagan holatda notanish buyruq oladi va ba'zi modellarda
    // butun jarayonni chalkashtirib qo'yishi mumkin.
    final data = beep ? [...bytes, ..._buzzerBytes] : bytes;
    if (config.usesWindowsPrinter) {
      if (!Platform.isWindows) {
        return (ok: false, error: "USB printer faqat Windows da ishlaydi.");
      }
      // `windowsPrinterName` odatda ad-hoc konfiglarda (Test Printer) to'g'ridan
      // -to'g'ri keladi; `_storage`dan kelgan haqiqiy chek konfiglari faqat
      // `entryId` bilan keladi — shu qurilmada mahalliy saqlangan tanlovni
      // shu yerda qidiramiz (backend bilan sinxronlanmaydi, sof lokal holat).
      final targetName = config.windowsPrinterName ??
          (config.entryId != null
              ? _storage.getUsbPrinterName(config.entryId!)
              : null);
      return _printViaWindowsRaw(data, targetPrinterName: targetName);
    }

    if (!config.usesNetworkTcp) {
      return (
        ok: false,
        error: "Printer ulanish turi [${config.connectionType}] qo’llab-quvvatlanmaydi.",
      );
    }

    int attempt = 0;
    String? lastSocketMessage;
    while (attempt <= maxRetries) {
      try {
        final socket = await Socket.connect(
          config.ip,
          config.port,
          timeout: Duration(milliseconds: config.timeoutMs),
        );

        // 250 bayt — raster (logo) va boshqa buyruqlarni o‘rtadan uzib, printer
        // qolganini matn sifatida chop etishi mumkin. Katta bo‘lak yoki bitta yuborish.
        final chunks = _socketSendChunks(data);
        await socket.addStream(Stream.fromIterable(chunks));
        await socket.flush();
        await socket.close();
        socket.destroy();

        debugPrint('[PrinterService] Chek yuborildi → ${config.ip}:${config.port}');
        return (ok: true, error: null);
      } on SocketException catch (e) {
        lastSocketMessage = _formatSocketException(e);
        attempt++;
        if (attempt > maxRetries) {
          debugPrint(
            '[PrinterService] Printer ${config.ip} offline ($lastSocketMessage). '
            '$maxRetries urinishdan keyin bekor qilindi.',
          );
          return (ok: false, error: lastSocketMessage);
        }
        debugPrint('[PrinterService] Ulanish xatosi, qayta urinish $attempt/$maxRetries...');
        await Future.delayed(const Duration(seconds: 1));
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[PrinterService] Yuborish xatosi: $e\n$st');
        }
        return (ok: false, error: e.toString());
      }
    }
    return (ok: false, error: 'Ulanib bo\'lmadi (${config.ip}:${config.port})');
  }

  /// Android/iOS ba'zida `message` bo'sh; `osError` — "Network is unreachable" va h.k.
  static String _formatSocketException(SocketException e) {
    final m = e.message.trim();
    final os = e.osError;
    if (os != null) {
      final osPart = '${os.message} (kod ${os.errorCode})';
      return m.isNotEmpty ? '$m — $osPart' : osPart;
    }
    if (m.isNotEmpty) return m;
    return e.toString();
  }

  // ── Windows USB printing ──────────────────────────────────────────────────

  /// USB kabel orqali ulangan printerga raw ESC/POS bytes yuboradi.
  /// Windows printer API: OpenPrinter → WritePrinter → ClosePrinter.
  ///
  /// [targetPrinterName] berilgan bo'lsa — aniq shu nomdagi (katta/kichik
  /// harf farqisiz) mahalliy printer qidiriladi va topilmasa xato qaytariladi
  /// (nima topilgani ro'yxati bilan — diagnostika uchun). Berilmagan bo'lsa —
  /// eski xulq-atvor: porti "USB" bilan boshlanadigan birinchi printer
  /// (bir nechta printer ulangan bo'lsa noaniq — shuning uchun sozlamalar
  /// formasida printer nomi tanlash tavsiya etiladi).
  Future<({bool ok, String? error})> _printViaWindowsRaw(
    List<int> bytes, {
    String? targetPrinterName,
  }) async {
    try {
      final printers = _enumerateLocalPrinters();
      String? printerName;
      final want = targetPrinterName?.trim() ?? '';
      if (want.isNotEmpty) {
        for (final p in printers) {
          if (p.name.toLowerCase() == want.toLowerCase()) {
            printerName = p.name;
            break;
          }
        }
        if (printerName == null) {
          final found = printers.map((p) => p.name).join(', ');
          return (
            ok: false,
            error: 'Tanlangan printer topilmadi: "$want".\n'
                "Ushbu kompyuterda o'rnatilgan printerlar: "
                "${found.isEmpty ? '(hech biri)' : found}",
          );
        }
      } else {
        for (final p in printers) {
          if (p.port.toUpperCase().startsWith('USB')) {
            printerName = p.name;
            break;
          }
        }
        if (printerName == null) {
          return (
            ok: false,
            error: "USB printer topilmadi.\n"
                "Windows: Sozlamalar → Bluetooth va qurilmalar → Printerlar da "
                "USB printer o'rnatilganini tekshiring, yoki printer "
                "sozlamalarida aniq printerni tanlang.",
          );
        }
      }
      return _writeRawToPrinter(printerName, bytes);
    } catch (e, st) {
      debugPrint('[PrinterService] USB print xatosi: $e\n$st');
      return (ok: false, error: "USB printer xatosi: $e");
    }
  }

  /// Ushbu kompyuterda o'rnatilgan barcha printerlar (nomi va porti) — USB
  /// printer tanlagichi (sozlamalar formasi) va diagnostika xabarlari uchun.
  List<({String name, String port})> _enumerateLocalPrinters() {
    final cbNeeded = calloc<DWORD>();
    final cReturned = calloc<DWORD>();

    // Birinchi chaqiriq — bufer hajmini aniqlash
    EnumPrinters(PRINTER_ENUM_LOCAL, nullptr, 2, nullptr, 0, cbNeeded, cReturned);

    final size = cbNeeded.value;
    if (size == 0) {
      calloc.free(cbNeeded);
      calloc.free(cReturned);
      return const [];
    }

    final buf = calloc<Uint8>(size);
    final ok = EnumPrinters(
      PRINTER_ENUM_LOCAL,
      nullptr,
      2,
      buf,
      size,
      cbNeeded,
      cReturned,
    );

    final result = <({String name, String port})>[];
    if (ok != 0) {
      final count = cReturned.value;
      for (int i = 0; i < count; i++) {
        final pInfo = Pointer<PRINTER_INFO_2>.fromAddress(
          buf.address + i * sizeOf<PRINTER_INFO_2>(),
        );
        result.add((
          name: pInfo.ref.pPrinterName.toDartString(),
          port: pInfo.ref.pPortName.toDartString(),
        ));
      }
    }

    calloc.free(buf);
    calloc.free(cbNeeded);
    calloc.free(cReturned);
    return result;
  }

  /// Sozlamalar formasidagi USB printer tanlagichi uchun — Windows'da
  /// o'rnatilgan barcha printerlar nomi. Windows'dan tashqarida bo'sh ro'yxat.
  List<String> listLocalWindowsPrinterNames() {
    if (!Platform.isWindows) return const [];
    return _enumerateLocalPrinters().map((p) => p.name).toList();
  }

  /// Win32 API orqali raw bytes yuboradi.
  ({bool ok, String? error}) _writeRawToPrinter(String name, List<int> bytes) {
    final pName = name.toNativeUtf16();
    final phPrinter = calloc<HANDLE>();

    if (OpenPrinter(pName, phPrinter, nullptr) == 0) {
      calloc.free(phPrinter);
      malloc.free(pName);
      return (ok: false, error: "Printer ochilmadi: $name");
    }

    final hPrinter = phPrinter.value;
    calloc.free(phPrinter);
    malloc.free(pName);

    final pDocName = 'POS Receipt'.toNativeUtf16();
    final pDatatype = 'RAW'.toNativeUtf16();
    final pDocInfo = calloc<DOC_INFO_1>()
      ..ref.pDocName = pDocName
      ..ref.pOutputFile = nullptr
      ..ref.pDatatype = pDatatype;

    final jobId = StartDocPrinter(hPrinter, 1, pDocInfo.cast());
    calloc.free(pDocInfo);
    malloc.free(pDocName);
    malloc.free(pDatatype);

    if (jobId == 0) {
      ClosePrinter(hPrinter);
      return (ok: false, error: "StartDocPrinter muvaffaqiyatsiz: $name");
    }

    StartPagePrinter(hPrinter);

    final pData = calloc<Uint8>(bytes.length);
    pData.asTypedList(bytes.length).setAll(0, bytes);
    final pWritten = calloc<DWORD>();
    WritePrinter(hPrinter, pData, bytes.length, pWritten);
    calloc.free(pData);
    calloc.free(pWritten);

    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);

    debugPrint('[PrinterService] USB chek yuborildi → $name');
    return (ok: true, error: null);
  }
}
