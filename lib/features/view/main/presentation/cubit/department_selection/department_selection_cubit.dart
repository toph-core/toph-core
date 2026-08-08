import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/department/department_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

/// Offline-first: departments/categories come from `MenuRepository`, the
/// reactive `LocalDatabase`-backed surface `SyncEngine` keeps hydrated
/// (§8 Phase 1) and `DetailBloc`/`menu_meals_list_screen.dart` already read
/// from — a synchronous local read plus a live subscription, never a network
/// await, so opening this screen never blocks on a round-trip. Only goods
/// search (`searchGoodsByName`) still goes through the older, live-only
/// `MenuLocalRepository` — there's no bounded local mirror of the full
/// catalog to search against instead (see that repository's doc comment).
class DepartmentSelectionCubit extends Cubit<DepartmentSelectionState> {
  DepartmentSelectionCubit(this._menuRepository, this._searchRepository)
    : super(const DepartmentSelectionState());

  final MenuRepository _menuRepository;
  final MenuLocalRepository _searchRepository;

  StreamSubscription<List<DepartmentModel>>? _departmentsSub;
  StreamSubscription<List<CategoryModel>>? _categoriesSub;

  Timer? _searchDebounce;
  static const _searchDebounceDuration = Duration(milliseconds: 500);

  static const String allDepartmentId = 'all';

  void load() {
    _departmentsSub?.cancel();
    _categoriesSub?.cancel();
    _departmentsSub = _menuRepository.watchDepartments().listen(_onDepartments);
    _categoriesSub = _menuRepository.watchCategories().listen(_onCategories);
  }

  void _onDepartments(List<DepartmentModel> departments) {
    if (isClosed) return;
    final deptTabs = [
      DepartmentModel(id: allDepartmentId, name: S.current.all),
      ...departments,
    ];
    emit(
      state.copyWith(
        status: Status.SUCCESS,
        departments: deptTabs,
        selectedDepartmentId: state.selectedDepartmentId ?? allDepartmentId,
        clearFailure: true,
      ),
    );
  }

  void _onCategories(List<CategoryModel> categories) {
    if (isClosed) return;
    emit(state.copyWith(status: Status.SUCCESS, categories: categories, clearFailure: true));
  }

  void selectDepartment(String departmentId) {
    if (departmentId == state.selectedDepartmentId) return;
    emit(state.copyWith(selectedDepartmentId: departmentId));
  }

  /// Categories are filtered locally (name contains) via [filteredCategories].
  /// Matching menu items are fetched from the API (debounced), same endpoint
  /// used by the Menus page's search.
  void search(String query) {
    final q = query.trim();
    if (q == state.searchQuery) return;
    _searchDebounce?.cancel();
    if (q.isEmpty) {
      emit(state.copyWith(searchQuery: '', matchedGoods: const []));
      return;
    }
    emit(state.copyWith(searchQuery: q));
    _searchDebounce = Timer(_searchDebounceDuration, () => _searchGoods(q));
  }

  Future<void> _searchGoods(String query) async {
    final result = await _searchRepository.searchGoodsByName(query);
    if (isClosed || state.searchQuery != query) return;
    result.fold(
      (failure) => emit(state.copyWith(matchedGoods: const [])),
      (goods) => emit(state.copyWith(matchedGoods: goods)),
    );
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    _departmentsSub?.cancel();
    _categoriesSub?.cancel();
    return super.close();
  }
}

class DepartmentSelectionState extends Equatable {
  final Status status;
  final Failure? failure;
  final List<DepartmentModel> departments;
  final List<CategoryModel> categories;
  final String? selectedDepartmentId;
  final String searchQuery;
  final List<GoodsModel> matchedGoods;

  const DepartmentSelectionState({
    this.status = Status.UNKNOWN,
    this.failure,
    this.departments = const [],
    this.categories = const [],
    this.selectedDepartmentId,
    this.searchQuery = '',
    this.matchedGoods = const [],
  });

  /// Categories visible for the currently selected department, further
  /// narrowed by [searchQuery] (name contains, case-insensitive) when set.
  /// When "all" is selected, every category in the department is shown.
  List<CategoryModel> get filteredCategories {
    final selected = selectedDepartmentId;
    Iterable<CategoryModel> base =
        (selected == null || selected == DepartmentSelectionCubit.allDepartmentId)
            ? categories
            : categories.where((c) => c.departmentId == selected);
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      base = base.where((c) => c.name.toLowerCase().contains(q));
    }
    return base.toList(growable: false);
  }

  DepartmentSelectionState copyWith({
    Status? status,
    Failure? failure,
    List<DepartmentModel>? departments,
    List<CategoryModel>? categories,
    String? selectedDepartmentId,
    String? searchQuery,
    List<GoodsModel>? matchedGoods,
    bool clearFailure = false,
  }) {
    return DepartmentSelectionState(
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
      departments: departments ?? this.departments,
      categories: categories ?? this.categories,
      selectedDepartmentId:
          selectedDepartmentId ?? this.selectedDepartmentId,
      searchQuery: searchQuery ?? this.searchQuery,
      matchedGoods: matchedGoods ?? this.matchedGoods,
    );
  }

  @override
  List<Object?> get props => [
        status,
        failure,
        departments,
        categories,
        selectedDepartmentId,
        searchQuery,
        matchedGoods,
      ];
}
