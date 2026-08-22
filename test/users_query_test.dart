/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 4 — the staff list as a local query,
/// and the first production write to travel through the Phase 2 outbox.
///
/// Two things are under test here, and they are deliberately in one file
/// because the plan puts them in one commit: the read (a page that composes
/// search, role and paging, which the split REST endpoints could not) and the
/// write (a local row plus a queued operation, committed together).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/db/apply_change.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/db/users_query.dart';
import 'package:mary_ai_pos/core/outbox/local_writer.dart';
import 'package:mary_ai_pos/core/outbox/outbox_store.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/users_local_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/users_local_repository.dart';

void main() {
  late LocalDatabase db;
  late UsersQuery query;
  late OutboxStore outbox;
  late UsersLocalRepository repo;

  void put(Map<String, dynamic> data) => db.upsert(
        kEntitiesByName['users']!,
        data['id'] as String,
        PayloadNormalizer.normalize(kEntitiesByName['users']!, data),
      );

  Map<String, dynamic> user({
    required String id,
    String? fullName,
    String? username,
    String role = 'waiter',
    bool isActive = true,
    int? deletedAt,
  }) =>
      {
        'id': id,
        'full_name': fullName,
        'username': username ?? id,
        'role': role,
        'branch_id': 'b-1',
        'is_active': isActive,
        'phone_number': '+998901234567',
        'deleted_at': deletedAt,
      };

  setUp(() {
    db = LocalDatabase.open(':memory:');
    query = UsersQuery(db);
    outbox = OutboxStore(db);
    repo = UsersLocalRepositoryImpl(
      db,
      LocalWriter(db: db, applier: ChangeApplier(db), outbox: outbox),
    );
  });

  tearDown(() => db.dispose());

  group('UsersQuery — filtering', () {
    test('excludes soft-deleted rows', () {
      put(user(id: 'u-1', fullName: 'Aziz'));
      put(user(id: 'u-2', fullName: 'Bobur', deletedAt: 1735689600));

      final page = query.page(limit: 20, offset: 0);
      expect(page.total, 1);
      expect(page.items.single['id'], 'u-1');
    });

    test('filters by role', () {
      put(user(id: 'u-1', fullName: 'Aziz', role: 'waiter'));
      put(user(id: 'u-2', fullName: 'Bobur', role: 'cashier'));

      final page = query.page(limit: 20, offset: 0, role: 'cashier');
      expect(page.total, 1);
      expect(page.items.single['id'], 'u-2');
    });

    test('searches full_name and username, case-insensitively', () {
      put(user(id: 'u-1', fullName: 'Aziz Karimov', username: 'aziz'));
      put(user(id: 'u-2', fullName: 'Bobur Aliyev', username: 'bobur'));

      expect(query.page(limit: 20, offset: 0, search: 'kaRIm').total, 1);
      expect(query.page(limit: 20, offset: 0, search: 'BOBUR').total, 1);
      expect(query.page(limit: 20, offset: 0, search: 'zzz').total, 0);
    });

    test('search folds case outside ASCII, which SQL LIKE would not', () {
      // The reason the search filter is Dart-side rather than a `LIKE`. SQLite
      // folds ASCII only, so this row would be missed by the obvious SQL.
      put(user(id: 'u-1', fullName: 'Шерзод', username: 'sherzod'));

      expect(query.page(limit: 20, offset: 0, search: 'шерзод').total, 1);
    });

    test('search and role compose — the old split endpoints could not', () {
      // `GET /users/search` ignored `role`, so the screen filtered one fetched
      // page client-side and silently dropped matches outside it. One query,
      // both filters, no lost rows.
      put(user(id: 'u-1', fullName: 'Aziz Karimov', role: 'waiter'));
      put(user(id: 'u-2', fullName: 'Aziz Tursunov', role: 'cashier'));

      final page = query.page(
        limit: 20,
        offset: 0,
        search: 'aziz',
        role: 'cashier',
      );
      expect(page.total, 1);
      expect(page.items.single['id'], 'u-2');
    });
  });

  group('UsersQuery — paging', () {
    setUp(() {
      for (var i = 0; i < 5; i++) {
        put(user(id: 'u-$i', fullName: 'User $i'));
      }
    });

    test('total counts all matches, not the page', () {
      final page = query.page(limit: 2, offset: 0);
      expect(page.items, hasLength(2));
      expect(page.total, 5);
    });

    test('pages do not overlap or repeat under a stable sort', () {
      final first = query.page(limit: 2, offset: 0).items;
      final second = query.page(limit: 2, offset: 2).items;
      final third = query.page(limit: 2, offset: 4).items;

      final ids = [...first, ...second, ...third].map((r) => r['id']).toList();
      expect(ids.toSet(), hasLength(5));
      expect(third, hasLength(1));
    });

    test('an offset past the end is an empty page, not a crash', () {
      final page = query.page(limit: 2, offset: 99);
      expect(page.items, isEmpty);
      expect(page.total, 5);
    });
  });

  group('UsersQuery — all (the waiter picker read)', () {
    test('returns every non-deleted user, soft-deleted ones excluded', () {
      put(user(id: 'u-1', fullName: 'Aziz', role: 'waiter'));
      put(user(id: 'u-2', fullName: 'Bobur', role: 'cashier'));
      put(user(
        id: 'u-3',
        fullName: 'Davron',
        role: 'waiter',
        deletedAt: 1735689600,
      ));

      expect(query.all().map((r) => r['id']), ['u-1', 'u-2']);
    });

    test('rows parse via UserModel.fromJson — the shape getStaffWaiters needs',
        () {
      // getStaffWaiters maps these rows through UserModel.fromJson and keeps
      // role == UserRole.waiter. The replica stores `role` as the enum's own
      // name, so this parse must land. If the backend ever changed that column
      // to an int or a different casing, this is the test that catches it —
      // before a waiter picker silently goes empty on a device.
      put(user(id: 'u-1', fullName: 'Aziz', role: 'waiter'));
      put(user(id: 'u-2', fullName: 'Bobur', role: 'cashier'));

      final waiters = query
          .all()
          .map(UserModel.fromJson)
          .where((u) => u.role == UserRole.waiter)
          .toList();

      expect(waiters, hasLength(1));
      expect(waiters.single.id, 'u-1');
      expect(waiters.single.fullName, 'Aziz');
      expect(waiters.single.role, UserRole.waiter);
    });
  });

  group('UsersLocalRepository — writes', () {
    test('update writes the row and queues the send in one commit', () {
      put(user(id: 'u-1', fullName: 'Aziz', isActive: true));

      final result = repo.updateUser('u-1', {'is_active': false});

      expect(result.isRight(), isTrue);
      // Visible locally, immediately — no refetch, no round trip.
      expect(db.byId('users', 'u-1')!['is_active'], false);
      expect(outbox.depth, 1);
      final op = outbox.pending().single;
      expect(op.entity, 'users');
      expect(op.action, 'update');
      expect(op.entityId, 'u-1');
      // The request carries only what the form changed, not the merged row.
      expect(op.payload, {'is_active': false});
    });

    test('update merges over the stored row rather than replacing it', () {
      put(user(id: 'u-1', fullName: 'Aziz Karimov', username: 'aziz'));

      repo.updateUser('u-1', {'is_active': false});

      final row = db.byId('users', 'u-1')!;
      expect(row['full_name'], 'Aziz Karimov');
      expect(row['username'], 'aziz');
      expect(row['is_active'], false);
    });

    test('a credential in the update is sent but never stored', () {
      put(user(id: 'u-1', fullName: 'Aziz'));

      repo.updateUser('u-1', {'full_name': 'Aziz K', 'pincode': '4321'});

      // `redactKeys` keeps it off disk...
      expect(db.byId('users', 'u-1')!.containsKey('pincode'), isFalse);
      // ...while the request the server needs keeps it.
      expect(outbox.pending().single.payload['pincode'], '4321');
    });

    test('delete removes the row, guards it, and queues the send', () {
      put(user(id: 'u-1', fullName: 'Aziz'));

      expect(repo.deleteUser('u-1').isRight(), isTrue);
      expect(db.byId('users', 'u-1'), isNull);
      // The guard stops an in-flight pull from resurrecting it.
      expect(db.isPending('users', 'u-1'), isTrue);
      expect(outbox.pending().single.action, 'delete');
    });

    test('a created user appears at once, with credentials left off disk', () {
      // Was queued with no local row. Now the row lands under a provisional id
      // — which made `password` a new problem: the create body is both the
      // request and the row, and a plaintext credential must not end up in a
      // table every staff screen can query. The registry redacts it.
      final result = repo.createUser({
        'full_name': 'Yangi Xodim',
        'username': 'yangi',
        'role': 'waiter',
        'branch_id': 'b-1',
        'password': 'hunter2',
        'pincode': '1234',
      });

      expect(result.isRight(), isTrue);

      final op = outbox.pending().single;
      final row = db.byId('users', op.entityId!)!;
      expect(row['full_name'], 'Yangi Xodim');
      expect(row.containsKey('password'), isFalse);
      expect(row.containsKey('pincode'), isFalse);
      // The credential still has to reach the server, so it is in the queued
      // payload — a narrower exposure than a column, but not nothing.
      expect(op.payload['password'], 'hunter2');
    });
  });

  group('UsersLocalRepository — reactivity', () {
    test('the stream re-emits when this terminal writes', () async {
      put(user(id: 'u-1', fullName: 'Aziz', isActive: true));

      final pages = <UsersPage>[];
      final sub =
          repo.watchUsers(limit: 20, offset: 0).listen(pages.add);
      await Future<void>.delayed(Duration.zero);

      // The first emit is synchronous state — this is why the screen has no
      // loading flag to render.
      expect(pages, hasLength(1));
      expect(pages.first.items.single['is_active'], true);

      repo.updateUser('u-1', {'is_active': false});
      await Future<void>.delayed(Duration.zero);

      expect(pages, hasLength(2));
      expect(pages.last.items.single['is_active'], false);

      await sub.cancel();
    });
  });
}
