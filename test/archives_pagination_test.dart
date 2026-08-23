/// The Orders screen must be able to reach every bill the replica holds.
///
/// The bug these pin, reported from a live venue: a paid check was visible in
/// the Orders list, then was not, while the same check was still on the web.
/// It had not been deleted from anywhere. The list asked for 20 rows and had
/// no way to ask for more — no scroll handler, no button, and the arithmetic
/// that would have built the next request computed a *page index* where a
/// *row offset* was needed (`PaginationRequestModel.calculate`). So the 21st
/// bill of a shift was unreachable in every filter, and searching for it by
/// number was broken by the same arithmetic: with a full page on screen the
/// single match was skipped and the screen said there was nothing.
///
/// Everything here runs against a real in-memory replica through the real
/// repository. There is no HTTP in this file because there is none in the
/// path: the screen reads the database and nothing else.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/archives_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/archives_local_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late ArchivesLocalRepositoryImpl repo;

  String pgTs(DateTime t) =>
      '${t.toUtc().toIso8601String().split('.').first}+00:00';

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(
      spec,
      data['id'] as String,
      PayloadNormalizer.normalize(spec, data),
    );
  }

  /// [count] paid bills inside the "today" window, newest first, numbered
  /// from 100 and each settled at 400 000.
  void seedBills(int count, {int grandTotal = 400000}) {
    final now = DateTime.now().toUtc();
    for (var i = 0; i < count; i++) {
      final paidAt = now.subtract(Duration(minutes: i + 1));
      put('orders', {
        'id': 'o$i',
        'table_id': 'tb1',
        'branch_id': 'b1',
        'bill_no': 100 + i,
        'bill_status': 'paid',
        'status': 'paid',
        'order_type': 'dine_in',
        'created_at': pgTs(paidAt.subtract(const Duration(hours: 1))),
        'paid_at': pgTs(paidAt),
        'grand_total': grandTotal,
        'deleted_at': 0,
      });
    }
  }

  ArchivesBloc openScreen() =>
      ArchivesBloc(archivesRepository: repo)
        ..add(const ArchivesEvent.started());

  /// The next state satisfying [predicate]. Every path under test is local, so
  /// a state that never arrives is a failure and not a slow network.
  Future<ArchivesState> settle(
    ArchivesBloc bloc,
    bool Function(ArchivesState) predicate,
  ) {
    if (predicate(bloc.state)) return Future.value(bloc.state);
    return bloc.stream
        .firstWhere(predicate)
        .timeout(const Duration(seconds: 5));
  }

  /// Presses "load more" until the list holds the whole window.
  Future<ArchivesState> loadAll(ArchivesBloc bloc) async {
    var state = bloc.state;
    var guard = 0;
    while (state.hasMore) {
      if (guard++ > 50) fail('load-more never converged');
      final before = state.loadedCount;
      bloc.add(const ArchivesEvent.loadMore());
      state = await settle(bloc, (s) => s.loadedCount > before || !s.hasMore);
    }
    return state;
  }

  setUp(() {
    db = LocalDatabase.open(':memory:');
    repo = ArchivesLocalRepositoryImpl(db);
    put('halls', {
      'id': 'h1',
      'name': 'Asosiy zal',
      'branch_id': 'b1',
      'deleted_at': 0,
    });
    put('cafe_tables', {
      'id': 'tb1',
      'hall_id': 'h1',
      'number': 5,
      'deleted_at': 0,
    });
  });

  tearDown(() => db.dispose());

  group('the window is a page size, not a ceiling', () {
    test('every bill of a busy shift can be reached', () async {
      seedBills(120);
      final bloc = openScreen();
      addTearDown(bloc.close);

      var state = await settle(bloc, (s) => s.loadedCount > 0);
      expect(state.totalCount, 120, reason: 'the window holds every bill');
      expect(state.loadedCount, kArchivesPageSize);
      expect(state.hasMore, isTrue);

      state = await loadAll(bloc);

      expect(state.loadedCount, 120);
      expect(state.hasMore, isFalse);
      // The bill this whole report started from: the oldest of the shift, the
      // one that used to be unreachable from the terminal entirely.
      expect(state.archives!.archives.map((a) => a.id), contains('o119'));
    });

    test('rows are not duplicated or skipped as the window grows', () async {
      seedBills(120);
      final bloc = openScreen();
      addTearDown(bloc.close);

      await settle(bloc, (s) => s.loadedCount > 0);
      final state = await loadAll(bloc);

      final ids = state.archives!.archives.map((a) => a.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicates');
      expect(ids, [
        for (var i = 0; i < 120; i++) 'o$i',
      ], reason: 'newest first, every bill, in order');
    });

    test(
      'a window that fits on one page reports nothing more to load',
      () async {
        seedBills(3);
        final bloc = openScreen();
        addTearDown(bloc.close);

        final state = await settle(bloc, (s) => s.loadedCount > 0);
        expect(state.loadedCount, 3);
        expect(state.totalCount, 3);
        expect(state.hasMore, isFalse);
      },
    );

    test('load-more is a no-op once everything is loaded', () async {
      seedBills(3);
      final bloc = openScreen();
      addTearDown(bloc.close);

      await settle(bloc, (s) => s.loadedCount == 3);
      bloc.add(const ArchivesEvent.loadMore());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.loadedLimit, kArchivesPageSize);
      expect(bloc.state.isLoadingMore, isFalse);
      expect(bloc.state.loadedCount, 3);
    });
  });

  group('search', () {
    test('finds a bill that is far past the first page', () async {
      seedBills(120);
      final bloc = openScreen();
      addTearDown(bloc.close);

      // A full page on screen is exactly the state that used to break this:
      // the search inherited the list's pagination and skipped its own match.
      await settle(bloc, (s) => s.loadedCount == kArchivesPageSize);

      bloc.add(const ArchivesEvent.searchByArchiveNum('215'));
      final state = await settle(bloc, (s) => s.loadedCount == 1);

      expect(state.archives!.archives.single.bilNumber, 215);
      expect(state.totalCount, 1);
    });

    test('finds by the first digits of a number', () async {
      seedBills(120);
      final bloc = openScreen();
      addTearDown(bloc.close);
      await settle(bloc, (s) => s.loadedCount > 0);

      bloc.add(const ArchivesEvent.searchByArchiveNum('21'));
      final state = await settle(bloc, (s) => s.loadedCount == 10);

      // 210..219 — ten bills, all of them, not one page of them.
      expect(state.archives!.archives.map((a) => a.bilNumber).toSet(), {
        for (var n = 210; n <= 219; n++) n,
      });
    });

    test('clearing the search restores the full window', () async {
      seedBills(120);
      final bloc = openScreen();
      addTearDown(bloc.close);
      await settle(bloc, (s) => s.loadedCount > 0);

      bloc.add(const ArchivesEvent.searchByArchiveNum('215'));
      await settle(bloc, (s) => s.loadedCount == 1);

      bloc.add(const ArchivesEvent.searchByArchiveNum(''));
      final state = await settle(bloc, (s) => s.totalCount == 120);
      expect(state.loadedCount, kArchivesPageSize);
      expect(state.hasMore, isTrue);
    });
  });

  group('the header describes the window, not the page', () {
    test('count and revenue cover every bill in the filter', () async {
      seedBills(120);
      final bloc = openScreen();
      addTearDown(bloc.close);

      final state = await settle(bloc, (s) => s.summary.count > 0);

      expect(state.loadedCount, kArchivesPageSize);
      expect(state.summary.count, 120);
      expect(state.summary.revenue, 120 * 400000);
      expect(state.summary.avgCheck, 400000);
    });

    test('scrolling does not change the totals', () async {
      seedBills(120);
      final bloc = openScreen();
      addTearDown(bloc.close);

      final first = await settle(bloc, (s) => s.summary.count > 0);
      final after = await loadAll(bloc);

      expect(after.summary.count, first.summary.count);
      expect(after.summary.revenue, first.summary.revenue);
    });
  });

  group('a bill that lands from the feed', () {
    test('appears in the list without any fetch', () async {
      seedBills(3);
      final bloc = openScreen();
      addTearDown(bloc.close);
      await settle(bloc, (s) => s.loadedCount == 3);

      // Replication delivering a newer bill — the same write path a pull uses.
      put('orders', {
        'id': 'fresh',
        'table_id': 'tb1',
        'branch_id': 'b1',
        'bill_no': 999,
        'bill_status': 'paid',
        'status': 'paid',
        'created_at': pgTs(DateTime.now().toUtc()),
        'paid_at': pgTs(DateTime.now().toUtc()),
        'grand_total': 50000,
        'deleted_at': 0,
      });

      // The list and the header are two subscriptions over the same write, so
      // wait for both rather than assuming an ordering between them.
      final state = await settle(
        bloc,
        (s) => s.loadedCount == 4 && s.summary.count == 4,
      );
      expect(state.archives!.archives.first.id, 'fresh');
      expect(state.summary.revenue, 3 * 400000 + 50000);
    });
  });

  group('a picked date range', () {
    test('includes bills on the last day, and a future end date', () async {
      seedBills(3);
      final bloc = openScreen();
      addTearDown(bloc.close);
      await settle(bloc, (s) => s.loadedCount == 3);

      final today = DateTime.now();
      bloc.add(
        ArchivesEvent.updateFilterDateRange(
          // Both midnight, exactly as showDateRangePicker returns them. The
          // end used to be spent as-is, so today's bills fell outside it.
          startDate: DateTime(today.year, today.month, today.day - 1),
          endDate: DateTime(today.year, today.month, today.day),
        ),
      );

      final state = await settle(
        bloc,
        (s) => s.filterType == ArchivesFilterType.date && s.totalCount == 3,
      );
      expect(state.loadedCount, 3);
    });

    test('a future end date is accepted and still shows today', () async {
      seedBills(3);
      final bloc = openScreen();
      addTearDown(bloc.close);
      await settle(bloc, (s) => s.loadedCount == 3);

      final today = DateTime.now();
      bloc.add(
        ArchivesEvent.updateFilterDateRange(
          startDate: DateTime(today.year, today.month, today.day),
          endDate: DateTime(today.year, today.month, today.day + 7),
        ),
      );

      final state = await settle(
        bloc,
        (s) => s.filterType == ArchivesFilterType.date && s.totalCount == 3,
      );
      expect(state.loadedCount, 3);
    });
  });

  group('PaginationRequestModel.calculate', () {
    test('continues from the row after the ones already held', () {
      expect(PaginationRequestModel.calculate(items: 20, limit: 20).offset, 20);
      expect(PaginationRequestModel.calculate(items: 50, limit: 50).offset, 50);
      expect(PaginationRequestModel.calculate(items: 0, limit: 20).offset, 0);
    });

    test('a page index is not a row offset', () {
      // The old implementation returned `items ~/ limit`, so a full page asked
      // for offset 1 and quietly dropped the newest row from the next read.
      expect(
        PaginationRequestModel.calculate(items: 20, limit: 20).offset,
        isNot(1),
      );
    });
  });
}
