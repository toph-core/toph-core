import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/local_write_result.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/users_local_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the screen stopped resolving
/// repositories itself; this owns that dependency.
///
/// Note what the state does **not** carry: a `loading` flag. The read is a
/// synchronous query against the replica, so the first emit already has rows.
/// There is no interval between "asked" and "answered" for a spinner to fill,
/// on this screen or any other Phase 4 moves across.
class UsersState {
  final List<Map<String, dynamic>> items;
  final int total;
  final int page;
  final int pageSize;
  final String search;
  final String? role;

  /// A local write that failed — a disk fault, a malformed row. Never a
  /// connection error: nothing on this screen touches the network.
  final String? error;

  /// One-shot message for a write whose effect is not yet visible, i.e. a
  /// queued create. Cleared by [acknowledge] once shown.
  final String? notice;

  const UsersState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.search = '',
    this.role,
    this.error,
    this.notice,
  });

  bool get isSearching => search.trim().isNotEmpty;

  int get totalPages {
    if (total <= 0) return 1;
    final p = (total + pageSize - 1) ~/ pageSize;
    return p > 0 ? p : 1;
  }

  UsersState copyWith({
    List<Map<String, dynamic>>? items,
    int? total,
    int? page,
    int? pageSize,
    String? search,
    Object? role = _sentinel,
    Object? error = _sentinel,
    Object? notice = _sentinel,
  }) {
    return UsersState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: search ?? this.search,
      role: identical(role, _sentinel) ? this.role : role as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
      notice: identical(notice, _sentinel) ? this.notice : notice as String?,
    );
  }

  static const _sentinel = Object();
}

class UsersCubit extends Cubit<UsersState> {
  final UsersLocalRepository _repository;
  StreamSubscription<UsersPage>? _sub;

  UsersCubit(this._repository) : super(const UsersState()) {
    _subscribe();
  }

  /// Re-points the subscription at the current filters.
  ///
  /// Every filter change goes through here, and the stream re-emits on every
  /// change to `users` — so this terminal's own edit reaches the list by the
  /// same path replication's does. There is no "refetch after save" step,
  /// because there is nothing to refetch.
  void _subscribe() {
    _sub?.cancel();
    _sub = _repository
        .watchUsers(
      limit: state.pageSize,
      offset: (state.page - 1) * state.pageSize,
      search: state.search,
      role: state.role,
    )
        .listen(
      (page) {
        if (isClosed) return;
        // A delete can empty the last page. Step back rather than showing a
        // blank list under a paginator that still offers the page.
        final maxOffset = (state.page - 1) * state.pageSize;
        if (page.items.isEmpty && page.total > 0 && maxOffset >= page.total) {
          emit(state.copyWith(total: page.total));
          setPage(state.totalPages);
          return;
        }
        emit(state.copyWith(items: page.items, total: page.total));
      },
      onError: (Object e) {
        if (!isClosed) emit(state.copyWith(error: '$e'));
      },
    );
  }

  void setPage(int page) {
    if (page == state.page || page < 1) return;
    emit(state.copyWith(page: page));
    _subscribe();
  }

  void setPageSize(int size) {
    if (size == state.pageSize) return;
    emit(state.copyWith(pageSize: size, page: 1));
    _subscribe();
  }

  void setSearch(String query) {
    final next = query.trim();
    if (next == state.search) return;
    emit(state.copyWith(search: next, page: 1));
    _subscribe();
  }

  void setRole(String? role) {
    if (role == state.role) return;
    emit(state.copyWith(role: role, page: 1));
    _subscribe();
  }

  bool createUser(Map<String, dynamic> body) =>
      _apply(() => _repository.createUser(body));

  bool updateUser(String id, Map<String, dynamic> changes) =>
      _apply(() => _repository.updateUser(id, changes));

  bool deleteUser(String id) => _apply(() => _repository.deleteUser(id));

  /// Runs a write and reports whether it was accepted locally.
  ///
  /// Synchronous throughout — the repository's mutations return a value, not a
  /// future, so there is no await anywhere on this path and no window in which
  /// the UI could be waiting on anything.
  bool _apply(Either<Failure, LocalWriteResult> Function() write) {
    final result = write();
    return result.fold(
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
    _sub?.cancel();
    return super.close();
  }
}
