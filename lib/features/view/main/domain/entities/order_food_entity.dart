abstract class OrderFoodEntity {
  final String id;
  final String name;
  final int quantity;
  final int price;
  final String comment;

  OrderFoodEntity({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.comment,
  });
}
