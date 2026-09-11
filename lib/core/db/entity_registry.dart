/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 0 — the replicated-entity registry.
///
/// Every entity here is one table in the backend's tenant database that the
/// client keeps a local mirror of. `POST /api/v1/sync/pull` keys its `changes`
/// map by exactly these names — they are Postgres table names
/// (`TG_TABLE_NAME`), not API resource names.
///
/// Each one carries an `AFTER INSERT OR UPDATE OR DELETE` trigger writing into
/// `change_log` (`app/migrations/tenants/8_movements.up.sql`,
/// `41_modifier_calculation.up.sql`, `71_change_log_triggers_batch2.up.sql`).
///
/// That is a claim about a different repository, and it is checked rather than
/// asserted: `test/registry_backend_pin_test.dart` replays the backend's
/// tenant migrations and fails if this list and that SQL disagree — in either
/// direction, so a backend trigger the client ignores fails too. It exists
/// because comments here once claimed a migration that was never written,
/// which left four entities listed as replicated with nothing feeding them and
/// three screens rendering a permanently empty list as though it were data.
///
/// [ReplicationStatus] is the vocabulary for saying "the client is ready, the
/// server is not" honestly when that happens again. Nothing needs it today.
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

/// Whether the backend actually feeds an entity today, or the client is
/// merely ready for it.
///
/// The registry used to carry only one kind of entry, which made it a claim
/// it could not keep: four entities were listed as replicated while no
/// `trg_change_log_*` trigger existed on the backend table, so their local
/// tables were created, indexed, queried — and stayed empty forever. The screens
/// reading them rendered a blank list that is indistinguishable from "this
/// venue has no transaction groups", online or offline.
///
/// Deleting those entries was the other obvious move and it is worse: the
/// local table disappears, the queries that read it stop compiling, and the
/// screens lose their read path for a gap that is one backend migration wide
/// and already being closed. So the distinction is recorded instead. A
/// [pendingBackendTrigger] entity is a complete, working local table with a
/// working query behind it; the only thing missing is the server-side trigger
/// that would put rows in it. That fact is now in the type system, a screen
/// can ask for it ([isFedByChangeLog]), and `registry_backend_pin_test.dart`
/// asserts it against the backend's own migration SQL — so the moment a
/// trigger lands, the test fails and tells you to flip the flag.
enum ReplicationStatus {
  /// A `trg_change_log_*` trigger exists on the backend table, so `/sync/pull`
  /// delivers this entity and the local table fills on its own.
  live,

  /// The client models, stores and reads this entity, but the backend has no
  /// change-log trigger on the table yet — nothing will ever arrive, and
  /// nothing writes it locally either, so the table stays empty.
  ///
  /// This is a temporary state by construction. It is never the right answer
  /// for a new entity: add the trigger first, then the registry entry.
  pendingBackendTrigger,
}

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

  /// Whether the backend logs this entity into `change_log` today.
  ///
  /// Defaults to [ReplicationStatus.live], because that is what a registry
  /// entry is supposed to mean and anything else should have to say so. See
  /// [ReplicationStatus] for why the exception is recorded rather than
  /// deleted.
  ///
  /// Note what this deliberately does **not** do: it is not consulted by
  /// [ChangeApplier] or by the schema builder. The local table is created and
  /// an arriving row is applied either way. So when the backend's trigger
  /// lands, data starts flowing on the terminals already in the field —
  /// before anyone flips this flag — and the flag's only job is to keep the
  /// UI honest in the meantime.
  final ReplicationStatus status;

  /// A key whose transition from empty to set is **monotonic**, and which an
  /// arriving row may therefore apply even over an unsynced local edit.
  ///
  /// [ChangeApplier] normally refuses to overwrite a row this terminal has
  /// pending, because a stale row landing between a cashier's write and its
  /// replay would silently revert what they just did. That rule is right for
  /// almost everything and wrong for one shape: a field that only ever goes
  /// from unset to set, written by a *different* terminal.
  ///
  /// `branch_shifts.closed_at` is that shape. The till that opened the venue's
  /// shift holds it pending until its queue drains; a colleague closing the
  /// shift on the till beside it sends the closed row, and the pending guard
  /// dropped it — so the terminal that opened the shift kept trading under a
  /// shift the branch had already closed. That is the exact failure a
  /// branch-wide shift exists to prevent.
  ///
  /// Deliberately one-directional. The reverse — an arriving row with the key
  /// *unset* landing on a locally-closed row — stays guarded, so a pull that
  /// delivers the still-open server copy cannot reopen a shift this terminal
  /// has just closed and not yet reported. Relaxing the guard in both
  /// directions would trade one visible bug for another.
  final String? monotonicSetKey;

  /// Why this entity is not yet fed, and what closes the gap.
  ///
  /// Required in spirit for a [ReplicationStatus.pendingBackendTrigger] entry
  /// (`validateRegistry` enforces it) so the entry cannot decay into an
  /// unexplained flag that nobody dares remove.
  final String? pendingReason;

  const EntitySpec({
    required this.name,
    this.pk = 'id',
    this.promoted = const [],
    this.numericKeys = const {},
    this.redactKeys = const {},
    this.status = ReplicationStatus.live,
    this.pendingReason,
    this.monotonicSetKey,
  });

  /// True when `/sync/pull` actually delivers rows for this entity.
  bool get isFed => status == ReplicationStatus.live;
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

  /// Rows this terminal learned about from a LAN peer rather than from the
  /// server.
  ///
  /// A peer's row is deliberately not marked pending — the terminal that wrote
  /// it owns its trip to the server, and two terminals queuing the same create
  /// is the duplicate that would cause (see `ChangeApplier.applyFromPeer`). But
  /// "not pending" also meant "nothing is protecting it", and a repair sweep
  /// asks the server what exists: a bill rung on the next till, still sitting in
  /// *its* outbox, is not in that answer. The sweep would delete a live check —
  /// and broadcast the delete to the terminal that owns it.
  ///
  /// So provenance is recorded. An entry is written when a row arrives from a
  /// peer and dropped the moment the server sends the same row, which is the
  /// point at which the snapshot becomes authoritative about it.
  static const peerOrigin = '_peer_origin';

  /// Live per-order table-timer records — the local-authority billing engine's
  /// store, moved off the retiring Hive box onto the replica DB.
  ///
  /// Like [tableStatus], this is decided *here*, not delivered by the feed: a
  /// cashier's start/pause/resume writes the record and prices the interval
  /// locally, and the server's snapshot only re-enters through SyncEngine's
  /// hydration. So it is a local table, not a replicated entity — the raw
  /// `table_time_sessions` feed row is a different shape, and this keeps the
  /// proven compute engine unchanged across the storage swap.
  static const tableTimers = '_table_timers';

  /// Menu image bytes, keyed by their Minio object name.
  ///
  /// Not a replicated entity: Minio is a blob store with no change-log
  /// trigger, so these arrive by fetch-on-miss and an ahead-of-time pass over
  /// the replicated `goods.picture_url` values, never from the feed. It lives
  /// here rather than in a second store because "one database" means the
  /// bytes a screen renders come from the same file as the row that
  /// references them — and because a brand switch then drops the previous
  /// tenant's images with everything else, in one wipe.
  static const images = '_images';

  static const all = {
    meta,
    outbox,
    pending,
    tableStatus,
    provisional,
    tableTimers,
    images,
  };

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
  // The venue's shift, and the reason this entity is replicated at all: every
  // terminal in a branch must see the same open shift, including the ones that
  // did not open it. `cash_register_shifts` stays out of the registry (see
  // `kIntentionallyNotReplicated` in registry_backend_pin_test.dart) because it
  // is per-register by construction and so has nothing branch-wide to agree on.
  //
  // Being a replicated entity is what gives the shift both halves of "synced
  // between local instances first": `LocalWriter` writes the row through
  // `ChangeApplier.applyLocalWrite`, which broadcasts it to LAN peers the
  // instant it is committed, and `/sync/pull` carries the same row to any
  // terminal that was not on the network at the time. One row, two delivery
  // paths, no second code path deciding what a shift is.
  EntitySpec(
    name: 'branch_shifts',
    promoted: [
      PromotedColumn('branch_id', SqlType.text, indexed: true),
      // Indexed because it is the only column the hot query filters on: the
      // active shift is "the branch's row with no closed_at".
      PromotedColumn('closed_at', SqlType.text, indexed: true),
      PromotedColumn('opened_at', SqlType.text, indexed: true),
      PromotedColumn('opened_by', SqlType.text),
      PromotedColumn('closed_by', SqlType.text),
    ],
    numericKeys: {
      'opening_cash',
      'opening_card',
      'closing_cash',
      'closing_card',
    },
    // A close made on any till in the branch has to reach the till that opened
    // the shift, which still holds its own row pending. See [monotonicSetKey].
    monotonicSetKey: 'closed_at',
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
  //
  // This entry was the most dangerous of the four that claimed a trigger they
  // did not have, precisely because the rule above is strict:
  // `MenuAdminQuery.ingredients()` requires a visibility row, so an unfed
  // table hid the ENTIRE ingredient catalogue rather than showing too much of
  // it — the tech-card editor's ingredient picker was empty on every terminal
  // and nothing said why. `71_change_log_triggers_batch2.up.sql` supplies the
  // trigger and the backfill. Fail-closed stays: the correction belongs on the
  // server, not in a client-side "if the table is empty, show everything"
  // fallback that would leak another branch's catalogue the moment one row
  // arrived late.
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
  // The transactions screen's two back-office pickers: transaction (expense/
  // income) groups and cash registers. Both are small id+name catalogues the
  // feed carries.
  //
  // These two — and `transactions` below, and `ingredient_visibility` above —
  // carried a comment claiming "tenants migration 70
  // (change_log_missing_triggers) added their triggers and backfilled a create
  // per live row". No such migration was ever written: tenant 70 is
  // `70_order_items_client_id`, and for a long stretch these entries were
  // listed here while nothing on the server logged them, so the pickers
  // rendered a permanently empty list that reads as "this venue has none".
  // The trigger that actually feeds them is
  // `71_change_log_triggers_batch2.up.sql`, which also backfills one `create`
  // per live row so a terminal bootstrapping from cursor 0 sees them.
  //
  // The lesson is in the test, not the comment: nothing here asserts the
  // backend any more. `test/registry_backend_pin_test.dart` replays the tenant
  // migrations and fails if this line and that SQL disagree, in either
  // direction.
  //
  // The rest of the original comment claimed the feed is branch-scoped on the
  // backend (`change_log.branch_id`) and that the local reads therefore need no
  // branch filter. There is no such column: `change_log` carries `brand_id`,
  // and `SyncS.Pull` selects `WHERE id > $1`. What remains true is that `name`
  // is promoted because that is what the pickers order on.
  EntitySpec(
    name: 'group_transactions',
    promoted: [PromotedColumn('name', SqlType.text)],
  ),
  EntitySpec(
    name: 'cash_registers',
    promoted: [PromotedColumn('name', SqlType.text)],
  ),
  // The transactions ledger. Promotes exactly what its list screen filters,
  // sorts and paginates on, so those become SQL over the local replica instead
  // of a paginated REST call. `type` is the enum's string label (the payload
  // carries the label, not the ordinal); `date` is the ISO timestamp, sortable
  // lexically. amount/customer_paid_amount/change_amount are canonicalised to
  // strings on the way in, like every other numeric.
  //
  // Note that the ledger screen does not read this table yet:
  // `TransactionsListController.getTransactions` still pages over REST through
  // `MainRepository`, so `TransactionsQuery` and
  // `TransactionsRepositoryImpl.getTransactions` are a finished read path with
  // no caller. Flipping that caller is a separate change; this entry is what
  // makes it possible.
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

/// Entities the client is ready for and the backend does not log yet.
///
/// Derived, never hand-maintained: flipping one [EntitySpec.status] back to
/// [ReplicationStatus.live] is the whole of "this gap closed", and this set
/// shrinks with it. `registry_backend_pin_test.dart` fails while the two
/// disagree in either direction, so it cannot quietly grow.
final Set<String> kEntitiesAwaitingBackendTrigger = {
  for (final e in kReplicatedEntities)
    if (e.status == ReplicationStatus.pendingBackendTrigger) e.name,
};

/// Whether rows for [entity] can actually arrive from `/sync/pull` today.
///
/// The question a screen should ask before it renders an empty list. An empty
/// list from a fed entity means the venue has none of that thing; an empty
/// list from an unfed one means the client is waiting on the server and the
/// operator deserves to be told that instead of shown a blank panel.
///
/// Unknown entities answer `false`: the client neither stores nor receives
/// them, which for a caller's purposes is the same "do not present this as
/// data".
bool isFedByChangeLog(String entity) =>
    kEntitiesByName[entity]?.isFed ?? false;

/// Column names every replicated table defines for itself. A promoted column
/// may not reuse one — the generated `CREATE TABLE` would declare it twice.
///
/// `id` is excluded from promotion because the primary key is written from
/// [EntitySpec.pk], which is not always the payload's `id` key
/// (`bill_daily_counters` is keyed by `day`).
const Set<String> kReservedColumns = {'id', 'deleted_at', 'data', 'synced_at'};

/// Entities whose rows are work an operator did, not configuration someone
/// typed into a settings screen.
///
/// The distinction exists for one decision: what to do with a local row whose
/// create the server rejected for good. For a hall or a menu item the answer is
/// to drop it — the server assigned no id, no other terminal has it, and
/// leaving it behind puts something on screen that exists nowhere else. For a
/// bill, a line on a bill, or a shift, dropping it would erase what somebody
/// actually did at the till: items rung, money taken, a shift opened. Those
/// rows stay, rejected or not, and the operator finds the failure in the
/// quarantine list rather than discovering the check has vanished.
///
/// Note that "the client chose the id" is *not* the test. `order_items` picks
/// its own ids and the backend still mints its own (see
/// `ChangeApplier._retireClientTwin`), so id ownership says nothing about
/// whether the row is safe to throw away.
const Set<String> kOperatorWorkEntities = {
  'orders',
  'order_items',
  'branch_shifts',
  'cash_register_shifts',
  'transactions',
  'group_transactions',
  'user_payments',
  'table_time_sessions',
};

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

    // A pending entry that does not say why it is pending is indistinguishable
    // from an oversight, and nobody deletes a flag they cannot explain.
    if (spec.status == ReplicationStatus.pendingBackendTrigger &&
        (spec.pendingReason ?? '').trim().isEmpty) {
      problems.add('${spec.name}: pendingBackendTrigger without a '
          'pendingReason — say which trigger is missing and what lands it');
    }
    if (spec.status == ReplicationStatus.live && spec.pendingReason != null) {
      problems.add('${spec.name}: has a pendingReason but is marked live — '
          'delete the reason with the flag');
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
