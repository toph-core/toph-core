abstract class OrderFoodEntity {
  final String id;
  final String name;
  final int quantity;

  /// Unit price, in so'm, **with cents**. Not an int: a markup-derived price
  /// like 666.66 is ordinary, and truncating it here is how a bill silently
  /// came up short of what the backend charges.
  final double price;
  final String comment;
  final String status;
  final DateTime? createdAt;
  // Menu item id (`good_id`) — used to merge duplicate lines of the same
  // menu item and to resolve its department for receipt grouping. May be
  // empty for older/legacy responses that don't include it.
  final String goodId;

  OrderFoodEntity({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.comment,
    this.status = 'pending',
    this.createdAt,
    this.goodId = '',
  });
}
