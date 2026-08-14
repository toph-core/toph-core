/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 0 — the replicated-entity registry.
///
/// Every entity here is one table in the backend's tenant database that carries
/// an `AFTER INSERT OR UPDATE OR DELETE` trigger writing into `change_log`
/// (`app/migrations/tenants/8_movements.up.sql`, `41_modifier_calculation.up.sql`).
/// `POST /api/v1/sync/pull` keys its `changes` map by exactly these names —
/// they are Postgres table names (`TG_TABLE_NAME`), not API resource names.
///
/// ## Why a registry instead of 35 hand-written table classes
///
/// The inbound data shape is uniform: `{entity, action, entity_id, payload}`
/// where `payload` is `to_jsonb(NEW)` — the complete row. A registry turns
/// [ChangeApplier] into a map lookup instead of a 35-branch switch, survives
/// backend column additions without a client migration (new columns land in
/// `data` automatically), and lets a new entity be replicated by adding one
/// line here.
///
/// ## The hybrid column model
///
/// Each local table stores the full server row verbatim in `data`, plus a small
/// set of **promoted** columns lifted out of that row into real, indexed SQLite
/// columns. Promoted columns are what we filter, sort and join on; everything
/// else stays queryable through `json_extract(data, '$.field')`. Promoting a
/// column later is additive — add it here and backfill from `data`, no schema
/// migration of stored content.
///
/// Promotion is deliberate, not exhaustive: the POS-hot entities (orders, order
/// items, goods, categories, tables, halls, users) are promoted richly; the
/// back-office long tail keeps only its primary key and relies on
/// `json_extract`, which is fast enough for screens opened occasionally.
library;

/// SQLite storage class for a promoted column.
enum SqlType { text, integer, real }

/// A column lifted out of the JSON payload into a real SQLite column.
///
/// [name] doubles as the payload key — the local column is always named after
/// the server column it mirrors, so there is no second mapping to keep in sync.
/// A key absent from a payload stores NULL rather than failing, so a promoted
/// column that a future backend version drops degrades quietly.
class PromotedColumn {
  final String name;
  final SqlType type;
  final bool indexed;

  const PromotedColumn(this.name, this.type, {this.indexed = false});

  String get sqlType => switch (type) {
        SqlType.text => 'TEXT',
        SqlType.integer => 'INTEGER',
        SqlType.real => 'REAL',
      };
}

/// One replicated entity: its change-log name, primary key, promoted columns,
/// and the two payload transforms that must happen before it is stored.
class EntitySpec {
  /// Change-log entity name == Postgres table name == local table name.
  final String name;

  /// Payload key holding the primary key. `log_change()` takes this as its
  /// trigger argument and reports it as `entity_id`; every entity uses `id`
  /// except `bill_daily_counters`, which is keyed by `day`.
  final String pk;

  final List<PromotedColumn> promoted;

  /// Keys that are `pgtype.Numeric` in the backend's sqlc models
  /// (`app/internal/repository/pg/tenantsdb/models.go`).
  ///
  /// These need coercing to strings: `to_jsonb` serialises a Postgres `numeric`
  /// as a JSON **number**, but the REST API marshals the same field as a JSON
  /// **string** ("15000.00"), and every Flutter model was written against the
  /// REST shape (`GoodsModel.price` is a `String`). Without this the existing
  /// `fromJson` constructors throw a type error on replicated rows. Derived
  /// mechanically from `models.go`, not by hand.
  final Set<String> numericKeys;

  /// Keys stripped before the row is written to disk.
  ///
  /// The change-log payload is the raw table row, so `users` rows carry
  /// `hash_password` and `pincode`. Replicating credential material to every
  /// terminal in the venue is not acceptable, and nothing in the POS reads
  /// these — offline PIN auth uses its own OS-backed secure store
  /// (`OfflineAuthCache`), never this table.
  final Set<String> redactKeys;

  const EntitySpec({
    required this.name,
    this.pk = 'id',
    this.promoted = const [],
    this.numericKeys = const {},
    this.redactKeys = const {},
  });
}

/// Local-only table names. Prefixed with `_` so they can never collide with a
/// replicated entity, since entity names come from the server.
class LocalTables {
  static const meta = '_sync_meta';
  static const outbox = '_outbox';
  static const pending = '_pending';

  /// Live table occupancy, and the one table here the server does not own.
  ///
  /// Everything else in this database is a replica: the server decides, the
  /// change log delivers, local rows follow. Table status is the exception —
  /// it is decided *here*, by a cashier opening an order or a peer terminal's
  /// LAN broadcast, and the server only learns of it indirectly, when the
  /// order that caused it syncs.
  ///
  /// So it cannot live in `cafe_tables`: a replication pass would overwrite
  /// the venue's live occupancy with whatever the server last logged, which
  /// offline is nothing at all. It is kept beside that table and overlaid on
  /// read, which also means a hall rename from the server still lands normally
  /// — the two kinds of truth stay separable instead of fighting over one row.
  static const tableStatus = '_table_status';

  /// Rows created locally under a client-invented id that the server has not
  /// yet replaced with its own.
  ///
  /// Only some creates need this. An order carries the id its terminal invents,
  /// because the backend accepts a client-supplied order id and returns the
  /// existing order when it already knows one. Every other create endpoint
  /// assigns the id itself, so the local row is a stand-in until the response
  /// arrives — and the two cases are indistinguishable from the operation
  /// alone, which is why it is recorded rather than inferred.
  static const provisional = '_provisional';

  static const all = {meta, outbox, pending, tableStatus, provisional};

  const LocalTables._();
}

/// Every entity replicated from the change-log feed.
///
/// Ordering is alphabetical to match the trigger list in the migrations, which
/// makes an audit against the backend a straight diff.
const List<EntitySpec> kReplicatedEntities = [
  EntitySpec(
    name: 'attendances',
    promoted: [
      PromotedColumn('user_id', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
      PromotedColumn('open_date', SqlType.text),
      PromotedColumn('close_date', SqlType.text),
    ],
  ),
  EntitySpec(
    name: 'bill_daily_counters',
    pk: 'day',
    promoted: [PromotedColumn('last_no', SqlType.integer)],
  ),
  EntitySpec(
    name: 'branches',
    promoted: [PromotedColumn('name', SqlType.text)],
    numericKeys: {'default_service_percent'},
  ),
  EntitySpec(
    name: 'cafe_tables',
    promoted: [
      PromotedColumn('hall_id', SqlType.text, indexed: true),
      PromotedColumn('number', SqlType.integer),
      PromotedColumn('status', SqlType.text, indexed: true),
      PromotedColumn('table_type', SqlType.text),
    ],
    numericKeys: {'price_per_hour'},
  ),
  EntitySpec(
    name: 'calculation',
    promoted: [
      PromotedColumn('good_id', SqlType.text, indexed: true),
      PromotedColumn('compound_id', SqlType.text, indexed: true),
      PromotedColumn('ingredient_id', SqlType.text, indexed: true),
    ],
    numericKeys: {'quantity', 'price_per_unit', 'total_cost'},
  ),
  EntitySpec(
    name: 'categories',
    promoted: [
      PromotedColumn('name', SqlType.text, indexed: true),
      PromotedColumn('department_id', SqlType.text, indexed: true),
      PromotedColumn('parent', SqlType.text),
    ],
  ),
  EntitySpec(
    name: 'compound_stock',
    promoted: [
      PromotedColumn('compound_id', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
    ],
  ),
  EntitySpec(
    name: 'compounds',
    promoted: [
      PromotedColumn('name', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
    ],
    numericKeys: {'quantity', 'price', 'cost_price', 'profit', 'profit_margin'},
  ),
  EntitySpec(
    name: 'compounds_details',
    promoted: [
      PromotedColumn('compound_id', SqlType.text, indexed: true),
      PromotedColumn('ingredient_id', SqlType.text, indexed: true),
    ],
  ),
  EntitySpec(name: 'deduction_act_groups'),
  EntitySpec(
    name: 'deduction_item_ingredients',
    promoted: [PromotedColumn('ingredient_id', SqlType.text, indexed: true)],
    numericKeys: {
      'quantity',
      'stock_before',
      'stock_after',
      'price_per_unit',
      'amount',
    },
  ),
  EntitySpec(
    name: 'deduction_items',
    numericKeys: {'quantity'},
  ),
  EntitySpec(
    name: 'deductions',
    numericKeys: {'balance'},
  ),
  EntitySpec(
    name: 'departments',
    promoted: [PromotedColumn('name', SqlType.text, indexed: true)],
  ),
  EntitySpec(
    name: 'goods',
    promoted: [
      PromotedColumn('name', SqlType.text, indexed: true),
      PromotedColumn('category_id', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
      PromotedColumn('price', SqlType.real),
    ],
    numericKeys: {
      'price',
      'cost_price',
      'profit',
      'profit_margin',
      'markup_percent',
    },
  ),
  EntitySpec(
    name: 'goods_details',
    promoted: [
      PromotedColumn('good_id', SqlType.text, indexed: true),
      PromotedColumn('ingredient_id', SqlType.text, indexed: true),
      PromotedColumn('compound_id', SqlType.text, indexed: true),
    ],
  ),
  EntitySpec(
    name: 'halls',
    promoted: [
      PromotedColumn('name', SqlType.text),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
    ],
  ),
  EntitySpec(
    name: 'ingredient_groups',
    promoted: [PromotedColumn('name', SqlType.text, indexed: true)],
  ),
  EntitySpec(
    name: 'ingredient_stock',
    promoted: [
      PromotedColumn('ingredient_id', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
    ],
    numericKeys: {'quantity'},
  ),
  EntitySpec(
    name: 'ingredient_stock_movements',
    promoted: [
      PromotedColumn('ingredient_id', SqlType.text, indexed: true),
      PromotedColumn('created_at', SqlType.text, indexed: true),
    ],
    numericKeys: {
      'qty_in',
      'qty_out',
      'stock_before',
      'stock_after',
      'price_per_unit',
    },
  ),
  EntitySpec(
    name: 'ingredients',
    promoted: [PromotedColumn('name', SqlType.text, indexed: true)],
    numericKeys: {'price_per_unit'},
  ),
  // Which ingredients this branch may see. The catalogue in `ingredients` is
  // brand-wide, so one row there is legitimately visible in several branches at
  // once and cannot itself carry a branch — this table is how the backend
  // narrows it, and without it a terminal shows every brand's ingredient.
  //
  // The rule is the strict one, matching all six of the backend's reads: an
  // ingredient is visible only where a row here says so with `is_visible`.
  // Absence is not permission.
  //
  // `is_visible` promotes to INTEGER because SQLite has no boolean; the applier
  // coerces true/false to 1/0 on the way in. `ingredient_id` is indexed because
  // it is the join key for every ingredient read.
  EntitySpec(
    name: 'ingredient_visibility',
    promoted: [
      PromotedColumn('ingredient_id', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text),
      PromotedColumn('is_visible', SqlType.integer),
    ],
  ),
  EntitySpec(
    name: 'inventories',
    numericKeys: {'surplus_amount', 'shortage_amount', 'remaining_amount'},
  ),
  EntitySpec(
    name: 'inventory_items',
    numericKeys: {'counted_quantity', 'system_quantity'},
  ),
  EntitySpec(
    name: 'invoice_detailed',
    numericKeys: {'quantity', 'price', 'price_per_unit'},
  ),
  EntitySpec(
    name: 'invoices',
    numericKeys: {'total_amount'},
  ),
  EntitySpec(
    name: 'modifier_calculation',
    promoted: [PromotedColumn('modifier_id', SqlType.text, indexed: true)],
    numericKeys: {'quantity', 'price_per_unit', 'total_cost'},
  ),
  EntitySpec(
    name: 'order_item_modifiers',
    promoted: [
      PromotedColumn('order_item_id', SqlType.text, indexed: true),
      PromotedColumn('modifier_id', SqlType.text, indexed: true),
    ],
  ),
  EntitySpec(
    name: 'order_items',
    promoted: [
      PromotedColumn('order_id', SqlType.text, indexed: true),
      PromotedColumn('good_id', SqlType.text, indexed: true),
      PromotedColumn('status', SqlType.text, indexed: true),
    ],
    numericKeys: {'price', 'cost_price'},
  ),
  EntitySpec(
    name: 'orders',
    promoted: [
      PromotedColumn('table_id', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
      PromotedColumn('cashier_id', SqlType.text, indexed: true),
      PromotedColumn('waiter_id', SqlType.text, indexed: true),
      PromotedColumn('status', SqlType.text, indexed: true),
      PromotedColumn('bill_status', SqlType.text, indexed: true),
      PromotedColumn('order_type', SqlType.text),
      PromotedColumn('bill_no', SqlType.integer),
      PromotedColumn('paid_at', SqlType.text, indexed: true),
      PromotedColumn('created_at', SqlType.text, indexed: true),
    ],
    numericKeys: {
      'total_amount',
      'food_cost',
      'food_total',
      'service_percent',
      'service_amount',
      'discount_percent',
      'discount_amount',
      'grand_total',
      'customer_paid_amount',
      'change_amount',
      'table_charge',
      'cash_amount',
      'card_amount',
    },
  ),
  EntitySpec(
    name: 'storages',
    promoted: [PromotedColumn('name', SqlType.text)],
  ),
  EntitySpec(
    name: 'suppliers',
    promoted: [PromotedColumn('name', SqlType.text, indexed: true)],
  ),
  EntitySpec(name: 'translations'),
  // The transactions ledger. Promotes exactly what its list screen filters,
  // sorts and paginates on, so those become SQL over the local replica instead
  // of a paginated REST call. `type` is the enum's string label (the payload
  // carries the label, not the ordinal); `date` is the ISO timestamp, sortable
  // lexically. amount/customer_paid_amount/change_amount are canonicalised to
  // strings on the way in, like every other numeric.
  EntitySpec(
    name: 'transactions',
    promoted: [
      PromotedColumn('cash_register_id', SqlType.text, indexed: true),
      PromotedColumn('type', SqlType.text, indexed: true),
      PromotedColumn('date', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text),
    ],
    numericKeys: {'amount', 'customer_paid_amount', 'change_amount'},
  ),
  EntitySpec(
    name: 'user_payments',
    promoted: [
      PromotedColumn('user_id', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
    ],
  ),
  EntitySpec(
    name: 'users',
    promoted: [
      PromotedColumn('full_name', SqlType.text),
      PromotedColumn('username', SqlType.text, indexed: true),
      PromotedColumn('role', SqlType.text, indexed: true),
      PromotedColumn('branch_id', SqlType.text, indexed: true),
      PromotedColumn('is_active', SqlType.integer),
    ],
    // `password` joins the list now that a staff create writes a local row.
    // The feed never carries it — this guards the *write* side: the create
    // form's body is the request and the row, and a plaintext credential must
    // not end up in a table every staff screen can query.
    //
    // It still travels in the outbox payload, because a create queued offline
    // has to carry the credential to send later. That is a narrower exposure
    // (one row, drained and deleted) than a column in `users`, but it is not
    // nothing, and it is the reason offline staff creation is worth a second
    // look before it ships to a venue.
    redactKeys: {'hash_password', 'pincode', 'password'},
  ),
];

/// Entity name → spec. Built once; [ChangeApplier] does a lookup per row.
final Map<String, EntitySpec> kEntitiesByName = {
  for (final e in kReplicatedEntities) e.name: e,
};

/// Whether the feed's entity name is one this client replicates.
///
/// The backend may log entities the POS has no use for (and may add more
/// without telling us). An unknown entity is skipped, never an error — a client
/// that crashes on an unrecognised row would break every sync pass after any
/// backend deployment.
bool isReplicatedEntity(String entity) => kEntitiesByName.containsKey(entity);

/// Column names every replicated table defines for itself. A promoted column
/// may not reuse one — the generated `CREATE TABLE` would declare it twice.
///
/// `id` is excluded from promotion because the primary key is written from
/// [EntitySpec.pk], which is not always the payload's `id` key
/// (`bill_daily_counters` is keyed by `day`).
const Set<String> kReservedColumns = {'id', 'deleted_at', 'data', 'synced_at'};

/// Validates the registry's internal consistency.
///
/// Returns the problems found rather than throwing, so a test can report all of
/// them at once. Called from `local_database_test.dart`; there is no runtime
/// cost because the registry is `const` and cannot change after a build.
List<String> validateRegistry() {
  final problems = <String>[];
  final seen = <String>{};

  for (final spec in kReplicatedEntities) {
    if (!seen.add(spec.name)) {
      problems.add('duplicate entity: ${spec.name}');
    }
    if (LocalTables.all.contains(spec.name)) {
      problems.add('entity collides with a local table: ${spec.name}');
    }
    if (spec.pk.isEmpty) {
      problems.add('${spec.name}: empty primary key');
    }

    final columns = <String>{};
    for (final column in spec.promoted) {
      if (kReservedColumns.contains(column.name)) {
        problems.add('${spec.name}: promoted column "${column.name}" is reserved');
      }
      if (!columns.add(column.name)) {
        problems.add('${spec.name}: duplicate promoted column "${column.name}"');
      }
    }

    // Redacting a promoted column would leave the column populated while the
    // value is stripped from `data` — an inconsistency that is easy to write
    // and hard to notice.
    for (final key in spec.redactKeys) {
      if (columns.contains(key)) {
        problems.add('${spec.name}: "$key" is both promoted and redacted');
      }
    }
  }

  return problems;
}
