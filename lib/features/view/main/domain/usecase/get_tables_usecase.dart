import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/models/restaurant_table.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

class GetTablesUsecase extends UseCase<List<RestaurantTable>, NoParams> {
  final MainRepository _repository;
  GetTablesUsecase(this._repository);

  @override
  Future<Either<Failure, List<RestaurantTable>>> call(NoParams params) async =>
      await _repository.getTables();
}
