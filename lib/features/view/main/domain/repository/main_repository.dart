import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/restaurant_table.dart';

abstract class MainRepository {
  Future<Either<Failure, List<RestaurantTable>>> getTables();
} 