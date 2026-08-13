# Server-side plan for offline-first

**Scope.** Work that has to happen in the backend for the client's offline-first
migration to finish. Written after the client side landed, so every item here is
something the client is either blocked on, working around, or depending on
without a guarantee.

**Not to be confused with `BACKEND_SYNC_PLAN.md`**, which despite its name covers
the *client's* sync layer (`SyncEngine`, `LeaderElectionService`, `LeaseManager`).
This document is about the server.

**What I could and could not see.** I worked from `api-docs/swagger.json`, the
client's entity registry, and the client's sync code. I have not seen the server
source or the database schema. Items below marked **VERIFY** are things I am
inferring from the API surface and could be wrong about; they are written as
questions with a recommended answer, not as instructions.

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
6. **Scoping is derived from the token.** `SyncPullRequest` has no branch or brand
   parameter, so the server decides what a terminal may see. **VERIFY**: a
   terminal must receive its own branch's rows and no other branch's — both for
   correctness (a floor plan showing another venue's tables) and for volume.

### What the client sends

Writes do **not** go through `/sync/push`. They go to the ordinary REST
endpoints, one bespoke outbox handler per entity. See P1-1 — this may be the
wrong choice, and the server already has the better one.

---

## 2. Findings

### The change feed exists and is used
`/sync/pull` and `/sync/change-logs` are implemented and the client replicates 36
entities through them today. This plan is not about building a sync engine; it is
about closing specific gaps in one that works.

### `/sync/push` exists and the client never calls it
`SyncPushChange` is `{entity, entity_id, action, payload}` — the exact shape of
the client's outbox row, including a **client-supplied `entity_id`**. If it does
what its shape suggests, it is a generic write path that would delete an entire
layer of client code and close the id problem outright. It is also the single
riskiest thing in this document if it bypasses business logic. See P1-1.

### Credentials travel in the feed
`ChangeLogEntry.payload` is the whole row, so `users` rows carry `hash_password`
and `pincode` to every terminal in the venue. The client redacts both before
writing to disk, and as of this week `password` too — but redaction protects the
disk, not the wire, and not any other client that ever consumes this feed.

### Eight tables have no trigger
Listed in P0-1. Four client screens cannot be migrated at all until they land;
they are the only remaining entries on the client's architecture ratchet.

---

## 3. Work

Ordered by what unblocks the most, with correctness ahead of features.

### P0-1 — Change-log triggers for eight tables

**Problem.** These tables do not replicate, so the screens that read them cannot
work offline and still call REST directly.

| Table | Blocks | Notes |
|---|---|---|
| `table_time_sessions` | Time-based table billing | **Highest value.** Drives `table_charge`, the largest line on a billiard/PS bill. Without it an entire table type cannot go offline, and the client's local totals engine cannot compute a bill it is otherwise fully capable of computing. |
| `modifiers` | Order screen modifier options | `order_item_modifiers` and `modifier_calculation` *are* logged, so the client replicates which modifiers an order used and what they cost — but not their names or prices. |
| `goods_modifiers` | Which modifiers a good offers | Same screen. |
| `transactions` | Cash ledger screen | |
| `transaction_category` | Its filter list | |
| `printer_settings` | Printer configuration screen | |
| `cash_registers` | Register picker, shift assignment | |
| `cash_register_shifts` | Shift reconciliation | |

**Change.** One trigger each, following the existing pattern:

```sql
CREATE TRIGGER trg_change_log_table_time_sessions
  AFTER INSERT OR UPDATE OR DELETE ON table_time_sessions
  FOR EACH ROW EXECUTE FUNCTION log_change('id');
```

**VERIFY** before writing these:
- Is the primary key `id` on all eight? The client keys every entity by `id`.
- Do any use hard deletes? The trigger must fire `AFTER DELETE` and capture the
  id from `OLD`, or the client will keep a row that no longer exists. Soft
  deletes arrive as updates and the client already handles `deleted_at`.
- Does `log_change` scope by brand automatically, as `ChangeLogEntry.brand_id`
  suggests? If it reads a session variable, these triggers inherit that; if it
  reads a column, all eight need one.

**Acceptance.** For each table: make a change, then confirm a `/sync/pull` from a
cursor before it returns the row, and that a fresh client bootstrap includes it.

**Client payoff.** Four screens migrate; `main_datasources.dart` — the last file
in the client that speaks HTTP — can then be deleted, along with the Hive store
that still shadows the replica.

**Effort.** Small. This is the highest value-to-effort item here by a wide margin.

---

### P0-2 — Stop shipping credentials in the feed

**Problem.** Every terminal in a venue receives every user's `hash_password` and
`pincode` on the wire, and any future consumer of `/sync/pull` or
`/sync/change-logs` gets them too.

**Change.** Strip them at the source. Either have `log_change()` remove the
columns from the payload for `users`, or exclude them from the trigger's column
list. Prefer the trigger-level exclusion: it is declarative and survives someone
adding a second consumer.

**Also.** `POST /users` and `POST /auth/register` take a plaintext `password`. The
client's outbox has to store that payload on disk to send a staff create queued
offline. That is a narrower exposure than a replicated column, and it is inherent
to offline creation — but it is worth a decision rather than an accident: either
accept it, or rule that staff creation requires connectivity.

**Acceptance.** `GET /sync/change-logs?entity=users` returns payloads with neither
field, for both historical and new rows. Historical rows matter — a client
bootstrapping from cursor 0 replays all of them.

---

### P0-3 — Verify the cursor cannot skip rows

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

**VERIFY.** Is the cursor a plain sequence? If so this is live, and its frequency
scales with concurrent write load — which is exactly when a venue is busy.

**Change.** Options, cheapest first:

- **Safety lag.** Add `committed_at timestamptz default clock_timestamp()` and
  return only rows with `committed_at < now() - interval '2 seconds'`. Trivial,
  probabilistic, and adds a fixed latency to every change. Adequate if
  transactions are short.
- **Snapshot horizon.** Record `pg_snapshot_xmin(pg_current_snapshot())` and
  return only rows whose `xmin` is below the oldest transaction that was in
  flight. Correct rather than probabilistic; needs care but is the standard fix.
- **Logical replication.** Correct by construction and a much larger change. Only
  if the feed becomes load-bearing beyond this app.

I would take the safety lag now and the snapshot horizon when write volume
justifies it. Two seconds of latency is invisible next to a 60-second poll.

**Acceptance.** A test that opens a transaction, inserts a change, opens and
commits a second transaction, pulls, then commits the first — and asserts the
client eventually receives both rows.

---

### P1-1 — Decide what `/sync/push` is for

**Problem.** The server has a generic write endpoint taking
`{entity, entity_id, action, payload}`. The client does not use it: every write
goes to a per-entity REST endpoint through a hand-written outbox handler. There
are six such handlers now and one per entity forever.

More consequentially, the REST creates assign their own ids, which forced real
machinery on the client: rows are created under a provisional id, and when the
server answers, the client swaps the id and rewrites every queued operation that
referenced it. That works and is tested, but it exists only because the client
cannot choose an id.

`SyncPushChange` carries `entity_id`. If push accepts it, that machinery is
unnecessary.

**The question is whether push is safe**, and it is a real question, not a
formality. A generic upsert bypasses whatever the REST handlers do — pricing,
stock movements, shift validation, permission checks scoped to a specific
action. For reference data (halls, tables, printer settings, categories) that is
probably fine. For orders and payments it is almost certainly not.

**VERIFY.**
- Is `/sync/push` implemented, or a stub?
- Does it validate `entity` against an allowlist, or accept any table name?
- Does it run business logic, or write rows?
- What does it do with an `entity_id` that already exists — upsert, or reject?
- What are the `SyncPushError` cases?

**Recommendation, pending those answers.** Do not route everything through push.
Define it narrowly: an allowlist of entities with no server-side invariants,
idempotent on `entity_id`, rejecting anything else. Then the client uses push for
those and keeps REST for orders and payments, where the server's logic is the
point.

If push is a stub and nobody wants to own it, say so and delete it from the
spec — an endpoint that looks like the right answer and is not is worse than no
endpoint.

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

**Overlaps P1-1.** If push takes ids for reference entities, this is only needed
for whatever stays on REST.

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

| Order | Item | Why here |
|---|---|---|
| 1 | P0-3 verify cursor skew | Silent data loss. Everything else assumes the feed is complete. |
| 2 | P0-1 eight triggers | Unblocks four screens and the deletion of the client's last HTTP file. Small. |
| 3 | P0-2 credentials | Small, and it is a live exposure in every venue running today. |
| 4 | P1-1 decide push | Determines whether P1-2 is needed at all. Decide before building. |
| 5 | P1-2 / P1-3 client ids | Deletes client machinery; fixes lost-response duplicates. |
| 6 | P2-1 snapshot | Before retention, because it is the recovery path. |
| 7 | P2-2 retention | Operational; the pressure is gradual. |

P0-1 through P0-3 are independent and can run in parallel.

---

## 5. What the client does in response

So the payoff is concrete:

- **After P0-1**: four screens migrate to the replica; `main_datasources.dart`
  and the Hive `LocalDatabase` are deleted; the architecture ratchet reaches
  zero and "exactly one database" becomes true.
- **After P0-2**: the client's redaction stays as defence in depth, but stops
  being the only thing standing between a venue's terminals and its password
  hashes.
- **After P1-1/P1-2**: provisional ids, reference rewriting and possibly the
  whole per-entity outbox handler layer are deleted.
- **After P2-1**: first login on a new terminal stops being a full history
  replay.

---

## 6. Open questions

Things I could not determine, listed so they get answered rather than assumed:

1. Does `/sync/pull` scope to the caller's branch? If it scopes only by brand, a
   multi-branch tenant sends every branch's data to every terminal.
2. Is the cursor a bare sequence? (P0-3 hinges on this.)
3. Is `/sync/push` implemented, and what does it validate?
4. Are any of the eight tables hard-deleted?
5. Does `log_change` derive brand scope from a session variable or a column?
6. What is the current `change_log` row count and growth rate? It sets the
   urgency of P2-1 and P2-2 and I have no way to see it.
7. Is there an existing integration test for `/sync/pull`? P0-3's acceptance test
   needs somewhere to live.
