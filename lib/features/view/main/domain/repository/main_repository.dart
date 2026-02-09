import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';

abstract class MainRepository {
  Future<Either<Failure, List<CafeTableModel>>> getTablesByHallId(String hallId);
  Future<Either<Failure, List<HallModel>>> getHalls();
}
