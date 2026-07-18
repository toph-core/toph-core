import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';

class GetDepartmentsUsecase extends UseCase<List<DepartmentModel>, NoParams> {
  final MainRepository _repository;
  GetDepartmentsUsecase(this._repository);

  @override
  Future<Either<Failure, List<DepartmentModel>>> call(NoParams params) async =>
      await _repository.getDepartments();
}
