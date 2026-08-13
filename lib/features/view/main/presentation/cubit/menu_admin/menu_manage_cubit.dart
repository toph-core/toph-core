import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/local_write_result.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_admin_local_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the meal editor's data.
///
/// The picker lists are subscriptions; loading a meal into the form is a
/// synchronous read, because a form is filled once rather than watched. That
/// asymmetry is deliberate: re-emitting a meal under an operator mid-edit would
/// overwrite what they were typing.
class MenuManageState {
  final List<CategoryModel> categories;
  final List<Map<String, dynamic>> ingredients;
  final List<Map<String, dynamic>> compounds;
  final String? error;
  final String? notice;

  const MenuManageState({
    this.categories = const [],
    this.ingredients = const [],
    this.compounds = const [],
    this.error,
    this.notice,
  });

  MenuManageState copyWith({
    List<CategoryModel>? categories,
    List<Map<String, dynamic>>? ingredients,
    List<Map<String, dynamic>>? compounds,
    Object? error = _sentinel,
    Object? notice = _sentinel,
  }) =>
      MenuManageState(
        categories: categories ?? this.categories,
        ingredients: ingredients ?? this.ingredients,
        compounds: compounds ?? this.compounds,
        error: identical(error, _sentinel) ? this.error : error as String?,
        notice: identical(notice, _sentinel) ? this.notice : notice as String?,
      );

  static const _sentinel = Object();
}

class MenuManageCubit extends Cubit<MenuManageState> {
  final MenuAdminLocalRepository _repository;
  final List<StreamSubscription<dynamic>> _subs = [];

  MenuManageCubit(this._repository) : super(const MenuManageState()) {
    _subs.addAll([
      _repository.watchCategories().listen((v) {
        if (!isClosed) emit(state.copyWith(categories: v));
      }),
      _repository.watchIngredients().listen((v) {
        if (!isClosed) emit(state.copyWith(ingredients: v));
      }),
      _repository.watchCompounds().listen((v) {
        if (!isClosed) emit(state.copyWith(compounds: v));
      }),
    ]);
  }

  /// The meal and its calculation rows, or null if it is not in the replica.
  ///
  /// Replaces three parallel network calls with two fallback paths between
  /// them. The endpoints returned different shapes and any could fail, so the
  /// screen had to decide at runtime which response it had actually got; there
  /// is one shape here and one way to read it.
  Map<String, dynamic>? mealForEdit(String id) =>
      _repository.goodWithCalculations(id);

  List<Map<String, dynamic>> translations() => _repository.translations();

  bool saveGood({
    String? mealId,
    required Map<String, dynamic> body,
    Map<String, String> headers = const {},
  }) =>
      _apply(() => _repository.saveGood(
            mealId: mealId,
            body: body,
            headers: headers,
          ));

  bool deleteGood(String id) => _apply(() => _repository.deleteGood(id));

  bool createTranslation(Map<String, dynamic> body) =>
      _apply(() => _repository.createTranslation(body));

  bool updateTranslation(String id, Map<String, dynamic> body) =>
      _apply(() => _repository.updateTranslation(id, body));

  bool _apply(Either<Failure, LocalWriteResult> Function() write) {
    return write().fold(
      (failure) {
        emit(state.copyWith(error: failure.toString(), notice: null));
        return false;
      },
      (outcome) {
        emit(state.copyWith(
          error: null,
          notice: outcome == LocalWriteResult.queued
              ? 'Navbatga qo\'yildi — sinxronlashtirilgach ro\'yxatda ko\'rinadi.'
              : null,
        ));
        return true;
      },
    );
  }

  void acknowledge() {
    if (state.notice != null || state.error != null) {
      emit(state.copyWith(notice: null, error: null));
    }
  }

  @override
  Future<void> close() {
    for (final s in _subs) {
      s.cancel();
    }
    return super.close();
  }
}
