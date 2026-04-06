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

  const OrderLineItemModel({
    required this.id,
    required this.goodId,
    required this.quantity,
    required this.price,
    this.comment,
    this.goodName,
    this.status,
  });

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
    );
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
