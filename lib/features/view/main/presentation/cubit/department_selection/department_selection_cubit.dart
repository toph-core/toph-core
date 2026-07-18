import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_categories_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/get_departments_usecase.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class DepartmentSelectionCubit extends Cubit<DepartmentSelectionState> {
  DepartmentSelectionCubit(
    this._getDepartmentsUsecase,
    this._getCategoriesUsecase,
  ) : super(const DepartmentSelectionState());

  final GetDepartmentsUsecase _getDepartmentsUsecase;
  final GetCategoriesUsecase _getCategoriesUsecase;

  static const String allDepartmentId = 'all';

  Future<void> load() async {
    emit(state.copyWith(status: Status.LOADING, clearFailure: true));

    final departmentsResult = await _getDepartmentsUsecase(NoParams());
    final categoriesResult = await _getCategoriesUsecase(NoParams());

    if (isClosed) return;

    Failure? failure;
    var departments = <DepartmentModel>[];
    var categories = <CategoryModel>[];

    departmentsResult.fold(
      (f) => failure = f,
      (list) => departments = list,
    );
    categoriesResult.fold(
      (f) => failure ??= f,
      (list) => categories = list,
    );

    if (failure != null && departments.isEmpty && categories.isEmpty) {
      emit(state.copyWith(status: Status.ERROR, failure: failure));
      return;
    }

    final deptTabs = [
      DepartmentModel(id: allDepartmentId, name: S.current.all),
      ...departments,
    ];

    emit(
      state.copyWith(
        status: Status.SUCCESS,
        departments: deptTabs,
        categories: categories,
        selectedDepartmentId: allDepartmentId,
        clearFailure: true,
      ),
    );
  }

  void selectDepartment(String departmentId) {
    if (departmentId == state.selectedDepartmentId) return;
    emit(state.copyWith(selectedDepartmentId: departmentId));
  }
}

class DepartmentSelectionState extends Equatable {
  final Status status;
  final Failure? failure;
  final List<DepartmentModel> departments;
  final List<CategoryModel> categories;
  final String? selectedDepartmentId;

  const DepartmentSelectionState({
    this.status = Status.UNKNOWN,
    this.failure,
    this.departments = const [],
    this.categories = const [],
    this.selectedDepartmentId,
  });

  /// Categories visible for the currently selected department.
  /// When "all" is selected, every category is shown.
  List<CategoryModel> get filteredCategories {
    final selected = selectedDepartmentId;
    if (selected == null || selected == DepartmentSelectionCubit.allDepartmentId) {
      return categories;
    }
    return categories
        .where((c) => c.departmentId == selected)
        .toList(growable: false);
  }

  DepartmentSelectionState copyWith({
    Status? status,
    Failure? failure,
    List<DepartmentModel>? departments,
    List<CategoryModel>? categories,
    String? selectedDepartmentId,
    bool clearFailure = false,
  }) {
    return DepartmentSelectionState(
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      departments: departments ?? this.departments,
      categories: categories ?? this.categories,
      selectedDepartmentId:
          selectedDepartmentId ?? this.selectedDepartmentId,
    );
  }

  @override
  List<Object?> get props => [
        status,
        failure,
        departments,
        categories,
        selectedDepartmentId,
      ];
}
