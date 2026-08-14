# Server-side plan for offline-first

**Scope.** Work that has to happen in the backend for the client's offline-first
migration to finish. Written after the client side landed, so every item here is
something the client is either blocked on, working around, or depending on
without a guarantee.

**Not to be confused with `BACKEND_SYNC_PLAN.md`**, which despite its name covers
the *client's* sync layer (`SyncEngine`, `LeaderElectionService`, `LeaseManager`).
This document is about the server.

**Verified against the server source.** This was first written from
`api-docs/swagger.json` alone, with the uncertain parts marked **VERIFY**. It has
since been checked against `Mary-Ai-Group/mary-ai-backend` at `3533b8b` — the
tenant migrations, `internal/service/sync.go`, `internal/handler/sync.go`. Every
**VERIFY** from the first draft is now answered against a named file.

Two came back wrong and are rewritten rather than patched: the trigger list in
P0-1, and the entire recommendation in P1-1. One came back confirmed and worse
than described: P0-3. Reading the source also turned up a problem nobody had
listed, now **P0-4** — `/sync/pull` applies no branch or brand filter at all.

Two things still need an answer from outside the source, and are marked where
they arise: production `change_log` volume (open question 6), and whether one
tenant schema is expected to hold more than one branch (P0-4, which sets that
item's priority). Everything else here is read, not inferred.

**P0-1 and P0-0 have since been implemented and tested** — see their STATUS
lines. Building them corrected three more claims and turned up the largest
finding in this document: **the sync endpoints returned 500 to every caller**, so
the feed this entire plan is about was not running. Section 7 lists what moved.

---

## 1. The contract the client now depends on

Everything the client does rests on this. It is worth stating exactly, because
three of the work items below are about places where the guarantee is weaker
than the client assumes.

### `POST /api/v1/sync/pull`

Request `{last_sync_cursor, limit}`, response:

```json
{ "data": {
    "next_sync_cursor": 12345,
    "changes": {
      "goods":  { "created": [{…}], "updated": [{…}], "deleted": ["id"] },
      "orders": { … }
    } } }
```

The client requires, in order of how badly it breaks if violated:

1. **No row is ever skipped.** A client that has applied up to cursor N and asks
   for changes after N must receive every change that will ever exist with a
   cursor above N. This is the one guarantee with no client-side recovery — see
   item P0-3, which is the most important thing in this document.
2. **The cursor is monotonic and resumable.** The client persists it, advances it
   only inside the same transaction as the rows, and never moves it backwards.
3. **Full rows in `created`/`updated`.** The client stores the payload whole and
   renders from it. Partial rows would blank fields.
4. **`deleted` carries ids only.** The client removes by id.
5. **A short page means caught up.** Fewer rows than `limit` ends the drain loop.
6. **Scoping is derived from the token.** **CORRECTED — there is no scoping.**
   The pull query is `WHERE id > $1 ORDER BY id ASC LIMIT $2` and nothing else
   (`service/sync.go:56-62`). It does not filter on `brand_id`, which is written
   to every row and never read back, and it has no concept of a branch. The only
   isolation is the tenant schema the connection is bound to. A tenant with two
   branches sends both branches' rows to every terminal in both. See open
   question 1 — this is a real finding, not a hypothetical.

### What the client sends

Writes do **not** go through `/sync/push`. They go to the ordinary REST
endpoints, one bespoke outbox handler per entity. Push exists and is implemented,
but accepts only `orders`, `order_items` and `attendances` — see P1-1, where the
recommendation I originally gave turns out to be backwards.

---

## 2. Findings

### The change feed exists — but it does not run
**CORRECTED, third pass.** `/sync/pull` and `/sync/change-logs` are implemented,
and the client is built to replicate 36 entities through them. But all three sync
endpoints returned 500 to every caller: see **P0-0**. The original sentence here
— "the client replicates 36 entities through them today" — was inferred from the
client calling pull, never from the server answering it. This plan is still not
about building a sync engine; it is about closing gaps in one that was written
but never actually served a request.

### `/sync/push` exists, is implemented, and the client never calls it
It is not a generic upsert and not a stub. It takes a batch, accepts a
client-supplied `entity_id`, is idempotent on create, returns per-item errors,
and routes through the real order service — but only for `orders`, `order_items`
and `attendances`. Every other entity is rejected. See P1-1.

### Credentials travel in the feed — confirmed
`log_change()` builds its payload as `to_jsonb(NEW)`, the whole row, with no
column filter (`8_movements.up.sql:42-72`). `users` carries `hash_password TEXT`
and `pincode VARCHAR(10)` (`1_core.up.sql`). Both reach every terminal in the
tenant, on both `/sync/pull` and `/sync/change-logs` — the latter returns the raw
payload verbatim (`service/sync.go:271-278`). The client redacts before writing
to disk, but redaction protects the disk, not the wire, and not any other
consumer of this feed.

### Eight tables have no trigger — but not the eight I listed
35 tables carry a `trg_change_log_*` trigger. One entry on my list,
`transaction_category`, is not a table at all. The corrected list is in P0-1.

---

## 3. Work

Ordered by what unblocks the most, with correctness ahead of features.

### P0-0 — The sync endpoints had no transaction and returned 500 to everyone

**Found while implementing P0-3. It outranks everything else in this document,
and it invalidates the premise of §2's first finding.** `/sync/pull`,
`/sync/push` and `/sync/change-logs` all returned
`tenant transaction not found in context`. Not for some callers or some tenants
— for every call, deterministically.

**Cause.** A half-finished refactor. `TenantMiddleware` used to open the tenant
transaction and set `search_path`; it no longer does, and says so itself:

> Note: DB transaction and search_path are NOT set here. They should be managed
> at service/repository layer where actual queries execute.

Since then every handler needing a transaction has had to call `BeginTenantTx`
itself — `handler/order.go` does, in three places. The three sync handlers were
never migrated. They kept forwarding `c.Request().Context()` straight to the
service, while `SyncS` kept reading its transaction out of that context and
refusing to run without one (`service/sync.go:52`, `:138`, `:214`).

Nothing caught it because nothing exercised these endpoints: the `handler`
package had no tests at all.

**This corrects §2.** "The change feed exists and is used… the client
replicates 36 entities through them today" was inferred from the client calling
`/sync/pull`, never from the server answering. The endpoint was there, the query
was there, and the response never came.

**Change.** Wire all three handlers the way `order.go` does: `BeginTenantTx`,
deferred `Rollback`, explicit `Commit`. The commit matters most on push, where
it is what makes the client's writes durable — without it the deferred rollback
discards the whole batch.

**STATUS: fixed and tested.** `internal/handler/sync.go` plus
`internal/handler/sync_tx_test.go`, on `claude/change-log-missing-triggers` in
`mary-ai-backend`. Not merged.

**Acceptance — run.** Against a real Postgres with migrations 1–70 applied and
five seeded entities: the old path errors, the new path returns
`next_sync_cursor=5` with all five entities, `modifiers`, `cash_registers` and
`printer_settings` among them — so P0-1 and P0-0 are verified together. The new
handler tests need no database: they stub `service.I`, and assert each handler
opens a transaction, passes the service a context carrying it, commits it, and
does not call the service at all when the transaction cannot be opened.
Reverting the fix fails them.

**What this means for everything below.** P0-3 is a silent-data-loss bug in a
feed that was not running. It is still real and still has to be fixed, but it
was never losing production data, because there was no production feed. The same
goes for P0-4's volume argument and for P0-2's exposure: **credentials were not
actually reaching terminals through pull**, because nothing reached terminals
through pull. P0-2 stays P0 — the payload is still unfiltered and
`/sync/change-logs` still returns it verbatim — but it becomes a live exposure
the moment P0-0 ships, rather than one that has already happened.

### P0-1 — Change-log triggers for eight tables

**CORRECTED — still eight, but not the same eight.** `transaction_category` is
not a table. It does not exist in any migration and has no endpoint in swagger.
What exists is `transaction_type`, a Postgres `ENUM` of six values — `income`,
`expense`, `transfer`, `transfer_income`, `transfer_expense`, `bill_payment` —
declared at the top of `11_transaction_category.up.sql`. The migration *filename*
is what misled me. An enum is static: nothing to replicate, and the client can
hardcode the six values in its filter.

There is a real missing table next to it, though. `group_transactions` is
referenced by `transactions.group_transaction_id` and has no trigger either, so
it takes the freed slot.

**Problem.** These tables do not replicate, so the screens that read them cannot
work offline and still call REST directly.

| Table | Blocks | Schema notes (verified) |
|---|---|---|
| `table_time_sessions` | Time-based table billing | `id UUID`, `deleted_at BIGINT`. **Highest value.** Drives `table_charge`, the largest line on a billiard/PS bill. Without it an entire table type cannot go offline, and the client's local totals engine cannot compute a bill it is otherwise fully capable of computing. |
| `modifiers` | Order screen modifier options | `id UUID`, `deleted_at BIGINT`. `order_item_modifiers` and `modifier_calculation` *are* logged, so the client replicates which modifiers an order used and what they cost — but not their names or prices. |
| `goods_modifiers` | Which modifiers a good offers | `id UUID`, `deleted_at BIGINT`. Same screen. |
| `transactions` | Cash ledger screen | `id UUID`, `deleted_at BIGINT`. |
| `group_transactions` | Grouped / cross-branch transfers | `id UUID`, `deleted_at BIGINT`. Takes the slot `transaction_category` wrongly occupied. |
| `printer_settings` | Printer configuration screen | `id UUID`, `deleted_at BIGINT`. **Correction, second pass:** an earlier draft called this a `SMALLINT` singleton with no `deleted_at`. That was migration 36. Migration 38 (`38_recreate_printer_settings.up.sql`) drops the table and recreates it as an ordinary multi-row UUID table — one row per printer, with `ip`, `port`, `type` and `connected_entity_ids`. Nothing special. |
| `cash_registers` | Register picker, shift assignment | `id UUID`, `deleted_at BIGINT`. |
| `cash_register_shifts` | Shift reconciliation | `id UUID`, `deleted_at BIGINT`. |

**VERIFY — all three answered.**

- **Primary key.** All eight are `id UUID`, so `log_change('id')` applies
  uniformly and every `entity_id` these triggers produce is a UUID string. The
  earlier claim that `printer_settings` was the exception came from reading
  migration 36 without noticing that 38 supersedes it. **The client still must
  not assume `entity_id` parses as a UUID**, but the reason is elsewhere in the
  feed, not here: `log_change` takes the PK column name as `TG_ARGV[0]`, and
  `bill_daily_counters` already uses `log_change('day')` — its `entity_id` is a
  date string. That table is in the feed today, so the constraint is live
  regardless of this migration.
- **Hard deletes.** All eight except `printer_settings` carry
  `deleted_at BIGINT DEFAULT 0`, so ordinary deletion is soft and arrives as an
  update, which the client already handles. But four of them sit behind
  `ON DELETE CASCADE` — `table_time_sessions.order_id` → `orders`,
  `.table_id` → `cafe_tables`, both `goods_modifiers` FKs, and
  `cash_register_shifts.cash_register_id` → `cash_registers`. A cascade **does**
  fire row-level `AFTER DELETE` triggers, so keeping all three events in the
  trigger is what makes those rows disappear on the client rather than linger.
  Keep `AFTER INSERT OR UPDATE OR DELETE`.
- **Brand scope.** `log_change` reads `current_setting('app.brand_id', true)` —
  a session GUC, not a column (`8_movements.up.sql:48`). New triggers inherit it
  with no extra work. Caveat: the `true` makes it return NULL rather than error
  when unset, so anything writing outside a request context — a migration, a
  background job — lands `brand_id` NULL. That is invisible today because pull
  never reads `brand_id` (open question 1), and would become a bug the moment
  someone adds the brand filter without backfilling.

**Change.** Next free tenant migration number is **70**. The whole file:

```sql
-- 70_change_log_missing_triggers.up.sql
DROP TRIGGER IF EXISTS trg_change_log_table_time_sessions ON table_time_sessions;
CREATE TRIGGER trg_change_log_table_time_sessions   AFTER INSERT OR UPDATE OR DELETE ON table_time_sessions   FOR EACH ROW EXECUTE FUNCTION log_change('id');

DROP TRIGGER IF EXISTS trg_change_log_modifiers ON modifiers;
CREATE TRIGGER trg_change_log_modifiers             AFTER INSERT OR UPDATE OR DELETE ON modifiers             FOR EACH ROW EXECUTE FUNCTION log_change('id');

DROP TRIGGER IF EXISTS trg_change_log_goods_modifiers ON goods_modifiers;
CREATE TRIGGER trg_change_log_goods_modifiers       AFTER INSERT OR UPDATE OR DELETE ON goods_modifiers       FOR EACH ROW EXECUTE FUNCTION log_change('id');

DROP TRIGGER IF EXISTS trg_change_log_transactions ON transactions;
CREATE TRIGGER trg_change_log_transactions          AFTER INSERT OR UPDATE OR DELETE ON transactions          FOR EACH ROW EXECUTE FUNCTION log_change('id');

DROP TRIGGER IF EXISTS trg_change_log_group_transactions ON group_transactions;
CREATE TRIGGER trg_change_log_group_transactions    AFTER INSERT OR UPDATE OR DELETE ON group_transactions    FOR EACH ROW EXECUTE FUNCTION log_change('id');

DROP TRIGGER IF EXISTS trg_change_log_printer_settings ON printer_settings;
CREATE TRIGGER trg_change_log_printer_settings      AFTER INSERT OR UPDATE OR DELETE ON printer_settings      FOR EACH ROW EXECUTE FUNCTION log_change('id');

DROP TRIGGER IF EXISTS trg_change_log_cash_registers ON cash_registers;
CREATE TRIGGER trg_change_log_cash_registers        AFTER INSERT OR UPDATE OR DELETE ON cash_registers        FOR EACH ROW EXECUTE FUNCTION log_change('id');

DROP TRIGGER IF EXISTS trg_change_log_cash_register_shifts ON cash_register_shifts;
CREATE TRIGGER trg_change_log_cash_register_shifts  AFTER INSERT OR UPDATE OR DELETE ON cash_register_shifts  FOR EACH ROW EXECUTE FUNCTION log_change('id');
```

The `.down.sql` is the eight `DROP TRIGGER IF EXISTS` lines alone.

**Note on existing rows.** A trigger only logs changes from the moment it exists.
The eight tables' current contents would never appear in the feed until each row
is next touched, so a client bootstrapping from cursor 0 gets nothing for them.
The fix is to seed one `create` per live row in the same migration, and the
`brand_id` question that blocked it in the last revision is now answered.

`log_change` reads the session GUC `app.brand_id`, which is set per request in
`withTenantRead`/`withTenantWrite` (`internal/service/tenant_read.go:33`,
`tenant_mutation.go:82`) to the brand **slug**, not a UUID. Migrations run with
no such GUC — but they do run with `search_path` bound to the tenant schema, and
that schema is always `tenant_<brand_id>` (`migrate.go`'s `validTenantSchema`,
`^tenant_[a-z0-9_]+$`). So the slug is recoverable from `current_schema()`
without knowing anything about how pull filters:

```sql
CASE WHEN left(current_schema(), 7) = 'tenant_'
     THEN substring(current_schema() FROM 8) END
```

which yields NULL for any schema not of that shape — the same value `log_change`
already writes outside a request context. This makes the seed independent of
open question 1 rather than blocked on it.

Two details the seed has to get right, both verified by running it:

- **Order parents before children** — `modifiers` before `goods_modifiers`,
  `cash_registers` before `cash_register_shifts`, `group_transactions` before
  `transactions` — so a client applying the feed in cursor order never sees a
  child row ahead of its parent.
- **Skip soft-deleted rows** (`WHERE deleted_at = 0`). A bootstrapping client
  never knew about them, and later deletions still arrive as ordinary trigger
  updates.

**STATUS: written and tested.** `70_change_log_missing_triggers.{up,down}.sql`,
on `claude/change-log-missing-triggers` in `mary-ai-backend`. Not merged.

**Acceptance — run, not just specified.** Migrations 1–69 were replayed into a
scratch Postgres 16 schema `tenant_testbrand`, rows were inserted into all eight
tables *before* migration 70, and then 70 was applied. Results:

- The backfill produced exactly one `create` per live row across all eight
  entities, with `brand_id = 'testbrand'` — correctly derived from the schema
  name — and parent-first cursor ordering.
- A soft-deleted `modifiers` row was correctly skipped.
- Post-migration: `INSERT` → `create`, `UPDATE` → `update`, soft delete
  (`UPDATE deleted_at`) → `update`, hard `DELETE` → `delete`.
- **The cascade claim above is confirmed, not assumed.** Deleting a
  `cash_registers` row logged its own `delete` *and* a `delete` for the
  `cash_register_shifts` row that cascaded from it.
- With no `app.brand_id` set (the cron path), the insert succeeds and lands
  `brand_id` NULL rather than erroring — the caveat above, reproduced.
- The `.down.sql` drops exactly the eight new triggers, leaves the 34
  pre-existing ones untouched, and preserves every `change_log` row.

Still unverified because it needs a real deployment: that a client `/sync/pull`
from a cursor below the backfill actually renders these entities.

**Client payoff.** Four screens migrate; `main_datasources.dart` — the last file
in the client that speaks HTTP — can then be deleted, along with the Hive store
that still shadows the replica.

**Effort.** Small. This is the highest value-to-effort item here by a wide margin.

---

### P0-2 — Stop shipping credentials in the feed

**Problem.** Every terminal in a venue receives every user's `hash_password` and
`pincode` on the wire, and any future consumer of `/sync/pull` or
`/sync/change-logs` gets them too.

**Confirmed.** `log_change()` has no column filter of any kind — the payload is
`to_jsonb(NEW)` for insert/update and `to_jsonb(OLD)` for delete
(`8_movements.up.sql:52-66`). Nothing downstream strips anything:
`/sync/change-logs` returns the payload verbatim (`service/sync.go:271-278`).

**Change.** Strip them at the source. Postgres has no per-column trigger payload
filter, so the exclusion has to live inside `log_change`, as a
`CREATE OR REPLACE FUNCTION` with no trigger changes:

```sql
IF TG_TABLE_NAME = 'users' THEN
  v_payload := v_payload - 'hash_password' - 'pincode' - 'fcm_token' - 'password';
END IF;
```

**Four keys, not the two this section originally listed.** A scan of every
credential-shaped column in the tenant schema turned up one more that is in the
feed:

- `fcm_token` — the push notification token. Not a password, but a capability:
  whoever holds it can push notifications to that user's device. It matters more
  than its severity suggests, because the client's redaction list
  (`lib/core/db/entity_registry.dart:401`) is `{hash_password, pincode,
  password}` — `fcm_token` is not in it. **It is the only one of the three that
  currently reaches terminal disk in the clear**, precisely because the
  defence-in-depth layer does not know about it.
- `password` is stripped defensively. `users` has no such column, the strip is a
  no-op when the key is absent, and it means a plaintext column added later
  cannot start replicating silently.

`pos_auth_settings.pos_password_hash` is deliberately untouched: that table has
no `change_log` trigger, so it never enters the feed. It must not gain one
without extending this filter.

Historical rows need a companion `UPDATE` in the same migration, or the
acceptance criterion below passes on new rows and fails on a bootstrap.

**Also.** `POST /users` and `POST /auth/register` take a plaintext `password`. The
client's outbox has to store that payload on disk to send a staff create queued
offline. That is a narrower exposure than a replicated column, and it is inherent
to offline creation — but it is worth a decision rather than an accident: either
accept it, or rule that staff creation requires connectivity.

**STATUS: written and tested.** `71_change_log_redact_credentials.{up,down}.sql`,
on `claude/change-log-missing-triggers` in `mary-ai-backend`. Not merged.

**Urgency changed with P0-0.** Until the sync endpoints were fixed this was
latent — the feed returned 500, so nothing leaked. Shipping P0-0 without this
would convert it into a live exposure, which is why it went next.

**Acceptance — run, not just specified.** Credentials were seeded into
`change_log` *before* applying the migration, so the historical path was really
exercised:

- All three pre-existing `users` rows — including one written by the migrations'
  own seed — came out with `hash_password`, `pincode` and `fcm_token` absent.
- After the migration, `create`, `update` and `delete` all write clean payloads.
  Delete matters on its own: it takes the `to_jsonb(OLD)` branch, so a filter
  placed inside the `IF` block would have missed it.
- The 14 user fields the client actually needs are untouched (`id`, `full_name`,
  `username`, `role`, `branch_id`, `shift_id`, `cash_register_id`, `is_active`,
  `email`, `phone_number`, …), and non-`users` entities are unaffected.
- The down migration restores the unfiltered function but leaves the history
  scrubbed. That asymmetry is deliberate: a rollback should not be able to
  republish credentials.

**Still open:** `email` and `phone_number` stay in the feed. They are PII rather
than credentials and are plausibly needed by staff screens, so removing them is a
product call, not a security fix.

---

### P0-3 — The cursor can skip rows (confirmed)

**This is the most important item here and the least visible.** Everything else
degrades loudly. This one loses data silently.

**Problem.** If `next_sync_cursor` is a bare `bigserial` on `change_log`, the feed
can skip rows, permanently, with no symptom.

Sequence numbers are assigned when a row is inserted, but rows become visible
when their transaction commits, and those orders differ:

1. Transaction A inserts `change_log` id 100 and is still open.
2. Transaction B inserts id 101 and commits.
3. A client pulls, sees 101, stores cursor 101.
4. Transaction A commits. Row 100 is now visible.
5. The client only ever asks for rows above 101. **Row 100 is never delivered.**

The client cannot detect this. Its cursor advanced legitimately, its gap
detection (which exists for the LAN relay) sees no gap, and the missing row looks
exactly like a row that was never written. It surfaces weeks later as a menu item
that is wrong on one terminal, or a table that never went free.

**VERIFIED — this is live.** The column is `id BIGSERIAL PRIMARY KEY`
(`8_movements.up.sql:29`) and the pull query is
`WHERE id > $1 ORDER BY id ASC LIMIT $2` (`service/sync.go:56-62`). There is no
commit-time ordering, no watermark, and no lag. The scenario above is not
hypothetical; its frequency scales with concurrent write load, which is exactly
when a venue is busy.

Worth being precise about the blast radius, because it is wider than the feed:
`log_change` fires inside the writing transaction, so a slow order-and-payment
transaction holds its `change_log` rows invisible for as long as it runs while
faster transactions commit past it. Orders and payments are the longest
transactions in this system.

**Change. CORRECTED — both options the previous revision proposed are wrong,
and I worked that out before writing either of them.**

**The safety lag does not do what its name says.**
`committed_at timestamptz DEFAULT clock_timestamp()` records the moment of
*insert*, not of *commit*. A transaction that inserts at T and commits at T+10s
carries `committed_at = T`. At T+2 the row passes the two-second test while
still being uncommitted and therefore invisible; a client pulling at T+3 sees
nothing and advances past it. The lag only helps when transactions are shorter
than the lag — and this document already says the longest transactions in the
system are orders and payments, which are exactly the ones at risk. It fails
precisely where it is needed. Getting a true commit timestamp needs
`track_commit_timestamp` and `pg_xact_commit_timestamp(xmin)`, which is a
different and much less trivial change.

**The snapshot horizon is right in spirit but does not work with an `id`
cursor.** Filtering `xmin < pg_snapshot_xmin(pg_current_snapshot())` while still
ordering and cursoring by `id` still skips rows:

1. Txn D (xid 100) inserts `change_log` id 4. Still open.
2. Txn C (xid 99) inserts id 5 afterwards, and commits.
3. A client pulls. Horizon is 100, because D is the oldest in flight. Row 5 has
   xid 99 < 100, so it is eligible — delivered, cursor becomes 5.
4. D commits. Row 4 is now visible, below a cursor that has already passed it.

Note what breaks it: **id order and xid order can disagree**, and the row that
gets skipped is *invisible* at pull time. So you cannot repair this by
truncating the batch at the first row with `xid >= horizon` — the row causing
the problem is not in the result set to be found. Any fix has to make
eligibility depend on something knowable about rows you cannot yet see.

Two that actually hold:

- **Order by xid; cursor becomes an `xid8`.** Correct by construction: once
  `xid < horizon`, every row from that transaction is visible-or-never, and no
  future row can ever carry a lower xid. The cost is that `next_sync_cursor`
  changes meaning, so every deployed terminal needs its stored cursor translated
  or a full re-bootstrap.
- **Watermark table, server-only.** Periodically record the pair
  `(pg_sequence_last_value('change_log_id_seq'), pg_snapshot_xmax(pg_current_snapshot()))`.
  A recorded pair `(S, M)` becomes safe once the live `pg_snapshot_xmin` reaches
  M: every transaction that was in flight when S was observed has finished by
  then, so every id ≤ S is now visible-or-never. Deliver
  `WHERE id > cursor AND id <= W`, where W is the largest such S. The `id` cursor
  keeps its exact current meaning.
- **Logical replication.** Still correct by construction, still a much larger
  change. Only if the feed becomes load-bearing beyond this app.

**I would take the watermark**, on deployment grounds rather than elegance: it
needs no client change. Terminals in venues update on their own schedule, so a
fix that requires a client release does not protect the installs that already
exist. It costs a small table, a background tick, and roughly one poll cycle of
extra latency on freshly-committed rows.

**STATUS: implemented and tested — as the watermark.** Migration
`72_change_log_watermark.{up,down}.sql`, `SyncS.ObserveWatermark` and the bounded
query in `service/sync.go`, the two-transaction sequence in
`handler/sync.go:SyncPull`, and `TestSyncPullObservesWatermarkInAnEarlierCommittedTx`.
Committed on the backend branch as `45bb4b3`.

**Reproduced before it was fixed.** Two concurrent sessions against a real
database, migrations 1–71: session D inserted `change_log` id 2 and stayed open,
session C inserted id 3 and committed. The pull returned **id 3 alone**, the
cursor a client would store advanced to 3, and id 2 appeared only after D
committed — permanently beneath the cursor. This is no longer a scenario
argued from the schema; it is a run.

**Two things the recommendation above got wrong, both found in the building.**

**It does not need a background tick.** The plan proposed observing periodically.
Observing at the *start of each pull*, in its own transaction, is strictly
better: it costs no new infrastructure, it self-scales (more terminals means more
observations), and it makes the freshness of the watermark a property of the
thing that consumes it.

**Therefore it does not cost "roughly one poll cycle of extra latency."** That
estimate assumed the observation and the pull are independent. Ordered
observation-then-pull inside one request, the cost in the common case is
approximately zero: the observing transaction commits, and with no other writer
in flight the next snapshot's `xmin` has already passed the `xmax` it recorded,
so the watermark is current and the pull delivers everything. Latency appears
only while a long write is genuinely in flight, and is bounded by *that
transaction*, not by a fixed lag or a tick interval. This is the property the
rejected safety-lag option could not have: it holds back exactly the rows that
are at risk, for exactly as long as they are at risk.

**The ordering is load-bearing, and silently so.** The observation must be
committed *before* the pull's transaction opens. A transaction's own xid always
sits below the boundary it records, so an observation read back inside the
transaction that wrote it is never yet safe — it excludes itself. Folding the
two into one transaction still returns correct data, but pins the feed a full
poll cycle (60s, `sync_engine.dart:66`) behind, forever. No correctness test
would catch that, which is why the handler test asserts the event order
(`begin/observe/commit`, then `begin/pull/commit`) rather than just the outcome.

**A dependency the plan did not state: the sequence must have `CACHE 1`.** The
whole argument rests on ids being handed out in the order rows are inserted. A
cache above 1 lets a session hold a block of low ids and use one long after
another session used a higher one, and then "every id ≤ S is settled" is simply
false. Verified on the live schema (`cache 1, increment 1` — the `BIGSERIAL`
default) rather than assumed, and recorded in the migration at the point of use
so a future tuning pass cannot quietly invalidate it.

**Acceptance — run.** The test this section specified, executed against a real
database through the actual service layer:

```
baseline drained, cursor = 1
txn D inserted its change_log row and is still open
txn C inserted and COMMITTED, above D's id

pull while D is open   -> cursor 1 -> 1, delivered {}          <- cursor HELD
txn D committed
pull after D commits   -> cursor 1 -> 3, delivered {modifiers:2}
```

Both rows delivered, in id order, nothing skipped — against the pre-fix run on
the same scenario, which advanced the cursor to 3 and stranded row 2.

**The stall is benign, and this was checked rather than assumed.** While a long
write is in flight the pull returns an empty page and echoes the incoming cursor
rather than zero (`nextCursor := lastCursor`, advanced only per delivered row).
The client treats a short page as "caught up" and retries on its next tick
(`replication_service.dart:169`), and independently guards a missing cursor as
"no advance" rather than zero (`sync_api_client.dart:92`). So a watermark stall
is indistinguishable from being up to date, and nothing rewinds. `SyncPullPage.empty`
carries `nextCursor: 0`, which would rewind — it is dead code, referenced
nowhere, and was checked for exactly that reason.

**Followers inherit this for free.** The LAN relay forwards batches the leader
pulled, so a watermark-bounded leader feed makes the follower feed
watermark-bounded too. No change to `change_feed_relay.dart`.

**Not changed: `/sync/change-logs`.** It is a filtered admin/debug endpoint, not
the cursor-based replication path, and no client replicates from it.

---

### P0-4 — `/sync/pull` returns every branch's rows to every terminal

**New. Found during verification, not present in the first draft.**

**Problem.** The pull query filters on the cursor and nothing else:

```sql
SELECT id, brand_id, entity, action, entity_id, payload
FROM change_log
WHERE id > $1
ORDER BY id ASC
LIMIT $2
```

`brand_id` is populated on write and never read on the way out. There is no
branch predicate anywhere. The only thing separating tenants is the schema the
connection is bound to, so within one tenant a terminal in branch A replicates
branch B's orders, tables, shifts, cash registers and staff.

Two costs, and the second is the one that will be noticed first:

- **Correctness.** A floor plan can show another venue's tables; a staff list
  another venue's employees. The client has no branch filter of its own — it
  trusts the feed, which is what §1 said it does.
- **Volume.** Every terminal pays for every branch's write traffic, on every
  poll, forever. A ten-branch tenant multiplies both the feed and each terminal's
  local database by ten. This also compounds P2-1: bootstrap replays all
  branches' history.

**Change.** Add the predicate to the pull query, from the caller's token — push
already resolves `branch_id` from context (`checkUserBranchInPayload` reads
`ctx.Value("branch_id")`), so the plumbing exists.

The obstacle is that `change_log` has no `branch_id` column, only `brand_id`, and
the branch is a property of the payload rather than of the log row. Two ways:

- **Add `branch_id` to `change_log`** and have `log_change` populate it from
  `current_setting('app.branch_id', true)` the same way it does brand. Cleanest,
  and **the GUC plumbing already exists** — checked while implementing P0-1:
  `withTenantRead` and `withTenantWrite` already issue
  `SET LOCAL app.branch_id = $1` immediately after `app.brand_id`
  (`tenant_read.go:38`, `tenant_read.go:80`, `tenant_mutation.go:88`), and
  several generated queries already read it back as
  `NULLIF(current_setting('app.branch_id', true), '')::uuid` (`shipments.sql.go`,
  `reports.sql.go`). So `log_change` can populate a `branch_id` column today with
  no middleware change at all. Two caveats: the GUC is set only when the token
  carries a branch (`if strings.TrimSpace(branchID) != ""`), so brand-scoped
  admin calls still land NULL; and `cron.go:71` sets `search_path` only, so
  background jobs land NULL too. Historical rows also need a backfill decision.
  Note that NULL is *also* the correct value for genuinely branch-less reference
  data, so the pull predicate has to keep an `IS NULL` escape hatch either way —
  the column does not remove that, it just makes it indexable.
- **Filter on the payload** — `WHERE payload->>'branch_id' = $2 OR payload->>'branch_id' IS NULL`.
  No schema change, but unindexed, and the `IS NULL` escape hatch has to stay
  because branch-less entities (goods, categories, translations, modifiers) must
  reach everyone.

I would take the column. The payload filter turns the hottest query in the system
into a JSONB scan.

**VERIFY before implementing.** Whether a tenant schema is ever expected to hold
more than one branch in production. If the deployment model is one branch per
tenant schema, this is latent rather than live and drops to P2. The schema
plainly supports many: `branches` is a table, and `branch_id` is a column on 24
others including `orders`, `users`, `halls`, `shifts`, `transactions` and
`cash_registers`. But the deployment may not use it. **This is the one item here whose
priority I cannot set from the source alone.**

**Acceptance.** Two branches in one tenant; a terminal authenticated to branch A
pulls from cursor 0 and receives no row whose payload carries branch B's id,
while still receiving all branch-less reference data.

---

### P1-1 — `/sync/push` is implemented, and its allowlist is the inverse of what I recommended

**ANSWERED — no server work required.** `service/sync.go:137-211`,
`handler/sync.go:48-64`. All five questions, in order:

- **Implemented, not a stub.** Routed at
  `sync.POST("/push", h.SyncPush)` behind `CheckTerminalOrUserAuth` +
  `TenantMiddleware` (`handler/handler.go:75-79`) — the same guard as pull.
- **It validates against a hard allowlist**, not a table name: a `switch` over
  `orders`, `order_items`, `attendances`, with `default: "entity not allowed for
  push"`. There is no generic upsert path and no way to reach an arbitrary table.
- **It runs business logic.** It builds an `OrderS` and delegates
  (`applyOrderChange` → `createOrderFromPayload` / `updateOrderFromPayload`),
  validating that `table_id` resolves to a real cafe table before writing.
- **Creates are idempotent on `entity_id`.** `createOrderFromPayload` opens with
  `if _, err := GetOrderByID(ctx, id); err == nil { return nil }` — a replayed
  create is a no-op, not a duplicate and not an error.
- **`SyncPushError` is per item** — `{index, entity, action, error}` — and the
  loop continues past a failure, so one bad row does not reject the batch.

It also does something I did not anticipate: for `orders` it calls
`checkUserBranchInPayload`, which rejects a `cashier_id` or `waiter_id` belonging
to another branch, and rejects the request outright when the token carries no
`branch_id`. That is the only branch enforcement anywhere in the sync surface —
push has it and pull does not.

**My recommendation was backwards, and the server is right.** I proposed
allowlisting the entities *with no server-side invariants* — halls, tables,
printer settings — and keeping REST for orders and payments "where the server's
logic is the point". The allowlist that exists is the exact inverse: the three
entities with the *most* logic, routed through the service that owns it, with
reference data excluded. That is the better design, for the reason my version
missed. Push exists to serve the offline write path, and the offline write path
is orders. Reference data is edited by an admin who is online; it does not need a
replay-safe batch endpoint.

**So the consequences run the other way than I wrote them:**

- **P1-2 is not made redundant by push — it is made necessary by it.** Halls,
  tables, categories, goods and translations will never travel through push as
  built. Client-supplied ids on their REST creates is the only route left for
  them, so P1-2 stands in full rather than "only for whatever stays on REST".
- **Nothing gets deleted from the spec.** Push is not a decoy endpoint.
- **There is a client-side refactor available, and it is optional.** The outbox
  handlers for orders, order items and attendances could collapse onto a single
  batched push call, which is closer to what an outbox drain wants than N
  sequential REST calls. Against it: the REST order endpoints already accept
  client ids, are already idempotent, and are already tested end to end. This is
  a nice-to-have with no server dependency — not a blocker, and not urgent.

**The one thing worth asking the server team.** Push writes orders through the
service layer, but `applyOrderChange`'s delete branch calls
`repo.Tenant(ctx).DeleteOrder(ctx, id)` directly, bypassing `OrderS`. If order
deletion has invariants — releasing a table, closing a time session, reversing
stock — push skips them. The client does not delete orders today, so this is
latent rather than live, but it is the one seam in an otherwise careful endpoint.

---

### P1-2 — Accept client-supplied ids on create

**Problem.** No create endpoint accepts an `id`: `RegisterRequest`,
`CreateHallRequest`, `CreateCafeTableRequest`, `CreateCategoryRequest`,
`CreateGoodRequest` and `CreateTranslationRequest` all omit it. `CreateOrder`
does accept one, and that asymmetry is the reason orders were straightforward to
make offline and everything else was not.

**Change.** Accept an optional `id` on those creates. When supplied and unknown,
use it. When supplied and already known, return the existing row rather than
erroring — that is what makes a replayed create idempotent, and it is what
`CreateOrder` already does.

**Payoff.** The client's provisional-id and reference-rewriting machinery becomes
dead code and gets deleted. Every created row keeps one id for its whole life,
which also removes a class of bug I cannot fully rule out: a create whose
response is lost after the server committed it. Today the client retries, the
server creates a second row, and nothing reconciles them. With client ids, the
retry is idempotent.

**That last point may matter more than the code deletion.** A duplicated hall is
an annoyance; a duplicated staff record with working credentials is not.

**No longer overlaps P1-1.** I originally wrote that push might make this
unnecessary. It does not: push's allowlist is `orders`, `order_items`,
`attendances` only, so every entity named above stays on REST permanently. This
item is needed in full.

---

### P1-3 — Client-supplied ids on `CreateOrderItems`

**Problem.** `order.go` reads `entry.GoodID` and `entry.Quantity` but no
`entry.ID`, so line items get server-assigned ids on replay. Local item ids are
provisional until the order's next pull.

**Change.** Same as P1-2, one endpoint. Small, and it makes items behave exactly
like the order that contains them.

---

### P2-1 — Bootstrap snapshot endpoint

**Problem.** `change_log` has no compaction, so `last_sync_cursor = 0` replays
every mutation in the tenant's history — including rows since deleted. It is
correct and it is O(all writes ever). The client caps bootstrap at 20 000 batches
of 500 and treats running out as "partially populated, later ticks finish",
which is survivable but not good.

**Change.** `GET /api/v1/sync/snapshot` returning current rows per entity plus
the cursor to resume from. The client's applier consumes the same
`{changes, next_sync_cursor}` shape, so this is a new source for an existing
parser, not a new format.

**When this becomes urgent.** When first login on a new terminal takes long
enough that someone reaches for the power button. That threshold arrives on its
own as history accumulates.

---

### P2-2 — `change_log` retention

**Problem.** Unbounded growth on a hot table with three indexes.

**Change.** Compact to one row per `(entity, entity_id)` beyond N days, or
partition by month and drop old partitions.

**Constraint that makes this subtle.** Compaction must not move the cursor of any
live client backwards past its own position. A terminal offline for the retention
window and then reconnecting must be detected and sent to bootstrap rather than
silently resumed from a cursor whose rows are gone. That needs a documented
minimum — "a terminal offline longer than N days re-bootstraps" — and a server
response the client can recognise. **Do P2-1 before this**, or the recovery path
does not exist.

---

## 4. Sequencing

Revised now that the verification is done. P1-1 leaves the list — it was a
question, and it has been answered with "the server is already correct". A new
item enters at the top, because the pull query turned out to have no scoping at
all.

| Order | Item | Why here |
|---|---|---|
| 0 | **P0-0 sync had no transaction** | **Fixed.** Every sync endpoint returned 500. Nothing below matters until the feed answers at all, and every item's severity is measured against a feed that was not running. |
| ~~1~~ | **P0-3 cursor skew** | **Done.** Reproduced against a real database first — the pull skipped a row permanently — then fixed with the watermark, and the same scenario re-run green. Cost less than predicted: no background tick, and no per-row latency. |
| 2 | **P0-4 branch scoping on pull** (new) | Every terminal receives every branch's rows. Correctness and volume, and it gets harder to add the longer `brand_id` stays unpopulated on some rows. |
| 3 | P0-1 eight triggers | Unblocks four screens and the deletion of the client's last HTTP file. Small, and the migration is written out in full above. |
| ~~4~~ | **P0-2 credentials** | **Done.** Moved ahead of P0-3 and P0-4 because P0-0 is what makes it live: the fix that got the feed working is the fix that would have started the leak. |
| 5 | P1-2 / P1-3 client ids | Deletes client machinery; fixes lost-response duplicates. Confirmed necessary — push does not cover these entities. |
| 6 | P2-1 snapshot | Before retention, because it is the recovery path. |
| 7 | P2-2 retention | Operational; the pressure is gradual. |
| — | ~~P1-1 decide push~~ | **Done. No work.** Push is implemented and correctly scoped; see P1-1. |

P0-1 through P0-4 are independent and can run in parallel.

---

## 5. What the client does in response

So the payoff is concrete:

- **After P0-1**: four screens migrate to the replica; `main_datasources.dart`
  and the Hive `LocalDatabase` are deleted; the architecture ratchet reaches
  zero and "exactly one database" becomes true.
- **After P0-0**: the feed answers at all. Every payoff below this line was
  previously gated on an endpoint that returned 500, including the 36 entities
  the client already believes it replicates.
- **After P0-2**: the client's redaction stays as defence in depth, but stops
  being the only thing standing between a venue's terminals and its password
  hashes — and `fcm_token`, which that redaction never covered, stops being
  replicated at all.
- **After P0-4**: the client's replica shrinks to its own branch, and bootstrap
  stops replaying other venues' history. No client code changes — it already
  trusts the feed; the feed just gets smaller and correct.
- **After P1-2/P1-3**: provisional ids and reference rewriting are deleted. The
  per-entity outbox handler layer stays — push does not cover those entities, so
  the earlier claim that it might all go was wrong.
- **After P2-1**: first login on a new terminal stops being a full history
  replay.

---

## 6. Open questions — answered

All but one, from `mary-ai-backend@3533b8b`.

1. **Does `/sync/pull` scope to the caller's branch?** **No — and it does not
   scope by brand either.** The query filters on the cursor alone
   (`service/sync.go:56-62`); `brand_id` is written to every row and never read
   back. Isolation is per-tenant-schema only, so a tenant with two branches
   ships both branches' rows to every terminal in both. Ironically `/sync/push`
   *does* enforce branch ownership (`checkUserBranchInPayload`) — the write path
   is stricter than the read path. Raised as **P0-4** in the sequencing above.

2. **Is the cursor a bare sequence?** **Yes.** `id BIGSERIAL PRIMARY KEY`
   (`8_movements.up.sql:29`). P0-3 is live.

3. **Is `/sync/push` implemented, and what does it validate?** **Implemented**;
   hard allowlist of `orders`, `order_items`, `attendances`; runs the real order
   service; idempotent creates; per-item errors; branch check on orders. Full
   detail in P1-1.

4. **Are any of the eight tables hard-deleted?** Not in the ordinary path — all
   but `printer_settings` carry `deleted_at BIGINT DEFAULT 0`. But four sit
   behind `ON DELETE CASCADE`, and cascades do fire row triggers, so the
   `AFTER ... DELETE` clause is doing real work and must stay.

5. **Does `log_change` derive brand scope from a session variable or a column?**
   **Session variable**: `current_setting('app.brand_id', true)`
   (`8_movements.up.sql:48`). New triggers inherit it for free. The `true`
   suppresses the error when it is unset, so writes outside a request context
   record `brand_id` NULL — harmless today, a trap for whoever implements P0-4.

6. **What is the current `change_log` row count and growth rate?** **Still
   unknown.** This is the only question the source cannot answer; it needs
   `SELECT count(*), min(changed_at), max(changed_at) FROM change_log` against a
   production tenant. It sets the urgency of P2-1 and P2-2 and nothing else.

7. **Is there an existing integration test for `/sync/pull`?** No test targets
   sync directly, but the harness P0-3's test needs already exists:
   `app/tests/branch_detail_isolation_test/isolation_test.go` runs a real
   Postgres via testcontainers, applies the tenant migrations with
   `golang-migrate`, and sets `search_path` per tenant schema specifically so the
   `change_log` triggers resolve. A `sync_cursor_skew_test` alongside it can copy
   that `TestMain` wholesale — which makes P0-3's acceptance test a few hours of
   work rather than a project.

---

## 7. What changed, by revision

**Fourth pass — implementing P0-3.**

- **The bug was reproduced before it was fixed.** Two concurrent sessions against
  a real database made the pull skip a row permanently. Everything this document
  said about P0-3 was inference from the schema until that run; a fix for a
  silent bug is worth very little without a test that fails first.
- **The watermark cost less than I estimated.** No background tick — observing
  once per pull, in its own committed transaction, is simpler and self-scaling.
  And near-zero added latency in the common case, not the "roughly one poll
  cycle" this document predicted, because the observation now happens inside the
  request that consumes it.
- **The observation's transaction boundary is load-bearing and invisible.**
  Committing it separately from the pull is what makes the watermark current; the
  natural-looking simplification of folding it into the pull's transaction leaves
  the feed permanently 60s stale while every correctness test still passes. The
  handler test asserts the ordering for that reason.
- **The design rests on `CACHE 1`, which this document never mentioned.** Verified
  on the live sequence rather than assumed, and written into the migration so a
  later tuning change cannot silently invalidate the whole argument.
- **The client's behaviour under a watermark stall was checked, not assumed.**
  Empty page, cursor echoed, read as "caught up", retried next tick — plus one
  piece of dead code (`SyncPullPage.empty`) that would have rewound the cursor to
  zero had anything referenced it.

**Third pass — implementing P0-1, and starting P0-3.** Written while actually building
against a scratch Postgres, which is why these are corrections to the *second*
pass rather than to the original:

- **P0-2 shipped, and it grew a third key.** A scan for credential-shaped
  columns found `fcm_token` in the feed alongside `hash_password` and `pincode`.
  It is the one the client's own redaction list misses, so it was the only one
  of the three actually reaching terminal disk in the clear. Ordered ahead of
  P0-3 and P0-4 because P0-0 is what makes the exposure live.
- **New P0-0, and it is the biggest thing here: the sync endpoints did not
  work.** All three returned `tenant transaction not found in context` to every
  caller, because a refactor moved transaction management out of
  `TenantMiddleware` and the sync handlers were never updated. Fixed and tested.
  This retires §2's claim that the client "replicates 36 entities through them
  today", and it rescales every other item — P0-3 was losing no data and P0-2
  was exposing no credentials, because nothing was being served.
- **Both of P0-3's proposed fixes were wrong.** The safety lag timestamps the
  insert rather than the commit, so it fails for exactly the long transactions it
  was meant to protect. The snapshot horizon is sound but not with an `id`
  cursor — id order and xid order can disagree, and the skipped row is invisible
  at pull time, so it cannot be detected by filtering what you can see. Replaced
  with two options that hold, and a recommendation that turns on deployment
  rather than elegance.

- **`printer_settings` is an ordinary UUID table, not a `SMALLINT` singleton.**
  The second pass read migration 36 and did not notice that migration 38 drops
  that table and recreates it — multi-row, UUID PK, with `deleted_at`. So all
  eight tables are uniform, `entity_id` is a UUID for all eight, and the special
  case the plan warned about does not exist. The client-side rule survives for a
  different reason: `bill_daily_counters` logs under `log_change('day')`.
- **The seed's `brand_id` is no longer blocked on open question 1.** The tenant
  schema is always `tenant_<brand_id>`, so the slug comes out of
  `current_schema()`. The seed shipped in the same migration, as the second pass
  recommended it should.
- **The cascade behaviour is now demonstrated rather than argued.** Deleting a
  `cash_registers` row logs both its own delete and the cascaded
  `cash_register_shifts` delete.
- **P0-4's cheaper half is cheaper than stated.** The `app.branch_id` GUC is
  already set on every tenant transaction and already read by other queries, so
  adding `branch_id` to `change_log` needs no middleware work.

**Second pass — verification against `mary-ai-backend@3533b8b`:**

- **P0-3 went from "verify" to "confirmed live."** Bare `BIGSERIAL`, no lag.
- **P0-1's table was wrong in one row.** `transaction_category` is an enum, not a
  table; `group_transactions` takes its place.
- **P0-1 gained a step I had missed**: triggers do not backfill, so the eight
  tables stay empty on a bootstrapping client until each row is next touched
  unless the migration seeds `change_log`.
- **P1-1's recommendation was inverted and is withdrawn.** Push is implemented
  and its allowlist is better than the one I proposed. No server work.
- **P1-2 is confirmed necessary** rather than possibly redundant.
- **A new P0-4**: `/sync/pull` has no branch or brand filter at all.
