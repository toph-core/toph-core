import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/data_source/main_datasources.dart';
import 'package:mary_ai_pos/features/view/main/data/models/restaurant_table.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

class MainRepositoryImpl implements MainRepository {
  final MainDataSources _dataSources;

  MainRepositoryImpl(this._dataSources);

  @override
  Future<Either<Failure, List<RestaurantTable>>> getTables() {
    return _dataSources.getTables();
  }
}
