import 'dart:ffi';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/open_order/open_order_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_departments_usecase.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

import 'printer_config.dart';
import 'printer_config_storage.dart';
import 'receipt/cashier_receipt_builder.dart';
import 'receipt/kitchen_receipt_builder.dart';
import 'receipt/shift_close_receipt_builder.dart';

class PrinterService {
  PrinterService(this._storage);

  final PrinterConfigStorage _storage;

  /// Hozir tizimga kirgan foydalanuvchi (buyurtmani qabul qilgan/qo'shgan kishi) — cheklarda ko'rsatish uchun.
  String get _waiterName => inject<UserBloc>().state.userMOdel?.fullName ?? '';

  /// categoryId -> nom — oshxona chekida pozitsiyalarni kategoriya bo'yicha
  /// guruhlab sarlavha chiqarish uchun. `CacheService` categoriyalarni
  /// DetailBloc har safar ro'yxatni yuklaganda saqlaydi.
  Map<String, String> get _categoryNames => {
        for (final c in inject<CacheService>().getCategories())
          if (c['id'] != null) c['id'].toString(): (c['name']?.toString() ?? ''),
      };

  /// goodId -> departmentId. Prefers the good's own `department_id`; falls
  /// back to its category's department when that's empty (older/denormalized
  /// records). Used to group closing-check items by department.
  Map<String, String> get _goodDepartmentId {
    final cache = inject<CacheService>();
    final categoryDept = <String, String>{
      for (final c in cache.getCategories())
        if (c['id'] != null) c['id'].toString(): (c['department_id']?.toString() ?? ''),
    };
    final map = <String, String>{};
    for (final g in cache.getGoods()) {
      final id = g['id']?.toString();
      if (id == null || id.isEmpty) continue;
      var deptId = g['department_id']?.toString() ?? '';
      if (deptId.isEmpty) {
        final catId = g['category_id']?.toString() ?? '';
        deptId = categoryDept[catId] ?? '';
      }
      map[id] = deptId;
    }
    return map;
  }

  /// departmentId -> name, and a fixed print order (cache/API response
  /// order, stable across a session). Fetches from the network once if the
  /// local cache is empty (e.g. app was never navigated to the menu screen
  /// this session).
  Future<({Map<String, String> names, List<String> order})> _resolveDepartments() async {
    var cached = inject<CacheService>().getDepartments();
    if (cached.isEmpty) {
      final result = await inject<GetDepartmentsUsecase>().call(NoParams());
      result.fold((_) {}, (list) {
        inject<CacheService>().saveDepartments(
          list.map((d) => {'id': d.id, 'name': d.name}).toList(),
        );
      });
      cached = inject<CacheService>().getDepartments();
    }
    final names = <String, String>{};
    final order = <String>[];
    for (final d in cached) {
      final id = d['id']?.toString();
      if (id == null || id.isEmpty) continue;
      order.add(id);
      names[id] = d['name']?.toString() ?? '';
    }
    return (names: names, order: order);
  }

  /// Archive/bill items don't always carry `good_id` (older backend
  /// responses). `/api/v1/order-items/order/{id}` does, keyed by line —
  /// same enrichment pattern as `DetailBloc._enrichExistingGoodsWithTimestamps`.
  /// Falls back silently (empty map) on any error — department grouping then
  /// just buckets those lines under "Other".
  Future<Map<String, String>> _fetchGoodIdsByName(String orderId) async {
    try {
      final res = await inject<DioClient>().get(ListAPI.orderItemsListByOrder(orderId));
      final raw = res.data['data'];
      final List<dynamic> list = raw is List
          ? raw
          : (raw is Map && raw['items'] is List ? raw['items'] as List : const []);
      final map = <String, String>{};
      for (final entry in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(entry);
        final name = (m['good_name'] ?? m['name'] ?? '').toString();
        final goodId = (m['good_id'] ?? '').toString();
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
      final deptInfo = await _resolveDepartments();
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
      final r = await _connectAndPrint(config, bytes, beep: true);
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
        nameToGoodId = await _fetchGoodIdsByName(detail.id);
      }
      final goodDept = _goodDepartmentId;
      final deptInfo = await _resolveDepartments();
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
      );
      final r = await _connectAndPrint(config, bytes, beep: true);
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
      final r = await _connectAndPrint(config, bytes, beep: true);
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

  /// `type: category` bo‘yicha guruhlab, har bir printerga alohida oshxona cheki.
  /// Printeri sozlanmagan kategoriya pozitsiyalari o‘tkaziladi (boshqa printerga qo‘shilmaydi).
  Future<void> printKitchenReceipt({
    required OpenOrderModel order,
    required List<OrderItem> items,
  }) =>
      printKitchenReceiptFor(
        tableLine: 'Стол: ${order.tableNumber}',
        hallName: order.hallName,
        guestCount: order.guestCount,
        items: items,
        orderId: order.id,
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
        );
        final r = await _connectAndPrint(config, bytes);
        if (!r.ok) {
          _notifyPrinterFailed(
            config,
            title: 'Oshxona cheki chop etilmadi',
            printerRole: 'category printer (backend) ${config.ip}',
            detail: r.error,
          );
          return;
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
    final data = beep ? [..._buzzerBytes, ...bytes] : bytes;
    if (config.usesWindowsPrinter) {
      if (!Platform.isWindows) {
        return (ok: false, error: "USB printer faqat Windows da ishlaydi.");
      }
      return _printViaWindowsRaw(data);
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
  Future<({bool ok, String? error})> _printViaWindowsRaw(List<int> bytes) async {
    try {
      final printerName = _findUsbPrinterName();
      if (printerName == null) {
        return (
          ok: false,
          error: "USB printer topilmadi.\n"
              "Windows: Sozlamalar → Bluetooth va qurilmalar → Printerlar da "
              "USB printer o'rnatilganini tekshiring.",
        );
      }
      return _writeRawToPrinter(printerName, bytes);
    } catch (e, st) {
      debugPrint('[PrinterService] USB print xatosi: $e\n$st');
      return (ok: false, error: "USB printer xatosi: $e");
    }
  }

  /// O'rnatilgan local printerlar orasidan USB portga ulangani topiladi.
  String? _findUsbPrinterName() {
    final cbNeeded = calloc<DWORD>();
    final cReturned = calloc<DWORD>();

    // Birinchi chaqiriq — bufer hajmini aniqlash
    EnumPrinters(PRINTER_ENUM_LOCAL, nullptr, 2, nullptr, 0, cbNeeded, cReturned);

    final size = cbNeeded.value;
    if (size == 0) {
      calloc.free(cbNeeded);
      calloc.free(cReturned);
      return null;
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

    String? found;
    if (ok != 0) {
      final count = cReturned.value;
      for (int i = 0; i < count; i++) {
        final pInfo = Pointer<PRINTER_INFO_2>.fromAddress(
          buf.address + i * sizeOf<PRINTER_INFO_2>(),
        );
        final portName = pInfo.ref.pPortName.toDartString().toUpperCase();
        if (portName.startsWith('USB')) {
          found = pInfo.ref.pPrinterName.toDartString();
          break;
        }
      }
    }

    calloc.free(buf);
    calloc.free(cbNeeded);
    calloc.free(cReturned);
    return found;
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
