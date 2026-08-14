# Offline-First Everywhere — Implementation Plan

Target: the master architecture specification, with no exceptions and no deferred
screens. One database. The UI never touches the network. The only backend request
triggered by a user action is the first login's initialization.

This plan is written against the actual backend (`mary-ai-group/mary-ai-backend`
@ `3533b8b`), so local calculations and local structure match the server exactly.

---

## 1. The finding that changes the approach

**The backend already has a full replication API. The POS does not use it.**

```
POST /api/v1/sync/pull   { last_sync_cursor, limit }
                       → { next_sync_cursor, changes: { <entity>: {created[], updated[], deleted[]} } }
POST /api/v1/sync/push   { changes: [{ entity, action, entity_id, payload }] }
                       → { applied, errors[] }
```

`app/internal/service/sync.go:40-125`. Backed by a `change_log` table
(`migrations/tenants/8_movements.up.sql:28-70`) populated by `AFTER INSERT OR UPDATE
OR DELETE` triggers on **35 tables**, whose payload is `to_jsonb(NEW)` — the complete
row, not a diff.

Every previous plan in this repo tried to make the POS offline-first *screen by
screen*, hand-building a local mirror per feature. That is why it stalled at the
cashier flow: there are ~40 more screens and each one needed bespoke work.

The replication feed removes that entirely. Mirror the tenant database once, and every
screen — present and future — is offline-first by construction, because there is
nothing left for a screen to fetch.

**This plan therefore replaces the entire REST read layer with one replication stream.**

### What the backend already gives us

| Capability | Evidence | Consequence |
|---|---|---|
| Cursor-based delta feed over 35 entities | `sync.go:40-125` | One inbound data path replaces every `GET` |
| Full-row payloads (`to_jsonb`) | `8_movements.up.sql:56-66` | Local rows are byte-equivalent to server rows |
| `CreateOrder` accepts a **client-supplied UUID** and is idempotent — returns the existing order on duplicate id | `order.go:203-227` | Offline order creation needs no ID reconciliation, ever |
| `CreateOrdersBatch` with `continue_on_error` + per-item results | `order.go:530-576` | Outbox drains in one round trip |
| `PayOrder` idempotent on already-paid status | `order.go:1247-1254` | Replay-safe payments |
| Total formula fully specified and deterministic | `order-total-calculation.md`, `order.go:2023-2027` | Totals computable locally with exact server parity |

The client already generates order UUIDs (`generateUuidV4()` in `create_order_bloc.dart:91`,
`waiter_local_repository_impl.dart:324`) and sends them. **That half is already right.**

---

## 2. Database decision: one SQLite database (Drift)

Delete **both** current stores. `CacheService` and the Hive `LocalDatabase` are
replaced, not merged.

Hive was the correct choice when only the cashier flow was local — the original design
note ("nothing here needs a relational join") was true then. It is false now. Once the
whole application is local, the local store must serve:

- paginated, filtered, sorted ledgers (transactions, admin users, archives)
- text search across a multi-thousand-row goods catalog
- joins (order → items → goods → category; table → hall; good → calculation → ingredients)
- aggregation for reports and shift close

Hive's model is one JSON blob per key; each of those queries becomes "decode everything,
filter in Dart." That does not hold up at catalog scale and cannot express the
back-office screens at all.

**Decision: SQLite.** Relational, reactive, and it maps 1:1 onto the change-log feed,
which is row-oriented.

> **Revised during Phase 0: raw `package:sqlite3`, not Drift.** Three reasons surfaced
> once the schema was actually built. (a) The schema is *generated* from the entity
> registry rather than declared per table, so there is nothing for Drift's codegen to
> type — its main benefit does not apply. (b) Drift needs `build_runner`, and this repo
> commits its generated output; a foundational layer that will not compile until a
> codegen step runs is a sharp edge. (c) `package:sqlite3` is **synchronous**, so a
> screen can read inside `build()` with no `await` and no `FutureBuilder` — which is
> precisely the "always feels local" property this architecture exists for. An async
> database would have reintroduced a loading state on every screen in the name of
> offline-first. Reactivity, the one thing Drift gave for free, is ~40 lines
> (`LocalDatabase.watch`) because invalidation is per-table and all writes already
> funnel through one class.

**Schema = a mirror of the tenant schema**, one table per replicated entity, columns
matching `migrations/tenants/*.up.sql`. Local-only additions:

- `_sync_meta(key, value)` — the pull cursor, bootstrap state
- `_outbox(...)` — replaces `OfflineQueueService`'s Hive boxes
- `_pending(entity, entity_id)` — rows written locally and not yet acknowledged, so a
  replication apply never overwrites an unsynced local edit

Device-scoped settings that are **not** server state (USB printer name per printer
entry, terminal id, LAN role, locale) stay in `SharedPreferences`. That is not a second
database — it holds no replicated entity. It is the one exception and it is deliberate.

---

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ UI  — every screen, every widget                              │
│      reads ONLY  db.watchX()  /  db.getX()                    │
│      writes ONLY  repository.doX()  → local write + outbox     │
└───────────────────────┬──────────────────────────────────────┘
                        │ Drift streams (reactive)
┌───────────────────────▼──────────────────────────────────────┐
│ SQLite (Drift) — the single source of truth                    │
│   replicated entities · _outbox · _sync_meta · _pending        │
└───────────────────────▲──────────────────────────────────────┘
                        │ writes only
┌───────────────────────┴──────────────────────────────────────┐
│ SyncEngine — the ONLY component that touches the network       │
│   pull loop (cursor) · outbox drain · LAN relay · bootstrap    │
└───────────┬────────────────────────────────┬─────────────────┘
            │ Leader only                     │ Follower only
      ┌─────▼─────┐                    ┌──────▼──────┐
      │   Cloud   │                    │ Leader (LAN)│
      └───────────┘                    └─────────────┘
```

Two rules that make this enforceable rather than aspirational:

1. **Nothing outside `lib/core/sync/` may import Dio, http, or MinioService.** Enforced
   by a lint rule + CI check (§9), not by review discipline.
2. **Nothing outside `lib/data/` may import the Drift database.** Screens see
   repositories; repositories see the database.

---

## 4. Phases

Ordered by dependency. Each phase leaves the app shippable.

### Phase 0 — Foundation

- Add `drift` + `sqlite3_flutter_libs`; define the schema mirroring the 35 replicated
  entities plus `_outbox`, `_sync_meta`, `_pending`.
- Build the entity-name → table map. Change-log entity names are **Postgres table
  names** (`TG_TABLE_NAME`): `cafe_tables`, `goods`, `goods_details`, `categories`,
  `halls`, `departments`, `users`, `orders`, `order_items`, `order_item_modifiers`,
  `modifier_calculation`, `shifts`, `branches`, `ingredients`, `compounds`,
  `compounds_details`, `calculation`, `translations`, `ingredient_stock`,
  `compound_stock`, `storages`, `suppliers`, `invoices`, `invoice_detailed`,
  `inventories`, `inventory_items`, `deductions`, `deduction_items`,
  `deduction_item_ingredients`, `deduction_act_groups`, `ingredient_groups`,
  `ingredient_stock_movements`, `attendances`, `user_payments`, `bill_daily_counters`.
- One `applyChange(entity, action, payload)` function: upsert on create/update, delete
  on delete, skipping any row present in `_pending`. Unknown entity → ignore, don't
  crash. This single function is the entire inbound write path.

### Phase 1 — Replication engine

Rewrite `SyncEngine` around the feed:

- **Bootstrap** (first login only): loop `POST /sync/pull` from `last_sync_cursor = 0`,
  500 rows per batch, applying each batch, until `next_sync_cursor` stops advancing.
  Persist the cursor. This is the *only* user-triggered network call in the product,
  and it is the initialization the spec permits. Show progress; it is a one-time cost.
- **Steady state**: same pull loop on the existing 60s tick, on reconnect, and after
  every outbox drain. Never triggered by a screen.
- **Retire** `_hydrateReferenceData`, `_hydrateGoodsByCategory`, `_hydrateArchives`,
  `_hydrateTransactionGroups`, `_hydrateCashRegisters`, `_hydratePrinterSettings`,
  `_hydrateServiceCharge`, `_hydrateOpenOrderDetails`, `_hydrateTableTimers`,
  `prefetchAllGoods` — ~300 lines of per-entity fetching replaced by one loop.

  > **Revised during Phase 1: the deletion happens in Phase 4, not here.** Those
  > methods feed `CacheService` and the Hive `LocalDatabase`, which every screen still
  > reads until Phase 4 rewires them. Deleting them in Phase 1 would empty the stores
  > the running app depends on. Phase 1 therefore runs replication *alongside* the old
  > hydration — the replica fills in the background while nothing reads it yet — and
  > Phase 4 deletes both the hydration and the stores in the same change that moves the
  > screens across. `SyncEngine.tick()` calls `drain()` immediately before the legacy
  > block for exactly this reason: in Phase 4, deleting everything below that call is
  > the whole edit.
  >
  > Same reasoning for bootstrap: it runs in the background at first login for now.
  > Phase 4 promotes it to a foreground step with a progress screen, once the replica
  > is what the screens actually read.
- Keep `_hydrateMenuImages` (Minio is a blob store, not in the change log), but move it
  to a lazy background pass keyed off replicated `goods.picture_url` values.

### Phase 2 — Every write goes through the outbox

`_outbox(id, entity, action, entity_id, payload, created_at, attempts, next_attempt_at,
status)`.

Every repository method becomes: **write the local row → insert an outbox row → return.**
No `await` on the network, ever, on any path.

- **Orders / items / payments / timers**: already client-UUID'd. Replay via
  `CreateOrdersBatch` (idempotent per id) and `POST /orders/{id}/pay` (idempotent on
  paid status).
- **Back-office writes** (users, halls, tables, categories, goods, translations,
  transactions, printer settings — the 23 operations currently bypassing the queue per
  V10 of the review): local write with a client-generated UUID, outbox row, replay
  against the existing REST endpoints. `/sync/push` only accepts `orders`,
  `order_items`, `attendances` (`sync.go:187-195`), so these stay on REST — which is
  fine, because the user never waits on them.
- Replay ordering: FIFO within an entity; orders before order_items before payments.
- Conflict rule: **last write wins, server is authoritative on apply.** When a replay
  returns the server's version, clear `_pending` and let the next pull overwrite the
  local row. No merge logic, no user-facing conflict UI.

### Phase 3 — Local calculation engine

Port `order-total-calculation.md` verbatim into `lib/core/pricing/order_totals.dart`,
verified line-by-line against `order.go:2023-2027`:

```dart
itemsAmount   = Σ (qty × price)                  // non-cancelled items only
tableCharge   = timeBased ? (activeSeconds / 3600) * pricePerHour : 0
serviceAmount = round(itemsAmount * servicePercent / 100)   // NOT on tableCharge
baseTotal     = itemsAmount + tableCharge + serviceAmount
discount      = pct != null ? round(baseTotal * pct / 100) : discountAmount
grandTotal    = max(round(baseTotal - discount), 0)
```

Every input is already local: item qty/price from `order_items`, `service_percent`
frozen on the order at creation (default from `branches.default_service_percent`,
fallback 20), `price_per_hour` from `cafe_tables`, active seconds from the local timer.

Because the server *recomputes and enforces* this exact number at pay time, a locally
computed total that follows this formula is accepted on replay. Use `double`
arithmetic with `round()` at the same points the Go code rounds — not `Decimal`, which
would diverge on the half-up boundary.

Delete `GET /orders/{id}/table-price` and `GET /orders/{id}/hour-price` calls; compute
the live table charge locally and send it in the pay body (the server accepts a
supplied `table_charge`).

### Phase 4 — Rewire every screen

Mechanical once Phases 0-3 land. For each screen: delete the repository/network field,
subscribe to a Drift query, delete the `_loading` flag and error state.

| Screen | Now | After |
|---|---|---|
| Table map, order detail, payment, waiter, timer | already local | move to Drift queries |
| Transactions list | `getTransactions` paginated | `watchTransactions(limit, offset, filters)` |
| Transaction categories | `getTransactionGroups` | local query |
| Admin users | `getAdminUsers` paginated | `watchUsers(...)` |
| Halls & tables settings | `getHalls`/`getAllTables` | `watchHalls()` / `watchTables()` |
| Printer settings | `getPrinterSettings` | local query + device-scoped prefs |
| Menu management / meals list | `searchGoodsAdmin`, `getGoodById`, `getGoodWithCalculations` | local joins over `goods`/`calculation`/`ingredients` |
| Archives | `getArchives` filtered | local query over `orders` |
| Reports / shift close | server aggregation | local aggregate queries |
| Images | `FutureBuilder` + Minio in widget | `StreamBuilder` over the local image table |

Pagination, search, sort and filter all become SQL — instant, offline, no spinner. This
is the payoff for choosing SQLite: these screens stop being special cases.

Then delete: `MainRepositoryImpl`, `MainDataSources`, `CacheService`, the Hive
`LocalDatabase`, `MenuLocalRepositoryImpl`, `ArchivesLocalRepositoryImpl`,
`WaiterLocalRepositoryImpl`'s network paths, and every `inject<MainRepository>()` in the
widget layer.

### Phase 5 — LAN: the Leader distributes the feed

This is the missing message type (V6) and it is now trivial, because the thing to
distribute is already a serialized change list.

- Add `LanHubMessageType.changeFeed` carrying a batch of
  `{entity, action, entity_id, payload}` plus the cursor it came from.
- Leader: after every successful pull, broadcast the applied batch to all followers.
- Follower: `applyChange()` per row — the *same function* the cloud path uses. Followers
  do not parse a second format and do not have a second code path.
- **Delete the follower's cloud uplink** (`sync_engine.dart:156-161`). A follower's only
  inbound path becomes the leader; its only outbound path stays the existing outbox
  relay. This closes V7.
- Follower cursor tracks the leader's, so a follower promoted to leader resumes cleanly.

### Phase 6 — Leader election on by default

- Flip `LeaderElectionService.isEnabled` to default **true**; delete `setEnabled` and the
  settings toggle.
- Remove cluster role and leader identity from `sync_status_section.dart` (V9). Queue
  depth and last-sync time may stay — they are not leadership.
- Keep the existing epoch fencing, priority, and terminal-id tiebreak as built.

---

## 5. What the backend needs (small, precise)

None of these block Phases 0-4; they raise the ceiling.

1. **Change-log triggers for 8 missing tables.** One line each, reusing the existing
   `log_change()` function:

   ```sql
   CREATE TRIGGER trg_change_log_transactions AFTER INSERT OR UPDATE OR DELETE
     ON transactions FOR EACH ROW EXECUTE FUNCTION log_change('id');
   ```

   | Table | Why it matters |
   |---|---|
   | `table_time_sessions` | **Critical.** Time-based table billing. `TableTimeSession.final_amount` and the session's active seconds drive `table_charge` — the largest line on a billiard/PS bill. Without a trigger the timer cannot replicate at all. |
   | `modifiers` | The modifier catalog. `order_item_modifiers` and `modifier_calculation` *are* logged, so we replicate which modifiers an order line used and what they cost — but not their names or prices. |
   | `goods_modifiers` | Which modifiers a good offers. Without it the order screen cannot show modifier options offline. |
   | `transactions` | The cash ledger screen. |
   | `transaction_category` | Its filter list. |
   | `cash_registers` | Register picker, shift assignment. |
   | `printer_settings` | Printer configuration screen. |
   | `cash_register_shifts` | Shift open/close reconciliation. |

   The first three are the ones that block *cashier-facing* functionality;
   `table_time_sessions` in particular is load-bearing for an entire table type. Until
   these land, those screens read a locally-mirrored copy maintained by the outbox on
   write and refresh fully only at bootstrap. **This is the highest-value backend
   change.**

5. **Stop shipping credentials in the feed.** `users` rows are logged whole, so
   `hash_password` and `pincode` travel to every terminal in the venue. The client
   redacts both before writing to disk (`entity_registry.dart`, `redactKeys`), so this
   is contained — but the fix belongs server-side: have `log_change()` strip them from
   the payload, or exclude the columns from the trigger. Client-side redaction protects
   the disk, not the wire.

2. **A bootstrap snapshot endpoint.** `change_log` has no retention or compaction, so
   `last_sync_cursor = 0` replays *every mutation in the tenant's history* — including
   rows since deleted. Correct, but O(all writes ever) for a new terminal. Ask:
   `GET /api/v1/sync/snapshot` returning current rows per entity plus the cursor to
   resume from. Phase 1 works without it; first login just costs more.

3. **`change_log` retention.** Unbounded growth on a hot table with three indexes.
   Compact to one row per `(entity, entity_id)` beyond N days, or partition by month.
   Operational, not blocking.

4. **Confirm client-supplied ids on `CreateOrderItems`.** `order.go:3110-3160` reads
   `entry.GoodID` and `entry.Quantity` but no `entry.ID`. If item ids are server-assigned,
   locally-created line items get a new id on replay, so local item ids must be treated
   as provisional until the order's next pull. Accepting a client id here would remove
   that asymmetry and make items behave exactly like orders. Worth doing; cheap.

---

## 6. Migration and rollout

- **Ship in one release, not incrementally.** Two databases coexisting is what produced
  V1; a half-migrated third state would be worse. Phases 0-4 land together behind a
  build flag; Phases 5-6 follow.
- **No data migration from Hive.** The local store is a replica — throw it away and
  re-bootstrap from `/sync/pull`. The only thing to preserve is the **outbox**: drain it
  to completion on the old build before upgrading, and fail the upgrade if it is
  non-empty. Unsynced orders are the one piece of data that exists nowhere else.
- Device-scoped prefs (printer names, terminal id) carry over untouched.

---

## 6b. Status finding — two storage engines run in parallel

Discovered while wiring the first Phase 4 read (transactions). The client has
**two** `LocalDatabase` classes, and the migration between them is half done:

- **SQLite `core/db/`** — the offline-first target. The change feed lands here;
  `halls_tables`, `menu_admin`, `users`, `archives`, `tables` and now the
  transactions read sit on it.
- **Hive `core/database/`** — the old `CacheService`, evolved. **`orders`,
  `waiter`, the order-detail read path, `menu` and `table_timer` still read from
  it.**

So the entire backend sync effort fills the SQLite replica, while the most
important screens in the POS — the order flow — read the Hive store the feed
never touches. The `deleted_at` fix, the branch scoping, the snapshot, the
compaction: none of it reaches those screens yet, because those screens are on
the wrong engine.

This reframes Phase 4. It is not "rewire screens onto the replica" from a clean
base; it is "finish moving off two engines onto one", and the order flow — the
highest-value, highest-traffic path — is the biggest piece still on Hive. The
`Hive present -> 86 files` line in the definition of done below is this, not
stragglers.

Recommended order when this resumes: the order/waiter read path first (it is
what the sync work exists to serve), then the remaining back-office lists, which
are smaller and lower-traffic.

---

## 7. Definition of done

The spec's own review questions, as CI-checkable assertions:

- [ ] `grep -rn "Dio\|http\|MinioService" lib/ --exclude-dir=core/sync` returns nothing.
- [ ] `grep -rn "inject<.*Repository>" lib/**/presentation/pages/` returns nothing.
- [ ] No `FutureBuilder` anywhere in `lib/`.
- [ ] Exactly one database class; `CacheService` and Hive `LocalDatabase` deleted.
- [ ] Every screen renders fully with the network cable pulled and the app cold-started.
- [ ] Every user action completes without awaiting a network call — measured, not assumed:
      a test harness that fails any action whose handler awaits a Dio future.
- [ ] Local `grandTotal` equals the server's for a fixture set covering
      `order-total-calculation.md` §10 examples A, B and C.
- [ ] Kill the leader mid-service: another terminal takes over with no UI change and no
      manual step.
- [ ] A follower with its LAN link up and its own internet **off** receives menu changes
      made on the leader within one tick.

---

## 8. Sequence

| Phase | Content | Depends on |
|---|---|---|
| 0 | Drift schema, `applyChange()`, entity map | — |
| 1 | Replication engine, bootstrap, cursor | 0 |
| 2 | Outbox for all writes | 0 |
| 3 | Local totals engine | 0 |
| 4 | Rewire all screens; delete the REST read layer | 1, 2, 3 |
| 5 | LAN change-feed relay; cut follower cloud uplink | 1, 4 |
| 6 | Leader election default-on; remove role from UI | 5 |
| B1 | Backend: 5 change-log triggers | — (parallel) |
| B2 | Backend: snapshot endpoint | — (parallel) |

Phases 2 and 3 are independent of 1 and can run in parallel. B1/B2 are backend-side and
gate nothing.

---

## 9. Guardrails

The previous plans failed on discipline, not knowledge — fixes landed on one path and
not its duplicate. Three mechanical guards:

1. **Import lint**: a `custom_lint` rule failing any import of `dio`, `http`,
   `minio`, or `connectivity` outside `lib/core/sync/`. This is what makes "networking is
   isolated" a build error instead of a review comment.
2. **No second write path**: repositories are the only writers; a test asserts every
   mutation method inserts an `_outbox` row.
3. **Offline integration suite**: the whole app driven with the Dio client replaced by
   one that throws on any call. Every screen must render and every action must succeed.
   Any new feature that reaches for the network fails this suite on the first run.
