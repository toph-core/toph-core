/// Line item from `GET /api/v1/order-items/order/{orderId}` (va boshqa javoblar).
/// API har bir qatorda `good_name` qaytarishi mumkin; yo‘q bo‘lsa `good` obyekti yoki `name` ishlatiladi.
class OrderLineItemModel {
  final String id;
  final String goodId;
  final int quantity;
  final String price;
  final String? comment;
  final String? goodName;
  final String? status;
  final DateTime? createdAt;

  const OrderLineItemModel({
    required this.id,
    required this.goodId,
    required this.quantity,
    required this.price,
    this.comment,
    this.goodName,
    this.status,
    this.createdAt,
  });

  OrderLineItemModel copyWith({
    String? id,
    String? goodId,
    int? quantity,
    String? price,
    Object? comment = _sentinel,
    Object? goodName = _sentinel,
    Object? status = _sentinel,
    Object? createdAt = _sentinel,
  }) {
    return OrderLineItemModel(
      id: id ?? this.id,
      goodId: goodId ?? this.goodId,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      comment: identical(comment, _sentinel) ? this.comment : comment as String?,
      goodName: identical(goodName, _sentinel) ? this.goodName : goodName as String?,
      status: identical(status, _sentinel) ? this.status : status as String?,
      createdAt: identical(createdAt, _sentinel)
          ? this.createdAt
          : createdAt as DateTime?,
    );
  }

  factory OrderLineItemModel.fromJson(Map<String, dynamic> json) {
    final good = json['good'];
    String? nameFromGood;
    if (good is Map<String, dynamic>) {
      nameFromGood = _stringField(good['name']) ?? _stringField(good['title']);
    }
    return OrderLineItemModel(
      id: json['id'] as String? ?? '',
      goodId: json['good_id'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      price: json['price']?.toString() ?? '0',
      comment: json['comment'] as String?,
      goodName: _stringField(json['good_name']) ??
          _stringField(json['name']) ??
          nameFromGood,
      status: json['status'] as String?,
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) {
      return DateTime.tryParse(v)?.toLocal();
    }
    if (v is DateTime) return v.toLocal();
    return null;
  }

  static String? _stringField(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    return v.toString();
  }

  String get displayName {
    final n = goodName?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (goodId.isNotEmpty) return 'Mahsulot';
    return '—';
  }

  bool get isCancelled =>
      (status ?? '').toLowerCase() == 'cancelled';

  /// Bekor qilish mumkinmi (serverda hali bekor qilinmagan).
  bool get canBeCancelled => !isCancelled;

  String get statusLabel {
    final s = (status ?? '').toLowerCase();
    switch (s) {
      case 'pending':
        return 'Ожидание';
      case 'cancelled':
        return 'Отменён';
      case 'cooking':
      case 'preparing':
        return 'Готовится';
      case 'ready':
        return 'Готово';
      case 'served':
        return 'Подано';
      default:
        return status?.isNotEmpty == true ? status! : '—';
    }
  }
}

const _sentinel = Object();
