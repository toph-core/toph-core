import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/local_write_result.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_admin_local_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the menu list screen's data.
///
/// No `loading` flag and no `error`: the page and its total come from one
/// synchronous query against the replica, so the first emission is the answer
/// and there is no failure mode between asking and having it.
class MenuGoodsState {
  final List<CategoryModel> categories;
  final List<GoodsModel> goods;
  final int total;
  final int page;
  final String? categoryId;
  final String search;
  final String? notice;

  const MenuGoodsState({
    this.categories = const [],
    this.goods = const [],
    this.total = 0,
    this.page = 1,
    this.categoryId,
    this.search = '',
    this.notice,
  });

  MenuGoodsState copyWith({
    List<CategoryModel>? categories,
    List<GoodsModel>? goods,
    int? total,
    int? page,
    Object? categoryId = _sentinel,
    String? search,
    Object? notice = _sentinel,
  }) =>
      MenuGoodsState(
        categories: categories ?? this.categories,
        goods: goods ?? this.goods,
        total: total ?? this.total,
        page: page ?? this.page,
        categoryId: identical(categoryId, _sentinel)
            ? this.categoryId
            : categoryId as String?,
        search: search ?? this.search,
        notice: identical(notice, _sentinel) ? this.notice : notice as String?,
      );

  static const _sentinel = Object();
}

class MenuGoodsCubit extends Cubit<MenuGoodsState> {
  final MenuAdminLocalRepository _repository;
  StreamSubscription<GoodsPage>? _sub;
  StreamSubscription<List<CategoryModel>>? _categoriesSub;

  int _pageSize;
  int get pageSize => _pageSize;

  MenuGoodsCubit(this._repository, {int pageSize = 20})
      : _pageSize = pageSize,
        super(const MenuGoodsState()) {
    _categoriesSub = _repository.watchCategories().listen((categories) {
      if (!isClosed) emit(state.copyWith(categories: categories));
    });
    _subscribe();
  }

  void setPageSize(int size) {
    if (size == _pageSize || size <= 0) return;
    _pageSize = size;
    emit(state.copyWith(page: 1));
    _subscribe();
  }

  /// Re-points the subscription at the current filters.
  ///
  /// Filtering and paging happen in SQL rather than over a fetched list, which
  /// is what fixes the old screen's silent truncation: it asked for one page
  /// and filtered *that* client-side, so matches beyond the page simply did not
  /// exist as far as the operator could tell.
  void _subscribe() {
    _sub?.cancel();
    _sub = _repository
        .watchGoods(
          limit: _pageSize,
          offset: (state.page - 1) * _pageSize,
          categoryId: state.categoryId,
          search: state.search,
        )
        .listen((page) {
      if (isClosed) return;
      emit(state.copyWith(goods: page.items, total: page.total));
    });
  }

  void setPage(int page) {
    if (page == state.page || page < 1) return;
    emit(state.copyWith(page: page));
    _subscribe();
  }

  void setCategory(String? categoryId) {
    if (categoryId == state.categoryId) return;
    // Back to page 1: staying on page 4 of a filter that now matches six items
    // shows an empty screen with no explanation.
    emit(state.copyWith(categoryId: categoryId, page: 1));
    _subscribe();
  }

  void setSearch(String search) {
    if (search == state.search) return;
    emit(state.copyWith(search: search, page: 1));
    _subscribe();
  }

  int get pageCount => total == 0 ? 1 : ((total - 1) ~/ _pageSize) + 1;
  int get total => state.total;

  bool createCategory(String name) =>
      _repository.createCategory(name).fold((_) => false, (outcome) {
        emit(state.copyWith(
          notice: outcome == LocalWriteResult.queued
              ? 'Navbatga qo\'yildi — sinxronlashtirilgach ro\'yxatda ko\'rinadi.'
              : null,
        ));
        return true;
      });

  void acknowledge() {
    if (state.notice != null) emit(state.copyWith(notice: null));
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _categoriesSub?.cancel();
    return super.close();
  }
}
