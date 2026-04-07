import 'package:mary_ai_pos/core/extension/list_extension.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';

class OpenOrderModel {
  final String id;
  final String? name;
  final int tableNumber;
  final String hallName;
  final int guestCount;
  final DateTime? openedAt;
  /// Present in `GET /api/v1/orders` (cashier); used to resolve stol/zal when [tableNumber] is missing.
  final String? tableId;
  /// e.g. `open`, `paid` — from branch orders list.
  final String? status;
  /// API `total_amount` (string).
  final String totalAmount;
  /// API `display_total_amount` (string). Time-based stol uchun ko‘pincha shu ko‘rsatiladi.
  final String displayTotalAmount;
  /// API `service_amount` — xizmat summasi (agar berilgan bo‘lsa).
  final String? serviceAmount;
  /// API `service_percent` — masalan 20 (%).
  final double? servicePercent;
  /// API `order_type` — masalan `dine_in`, `take_away`.
  final String? orderType;
  /// API `table_type` — masalan `time_based`.
  final String? tableType;
  /// API `table_started_at` — time based stol ishga tushgan vaqt.
  final DateTime? tableStartedAt;

  const OpenOrderModel({
    required this.id,
    this.name,
    required this.tableNumber,
    required this.hallName,
    required this.guestCount,
    this.openedAt,
    this.tableId,
    this.status,
    this.totalAmount = '0',
    this.displayTotalAmount = '0',
    this.serviceAmount,
    this.servicePercent,
    this.orderType,
    this.tableType,
    this.tableStartedAt,
  });

  OpenOrderModel copyWith({
    String? id,
    Object? name = _sentinel,
    int? tableNumber,
    String? hallName,
    int? guestCount,
    Object? openedAt = _sentinel,
    Object? tableId = _sentinel,
    Object? status = _sentinel,
    String? totalAmount,
    String? displayTotalAmount,
    Object? serviceAmount = _sentinel,
    Object? servicePercent = _sentinel,
    Object? orderType = _sentinel,
    Object? tableType = _sentinel,
    Object? tableStartedAt = _sentinel,
  }) {
    return OpenOrderModel(
      id: id ?? this.id,
      name: identical(name, _sentinel) ? this.name : name as String?,
      tableNumber: tableNumber ?? this.tableNumber,
      hallName: hallName ?? this.hallName,
      guestCount: guestCount ?? this.guestCount,
      openedAt:
          identical(openedAt, _sentinel) ? this.openedAt : openedAt as DateTime?,
      tableId: identical(tableId, _sentinel) ? this.tableId : tableId as String?,
      status: identical(status, _sentinel) ? this.status : status as String?,
      totalAmount: totalAmount ?? this.totalAmount,
      displayTotalAmount: displayTotalAmount ?? this.displayTotalAmount,
      serviceAmount: identical(serviceAmount, _sentinel)
          ? this.serviceAmount
          : serviceAmount as String?,
      servicePercent: identical(servicePercent, _sentinel)
          ? this.servicePercent
          : servicePercent as double?,
      orderType:
          identical(orderType, _sentinel) ? this.orderType : orderType as String?,
      tableType:
          identical(tableType, _sentinel) ? this.tableType : tableType as String?,
      tableStartedAt: identical(tableStartedAt, _sentinel)
          ? this.tableStartedAt
          : tableStartedAt as DateTime?,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value as String);
  }

  factory OpenOrderModel.fromJson(Map<String, dynamic> json) {
    double? sp;
    final rawSp = json['service_percent'];
    if (rawSp is num) {
      sp = rawSp.toDouble();
    } else if (rawSp != null) {
      sp = double.tryParse(rawSp.toString());
    }
    return OpenOrderModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String?,
      tableNumber: (json['table_number'] as num?)?.toInt() ?? 0,
      hallName: json['hall_name'] as String? ?? '',
      guestCount: (json['guest_count'] as num?)?.toInt() ?? 0,
      openedAt: _parseDate(json['opened_at']) ?? _parseDate(json['created_at']),
      tableId: json['table_id'] as String?,
      status: json['status'] as String?,
      totalAmount: json['total_amount']?.toString() ?? '0',
      displayTotalAmount: json['display_total_amount']?.toString() ?? '0',
      serviceAmount: json['service_amount']?.toString(),
      servicePercent: sp,
      orderType: json['order_type'] as String?,
      tableType: json['table_type'] as String?,
      tableStartedAt: _parseDate(json['table_started_at']),
    );
  }

  double get displayTotalAmountValue => double.tryParse(
        displayTotalAmount.replaceAll(RegExp(r'\s'), ''),
      ) ??
      0;

  double get totalAmountValue {
    final d = displayTotalAmountValue;
    if (d > 0) return d;
    return double.tryParse(totalAmount.replaceAll(RegExp(r'\s'), '')) ?? 0;
  }

  bool get isTimeBasedTable =>
      (tableType ?? '').trim().toLowerCase() == 'time_based';

  double get serviceAmountValue =>
      double.tryParse((serviceAmount ?? '0').replaceAll(RegExp(r'\s'), '')) ??
      0;

  int resolveTableNumber(List<CafeTableModel>? tables) {
    if (tableNumber != 0) return tableNumber;
    final tid = tableId;
    if (tid == null || tid.isEmpty || tables == null) return 0;
    return tables.firstWhereOrNull((t) => t.id == tid)?.number ?? 0;
  }

  String resolveHallName(List<HallModel>? halls, List<CafeTableModel>? tables) {
    if (hallName.isNotEmpty) return hallName;
    final tid = tableId;
    if (tid == null || tid.isEmpty || tables == null || halls == null) {
      return '';
    }
    final t = tables.firstWhereOrNull((x) => x.id == tid);
    if (t == null) return '';
    return halls.firstWhereOrNull((h) => h.id == t.hallId)?.name ?? '';
  }
}

/// Ro‘yxat / badge uchun qisqa yozuv (`GET /orders` `status` maydoni).
extension OpenOrderStatusLabel on OpenOrderModel {
  String get statusKeyNormalized =>
      (status ?? '').trim().toLowerCase();

  String get statusDisplayLabel {
    switch (statusKeyNormalized) {
      case 'open':
        return 'Открыт';
      case 'cooking':
      case 'preparing':
        return 'Готовится';
      case 'ready':
        return 'Готово';
      case 'served':
        return 'Подано';
      case 'paid':
        return 'Оплачен';
      case 'cancelled':
        return 'Отменён';
      case 'reserved':
        return 'Забронирован';
      case 'rescheduled':
        return 'Перенесён';
      default:
        final s = status?.trim();
        if (s != null && s.isNotEmpty) return s;
        return '—';
    }
  }

  /// To‘langan yoki yakuniy bekor — yopish / tahrirlash tugmalari kerak emas.
  bool get isTerminalOrderStatus {
    final s = statusKeyNormalized;
    return s == 'paid' || s == 'cancelled';
  }
}

const _sentinel = Object();
