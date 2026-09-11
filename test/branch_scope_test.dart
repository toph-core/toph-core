/// What a terminal shows belongs to its branch — and only where the backend
/// says so.
///
/// The replica holds the whole brand: `change_log` carries `brand_id` and no
/// branch column, and `SyncS.Pull` filters by cursor alone, so a two-branch
/// brand replicates both branches onto every till. The filter can only happen
/// on the read, and it has to mirror the backend table by table — filtering
/// something the backend serves brand-wide hides rows that are genuinely
/// shared, which is the same bug in the other direction.
///
/// The map these pin comes from reading the backend's own list queries:
///   scoped   — goods, compounds, users, transactions, group_transactions,
///              cash_registers, orders
///   brand-wide — ingredient_groups, modifiers, translations, branches
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/branch_scope.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/menu_query.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/db/transaction_pickers_query.dart';
import 'package:mary_ai_pos/core/db/transactions_query.dart';
import 'package:mary_ai_pos/core/db/users_query.dart';

const _mine = 'branch-mine';
const _other = 'branch-other';

/// A `goods` row complete enough for `GoodsModel.fromJson` — the query decodes
/// through the model and skips rows it cannot parse, so a thin fixture would
/// look exactly like a branch filter that removed everything.
Map<String, dynamic> _good(String id, String branch, {String name = 'Osh'}) => {
  'id': id,
  'name': name,
  'branch_id': branch,
  'category_id': 'cat-1',
  'cook_time': 0,
  'cost_price': '10000',
  'department_id': '',
  'description': '',
  'price': '20000',
  'profit': '0',
  'profit_margin': '0',
  'deleted_at': 0,
};

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase.open(':memory:'));
  tearDown(() => db.dispose());

  void put(String entity, Map<String, dynamic> row) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, row['id'] as String, PayloadNormalizer.normalize(spec, row));
  }

  group('entities the backend scopes by branch', () {
    test('the menu shows this branch, not the brand', () {
      put('goods', _good('g-1', _mine, name: 'Osh'));
      put('goods', _good('g-2', _other, name: 'Somsa'));

      final scoped = MenuQuery(db, branchId: () => _mine);
      expect(scoped.goods().map((g) => g.id), ['g-1']);
    });

    test('the staff list shows this branch', () {
      put('users', {
        'id': 'u-1',
        'full_name': 'Aziz',
        'branch_id': _mine,
        'role': 'cashier',
        'deleted_at': 0,
      });
      put('users', {
        'id': 'u-2',
        'full_name': 'Bek',
        'branch_id': _other,
        'role': 'cashier',
        'deleted_at': 0,
      });

      final page = UsersQuery(db, branchId: () => _mine).page(
        limit: 50,
        offset: 0,
      );
      expect(page.items.map((u) => u['id']), ['u-1']);
    });

    test('the ledger shows this branch', () {
      put('transactions', {
        'id': 't-1',
        'branch_id': _mine,
        'type': 'income',
        'date': '2026-09-10',
        'amount': '1000',
        'deleted_at': 0,
      });
      put('transactions', {
        'id': 't-2',
        'branch_id': _other,
        'type': 'income',
        'date': '2026-09-10',
        'amount': '2000',
        'deleted_at': 0,
      });

      final rows = TransactionsQuery(
        db,
        branchId: () => _mine,
      ).transactions(limit: 50, offset: 0);
      expect(rows.map((r) => r['id']), ['t-1']);
    });

    test('a null-branch ledger row stays hidden, not "unassigned"', () {
      // The backend uses `IS NOT DISTINCT FROM`, so a row with no branch is
      // visible only to a session with no branch. A terminal always has one.
      put('transactions', {
        'id': 't-mine',
        'branch_id': _mine,
        'type': 'income',
        'date': '2026-09-10',
        'amount': '1000',
        'deleted_at': 0,
      });
      put('transactions', {
        'id': 't-null',
        'branch_id': null,
        'type': 'income',
        'date': '2026-09-10',
        'amount': '5000',
        'deleted_at': 0,
      });

      final rows = TransactionsQuery(
        db,
        branchId: () => _mine,
      ).transactions(limit: 50, offset: 0);
      expect(rows.map((r) => r['id']), ['t-mine']);
    });

    test('the pickers read a branch that is not a promoted column', () {
      // group_transactions and cash_registers carry branch_id only inside the
      // stored row, so the filter reads it out of the JSON.
      put('group_transactions', {
        'id': 'gt-1',
        'name': 'Kassa',
        'branch_id': _mine,
        'deleted_at': 0,
      });
      put('group_transactions', {
        'id': 'gt-2',
        'name': 'Boshqa',
        'branch_id': _other,
        'deleted_at': 0,
      });
      put('cash_registers', {
        'id': 'cr-1',
        'name': 'Kassa 1',
        'branch_id': _mine,
        'deleted_at': 0,
      });
      put('cash_registers', {
        'id': 'cr-2',
        'name': 'Kassa 2',
        'branch_id': _other,
        'deleted_at': 0,
      });

      final pickers = TransactionPickersQuery(db, branchId: () => _mine);
      expect(pickers.transactionGroups().map((g) => g['id']), ['gt-1']);
      expect(pickers.cashRegisters().map((r) => r['id']), ['cr-1']);
    });
  });

  group('entities the backend serves brand-wide', () {
    test('ingredient groups are not filtered', () {
      // GetAllIngredientGroups has no branch predicate at all, and the
      // metadata endpoint names the table as deliberately shared.
      put('ingredient_groups', {'id': 'ig-1', 'name': 'Go\'sht', 'deleted_at': 0});
      put('ingredient_groups', {'id': 'ig-2', 'name': 'Sabzavot', 'deleted_at': 0});

      final rows = MenuQuery(db, branchId: () => _mine);
      expect(rows.ingredients(), isEmpty, reason: 'different table');
      expect(db.allOf('ingredient_groups').length, 2);
    });

    test('translations are not filtered — the table has no branch at all', () {
      put('translations', {'id': 'tr-1', 'deleted_at': 0});
      expect(db.allOf('translations').length, 1);
    });
  });

  group('the safety valve', () {
    test('no session yet shows everything rather than nothing', () {
      put('goods', _good('g-1', _mine, name: 'Osh'));
      put('goods', _good('g-2', _other, name: 'Somsa'));

      expect(MenuQuery(db, branchId: () => '').goods().length, 2);
      expect(MenuQuery(db).goods().length, 2);
    });

    test('a branch owning no row in a table falls back to everything', () {
      // A misconfigured brand — rows created against another branch id, or
      // predating branches. An empty menu stops a venue trading; a superset
      // does not.
      put('goods', _good('g-1', _other, name: 'Osh'));

      expect(MenuQuery(db, branchId: () => _mine).goods().length, 1);
    });

    test('the valve is per table, not global', () {
      // Goods are configured for this branch; the ledger is not. The menu must
      // filter and the ledger must fall back, independently.
      put('goods', _good('g-1', _mine, name: 'Osh'));
      put('goods', _good('g-2', _other, name: 'Somsa'));
      put('transactions', {
        'id': 't-other',
        'branch_id': _other,
        'type': 'income',
        'date': '2026-09-10',
        'amount': '1',
        'deleted_at': 0,
      });

      final scope = BranchScope(db, branchId: () => _mine);
      expect(scope.of('goods'), _mine, reason: 'this branch owns goods');
      expect(scope.of('transactions'), '', reason: 'it owns no ledger row');
    });
  });
}
