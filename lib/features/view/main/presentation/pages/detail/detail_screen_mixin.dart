import 'package:mary_ai_pos/features/view/main/data/models/food_additional/food_additional_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';

// mixin DetailScreenMixin<T extends StatefulWidget> on State<T> {
mixin DetailScreenMixin {
  late final List<FoodAdditionalModel> additionals = [
    FoodAdditionalModel(title: "Qo'shimcha achchiq", price: 10000),
    FoodAdditionalModel(title: "Qo'shimcha tuz"),
    FoodAdditionalModel(title: "Ketchup ko'proq", price: 10000),
    FoodAdditionalModel(title: "Issiqroq"),
  ];

  double calculateTotalPrice(List<OrderItem> orders) {
    if (orders.isNotEmpty) {
      return orders
          .map((value) {
            if (value.goods.additionals.isNotEmpty) {
              return (value.goods.additionals
                          .map((v) => v.price)
                          .toList()
                          .reduce((a, b) => a + b) +
                      double.parse(value.goods.price)) *
                  value.quantity;
            } else {
              return double.parse(value.goods.price) * value.quantity;
            }
          })
          .toList()
          .reduce((a, b) => a + b)
          .toDouble();
    } else {
      return 0;
    }
  }
}
