# Offline-First & LAN-Sync Architecture — Execution Plan

**Companion to:** `offline-first-plan.md` (the architect-prompt template that scoped this work).
**Status:** Draft for review. Written against the actual codebase as of 2026-07-31, branch `pos/probs`.
**Confirmed via discussion (2026-07-31):** local storage stays on Hive, not Drift (§3, §11 Phase 3, §13); outage duration to survive is unbounded and unpredictable — but every branch does eventually reconnect, not literally forever for any of them (§1 Q4) — this reshaped §4.1 (new), §9, and the numbering guidance in §1 Q7, and rules out needing a local-only reference-data editing subsystem; cash registers are one-per-terminal with no sharing (§1 Q8) — the shared-resource case that actually matters is USB-attached printers (§8), not registers. **2026-08-01:** one terminal is a real local server with sole cloud uplink for its branch (§1 Q5, §7) — reverses this document's earlier "every terminal syncs independently" recommendation; the resulting single point of failure is explicitly accepted, not an open question (§13).

## How this document differs from the prompt

`offline-first-plan.md` was written as if this were a greenfield design exercise, with
`[FILL IN]` placeholders for client runtime, local DB, and outage duration. It isn't
greenfield. A working codebase audit turned up a **Hive-backed offline outbox, a LAN
peer-relay service, offline PIN auth caching, a cache layer, and a 409-conflict
resolver already in production code** — this is a partially-built system with real
gaps, not a blank page. Every section below is grounded in specific files and, where
backend behavior matters, in the actual `api-docs/` contract. Facts are stated as
facts; anywhere I'm inferring intent rather than reading it directly, it's marked
**Assumption**.

The structure follows the deliverable list from the prompt, with one section added
up front (§2, current-state audit) because you cannot plan the next move without
first knowing which pieces are already on the board.

---

## 1. Assumptions and open questions

These are the `[FILL IN]`s from the original prompt, answered from evidence where
possible, flagged where not.

| # | Question | Answer |
|---|---|---|
| 1 | POS client runtime | **Confirmed: Flutter** (single codebase), targeting Windows, Android, Linux, macOS, iOS, and web (all six platform folders present and building). |
| 2 | Which platform is the *real* POS terminal | **Assumption:** Windows desktop. Evidence: Win32 raw-USB-printer API (`printer_service.dart`), `fluent_ui`, `window_manager`, `flutter_acrylic`, a Windows installer (`windows/installer.iss`) and a dedicated `docs/WINDOWS_BUILD_FLOW.md`. Android is plausibly a secondary handheld/waiter device (a `WaiterCubit` and waiter-specific screens exist). Linux/macOS/web look like default Flutter multi-platform scaffolding without POS-specific investment — please confirm which of these actually ship to a restaurant. |
| 3 | Local DB on the POS device | **Confirmed: Hive** (`hive_flutter`) for JSON-blob caches and the offline queue, plus `shared_preferences` for small KV config (tokens, printer routing, offline auth cache). No relational embedded DB exists today. **Decision (confirmed): stay on Hive** — restructure into typed per-entity records instead of raw JSON blobs, rather than introducing a second storage engine; see §3. |
| 4 | Outage duration to survive | **Confirmed by the user: unbounded and unpredictable — no assumed worst case — but every branch does eventually reconnect** (resolved: not literally permanent for any branch). Harder than the original prompt's own framing anticipated, and it reshapes several sections: retention/pruning can no longer be gated on "has this synced to the cloud yet" (§4.1, new), offline-auth TTL cannot hard-lock staff out during a long outage (§9, revised), and any order/check numbering scheme cannot depend on leasing a range from the server (Q7 below, revised). It also sharpens Q6/fiscal from an open question into a likely direct conflict — see §12, §13. Because reconnection is guaranteed eventually (just not on any schedule), **no local-only reference-data administration subsystem is needed** — the cloud remains the sole place menu/price/staff data is edited; it may just take a while to reach a given branch. |
| 5 | "Local server" = miniature cloud backend, or something lighter? | **Confirmed by the user: yes, one terminal is a real local server** — specifically, the *sole cloud uplink* for its branch (§7, revised). Not a full clone of the Go backend's business logic (order totals, stock, etc. stay computed server-side, cloud-side) — the local server's job is to be the only terminal that talks to the cloud, relaying every other terminal's queued work through itself. **Explicitly accepted: this is a single point of failure.** If the designated terminal goes down, the branch loses cloud connectivity entirely until it returns or an admin manually re-designates another terminal as leader. The user weighed this directly and chose it — §7, §10, and §13 are updated accordingly; this is no longer an open question. |
| 6 | Uzbekistan fiscal requirements | **No fiscal/OKKM/online-cash-register integration exists anywhere in the codebase — confirmed not yet integrated.** Per discussion, explicitly **deferred**, not a blocker for §11's phases right now. Revisit before building Phase 5's cashier-receipt work for real if fiscal integration gets scoped later. |
| 7 | Human-readable order/check numbers | Not confirmed either way in the API docs or client code surveyed (order identity today is the UUID `id`; `PrinterService.printKitchenReceiptFor` accepts an optional `orderNumber` string, suggesting *some* numbering exists upstream, but its generation scheme wasn't located). **Flag as open — confirm the current scheme before designing an offline-safe numbering strategy.** Given Q4's answer (outage may be unbounded/permanent), any scheme that leases or renews a number range from the server is disqualified outright — it must be fully self-sufficient on-device: a per-device prefix plus a local counter, or a LAN-leader-issued local sequence, never a server-leased range. |
| 8 | Cash register ↔ terminal cardinality | **Resolved: one register per terminal, no sharing** (confirmed via discussion). The shared-register conflict scenario in §6 (two terminals racing to open a shift on the same register) is a non-issue in practice — kept there for documentation, not because it needs active engineering investment. The shared-resource case that *does* matter is USB-attached printers (§8): cable-, not network-, connected, so only the owning terminal can physically print regardless of which terminal triggers the job. |
| 9 | Does the client already use the backend's terminal-provisioning flow? | Backend exposes `POST /auth/terminal/branches` and `POST /auth/terminal/token` (issues a **permanent branch-scoped JWT** — built for exactly this kind of always-on terminal/leader use case). No evidence found that the Flutter client currently calls either endpoint. **Confirm** — if unused, §7 recommends adopting it for the LAN leader's cloud identity. |

---

## 2. Current-state audit

This is the map of what already exists. Read this before reading anything else — it's
what turns the rest of this document from "design" into "execution."

### 2.1 Client-side components

| Component | File(s) | What it does today | Key gaps |
|---|---|---|---|
| Connectivity detection | `lib/core/services/connectivity/connectivity_cubit.dart` | Wraps `connectivity_plus`; emits `bool` for wifi/ethernet/mobile/vpn/other link state. | **Link-layer only.** No application-level reachability check — WiFi can be "connected" while the cloud backend is unreachable (DNS failure, server down, captive portal), and the app would report itself online the whole time. |
| Local reference cache | `lib/core/services/cache/cache_service.dart` (Hive box `pos_cache`) | Raw-JSON blobs for categories/goods/departments/halls/tables/per-table order-detail/per-order item-timestamps. Only `goods` has a staleness policy (30 min TTL) and a paginated background prefetch (`prefetchAllGoods`, 500/page). | No delta sync — every refresh is whole-list overwrite. No TTL on halls/tables/categories/departments. Not tied to any server-side cursor. |
| Offline outbox | `lib/core/services/offline_queue/offline_queue_service.dart` + `pending_operation.dart` (Hive box `offline_queue`, `HiveType` 10/11) | Exactly **3 queueable operation types**: `createOrder`, `addItems`, `payOrder`. Drained by `syncAll()`, called **only** from `lib/core/widgets/app_scaffold.dart:75-82` on a connectivity `false→true` edge. 4xx responses are dropped as terminal; everything else is retried on the next drain. | No idempotency key. No periodic retry — purely edge-triggered (if the app never observes a false→true transition, e.g. it was never marked offline because the *link* stayed up while the *backend* was down, the queue never drains). Ordering is type-partitioned (all `createOrder`s, then all `addItems`, then all `payOrder`) rather than per-table chronological — safe for the common case, breakable if a table is closed and reopened twice while offline. Replays via serial single-item POSTs to `ListAPI.orders` / `ListAPI.orderItems` / `ListAPI.payToOrder` — **does not use the backend's purpose-built `POST /orders/batch` endpoint** (see §2.2), which already supports client IDs and `continue_on_error`. |
| Offline auth | `lib/core/services/auth/offline_auth_cache.dart` | Caches `{password/pincode, accessToken, refreshToken, user}` per `brandId` and per `brandId_pincode`, in **plaintext `SharedPreferences`**, with **no TTL**. | Cleartext credential storage (should be platform secure storage). No expiry — a terminated employee's cached PIN works offline indefinitely; no bound on revocation lag at all. |
| LAN cluster | `lib/core/services/lan_hub/{lan_hub_service,lan_hub_server,lan_hub_client,lan_hub_message}.dart`, configured in `lib/features/view/main/presentation/pages/settings/sections/lan_network_section.dart` | Manual mode selection: `disabled` / `server` / `client`. Server = raw unauthenticated `ws://` (`HttpServer` + `WebSocketTransformer`) on port 8765. Client = WebSocket with a flat 5s reconnect loop. **Single message type carried**: table status (`free`/`busy`/`away`). | No discovery (server IP is typed in by hand). No authentication or encryption — any device on the branch WiFi can open the socket and inject fake table-status messages. No leader election (fine, see §7) but also no fallback UX when the leader disappears. Not used for orders/payments/print jobs — only table badges. |
| Printing | `lib/core/service/printer/{printer_service,printer_config_storage,printer_config,printer_setting_entry}.dart` + `receipt/*_builder.dart` | ESC/POS over TCP (port 9100, direct per-terminal socket) for network printers, or raw Win32 printer API for USB-attached printers. Routing config (`ip`, `port`, `connection_type`, `connected_entity_ids`) is pulled from `GET /settings/printer-settings` via `SyncPrinterSettingsUsecase` and cached identically (`SharedPreferences`) on **every** terminal. | No print-job entity, no persistence, no state machine — every print is a fire-and-forget async call with 2 retries over ~1s, then a user-facing error toast. A USB-attached printer is only reachable from the terminal it's physically plugged into; any other terminal targeting it just fails (`"USB printer faqat Windows da ishlaydi"`) — **no relay-to-owner fallback exists**. Network (TCP) printers, by contrast, already work correctly from any terminal today (any machine can open a direct socket) — the "shared printer" problem is narrower than it first appears: it's a USB-only problem. |
| Conflict handling | `lib/core/utils/order_conflict_helper.dart` | Regex-extracts an existing order UUID out of a `409` error body so the client can re-target that order instead of showing an error. Used in `create_order_bloc.dart`, `table_timer_cubit.dart`, `waiter_cubit.dart`. | This is the **only** conflict-handling code in the app, and it covers exactly one scenario: duplicate order-create race for the same table. Nothing exists for concurrent item edits, stock counters, shift overlap, or stale pricing. |
| Per-feature offline coverage | scattered | **Fully wired** (cache + connectivity + queue/LAN): `main_cubit.dart` (tables/halls, plus bidirectional LAN table-status sync), `create_order_bloc.dart`, `payment_bloc.dart` (primary pay path). **Partial:** `payment_bloc.dart`'s zero-total cancel path bypasses the queue; `detail_bloc.dart` reads cache-first but existing-item edits (quantity/cancel) POST directly and swallow failures in `catch (_) {}` — **offline item edits are silently lost, not queued**; `shift_bloc.dart` has its own bespoke `SharedPreferences`-based local-shift fallback that **never reconciles with the server** (a shift opened offline stays local forever). **Not wired at all** (direct-to-`DioClient`, zero offline resilience): `waiter_cubit.dart` (the entire separate waiter order-taking/closing panel), `table_timer_cubit.dart`, `archives_bloc.dart`/`archive_bloc.dart`, `department_selection_cubit.dart`. | Root cause: `MainRepositoryImpl`/`MainDataSourcesImpl` — the one place a cache/offline decorator could live centrally — has **zero** cache or connectivity logic (confirmed: `MainDataSourcesImpl` never imports `CacheService`). Every bit of offline behavior that exists was hand-added per-Bloc, which is exactly why coverage is patchy instead of uniform. |
| Observability | `lib/core/widgets/offline_banner.dart` | One binary amber banner: online or "offline mode," nothing else. `payment_screen.dart` separately shows a pending-items indicator, but only on that one screen. | No visibility anywhere into outbox depth, LAN cluster role/peer count, printer reachability, or last-successful-sync time. Staff cannot tell *how* offline they are or whether anything is stuck. |
| Testing | `test/order_totals_test.dart`, `test/widget_test.dart` | Pure-function tests for order-total arithmetic; one Flutter smoke test. | **Zero** coverage of the offline queue, LAN hub, or conflict logic. |
| Scattered polling | `main_header.dart` (30s), `waiter_floor_plan_screen.dart` (bg refresh + 30s ticker), `time_based_table_badge.dart` (60s), `table_timer_cubit.dart` (periodic), `archive_screen.dart` (bg refresh), `close_shift_screen.dart` (1s), `lan_network_section.dart` (periodic) | Roughly eight independent per-widget `Timer.periodic` polls, each refreshing its own screen. | This is a symptom of the same root cause above: there is no single sync engine, so every screen re-invented its own polling cadence. Consolidating these is part of the plan (§3, §11). |

Note on `docs/ISSUES.md`: it's dated 2026-03-27 and lists "Offline mode: not done" and
"Printer integration: not done" as open feature requests. Both are now substantially
built (imperfectly, per above) — treat that document as **historical**, not current
status.

### 2.2 Backend contract (from `api-docs/`)

- **`/sync/pull`, `/sync/push`, `/sync/change-logs` exist**, but are thin and appear
  unused by the client. The pull/push cursor is a **single global integer**
  (presumably the `change_log` table's own auto-increment id) — the request schema
  has no branch/tenant scoping field at all, no idempotency key, and no documented
  whitelist of which entities actually populate `change_log`. Treat this as an
  unproven scaffold, not a ready-made sync bus.
- **`POST /orders/batch`** is purpose-built and explicitly documented "useful for
  offline sync" — it accepts an array of `CreateOrderRequest`, each with a
  **client-suppliable `id` (UUID) and `client_created_at`**, plus a top-level
  `continue_on_error` flag. This is a much better foundation for the outbox than the
  generic sync endpoints, and **the client doesn't call it today** (the outbox
  replays single-order POSTs one at a time instead).
- **Order items have no client-suppliable id** — server-assigned only, on every
  order-item creation path. Anything that needs to reference a not-yet-synced item
  locally has to key off the local queue-op, not a stable item id.
- **No entity anywhere carries a `version`/optimistic-concurrency field** (confirmed
  by grepping all 341 schemas in `swagger.json` — only `created_at`/`updated_at`
  audit pairs exist). Conflict detection can't lean on server-side versioning; it has
  to be built client-side.
- **Stock (`compound-stock`, `ingredient-stock`) already exposes commutative
  add/remove delta endpoints** alongside a dangerous absolute-set `PUT` — exactly the
  shape an offline design wants, as long as offline clients are restricted to the
  delta endpoints.
- **Cash register shifts: server enforces one active shift per register.** A hard,
  already-real conflict surface for two terminals sharing a register while
  partitioned.
- **Auth is JWT access+refresh**, with a dedicated `POST /auth/login-pincode` for
  staff PIN login (already what the client's offline auth cache is built around), and
  a **permanent branch-scoped terminal JWT** (`POST /auth/terminal/token`) that looks
  purpose-built for an always-on local leader's cloud identity (see §1, open question
  9, and §7).
- **Order totals are server-authoritative** at `POST /orders/{id}/pay`, which
  recomputes and enforces `grand_total`; the item `price` is snapshotted onto the
  order line at add-time and never silently re-priced (confirmed directly in
  `order-total-calculation.md`). This is already the right behavior for the
  stale-price conflict scenario in §6 — nothing needs to change here, only be
  preserved.

---

## 3. Target architecture

Two-layer split, per the prompt's non-negotiable requirement #2 — and the biggest
single structural change this plan proposes, because **it does not exist today**: as
§2.1 shows, six-plus Blocs each reimplement their own slice of offline/cache logic
directly against `DioClient`, at wildly inconsistent levels of completeness.

### Client layer (unchanged responsibility, changed plumbing)

Every Bloc/Cubit reads and writes **exclusively** through a small set of new
`LocalRepository` interfaces — `OrdersLocalRepository`, `TablesLocalRepository`,
`StockLocalRepository`, `ShiftsLocalRepository`, `PrinterLocalRepository`. None of
them import `DioClient`, `CacheService`, `OfflineQueueService`, or `LanHubService`
directly, ever again. Reads are `Stream`-based (`watchOpenOrders(tableId)`, not
`Future<List<Order>>`) so the UI reacts uniformly to a local write, a LAN-relayed
peer write, and a completed cloud sync — the Bloc never needs to know which one
happened.

This directly satisfies requirement #1 ("local DB is the only read path") — today
that's true for `MainCubit`/`CreateOrderBloc`/`PaymentBloc` and false everywhere
else.

### Sync engine (new: `lib/core/sync/`)

Owns **all** backend and LAN communication. Built by generalizing what's already
there, not replacing it wholesale:

- **`LocalStore`** — the durable local DB. **Decision (confirmed): stay on Hive
  everywhere** rather than introduce a second storage engine — restructure it into
  typed per-entity records (one `HiveType`-adapted class per aggregate: orders,
  order_items, payments, shift_sessions, print_jobs, outbox, sync_cursor) instead of
  today's raw JSON blobs, with query needs (per-table FIFO, per-order item lists,
  print-job claims) served by small in-memory indices rebuilt at startup — the data
  scale here (one branch's live working set) never approaches where that stops being
  fine. See §11 Phase 3 for the reasoning and the escalation condition under which a
  relational engine (Drift/sqlite3) would become worth its cross-platform packaging
  cost.
- **`SyncEngine`** — generalizes today's edge-triggered `app_scaffold.dart` listener
  into: a periodic 60s tick (per requirement #3), an event-driven immediate push for
  high-value mutations (order closed, payment taken, shift closed), reconnect-edge
  drain (kept), and a new application-level reachability probe that closes the
  "WiFi up, backend down" blind spot from §2.1.
- **`Outbox`** — generalizes `PendingOperation`/`OfflineQueueService` from 3
  operation types to every mutation, adds a client-generated idempotency key to
  each, replays order creation via `/orders/batch` instead of serial POSTs, and
  enforces per-table/per-aggregate FIFO ordering instead of today's type-partitioned
  passes. Rejected ops go to a quarantine list with operator visibility instead of
  being silently dropped.
- **`ConflictResolver`** — generalizes `order_conflict_helper.dart` into a
  policy-per-entity dispatcher (§6).
- **`LanCluster`** — evolves `LanHubService`/`Server`/`Client` into an authenticated,
  richer-protocol peer relay and, per the confirmed local-server decision (§1 Q5,
  §7), the branch's *sole cloud uplink*: the designated leader's `LanCluster`
  accepts followers' forwarded outbox operations and replays them to the cloud
  alongside its own. Followers' `SyncEngine` talks to the leader over LAN, not to
  the cloud directly — still not a local clone of the cloud API's business logic,
  just the single relay point for reaching it.
- **`PrintCoordinator`** — wraps `PrinterService` with a persisted job queue and a
  claim/lease state machine (§8).

```
┌─────────────────────────── Client layer ───────────────────────────┐
│  WaiterCubit  TableTimerCubit  DetailBloc  PaymentBloc  ShiftBloc … │
│                     (UI + user interaction only)                   │
└───────────────────────────────┬─────────────────────────────────────┘
                                 │  LocalRepository interfaces (Streams)
┌────────────────────────────────▼────────────────────────────────────┐
│                            Sync engine                              │
│  LocalStore (typed Hive records)  Outbox  ConflictResolver          │
│  SyncEngine (periodic+event+reachability)  LanCluster  PrintCoord.  │
└───────┬───────────────────────────────────────────────┬─────────────┘
        │ REST (Dio) — cloud, independent per terminal   │ WebSocket — LAN peers
        ▼                                                 ▼
   Go + Postgres backend                          other branch terminals
```

**Revised 2026-08-01:** the left arrow above (REST to cloud) is no longer "per
terminal" — per the confirmed local-server decision (§1 Q5, §7), only the
designated leader terminal has it. Follower terminals' `SyncEngine` sends its
outbox down the *right* arrow (LAN WebSocket) instead, to the leader, which
replays followers' forwarded operations to the cloud alongside its own. Every
terminal still has its own `LocalStore`/`Outbox` underneath — reads and local
write-durability are unaffected; only the cloud uplink itself is now singular.

---

## 4. Data classification table

| Entity | Class | Sync direction | Conflict policy | Retention |
|---|---|---|---|---|
| Goods, categories, departments, halls, modifiers, service/tax config | Server-authoritative reference data | Pull-only; hydrate at login, refresh on TTL/cursor | Server always wins; client never mutates locally | Cache indefinitely, refresh in place |
| Printer routing settings | Server-authoritative reference data | Pull-only | Server wins | Cache indefinitely, refresh on change |
| Staff, roles, permissions, PIN credentials | Server-authoritative reference data (security-sensitive) | Pull-only, cached at login with an explicit TTL | Server wins; TTL forces re-check | **Short TTL** (§9) — not indefinite like menu data |
| Orders, order items | Client-originated transactional data | Push via outbox; client-generated order id; item mutations as an append-only event log | Client-authoritative / append-only (§6) | Retain locally until synced + N days for support/reprint |
| Payments | Client-originated transactional data | Push via outbox, append-only | Client-authoritative, but server recomputes/enforces `grand_total` at `/pay` | Retain until synced + fiscal retention window (pending §1 Q6) |
| Discounts, voids, refunds | Client-originated, privileged | Push via outbox + full audit log | Client-authoritative, flagged for server-side review when performed offline | Retain with audit trail per compliance |
| Shift / cash-register sessions | Client-originated, single-owner contended | Push via outbox | Single-owner lock (server already enforces one active shift per register); offline-opened shift is provisional until reconciled (§6) | Retain until closed + synced |
| Table occupancy (`TableStatus`) | Shared mutable state, contended | LAN-relayed in real time + cloud push | HLC-ordered last-write-wins, reconciled against server order state as ground truth | Ephemeral — not retained beyond session |
| Table timer sessions (start/pause/resume, segments) | Shared mutable state, contended (server already models a rich session/segment/pause history) | Push on each transition; cloud is the metering source of truth | Single owner per order at a time; append segments, never overwrite | Retain, synced |
| Stock levels (compound/ingredient) | Shared mutable counter | Push **delta-only** (add/remove) while offline, never absolute-set | Commutative merge (sum of deltas); reject/quarantine an offline absolute `PUT` | Retain |
| Stop-list (86'd items) | Shared mutable state, low contention | Push + pull | Last-write-wins acceptable (low stakes, staff-visible, server already models `expires_at`) | Expires per `expires_at` |
| Print jobs | New; client/LAN-local | LAN-local primarily; optionally logged server-side as an audit artifact | Single-owner claim (owning terminal only), leased | Prune after N days |

### 4.1 Local storage lifecycle & retention

Elevated from a footnote to its own subsection given the outage-duration answer in
§1 Q4 (unbounded/possibly permanent) — a terminal that may never resync cannot use
"has this synced to the cloud yet" as its pruning trigger, or it simply never prunes.

- **Pruning must be independent of sync status.** Closed/paid orders and printed
  jobs age out by local retention window (time- and/or count-based, e.g. "keep the
  last 90 days or last N thousand orders, whichever is larger") and by an explicit
  disk-budget ceiling, not by "confirmed synced." A synced-but-recent order is kept
  regardless; an ancient unsynced one still eventually prunes once past the window,
  with a last-chance export (see below) rather than a silent loss.
- **Unsynced data that's about to be pruned needs an escape hatch** — e.g. a manual
  "export pending records" action (to a file, for a technician to carry out and
  reconcile manually) before anything old and still-unsynced is dropped, since for a
  permanently-offline branch there may be no other path back to the cloud at all.
- **Schema migration across a fleet that may never phone home.** Version the local
  Hive schema explicitly (already partially true — `HiveType` ids are assigned per
  class) and ship migrations as app-upgrade-time code, not server-pushed
  configuration — a device that never reconnects still needs to self-migrate purely
  from the next app binary it's given (e.g. via a USB installer), never from a
  server-delivered schema update.
- **Encryption at rest and device-loss handling** (per the original prompt): the
  offline-auth and outbox stores hold credentials and financial records indefinitely
  on a device that may never check in with the cloud again — encrypt at rest and
  define a local (not cloud-triggered) wipe/lockout procedure for a stolen or
  decommissioned terminal, since a cloud-issued remote revoke can't be assumed to
  ever reach it.

---

## 5. Sync protocol specification

**Recommendation, stated plainly:** do not build this design's correctness on the
generic `/sync/pull` / `/sync/push` endpoints as they stand — no branch scoping in
the request schema, no idempotency, no documented entity whitelist. Two tracks:

1. Push the backend to harden them (add `branch_id` scoping, an idempotency-key
   field, a documented entity whitelist) and adopt them as the general reference-data
   delta mechanism once that's done.
2. In the meantime — and permanently for the transactional core — use the
   already-more-mature, purpose-built domain endpoints: `POST /orders/batch` for
   order replay, and the existing per-domain endpoints (order-items, `/pay`, stock
   add/remove) for everything else. Reserve generic `/sync/pull` for low-stakes
   reference-data hydration only, where a coarse global cursor is an acceptable risk
   because no money is involved.

**Hydration (login):** call `/metadata` for lightweight dropdowns, then extend the
existing 500-item paginated prefetch pattern (`CacheService.prefetchAllGoods` already
does this) to halls, tables, categories, departments, printer settings, and
stop-list. Same pattern, more entities — don't invent a second hydration mechanism.

**Delta refresh:** periodic 60s tick (new, §3) either calls the hardened `/sync/pull`
once available, or, until then, re-fetches each list endpoint on its own throttle
(current per-entity TTL model, generalized beyond just `goods`).

**Push / outbox:** every queued mutation carries a client-generated idempotency key
(new — none exists server-side today). Order creation/replay batches through
`/orders/batch` with `continue_on_error: true`. This requires a **backend change** to
accept and dedupe on a `client_op_id`-style field — flagged as a cross-team
dependency in §11 Phase 1. Interim mitigation: rely on the already-supported
client-generated order `id` for dedup, **after confirming** that resubmitting the
same order `id` safely no-ops server-side rather than erroring (unverified — check
before depending on it).

**Tombstones:** the existing (if thin) `EntityChanges{created, updated, deleted:
[]string}` shape from the sync models is the right structure for deletes once
`/sync/pull` is hardened — reuse it rather than inventing a new tombstone format.

**Pagination/resumability:** already solved (500/page, stop on short page) — reuse
for hydration, don't reinvent.

**Backoff/jitter/reconnect storms:** neither the outbox retry (today: immediate,
edge-triggered, no delay) nor the LAN client reconnect (today: flat 5s) has backoff.
Add exponential backoff with jitter to both, so that when a branch's WiFi returns
after an outage, N terminals don't all hammer the cloud API in the same instant.

**Partial batch failure:** `/orders/batch`'s `continue_on_error` plus the
`{applied, errors: [{entity, error, index}]}` shape already present on the (thin)
`/sync/push` model is the right structure for a quarantine list — surface rejected
ops in a new Sync Issues screen (§11 Phase 6) instead of the silent drop that happens
today on any 4xx.

---

## 6. Conflict matrix

| Scenario | Resolution | Rationale |
|---|---|---|
| Two waiters edit the same open order on two terminals simultaneously | Model order items as an **append-only event log** (add / cancel / quantity-change events), not a mutable row set. Merge by replaying all events in HLC order; concurrent adds are always additive; the latest quantity-change per item-instance wins. | Matches the prompt's own suggested default. Today's reality is worse than a naive merge: `DetailBloc`'s direct-to-API item edits fail silently offline (`catch (_) {}`) — the edit is simply lost, not even queued. |
| Same order closed and paid on two terminals during a partition | The server's order-status transition is the single arbiter: whichever `/pay` reaches the server first wins; a `/pay` against an already-`paid` order is rejected. The losing terminal shows "already paid elsewhere" — never a silent retry that could double-charge. | No double-charge is non-negotiable. Today, nothing stops two terminals from both queuing a `payOrder` for the same order while both offline — the outbox needs an explicit "check order status before replaying payment" guard (§11 Phase 1). |
| Reference data changes on the server while a device holds a stale copy mid-order (price changes after the item was added) | **Already handled correctly** — price is snapshotted onto the order line at add-time and never silently re-priced; the server recomputes and enforces the authoritative total at `/pay`. Preserve this; don't change it. | Confirmed directly in `order-total-calculation.md`. |
| Stock decrements from multiple terminals | Treat as a **commutative counter**: offline clients may only push `add`/`remove` deltas, never the absolute-set `PUT`, while offline. Deltas apply in any order. | Backend already exposes dedicated add/remove endpoints separate from the absolute `PUT` — the client just needs to be restricted to the safe subset when replaying from the outbox. |
| A shift closed on one terminal while another still has open orders | Don't block shift-close on other terminals' open orders (the server doesn't model that relationship). Surface a warning listing still-open tables/orders at close time; those orders stay tied to the now-closed shift's register for reporting continuity. | Resolved via §1 Q8: registers are one-per-terminal, so this is rare in practice (e.g., only if a terminal is reconfigured mid-shift) — kept as documented behavior, not a priority build target. |
| Server-side edits to an order the client also edited offline | Treat server-authored changes as just another actor in the same append-only event log from row 1 — no bespoke rule needed. | No evidence of a back-office order-edit UI exists today, so this is low-probability; reusing the same mechanism is simpler and more "boring" than a special case. |

---

## 7. LAN cluster design

- **Discovery:** keep manual IP entry as the always-available fallback (already
  built — `lan_network_section.dart`), but add mDNS/NSD auto-discovery (recommend the
  pure-Dart `multicast_dns` package — boring, no native-plugin surprises) as the
  primary path so staff don't need to type an IP.
- **Election:** **keep manual leader designation.** The team already independently
  arrived at the same answer the original prompt steers toward ("full Raft is almost
  certainly over-engineering") — `LanMode.server`/`LanMode.client`, hand-picked in
  Settings, is the right amount of mechanism. Add one guard rail that's currently
  missing: refuse to enter `server` mode if an existing server is already
  discoverable via mDNS, to stop two terminals from accidentally both becoming
  leader.
- **Failover — revised 2026-08-01 given the confirmed sole-uplink decision (§1 Q5):**
  leader loses power mid-service → followers keep retrying per the existing
  backoff (`LanHubClient`), and show an "operating solo" banner (extends
  `offline_banner.dart`) after N failed reconnects — but unlike this document's
  original design, there is now **no cloud fallback** while the leader is down.
  Followers keep working against their own local cache (read path unaffected,
  requirement #1 still holds) and keep queuing writes in their own local outbox
  (nothing is lost — durability is per-terminal, not leader-dependent), but nothing
  drains to the cloud until the leader returns. The banner copy should say so
  plainly ("not syncing to head office," not just "not getting live table
  updates") — staff will hit this for real, not just in theory. Recovery: the
  leader terminal comes back and drains its own backlog plus everything followers
  forwarded to it meanwhile, **or** an admin manually re-designates a different
  terminal as leader (existing `LanMode` mechanism, no new tooling needed — but
  keep this a deliberate admin action, not automatic promotion).
- **Split-brain:** with manual-only election and no auto-promotion, split-brain can
  only happen via staff error (two terminals both set to `server`) — mitigated by the
  discovery guard rail above, plus a periodic health-broadcast so a second accidental
  server is visibly flagged.
- **Rejoin:** a terminal that was solo for 40 minutes doesn't need a special
  LAN-rejoin protocol — on reconnect it re-pulls current table/order state from the
  **cloud** (source of truth), exactly like any other reconnect. LAN state is always
  a courtesy cache of cloud state, never the reverse.
- **Clocks:** introduce a Hybrid Logical Clock for ordering LAN-relayed and outbox
  events; wall-clock time stays display-only metadata, except where legally required
  (fiscal receipt timestamps — pending §1 Q6).
- **Cluster vs. cloud sync — confirmed 2026-08-01: sole uplink through the leader**
  (reverses this document's earlier recommendation against it). The designated
  local-server terminal is the *only* one with an active cloud sync relationship
  for its branch. Followers' `SyncEngine` forwards their locally-queued outbox
  operations to the leader over the (now-authenticated, see Security below) LAN
  WebSocket instead of posting to the cloud directly; the leader replays followers'
  forwarded operations alongside its own. Followers also pull reference-data
  refreshes (goods/categories/etc.) from the leader instead of the cloud — cutting
  the redundant per-terminal cloud traffic this document previously used as the
  reason *not* to do this; that reasoning is superseded by the user's explicit
  choice. The leader's own cloud calls (whether relaying its own queued work or a
  follower's) should authenticate with the permanent branch-scoped terminal JWT
  (`POST /auth/terminal/token`, §2.2) rather than whichever staff PIN happens to be
  logged in at that moment — decouples sync continuity from staff shift
  changes/logouts. **Explicitly accepted, not a residual risk to fix:** this makes
  the leader a real single point of failure for the branch's cloud connectivity —
  see Failover above for exactly what "down" looks like, and given every branch now
  depends on its leader for *all* cloud sync (not just LAN-only branches), LAN
  cluster hardening (§11 Phase 4) should move earlier in the phase order than
  originally planned, not stay a late hardening pass.
- **Security:** today's `ws://` socket is **completely unauthenticated** — any device
  on the branch WiFi can connect and inject fake table-status messages. Fix: require
  the backend's permanent terminal JWT (`POST /auth/terminal/token`, confirmed to
  exist, apparently unused today) at WebSocket handshake, validated by
  `LanHubServer` before upgrading the connection; move from `ws://` to `wss://`
  reusing the existing `AppSecurityContext`/cert-pinning pattern already built for
  the cloud Dio client (`assets/certs/isrg_roots.pem`) rather than inventing a new
  security mechanism.

---

## 8. Print subsystem design

- New persisted `PrintJob` entity (in the restructured local store, §3/§11 Phase 3):
  `id, job_type (kitchen | cashier | shift_close), payload, target_printer_id,
  owner_terminal_id, state (queued→claimed→printing→printed|failed), claimed_at,
  printed_at, retry_count`.
- **Network (TCP) printers need no relay** — any terminal can already open a direct
  socket to them, and this already works correctly today. A job still gets a
  persisted row (so a crash mid-print is retryable/visible), but claim = the
  originating terminal, no handoff required.
- **USB-attached printers are today's actual gap** (confirmed:
  `_printViaWindowsRaw` simply errors on any non-owning terminal, with no fallback).
  Fix: when a terminal resolves a target printer as USB/cable and is not the owner,
  publish the job over the LAN hub's richer protocol (§7) instead of attempting a
  local print; the owning terminal claims it, prints via the existing Win32 path, and
  reports completion back over the same channel. Concretely: Terminal B closes a
  check whose receipt printer is USB-cabled only to Terminal A — Terminal B never
  attempts to print locally; it publishes the job, Terminal A claims it and prints,
  and reports back. The trigger and the physical printing are allowed to happen on
  different machines by design.
- **Exactly-once:** claims use a lease (recommend 10s). If the claiming terminal
  doesn't report completion within the lease, the job returns to `queued` for at
  most **one** automatic re-claim by any owner-capable terminal, then requires manual
  operator retry from the new print-status screen (§11 Phase 6) — bounded retries,
  not an infinite loop that could produce duplicate physical printouts.
- **Kitchen vs. customer receipts, different treatment** (per the prompt's own
  framing: kitchen tickets are urgent and locally reprintable; a customer/fiscal
  receipt is not): kitchen tickets keep today's "fire, alert on failure, let staff
  manually reprint" behavior, but now backed by a real persisted `PrintJob` row so
  "reprint" is a tracked action instead of re-invoking a bare function. Cashier /
  close-check receipts get the full claim/lease/dedupe treatment, since a duplicate
  fiscal-adjacent receipt is a real problem, not a cosmetic one.
- **Transport/driver layer stays as-is** — ESC/POS builders, TCP sockets, and the
  Win32 raw-printer API are unchanged; only the job-queuing/routing wrapper around
  them is new.

---

## 9. Offline authentication and authorization

- Keep the `OfflineAuthCache` mechanism (it's the right idea) but: move storage off
  plaintext `SharedPreferences` onto platform secure storage (`flutter_secure_storage`
  — Windows DPAPI / Keychain / Keystore under the hood); snapshot the role/permission
  set alongside the cached credential so a server-side permission change is picked up
  on the next successful online check rather than trusted forever from cache.
- **TTL design changes given §1 Q4's answer (outage may be unbounded/permanent):** a
  hard TTL that requires a cloud check-in to keep working (e.g. "locks out after
  24h with no reconnect") isn't viable — it would eventually lock every employee out
  of a branch that never reconnects, including whoever would need to fix that. Use a
  **local-authority renewal model instead**: a local manager/admin PIN (itself
  cached, at a longer-lived tier) can re-authorize other staff PINs entirely on-device
  with no cloud involved, the same way a manager override already works for other
  privileged actions. An opportunistic cloud re-check still happens whenever
  connectivity is available and tightens the effective TTL, but it is never the
  *only* path to renewal.
- **Revocation lag** becomes bounded by that TTL, and — importantly — **visible**:
  show staff "offline PIN login valid until HH:mm without reconnecting" rather than
  an invisible background limit (extends §11 Phase 6 observability work).
- **Privileged actions offline** (voids, discounts, drawer opens, price overrides):
  none of this is queued or logged today (only 3 basic op types exist in the outbox
  at all). Net-new: log locally with a full audit trail (actor, timestamp, HLC,
  reason), sync on reconnect as its own entity, reviewable server-side.

---

## 10. Failure-mode table

| Failure | What the user sees | What the system does |
|---|---|---|
| WAN drops, LAN fine | Offline banner (existing) + new outbox-depth count | Client layer keeps working off the local store; Outbox queues writes; periodic tick keeps retrying with backoff; LAN cluster keeps relaying table/print state normally |
| WAN fine but backend down | **Today: nothing — invisible.** New: same offline banner | New app-level reachability probe demotes to offline mode even though the OS reports a live link |
| LAN leader (designated local server) loses power mid-service | "Operating solo — not syncing to head office" banner after N failed reconnects | **Revised 2026-08-01 — accepted single point of failure (§1 Q5, §7):** followers keep working off local cache and keep queuing writes locally, but nothing reaches the cloud until the leader returns or an admin manually re-designates a new leader; USB-print jobs owned by the dead leader queue until it returns or an operator manually re-routes |
| Terminal crashes/reboots mid-order | Order resumes from durable local store on relaunch | Outbox/local store already survive process death (Hive today, restructured/typed Hive after §11 Phase 3); any in-flight print-job lease simply expires and is reclaimed per §8 |
| Two terminals both open a shift on the same register while partitioned | Second terminal's shift-open is flagged on reconnect | Local shift is provisional until server-confirmed; conflict surfaced for manual reconciliation — replaces today's `ShiftBloc` fallback that goes local-only and never reconciles at all |
| Same order paid on two terminals during a partition | Losing terminal sees "already paid elsewhere," never a duplicate charge | Server order-status transition is the single arbiter (§6); Outbox checks order status before replaying a queued payment |
| Local DB corrupted / device replaced | Brief empty state, then full rehydration | Cold-start pulls full reference data + all currently-open orders/tables for the branch from the cloud (ground truth); LAN peers aren't needed for this |
| Network printer temporarily unreachable | Today: a toast, then silence. New: job shows `failed`, retryable from a status screen | Bounded retries (existing 2×/1s) then quarantine as a `failed` `PrintJob` instead of vanishing after the toast |
| A fired employee's PIN is still cached locally | Today: silent risk. New: banner shows "PIN valid offline until HH:mm" | TTL-bounded offline auth (§9) instead of indefinite validity |

---

## 11. Phased implementation plan

Ordered by risk, low first. Each phase names concrete files.

**Phase 0 — Foundation & safety nets (low risk, do first) — implemented 2026-07-31**
- Re-verified the three named `docs/ISSUES.md` bugs against current code before
  touching anything, since that doc had already proven stale once (§2.1): **all
  three turned out to already be fixed or not real** — further confirmation it's
  pure history, not a live backlog. #5 (`.dio.post` interceptor bypass) — no
  `.dio.post(` call exists anywhere in `main_datasources.dart` anymore. #7
  (leading-slash inconsistency in `ListAPI`) — traced through Dio 5.9.1's actual
  `RequestOptions.uri` path-joining logic (`options.dart:628-643`): it normalizes
  away a doubled or missing slash at the base-URL/path join regardless of which
  style a given `ListAPI` constant uses, given `BASE_URL` ends in `/` (it does) —
  cosmetically inconsistent, functionally harmless, left as-is rather than a
  no-op stylistic sweep. #12 (`checkShift` swallowing network errors as "no
  shift") — current code already separates the 404-means-"none" case from a real
  `DioException`/`UnknownFailure`, correctly. Nothing to fix for this bullet; no
  code changed.
- **Done:** `ConnectivityCubit` now runs an application-level reachability probe
  (`GET` to the bare base URL, `validateStatus: (_) => true` so any HTTP response
  counts as reachable — only a connection-level failure counts as not) alongside
  the existing `connectivity_plus` link-state check: a 20s periodic probe while
  the link is up, plus an immediate probe on every link-state change. Reuses the
  app's existing `DioClient` (same TLS trust config, same interceptor stack) via a
  post-construction `attachProbeClient()` call from `di.dart`, rather than a second
  HTTP client — avoids both the constructor-time circular dependency (`DioClient`
  already depends on `ConnectivityCubit`) and a `dart:io`-on-web compile risk a
  from-scratch client would add. Every existing consumer of
  `ConnectivityCubit.isOnline` (the offline interceptor, `CreateOrderBloc`,
  `PaymentBloc`, ~11 call sites total) gets the more accurate signal automatically —
  no call-site changes needed.
- **Done:** exponential backoff with jitter in `OfflineQueueService.syncAll` (5s
  base, 2min cap, resets on a fully-clean pass) and
  `LanHubClient._scheduleReconnect` (2s base, 30s cap, resets on successful
  connect) — both were flat/immediate before. Also added a re-entrancy guard
  (`_isSyncing`) to `syncAll`, since adding a periodic tick (below) alongside the
  existing reconnect-edge trigger means two callers could otherwise race and post
  the same queued operation twice — a correctness gap the original implementation
  never had to guard against when it only ever had one caller.
- **Done:** thin `SyncEngine` shell (`lib/core/sync/sync_engine.dart`) — a 60s
  periodic tick that drains the outbox (if non-empty) and refreshes the goods
  cache (reusing `CacheService.prefetchAllGoods`'s existing 30-min staleness check,
  so the extra calls are cheap no-ops most of the time). `app_scaffold.dart`'s
  reconnect-edge listener now calls `SyncEngine.tick()` instead of reaching into
  `OfflineQueueService`/`CacheService` directly — removes those two direct
  dependencies from a client-layer widget, a small concrete step toward §3's
  two-layer split.
- *Verification done:* `flutter analyze` — 0 new issues introduced (70 pre-existing
  issues elsewhere in the codebase, unrelated to this change).
- *Verification still needed, not done this session:* no emulator or live backend
  was exercised — the cable-pull acceptance test below is still manual/pending.
- *Acceptance:* existing flows behave identically; logs prove the periodic tick and
  reachability probe fire correctly in a manual cable-pull test.

**Phase 1 — Generalize the outbox, adopt idempotency (medium risk) — implemented 2026-08-01, partial**

- **Deferred: the `/orders/batch` switch.** Checked the actual response schema in
  `api-docs/swagger.json` before touching anything, given §2.2's own warning that
  the sync endpoints were unproven: `model.SuccessResponse` — the batch endpoint's
  documented `201` response — is just `{status, message}`, with **no per-order
  results**. With `continue_on_error: true` there is no way to tell which orders in
  a batch actually succeeded vs. failed from that shape alone. Switching the outbox
  to batch replay without that would risk exactly the failure mode this plan exists
  to prevent — deleting a locally-queued order from the outbox that the server
  actually rejected. Left the existing serial single-order-POST replay in place (it
  gives an unambiguous per-request HTTP status) and flagged this for the backend
  team: confirm whether the real response actually includes per-order results
  before revisiting.
- **Done, narrower than planned: client-generated order id, not a full idempotency
  scheme.** `CreateOrderRequestModel` now carries an `id` (hand-rolled RFC4122 v4
  UUID, `lib/core/utils/uuid.dart` — no new dependency, since the backend's
  documented example is a real UUID shape and may validate against it) sent on
  every order-creation path — online, offline-queued, and the saved-draft path in
  `DetailBloc.saveOrder`. A connection-failure retry in `create_order_bloc.dart`
  reuses the same id rather than generating a new one, so a request that actually
  landed server-side before the response was lost doesn't risk becoming a second
  order under a different id. **Still unverified** (no backend source access, no
  live server to test against): whether resubmitting the same `id` is actually
  deduped server-side, or accepted as a duplicate row, or rejected. Flagged as a
  cross-team question, not assumed solved.
- **Not done: the per-table FIFO ordering rewrite.** With `/orders/batch` deferred,
  there was no forcing reason to touch the type-partitioned loop structure this
  round. The three new op types below were added as three more type-partitioned
  loops in dependency order (`cancelLineItems` → `payOrder` → `openShift` →
  `closeShift`, with `closeShift` explicitly run after `openShift` so a same-pass
  open-then-close has something to find) — consistent with, not a fix for, the
  known type-partitioned-vs-per-table-chronological gap from §2.1.
- **Not applicable: stock add/remove deltas.** Checked first — there is no
  stock/inventory adjustment feature anywhere in the Flutter client today (grepped
  across all of `lib/features`, zero hits). The backend endpoints exist (§2.2) but
  nothing in the app calls them. Nothing to wire into the outbox; building a new
  stock-management UI would be a different, unrequested scope than "generalize the
  existing outbox."
- **Done: shift open/close**, replacing `ShiftBloc`'s dead-end local-only fallback.
  `_openShift` now distinguishes a real rejection (shown to the user, no fabricated
  shift) from a `ConnectionFailure` (offline-friendly local shift as before, now
  also enqueued as a new `openShift` op). `_closeShift` does the same — the
  previously-permanent "closed offline, won't be sent to server" case is now queued
  as a `closeShift` op instead. Both new op types key on `cash_register_id`, not the
  shift's own id (which doesn't exist yet for an offline-opened shift), mirroring
  the existing `addItems`-resolves-by-table pattern rather than inventing a new one.
  `closeShift` replay looks up the real active shift by register id; if none is
  found yet (the paired `openShift` hasn't synced), it stays queued rather than
  being dropped as stale — biased toward "visibly stuck" over "silently lost."
  **Known gap accepted for this round:** once these sync in the background, the
  locally-cached shift record (`SharedPreferences`) isn't proactively updated to
  the real server state — the UI self-corrects on the next explicit shift check
  (e.g. app relaunch), not instantly. Fixing that needs a callback path from the
  queue back to the Bloc, which fits Phase 6 (observability/reconciliation) better
  than this phase.
- **Done: item cancel and quantity-change**, replacing `DetailBloc`'s silent-failure
  paths. Both `_deleteExistingByKey` and `_onSyncExistingItem` now check whether a
  failure is connection-related (same `DioExceptionType` check already used in
  `CreateOrderBloc`) and, if so, enqueue a compensating operation instead of letting
  the global interceptor show a toast while the optimistic UI silently reverts on
  refetch. Reused the existing `addItems` op type for "add more of this good" rather
  than inventing a parallel mechanism, and added one new op type, `cancelLineItems`
  ("cancel these line ids"), used by both the delete-item path and the
  quantity-decrease path — the latter cancels the original lines and re-adds the
  remainder as a new line, mirroring the existing online behavior exactly (the
  backend has no "reduce an existing line's quantity" endpoint).
- *Verification done:* `flutter analyze` — 0 new issues (same 70 pre-existing,
  unrelated issues as Phase 0's run). `dart run build_runner build
  --delete-conflicting-outputs` succeeded cleanly, regenerating
  `pending_operation.g.dart` (new enum cases) and
  `create_order_request_model.freezed.dart` (new `id` field) — no hand-edited
  generated code.
- *Verification still needed, not done this session:* no emulator or live backend —
  none of this has been exercised against a real device, a real cash-register
  shift, or a real order.
- *Acceptance:* pulling the network cable mid-service for shift open/close and item
  cancel/quantity-change produces a queued, later-synced record — never a silent
  loss or an unreconciled local shift. (Stock deltas N/A — no such flow exists in
  the client. `/orders/batch` deferred — existing per-order replay already met this
  bar before this phase.)

**Phase 2 — Repository seam: close the "not wired at all" gap (biggest single lift) — complete 2026-08-01**

- **Done: `ArchivesBloc`/`ArchiveBloc`.** New `ArchivesLocalRepository` (domain
  interface, `lib/features/view/main/domain/repository/archives_local_repository.dart`)
  / `ArchivesLocalRepositoryImpl` (data — wraps the existing `MainRepository`
  rather than reimplementing the HTTP calls, adds cache-first + connectivity-aware
  behavior) replaces the two usecases (`GetArchivesUsecase`,
  `GetArchiveWithIdUsecase`, both deleted — nothing else referenced them) that both
  Blocs previously called directly. `CacheService` gained `saveArchivesList` /
  `getArchivesList` and `saveArchiveDetail` / `getArchiveDetail`.
  **Deliberately scoped down from §3's full ambition:** still `Future`-based
  (`Either<Failure, T>`), not the `Stream`-based "reacts uniformly to local/LAN/
  cloud writes" interface described in §3 — archives are read-only history, so
  there's no write path needing that; forcing every repository through a `Stream`
  contract this early would multiply this phase's scope for no benefit here. Only
  the unfiltered/first-page list is cached, not every filter/pagination
  combination — matches "the screen you had open when the connection dropped
  stays usable," not full offline archive search.
- **Done: `DepartmentSelectionCubit`.** New `MenuLocalRepository` /
  `MenuLocalRepositoryImpl` (same shape as the archives one — wraps
  `MainRepository`, adds cache-first + connectivity-aware behavior) covers
  `getDepartments()`/`getCategories()`; `searchGoodsByName()` stays a live,
  uncached call (a text search against a potentially large catalog has no
  bounded local mirror to fall back to — offline just means no results, same as
  before). **Unlike the archives slice, the three usecases this Cubit used
  before (`GetDepartmentsUsecase`, `GetCategoriesUsecase`,
  `GetGoodsWithNameUseCase`) were NOT deleted** — checked first and found
  `GetDepartmentsUsecase` is also used by `printer_service.dart`, and the other
  two by `detail_bloc.dart`; both are outside this slice's scope, so the
  usecases stay registered and untouched, and only `DepartmentSelectionCubit`
  itself moved onto the new repository. Also fixed a real gap while doing this:
  the Cubit previously cached departments (via a direct, inline
  `CacheService.saveDepartments` call it made itself) but never cached
  categories at all — `MenuLocalRepositoryImpl` now caches both, and the Cubit
  no longer touches `CacheService` directly at all (down to zero imports of
  it — a concrete instance of §3's "client layer doesn't reach into sync
  internals" goal, not just an aspiration).
- **Done: `TableTimerCubit`.** New `TableTimerLocalRepository` /
  `TableTimerLocalRepositoryImpl` — but **deliberately not the same shape as
  the other two.** No `CacheService`, no `ConnectivityCubit`, no cache-first
  fallback, and (unlike everything queued so far) start/pause/resume are
  **not** enqueued to the offline outbox on connection failure. Per §5's
  conflict matrix, table-timer sessions are the one kind of state where
  "cloud is the metering source of truth" — a paused/resumed timestamp
  determines how much a guest owes, so replaying a queued pause/resume later
  (whenever connectivity happens to return) would bill for the wrong
  interval, possibly silently over- or under-charging. This repository exists
  purely to get `DioClient`/`ListAPI`/raw-endpoint-string usage out of the
  presentation layer and centralize error mapping through the same
  `handleDioException` every other repository/datasource uses — it adds zero
  offline capability by design, and that's the correct call here, not a gap.
  The Cubit itself (538 lines) keeps 100% of its live-tick/anchoring/
  segment-overlay logic untouched; only the six direct `_client.get`/
  `_client.post` call sites moved into the repository, each mapped back to
  the exact pre-existing UI outcome (see below) rather than a generic
  success/failure split.
  **Behavior preserved exactly, including subtle per-branch differences that
  would've been easy to collapse:** `fetchTimer`'s old code had five distinct
  outcomes spread across a non-Map-data check, a not-time-based check, a
  400/404 `DioException` branch, an other-`DioException` branch, and a
  generic catch-all — each with slightly different combinations of
  hide-the-block / cancel-timers / clear-active-order-id / show-error-message.
  These now map onto `Failure` subtypes (`NotFoundFailure`/`ValidationFailure`
  → the old 400/404 silent-hide branch; `ParsingFailure`/`UnknownFailure` →
  the old generic-catch hide-with-error branch; everything else → the old
  "transient, keep showing stale state, just surface the error" branch) so
  the fold in the Cubit reproduces each one instead of averaging them together.
  **Two intentional, narrow behavior changes, both strictly safer, both
  called out rather than silently introduced:** (1) the old "non-Map `data`"
  branch didn't call `_cancelTimers()` (unlike the structurally-identical
  "parsed but not time-based" branch right below it in the old code) — almost
  certainly an oversight, since it could leave an orphaned 1s UI-tick
  `Timer.periodic` running invisibly behind a hidden block; both branches now
  cancel timers. (2) error *messages* for failures now prefer the backend's
  own `error`/`message` field (via `MessageFailure`, same as every other
  repository) instead of Dio's generic exception description
  (`e.message`/`e.toString()`), which for an HTTP error response was never the
  backend's actual message to begin with — same class of fix as the
  categories-caching gap in the department-selection slice, not scope creep.
  `_fetchBillDetails`'s pre-existing fully-silent catch-all (never surfaced
  billing-segment fetch errors to the UI at all) is unchanged.
  `ListAPI.archiveWithId(id)` (`/api/v1/bills/{id}`) now replaces a hardcoded
  duplicate of that same path string that lived in the Cubit.
- **Done: `WaiterCubit`.** The largest and most transactionally complex of
  the four, done last deliberately — it's the one Bloc in the original audit
  marked "not wired at all" that also *mutates* state (create/cancel/send/
  close), so this slice is where Phase 2 and Phase 1's offline-queue work
  actually meet. New `WaiterLocalRepository` / `WaiterLocalRepositoryImpl`
  (4 dependencies — `DioClient`, `MainRepository`, `CacheService`,
  `ConnectivityCubit` — one more than Archives/Menu/TableTimer because it
  folds in `GetStaffWaitersUsecase`'s logic too, deleted after confirming via
  grep it had no other consumers) covers all 8 of the Cubit's HTTP call
  sites. Split by risk, matching how this whole phase was ordered:
  - **Reads — cache-first for the list, live-only for detail.**
    `getOpenOrders` gets the exact same cache-first treatment as archives/
    departments (default first-page view only, keyed additionally by
    `myOrders` vs `branchOrders` so switching roles can't show the wrong
    cached list). `getOrderDetail`/`getOrderItems` are deliberately
    **live-only, no cache** — unlike archive history, an open order keeps
    changing, and a stale cached item list could understate what a guest
    owes; this mirrors table-timer's "don't cache what could silently be
    wrong" reasoning from the previous slice, applied to a different kind of
    staleness risk.
  - **Writes — reuse Phase 1's outbox exactly as built, add optimistic local
    updates.** `cancelOrderItem`/`sendItems`/`closeOrder`/`createOrder` now
    detect `ConnectionFailure` (matching `create_order_bloc.dart`/
    `payment_bloc.dart`/`shift_bloc.dart`'s existing convention — see the
    inconsistency note below) and enqueue via the **same** `PendingOperation`
    types those Blocs already use (`cancelLineItems`, `addItems`, `payOrder`,
    `createOrder`) with the **same** payload shapes the sync loop already
    replays — no changes to `OfflineQueueService` were needed for this slice.
    What *is* new: every one of these four write paths previously left the
    UI showing nothing-changed-yet on a queued action (a refetch that would
    just fail while offline) — each now applies an optimistic local update
    matching what the eventual sync will produce: cancelling marks the line
    item `cancelled` in place (`OrderLineItemModel` gained a `copyWith` for
    this — it had none before), sending items appends synthetic
    `OrderLineItemModel` rows (status `pending`, a fresh client UUID),
    closing an order removes it from the list and **prints the receipt
    immediately from the already-locally-computed total** (mirroring
    `payment_bloc.dart`'s established "queue it, treat as succeeded, print
    now" pattern exactly, via a new shared `_finishCloseOrderLocally` used by
    both the online-success and offline-queued paths), and creating an order
    inserts an optimistic `OpenOrderModel` keyed on a client-generated UUID
    (reusing `generateUuidV4()` from Phase 0) exactly like
    `create_order_bloc.dart` already does. `OpenOrderModel` gained a `toJson`
    (it had `fromJson` but no inverse) to support the new open-orders cache.
  - **Two called-out, strictly-safer deviations, same bar as table-timer's:**
    (1) `createOrder`'s success path previously had no guard at all against a
    missing/empty response `id` — it would have silently built a broken
    empty-id order. The repository now reports `EmptyFailure` in that case
    (an existing `Failure` type already used this way for table-timer),
    surfaced as a normal error instead. (2) error messages throughout prefer
    the backend's own `error`/`message` text (`MessageFailure`) over Dio's
    generic exception description, same as every prior slice.
  - **Observed but deliberately not touched:** the codebase has two
    different definitions of "connection issue worth queuing" —
    `detail_bloc.dart`'s raw-`DioException` `_isConnectionIssue` treats
    connection errors *and* all three timeout types as queue-worthy;
    `create_order_bloc.dart`/`payment_bloc.dart`/`shift_bloc.dart` (and now
    this slice) check only `is ConnectionFailure`, which excludes timeouts.
    This slice matches the majority/more-recent convention rather than
    silently expanding scope to reconcile the two — worth a deliberate pass
    in Phase 6, not a side effect of a repository migration.
  - **Not touched:** LAN table-status broadcasting on order create/close —
    `WaiterCubit` doesn't do this today (online or offline), unlike
    `create_order_bloc.dart`/`payment_bloc.dart` which do; adding it would be
    new functionality, not preserved-plus-offline behavior, and belongs with
    Phase 4's LAN work instead.
- *Verification done (all four slices):* `flutter analyze` — 0 new issues in
  every slice (one real pre-existing bug caught and fixed in the archives
  slice — `ArchivesFilterRequestEntity.pagination` is nullable, an unguarded
  `.offset` access on it was a genuine compile error, not a style nit — plus
  a couple of self-introduced `unnecessary_import` infos in the table-timer
  slice, fixed before commit).
- *Verification still needed:* none of the four slices has been exercised
  against a live backend/device yet. Archives/departments/waiter-list: the
  cache-hit path (use the screen online once, go offline, confirm the last
  data still renders) is untested beyond static analysis. Table-timer: every
  preserved-behavior branch (400/404, malformed response, generic network
  error, 409-conflict recovery) needs a manual pass. `WaiterCubit` needs the
  most: all four optimistic-write paths above, end to end — create an order
  offline, add items to it offline, cancel one offline, close it offline,
  reconnect, and confirm the outbox drains to a server state matching what
  was shown locally the whole time. This is the highest-stakes untested path
  in the whole plan so far (real money, real order mutations) and should be
  the first thing a soak test (Phase 6) exercises.
- *Acceptance:* all four Phase-2 target Blocs (`ArchivesBloc`/`ArchiveBloc`,
  `DepartmentSelectionCubit`, `TableTimerCubit`, `WaiterCubit`) are off direct
  `DioClient`/usecase access and behind a `XxxLocalRepository` seam. Archive/
  history browsing, department/category selection, and the waiter's open-
  orders list survive an offline reopen for their common cases. Table-timer
  fails predictably and centrally instead of via inline try/catch (still
  online-only by design — cloud is the metering authority). The waiter panel
  can now create, add to, cancel from, and close orders while offline, with
  every write queued through the same outbox `detail_bloc.dart`/
  `create_order_bloc.dart`/`shift_bloc.dart` already use, and the UI reflects
  each action immediately rather than waiting for a sync that can't happen
  yet. Phase 2 is done; Phase 3 (typed Hive store) is next per the original
  ordering, though Phase 4's priority-raise (§ above) still applies.

**Phase 3 — Restructure the local store into typed Hive records (medium risk) —
skipped for now 2026-08-01, revisit on real pain**
- Replace today's raw-JSON Hive blobs and the 3-type `PendingOperation` with proper
  typed, `HiveType`-adapted records per aggregate: orders, order_items, payments,
  shift_sessions, print_jobs, outbox, sync_cursor — the same generator pipeline
  (`hive_generator`/`build_runner`) already wired into the project, no new dependency.
- Add the in-memory indices needed for per-table FIFO outbox ordering and print-job
  claims (§8) — built at startup from box contents, cheap at this data scale.
- Write a one-time migration draining the existing 3-type `PendingOperation` box into
  the new typed outbox on first launch post-upgrade, so in-flight offline work isn't
  lost across the upgrade.
- *Escalation condition, not a default:* if this hits real pain in practice — genuine
  need for atomic multi-row writes across aggregates, or cross-entity reporting
  queries Hive can't serve without excessive Dart-side iteration — revisit
  Drift/sqlite3 then, with the specific pain point in hand rather than speculatively.
- **Decision: this phase's own stated condition isn't met, so it's skipped rather than
  done speculatively.** By the time Phase 2 finished, `CacheService`'s raw-JSON-blob
  pattern had been extended cleanly across four repositories (archives, menu, waiter
  open-orders, plus the pre-existing order-detail/goods/departments caches) with zero
  friction — no atomic multi-row write need has come up, no cross-entity reporting
  query has come up. Separately, the "3-type `PendingOperation`" this phase set out to
  replace was already a typed `HiveType`/`HiveField`-adapted class from before this
  plan even started (confirmed in Phase 0's audit) and has since grown to 6 types
  (§11 Phase 0/1) without needing the restructure either. Revisit this phase if/when
  Phase 6's soak testing (or real field use) surfaces an actual limitation — not before.
- *Acceptance (deferred):* a soak test (Phase 6) runs a full simulated offline shift
  against the current store without data loss; if that's where the real pain shows up,
  that's the trigger to come back to this phase with a concrete problem in hand.

**Phase 4 — LAN cluster hardening + sole-uplink relay (priority raised 2026-08-01) —
auth + core relay done 2026-08-01, hardening extras not started**
- mDNS discovery, terminal-JWT auth on the WebSocket handshake, richer
  `LanHubMessage` protocol (order/payment/print-job events, not just table status),
  "operating solo" banner, guard against two manually-configured servers.
- **New scope from the confirmed local-server decision (§1 Q5, §7):** followers'
  `SyncEngine` forwards queued outbox operations to the leader instead of posting to
  the cloud directly; the leader's `LanCluster` accepts and replays them alongside
  its own, authenticating to the cloud with the permanent branch-scoped terminal
  JWT rather than a per-staff session.
- **Every branch now depends on its leader for all cloud sync, not just LAN-only
  branches** — this phase is more load-bearing than its original position implied.
  Consider pulling it forward, e.g. running it alongside Phase 1 rather than after
  Phase 3.
- **Done: WebSocket handshake auth — but reusing the logged-in staff session JWT,
  not the permanent terminal JWT this section originally sketched.** Before building
  the relay itself, the existing `LanHubServer` was a completely open, unauthenticated
  `dart:io` `WebSocket`/`HttpServer` — any device on the branch WiFi that knew the
  IP:port could connect and inject messages. That was a narrow problem while the only
  message type was table-status (cosmetic spoofing at worst); it would have become a
  real one the moment the relay starts forwarding outbox operations, since a rogue
  device could then inject fake orders/payments that the leader would forward to the
  cloud under its own trusted identity. Auth had to land before the relay, not after.
  **Given a choice between the permanent-terminal-JWT flow (new brand-admin-password
  provisioning UI, matches what `POST /auth/terminal/token` was built for) and reusing
  the already-logged-in staff member's existing session JWT, the session-JWT route was
  chosen** — no new credential-entry UI, no admin password handling, reuses auth that
  already exists. Concretely:
  - `LanHubMessage` gained `auth`/`authOk`/`authFail` types (`token`, `branch_id`,
    `reason` fields) alongside the existing `tableStatus`/`ping`.
  - `LanHubServer` no longer adds a socket to its broadcast set on connect. It holds
    the socket in a pending state, waits up to 5s for an `auth` message, and only
    promotes it to a real client after an injected `LanAuthValidator` callback
    approves it — otherwise sends `authFail` (with a reason) and closes. This keeps
    the transport class decoupled from app-level auth concerns (mirrors the
    repository-interface pattern from Phase 2 — the mechanism lives here, the
    *decision* lives in `LanHubService`).
  - `LanHubClient` sends its `auth` message immediately after the socket opens
    (before anything else) and now gates `isConnected` on having received `authOk`,
    not just "socket open" — a still-mid-handshake connection isn't usable yet. An
    `authFail` reason is captured and surfaced through to the settings screen's
    status card instead of a generic "disconnected."
  - `LanHubService` (now depending on `AppTokenStorage` and `ConnectivityCubit`, both
    already app-wide singletons) supplies the actual decisions: the connecting
    follower's token + branch id come from `AppTokenStorage.readAccessToken()` +
    the current `UserBloc` state, re-read fresh on every (re)connect attempt so a
    token refresh or a different staff member logging in is picked up automatically.
    The leader validates an incoming `(token, branchId)` pair by, first, rejecting
    anything whose branch doesn't match its own; then, **if the leader itself
    currently has cloud connectivity**, round-tripping the presented token through
    `GET /api/v1/user/me` (via a bare, one-off `Dio` instance — deliberately bypassing
    `DioClient`'s interceptor, which would otherwise unconditionally overwrite the
    `Authorization` header with the *leader's own* token) to confirm it's live and
    branch-matched server-side; **if the leader has no cloud connectivity right now**,
    it falls back to a local, signature-less check (decode the JWT payload, confirm
    `exp` hasn't passed) rather than refusing every follower outright — refusing LAN
    traffic specifically because the branch is offline together would defeat the one
    scenario this whole mechanism exists for.
  - Fixed a DI-ordering hazard this introduced: `LanHubService.init()` (called eagerly
    during app startup) can now, in `client` mode, need `inject<UserBloc>()` for the
    initial connect attempt — but `UserBloc` wasn't registered until later in the same
    setup function. `lib/di.dart` now constructs and registers `LanHubService` where
    it did before, but defers the actual `await lanHubService.init()` call to after
    `_cubit()` runs, mirroring the existing `connectivityCubit.attachProbeClient(...)`
    precedent for the same class of problem (Phase 0).
  - **Residual risk, disclosed rather than glossed over:** the session token is sent
    over the LAN WebSocket in cleartext (`ws://`, no TLS) — every other place this
    same token travels goes over `https://` (`BASE_URL`), so this introduces one new,
    LAN-scoped cleartext hop for an otherwise TLS-protected credential. A capable
    attacker already on the same branch WiFi with packet capture could intercept a
    valid session token in transit. This is a real, meaningfully-smaller-than-before
    exposure (was: anyone can inject anything, unauthenticated; now: a passive
    on-network attacker can potentially harvest one active token) — not a closed hole.
    Closing it fully means `wss://` (TLS), which needs certificate provisioning for
    what's effectively an ad-hoc peer-to-peer LAN server — out of scope for this
    slice, worth a line item before this ships to real branches. Separately, the
    offline fallback path never verifies a signature (no local copy of the backend's
    signing key) — it can only catch an *expired* token, not a *forged* one; that
    weaker check only kicks in when the leader itself is already offline.
  - *Verification still needed:* no live two-terminal test yet (one real device
    connecting to another over an actual LAN, both branches of the online/offline
    validator path, the timeout-reject path, and the settings screen's new
    rejection-reason text) — everything above is confirmed only via `flutter analyze`
    (0 new issues) and code review, not exercised against a running pair of terminals.
- **Done: the sole-uplink relay itself — followers forward queued outbox operations
  to the leader; the leader executes them against the cloud and reports back.** One
  adjustment from this section's original sketch: the leader authenticates to the
  cloud with **its own already-logged-in staff session** (same `DioClient`/`inject
  <DioClient>()` every other cloud call on that terminal already uses), not a
  "permanent branch-scoped terminal JWT" — consistent with the auth slice above
  choosing session-JWT reuse over building the terminal-JWT provisioning flow.
  - **Refactored `OfflineQueueService.syncAll` before building anything on top of
    it**, since the relay needs to execute one arbitrary queued op on demand, not
    just iterate its own box. The six per-type blocks (createOrder, addItems,
    cancelLineItems, payOrder, openShift, closeShift) each now return an `OpOutcome`
    (`synced` / `dropped` / `retryableFailure` / `notReadyYet`) instead of directly
    deleting from the box or setting the backoff flag inline — `syncAll`'s loops
    translate that outcome into exactly the same delete/keep/backoff behavior as
    before. This was the highest-risk step of this slice (touching live,
    already-working money-handling replay logic), done with the same
    branch-by-branch preservation discipline as the Phase 2 Cubit migrations — every
    original code path (including `closeShift`'s "underlying openShift hasn't landed
    yet, leave queued but don't count as a failure" special case, preserved as
    `notReadyYet`) maps to an identical observable outcome, confirmed by re-reading
    the original six blocks line by line against the new ones.
  - New `OfflineQueueService.executeRelayedOp(dio, op)` (leader side) reuses that
    same per-type executor for a `PendingOperation` that isn't in this leader's own
    box at all — it never touches `_box`, just runs the op and reports
    `RelayOpResult` (`synced` / `terminalFailure` / `retryLater`).
  - New `OfflineQueueService.relayViaLan({isLeaderConnected, relayOne})` (follower
    side) walks `pending` and, for each op, calls the injected `relayOne` callback
    and deletes locally only on `synced`/`terminalFailure` — `retryLater` or no reply
    at all leaves it queued for the next pass. Callback-based (not a direct
    `LanHubService` reference) so `offline_queue_service.dart` stays decoupled from
    the LAN module, mirroring `LanHubServer`'s own `LanAuthValidator`/`LanRelayHandler`
    typedefs — the pattern established in the auth slice reused here on purpose.
  - `LanHubMessage` gained `relayOp` (`op_id`, `op_type`, `op_payload`, `op_table_id`,
    `op_created_at` — mirrors `PendingOperation`'s own fields) and `relayOpResult`
    (`op_id`, `result`).
  - `LanHubServer` now special-cases an authenticated connection's `relayOp` message:
    routes it to an injected `LanRelayHandler` and replies **only to the sender**
    with a `relayOpResult`, instead of the default `_broadcastExcept` fan-out every
    other message type still gets (a relay request is a directed RPC, not a
    broadcast-worthy event like table status).
  - `LanHubClient` gained `relayOp(...)` — send the request, correlate the reply by
    `op_id` via its existing `onMessage` stream, bounded by a timeout (see below).
  - `LanHubService` bridges both sides: `_handleRelayOp` (leader) reconstructs a
    `PendingOperation` from the wire fields and calls `executeRelayedOp` using
    `inject<DioClient>()` + `inject<OfflineQueueService>()`; `relayOperation` (follower)
    calls `_client.relayOp(...)` and parses the result string back to `RelayOpResult`.
  - `SyncEngine.tick()` now branches on `LanHubService.mode`: `client` relays via LAN
    (and deliberately does **not** gate on this terminal's own `ConnectivityCubit` —
    a follower with no internet of its own but a live LAN link to the leader must
    still be able to sync, which was the entire point); `server`/`disabled` behave
    exactly as before (direct-to-cloud via this terminal's own connectivity). Cache
    refresh (`prefetchAllGoods`) is unchanged either way — relaying arbitrary reads
    through the leader is a separate, bigger feature this phase doesn't attempt.
  - Fixed a second DI-ordering issue in the same spirit as the auth slice's: `di.dart`
    now constructs `LanHubService` *before* `SyncEngine` (`SyncEngine` needs it as a
    constructor dependency), still deferring the actual `lanHubService.init()` call
    to the end of `initDi()`.
  - **Residual risk, disclosed rather than glossed over:** the relay adds one more
    network hop (LAN, in addition to the leader's own cloud call) where a "the
    operation actually landed server-side but the confirmation never made it back"
    gap can occur — if the follower's 60s wait times out, it retries an op that may
    have already succeeded. This is not a new *class* of risk — the exact same gap
    already exists in `syncAll`'s direct-to-cloud path if a connection drops between
    request and response, and the backend has no idempotency-key mechanism for any
    of the six op types (confirmed in §2's audit) — but the relay hop makes it
    *somewhat* more likely to occur in practice (two network hops with a timeout
    each, instead of one), and it matters most for `payOrder` specifically (a
    duplicate-charge risk, not just a duplicate no-op). `createOrder`'s client-UUID
    scheme and `cancelLineItems`'s 404-tolerance already blunt this for those two op
    types; `payOrder` has no equivalent protection on the backend today. The 60s
    relay timeout (comfortably above the leader's own 30s `DioClient` timeout, plus
    margin for multi-call ops like `cancelLineItems`/`closeShift`) reduces how often
    this triggers but doesn't close it — closing it for real needs a backend
    idempotency key per operation, out of scope for a client-only change.
  - *Verification still needed:* none of this has been exercised against two real
    terminals yet — a follower with pending ops relaying through a leader with live
    cloud access, a leader that's itself offline (relay should report `retryLater`
    consistently, not crash), a follower's LAN link dropping mid-relay (should leave
    the in-flight op queued, not lose it), and a timeout firing on a slow relayed op
    are all unverified beyond `flutter analyze` (0 new issues) and code review.
  - **Not started:** mDNS discovery, the "operating solo" banner, and the guard
    against two manually-configured servers — none of these block the relay
    mechanism itself, they're operational polish (auto-discovery instead of typing
    an IP, visibility into cluster health) layered on top of what now exists.
- *Acceptance:* a device presenting no token, an empty branch id, a mismatched branch
  id, or an expired token cannot join the leader's broadcast set or get anything
  relayed; one presenting a live, same-branch token can do both. A follower with no
  internet of its own but a live LAN link to its leader can still create/modify/close
  orders, open/close shifts, and cancel line items — each op is queued locally,
  handed to the leader over LAN, and only cleared once the leader confirms it landed
  (or was terminally rejected) server-side. Solo-mode banner and the two-server guard
  remain open per the "not started" list above.

**Phase 5 — Print subsystem: job queue + USB relay**
- `PrintJob` table, claim/lease state machine, LAN-relay path for USB-owned
  printers, persisted retry/reprint for kitchen tickets, dedupe for cashier/
  close-check receipts.
- *Acceptance:* closing a check on a terminal with no physically attached receipt
  printer produces exactly one printout on the owning terminal — including across a
  simulated claim-timeout (kill the owner mid-print: confirm one eventual reprint,
  never zero, never two).

**Phase 6 — Offline auth hardening, observability, testing**
- Secure-storage migration for cached credentials, TTL + operator-visible expiry,
  privileged-action offline audit log.
- Real sync-status UI: outbox depth, cluster role/peers, printer reachability,
  last-sync time, quarantine list with manual resolution — replacing today's binary
  banner.
- Deterministic tests: partition simulation, clock-skew, leader-kill-during-open-
  transaction, duplicate-delivery, full-shift offline-then-reconnect soak test —
  filling today's zero-coverage gap.

**Phase 7 — Fiscal compliance gate (deferred — not currently in scope)**
- Per discussion, explicitly deferred: no fiscal/OKKM integration exists today and
  none is being designed for right now. Not started, not blocking Phases 0-6.
  Revisit if/when fiscal integration is scoped — at that point, re-examine Phase 5's
  cashier-receipt design (§8) against whatever legal constraint applies.

**Rollout mechanics:** feature-flag each phase; per-branch canary (pick one
low-volume branch first); during Phase 2 specifically, run old (direct-API) and new
(local-repository) code paths side by side with divergence logging before cutting
over, since that's the highest-blast-radius phase; rollback is a flag flip back to
the direct-API path, kept intact until each phase is proven in the field for
2-4 weeks.

---

## 12. What this design does not handle / residual risks

- A full local server mirroring the entire cloud API (the "miniature cloud backend"
  framing from the original prompt) is deliberately out of scope — the lighter relay
  model (§3, §7) means the LAN leader is **not** a substitute cloud when the leader
  itself also has no WAN. In that case every terminal, leader included, is
  independently offline against the cloud — which is fine (each already operates
  solo) but there is no "local-only cloud" fallback.
- True exactly-once delivery to the cloud needs the backend's cooperation
  (idempotency-key dedup) — the client alone can reduce but not eliminate duplicate-
  submission risk.
- Fiscal compliance is explicitly **not** resolved here, and is **deferred rather
  than blocking** for now per discussion (§1 Q6, §13) — no fiscal/OKKM integration
  exists today and Phase 7 is paused, not executed. Worth keeping the reasoning on
  record even while deferred: combined with §1 Q4's unbounded-outage answer, the
  likely eventual resolution is a **split** — order-taking, kitchen routing, and
  table management can reasonably run offline for a long time, but the payment/
  fiscal-receipt step may end up needing a bounded reconnection window. Revisit when
  fiscal integration is scoped.
- The `/sync/*` endpoints' lack of tenant/branch scoping is a backend-side risk this
  plan cannot fix from the client alone.
- Web target: both printing paths (raw TCP and Win32 USB) fundamentally cannot work
  in a browser sandbox. If the web build is meant to be a real POS terminal
  (unconfirmed — see §1 Q2), printing there needs an entirely different approach
  (e.g. a local print-agent process) not covered by this plan.

---

## 13. Three highest-risk decisions worth pushing back on

1. **Resolved 2026-08-01: one terminal is a real local server (sole cloud uplink),
   not independent-per-terminal sync (§1 Q5, §7).** Reverses this document's
   earlier recommendation. The user weighed the single-point-of-failure trade-off
   directly and chose it — no longer an open decision, but the operational
   consequence is worth stating plainly: **the whole branch loses cloud
   connectivity whenever the designated terminal is down**, until it returns or an
   admin manually promotes a different one. Local operation (reads, local
   write-queueing) is unaffected — only cloud sync stops. Worth a documented
   runbook (§11 Phase 4/6) for "the leader is down, here's what staff and admins
   do" — this will happen in practice, not just in theory.
2. **Client-generated order IDs are now sent (§11 Phase 1, implemented), but
   `/orders/batch` was deliberately not adopted** — its documented response
   (`{status, message}`, no per-order results) can't safely support telling which
   orders in a batch succeeded, so the outbox still replays orders as serial single
   POSTs (unambiguous per-request status, at the cost of more round-trips). Whether
   resending the same client order id is actually deduped server-side remains
   unverified — a cross-team question I can't resolve from the client alone.
   Order-item-level and non-order mutations (shift open/close, item cancel) have no
   id-based dedup at all yet, only the outbox's own at-least-once replay.
3. **Fiscal compliance (§1 Q6) — explicitly deferred, not currently blocking.** No
   fiscal/OKKM integration exists today, and per discussion this isn't being designed
   for right now; Phase 7 (§11) is paused rather than executed. Flagging so it isn't
   forgotten later: if fiscal integration gets scoped, revisit Phase 5's
   cashier-receipt design (§8) against whatever legal constraint applies — nothing
   built in Phases 0-6 assumes this is solved.
