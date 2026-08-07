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
  — Windows DPAPI / Keychain / Keystore under the hood). **Done, §11 Phase 6
  (2026-08-05, secure-storage-migration slice).**
- **TTL design — superseded by direct decision, not built as originally sketched
  below.** This section originally proposed a "local-authority renewal model" (a
  cached manager PIN re-authorizing other staff PINs on-device, tightened
  opportunistically by cloud re-checks) as the answer to §1 Q4's "outage may be
  unbounded" constraint ruling out a hard TTL. That was a reasonable design on
  paper but was never built — when the question was put to the user directly
  during Phase 6 execution, the actual answer was simpler and more direct: **no
  TTL of any kind, local-authority or time-based.** A cached credential stays
  valid until the terminal gets an actual, authoritative rejection from the
  server about it — see §11 Phase 6 for the full mechanism
  (`Failure.isDefiniteAuthRejection`, cache purge on confirmed rejection,
  reconnect-triggered re-validation). This makes the manager-PIN-renewal idea
  above moot: there is no expiring tier to renew. Left here, struck through in
  spirit rather than deleted, so a future reader doesn't rediscover the same
  design space and wonder why it wasn't picked.
- **Revocation lag** is bounded by reconnect frequency instead of a TTL — closer
  the terminal's reconnects, tighter the lag; a terminal that never reconnects
  again never learns of a revocation, an explicit accepted tradeoff (§11 Phase 6
  "Residual gap, disclosed"). No operator-visible "valid until HH:mm" countdown
  exists or is needed, since there's no countdown to show — this also means the
  "TTL + operator-visible expiry" line item that appeared at the top of §11
  Phase 6's original scope list was removed as stale once the no-TTL decision
  was made.
- **Privileged actions offline** (manager-gated voids and shift open/close — this
  codebase's actual scope, narrower than the original prompt's own list of
  "voids, discounts, drawer opens, price overrides," none of the latter three
  being gated by a manager check anywhere in the code): **done, §11 Phase 6
  (2026-08-05, fifth slice)**. Manager-pincode verification now falls back to
  the same offline credential cache regular PIN login uses (no separate TTL
  mechanism — reuses the first slice's "revoked only by the next definite
  server rejection" design), and every attempt — approved or denied, online or
  offline — is logged locally to a new append-only audit entity
  (`PrivilegedActionAuditLogService`), reviewable on-device via the
  sync-status section. **Not yet reviewable server-side** — no backend
  endpoint exists to submit these off-device, disclosed rather than assumed;
  sync-on-reconnect for this entity is real, un-started future work, not
  silently dropped scope.

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
auth + core relay + solo banner + discovery/conflict-guard done 2026-08-01**
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
  - *Verification done, added 2026-08-01:* `test/lan_hub_test.dart` — the codebase's
    first test for any of this, and only the second hand-written test file in the
    project (alongside `order_totals_test.dart`; `widget_test.dart` is unmodified
    `flutter create` boilerplate testing a counter app that doesn't match this POS
    app and was already failing before this session, unrelated to any of this work).
    Runs the **real** `LanHubServer`/`LanHubClient` — real `dart:io` `HttpServer`/
    `WebSocket` over loopback, no mocks — covering: a valid same-branch token being
    accepted and able to receive a broadcast; a wrong-branch token being rejected
    with a reason and never reaching the broadcast set; the exact token/branchId
    strings surviving the JSON round-trip to the validator unmodified; a relayed op
    executing end-to-end with the result correctly correlated back by `op_id`; two
    sequential relayed ops on the same connection not cross-talking; a relay
    request timing out cleanly (returns `null`, doesn't hang) when the handler never
    replies; and a connection that never sends its `auth` message being dropped
    after the real 5s server-side timeout. All 7 pass. **This covers the wire
    protocol layer only** — `LanHubService`'s app-level decisions (the actual
    `UserBloc`/`AppTokenStorage` branch/token lookup, the online-vs-offline
    validator split, `OfflineQueueService` wiring) aren't exercised here, since that
    needs the full DI graph; catching a real misunderstanding while writing this
    (an early draft test asserted `LanHubServer` itself rejects empty credentials —
    it doesn't, that check lives entirely in `LanHubService`'s validator) is itself
    a small data point for why this kind of test is worth having.
  - *Verification still needed:* still no test against two actual separate running
    app instances/devices — everything above runs the real network stack but within
    one test process. A leader that's itself offline (relay should report
    `retryLater` consistently, not crash), a follower's LAN link dropping mid-relay
    (should leave the in-flight op queued, not lose it), and the full
    `LanHubService`-level branch/token decision logic remain unverified beyond
    `flutter analyze` and code review.
- **Done: "operating solo" banner.** `LanHubClient` gained a `BehaviorSubject<bool>`-
  backed `connectionState` stream (seeded with the current value, so a widget that
  subscribes late still sees the current state immediately) — re-emitted at every
  point `isConnected` could change (auth accepted, auth rejected, disconnected,
  explicit `disconnect()`), always by re-reading the existing `isConnected` getter
  rather than tracked as a second, independently-maintained value, so it can't drift
  from what that getter would say. Exposed through `LanHubService.
  onClientConnectionChanged`. New `LanSoloBanner` widget (`lib/core/widgets/
  lan_solo_banner.dart`) mirrors `OfflineBanner`'s exact visual pattern (animated
  height-collapse strip, icon + text) and is mounted right below it in
  `AppScaffold` — reaching the same 11 screens `OfflineBanner` already covers, same
  known gap on the 4 screens with their own `Scaffold` (payment/detail/waiter/
  department-selection) that `OfflineBanner` already has, not a new one this adds.
  Deliberately a **distinct** indicator from `OfflineBanner`, not a merged/shared
  one: a `client`-mode follower can have perfectly good internet of its own and
  still be "solo" here, since Phase 4's relay design routes all outbox sync through
  the leader, never directly — the two conditions are orthogonal and can be true
  independently, so both banners can legitimately stack at once.
  - **Caught a real, newly-introduced bug while writing this, before it shipped:**
    the very first test run crashed with `Bad state: Cannot add new events after
    calling close`. `LanHubClient.dispose()` closes the socket, which can trigger
    `_onDisconnected` *asynchronously* (the `WebSocket.close()` future resolving
    doesn't guarantee the listener's `onDone` callback has already fired) — that
    handler was emitting onto `_connectionStateSubject` after `dispose()` had
    already closed it. Fixed by guarding every emission site through one
    `_emitConnectionState()` helper that checks `isClosed` first, rather than
    trusting `dispose()`'s call ordering to be race-free. This is exactly the kind
    of bug `flutter analyze` structurally cannot catch (it's a runtime ordering
    issue, not a type error) and the LAN test suite caught on the very first run —
    concrete evidence for why that test slice was worth adding before this one.
  - `LanSoloBanner` re-reads `mode` inside the `StreamBuilder`'s builder callback
    rather than gating on it with a separate check outside — `mode` itself has no
    stream, but every mode change in the app goes through `LanHubService.restart()`,
    which always calls `disconnect()` first, and `disconnect()` always emits on
    `connectionState`. Piggybacking the mode check on that same rebuild trigger
    means this banner doesn't need a polling `Timer` of its own to notice a mode
    change — consistent with the plan's own "scattered polling" finding (§2) this
    whole effort is trying to reduce, not add to.
  - *Verification:* `flutter test test/lan_hub_test.dart` (7/7, including the
    dispose-while-connected path that reproduced the race above) plus `flutter
    analyze` (0 new issues). Not yet visually confirmed in a running app — no
    screenshot/manual pass, just the underlying stream logic under test.
- **Done: discovery beacon + two-server conflict guard, added 2026-08-01.** Not
  actual mDNS/Bonjour — a hand-rolled UDP broadcast beacon (`LanDiscoveryService`,
  new), consistent with the rest of this LAN hub already being raw `dart:io`
  sockets rather than a pub.dev networking package:
  - A `server` broadcasts `{branch_id, ws_port}` every 2s on UDP port 8766 (a new
    port, separate from the WebSocket's 8765) to `255.255.255.255`, and, on that
    same socket, listens for any *other* hub announcing the same branch id — a
    split-brain signal that two terminals are both configured as `server` at once.
    Deliberately **detect-and-warn only, never automatic**: demoting one side
    automatically would need picking a "winner" with no reliable criteria, and this
    architecture already accepts a single leader as a known point of failure (§1 Q5)
    — resolving *which* terminal stays the leader is left to whoever's staffing the
    branch. Surfaced in the LAN settings screen as a red warning card naming the
    conflicting IP, shown alongside (not replacing) the existing status card.
  - A `client` can now run a bounded (4s) discovery scan (`LanHubService.
    discoverHubs()`) instead of only accepting a hand-typed IP — the settings
    screen's IP card gained a "search the local network" button that lists
    discovered hub IPs as tappable chips, filling the IP field on tap. Manual entry
    stays fully available as a fallback (a network that blocks UDP broadcast, or a
    hub not yet reached by a scan, still needs it) — this is additive, not a
    replacement.
  - An announcer filters out its own broadcast using a random per-process
    `instance_id` stamped on every packet it sends (not the source address — on one
    host, a leader's own announce-and-listen socket genuinely receives its own
    broadcast back, so address alone can't distinguish "me" from "someone else").
  - Not authenticated, and deliberately so: an announcement carries only a branch id
    and a port, never a token, and is used only to populate a picker or raise a
    warning — never to authorize anything. The real handshake still goes through
    `LanHubServer`'s existing JWT-based `auth` exchange (above) once a terminal
    dials whichever IP it picked, manually or via the scan.
  - *A real bug caught while writing the test, before it shipped:* the first draft
    of `test/lan_discovery_test.dart` deterministically failed (same tests, same
    failure, every run — not flaky) even though a standalone throwaway script using
    the identical `dart:io` UDP primitives worked fine. Root cause turned out to be
    in `LanDiscoveryService` itself, not the test or the environment: `_send()` sent
    every announcement to the hardcoded `defaultPort` constant instead of whichever
    port `startAnnouncing`/`startListening` had actually bound — invisible in
    production (every real caller uses the default port on both ends) but fatal for
    a test intentionally using non-default ports to avoid cross-test port
    collisions. Fixed by tracking the actually-bound port (`_activePort`) and
    sending to that instead of the constant. Confirmed by re-running the suite
    (deterministic failures → deterministic passes) — a good reminder that a
    *consistent* test failure, not just a flaky one, is still worth chasing to a
    root cause rather than assumed to be an environment quirk.
  - Also caught, while chasing the above: the test's own first draft for
    self-filtering ("an announcer never surfaces its own broadcast") would have
    passed even if broadcast delivery were completely broken, since it only ever
    asserted absence. Fixed by adding an independent third-party listener that must
    positively receive the same broadcast the announcer itself must not — so a
    fully-broken send path now fails this test instead of silently passing it.
  - *Verification:* `test/lan_discovery_test.dart` (4 tests, real UDP sockets over
    loopback, no mocking) — a listener hearing an announcer's fields correctly; an
    announcer never surfacing its own broadcast (witnessed independently, per
    above); two hubs on two different branches both heard distinctly; `stop()`
    actually halting the periodic beacon rather than leaking a live timer. All pass,
    alongside the existing 7 `lan_hub_test.dart` tests (11/11 total) and `flutter
    analyze` (69 issues, unchanged baseline). Same disclosed scope limit as the
    other LAN tests: one test process on loopback, not two physical machines on a
    real subnet — real-hardware broadcast delivery (firewall rules, multi-NIC
    routing, actual subnet behavior) remains unverified.
- *Acceptance:* a device presenting no token, an empty branch id, a mismatched branch
  id, or an expired token cannot join the leader's broadcast set or get anything
  relayed; one presenting a live, same-branch token can do both. A follower with no
  internet of its own but a live LAN link to its leader can still create/modify/close
  orders, open/close shifts, and cancel line items — each op is queued locally,
  handed to the leader over LAN, and only cleared once the leader confirms it landed
  (or was terminally rejected) server-side. A follower that loses its leader sees a
  visible "operating solo" indicator within moments (event-driven, not a poll
  interval) instead of silently failing sync in the background. A `client` can find
  its leader via a local-network scan instead of only manual IP entry, and a
  `server` is warned in-app if a second hub is ever heard on the same branch. Every
  item originally scoped for this phase is now built; what remains is the
  real-two-terminal verification called out throughout (leader offline mid-relay, a
  follower's LAN link dropping mid-relay, actual hardware broadcast behavior) —
  Phase 6's soak test is where that's scoped to happen.

**Branch note, 2026-08-05:** all of Phases 0-4 above were built on a branch
(`offline-again`) that had, in the meantime, diverged from `main` — `main` had
picked up independent, unrelated printer/receipt work (a "Test Printer" button,
USB-printer selection by Windows printer name instead of a first-USB-found guess,
an end-of-job beep signal, a cashier-receipt "closed by" name field, plus the
`CacheService` storage backing the printer-name choice) done directly on `main`
while this plan's execution stayed on its own branch. Since Phase 5 is exactly
the print subsystem and would touch these same files, `main` was merged into
`offline-again` **before** starting Phase 5 rather than after — building Phase 5
on a printer_service.dart that was about to be stale would have guaranteed a
harder conflict later, once Phase 5 had *also* added its own layer on top. The
merge was a clean 3-way auto-merge with no textual conflicts (verified there
were no leftover `<<<<<<<` markers anywhere in the tree); `flutter analyze` (69
issues, unchanged baseline) and `flutter test` (22/23, same pre-existing
unrelated `widget_test.dart` failure as every prior run this session) both
confirmed clean before committing the merge. Phase 5 below is scoped against
the **post-merge** printer subsystem, not the older pre-merge one.

**Phase 5 — Print subsystem: job queue + USB relay — done 2026-08-05 (cashier,
shift-close, and kitchen tickets all wired)**
- `PrintJob` table, claim/lease state machine, LAN-relay path for USB-owned
  printers, persisted retry/reprint for kitchen tickets, dedupe for cashier/
  close-check receipts.
- **Research done before writing any code:** a full read of the post-merge printer
  subsystem (`printer_service.dart`, `printer_config*.dart`, `printers_section.dart`,
  every call site) confirmed §8's original sketch's central claim exactly: a
  `usb`-type printer not physically attached to the calling terminal fails outright
  today (`_printViaWindowsRaw`'s `EnumPrinters(PRINTER_ENUM_LOCAL, ...)` is
  inherently local-only), with zero cross-terminal delivery of any kind. Also
  confirmed, and **corrected from §8's original sketch**: the Phase 4 sole-uplink
  relay (`relayOp`/`relayOpResult`) is a **leader-only directed RPC** — only a
  `client` sends, only the `server` answers, and the vocabulary (`RelayOpResult`'s
  three cloud-sync outcomes) doesn't fit a claim/lease print handoff. It does not
  reuse for print-job relay, which must be **peer-to-peer** (whichever terminal
  physically owns a given USB printer might be a `client`, the `server`, or — if LAN
  mode is off entirely — unreachable). What *does* reuse cleanly: the existing
  broadcast-to-all-except-sender path `tableStatus` already rides on, needing zero
  `LanHubServer` routing changes for the new message types themselves.
- **A real, pre-existing gap found and fixed while designing this, not after:** a
  `server`-mode terminal forwarded every client broadcast to its *other* clients but
  never surfaced it to its own app layer — harmless while the only broadcast was
  cosmetic table-status, but a real correctness bug for print relay, since the
  leader terminal can just as easily be the one physically holding the USB printer
  as any other. Fixed with a new optional `LanBroadcastListener` callback on
  `LanHubServer.start()`, invoked alongside (not instead of) the existing
  `_broadcastExcept` forwarding; `LanHubService` wires its own `_handleRemoteMessage`
  to it for `server` mode, reusing the exact same dispatcher `client` mode already
  used. Covered by a new dedicated test (below) — this is exactly the class of bug
  that only shows up once you ask "does the leader's own role matter here," not
  something `flutter analyze` or the existing test suite could have caught, since no
  prior code path needed the server to react to its own clients' broadcasts.
- **Done: `PrintJob` (persisted queue) + `PrintQueueService` (claim/lease state
  machine), wired to the `cashier` and `shiftClose` receipt paths** (both target the
  same single `close_check` printer via `PrinterConfigStorage
  .closeCheckConfigOrFallback()`, so both fit one job per call cleanly):
  - `PrintJob` (`lib/core/services/print_queue/print_job.dart`) — one new Hive
    typeId (12; 10/11 already taken by `PendingOperation`). Deliberately **not**
    three separate `@HiveType` enums for job-type/state — those are stored as plain
    `String` fields (`state`, `jobType`) with a `PrintJobStateX` extension exposing
    a real `PrintJobState` enum getter/setter, mirroring the exact convention
    `LanHubMessage`/`RelayOpResult` already use for enum values crossing a
    persistence/wire boundary. Avoids a second generated adapter for what's a small,
    closed set of string constants — this is the "don't design for hypothetical
    future requirements" call applied to schema, not just code: Phase 3's full
    typed-Hive-record restructure was skipped as unneeded, and this doesn't quietly
    reintroduce that scope through the back door for one new box.
  - `PrintQueueService` (`lib/core/services/print_queue/print_queue_service.dart`)
    — deliberately **zero import of `lan_hub_*`**, same reasoning
    `OfflineQueueService` already established for avoiding a `LanHubService`
    reference: this class already depends on `PrinterService` (for transport), so a
    `LanHubService` import back into it would be a genuine two-way circular import,
    not just an inconvenient one. The LAN side is three plain function-typed
    callbacks (`PrintAnnounceBroadcaster`/`PrintClaimBroadcaster`/
    `PrintResultBroadcaster`) + an `isLanRelayPossible` check, wired in `di.dart` to
    new `LanHubService` methods (`broadcastPrintJobAnnounce`/`Claim`/`Result`,
    `canRelayPrintJobs`) — same typedef-callback shape as
    `LanAuthValidator`/`LanRelayHandler`.
  - **Ownership determination reuses what already exists rather than inventing a
    terminal-registry:** a terminal is treated as owning a USB printer iff it has a
    non-empty `CacheService.getUsbPrinterName(entryId)` locally — confirmed via the
    research above to be the closest thing to a "who owns this USB printer" concept
    that already exists in this codebase. Deliberately did **not** resurrect
    `getDeviceId()` for this (confirmed dead code, and confirmed broken on Windows
    specifically — returns the literal string `'unknown_device'`, the actual POS
    terminal platform) — instead added a fresh, separately-scoped random id
    (`PrintQueueService.terminalId`, 16 hex chars, persisted in `SharedPreferences`
    once per install) used only for `PrintJob.ownerTerminalId` bookkeeping/history,
    never for the ownership decision itself.
  - **Protocol:** originator persists a `queued` row, then broadcasts
    `printJobAnnounce` (job id, type, target `entryId`, pre-rendered ESC/POS bytes
    as base64 — the receipt is built once, wherever the job originates, and shipped
    as bytes so a claiming terminal never needs the originator's order/cache
    context to print it, keeping "transport/driver layer stays as-is" from §8's
    original framing literally true). Every terminal receives it; only the one
    holding a matching `getUsbPrinterName(entryId)` broadcasts `printJobClaim` and
    attempts the print, then broadcasts `printJobResult`. The originator: waits up
    to 3s (`claimWait`) for a claim, else fails visibly with an "unclaimed" reason;
    once claimed, waits up to 10s (`lease`, per §8's own "recommend 10s") for a
    result; either timeout gets **exactly one** automatic re-announce
    (`retryCount`), then a permanent, clearly-worded failure — bounded retries, not
    an unbounded loop that could risk a duplicate physical printout, per §8's own
    exactly-once framing. A second/late claim for an already-`claimed` job is
    ignored by construction (the state guard only accepts a claim while still
    `queued`) — ​"first claim wins" needed no extra arbitration code.
  - **Crash/restart recovery:** any `queued`/`claimed` row found at `init()` time
    (no live timer survives a restart, so an interrupted job would otherwise sit
    silently stuck forever) is swept to `failed` with a clear "interrupted by
    restart" reason — visible for manual retry once Phase 6's print-status screen
    exists, not silently lost.
  - **`PrinterService` integration, kept minimal:** a new public `printRenderedBytes`
    (thin wrapper over the existing private `_connectAndPrint` — no transport code
    duplicated) plus an `attachPrintQueue` hook `di.dart` wires once both services
    exist. `printCashierReceipt`/`printCashierReceiptFromDetail`/
    `printShiftCloseReceipt` now call a new `_dispatchOrPrint` helper instead of
    `_connectAndPrint` directly — routes through the queue when wired, falls back
    to direct printing if somehow not (never a silent no-op). Their **public
    signatures are unchanged**, so `WaiterCubit`/`PaymentBloc`'s existing call sites
    needed zero edits — the queue-routing decision is fully encapsulated inside
    `PrinterService`. The existing `if (!r.ok) { _notifyPrinterFailed(...) }` toast
    logic at each of the three call sites is untouched and stays the **sole** place
    a failure toast fires — `PrintQueueService` itself never shows one, deliberately,
    since `submitJob`'s `Future` only resolves once the job is *fully* finalized
    (including the whole relay lifecycle), so double-toasting was a real risk once
    the relay path could also "fail" out from under an already-returned local
    result if both places tried to notify.
  - **Done: kitchen tickets, added 2026-08-05.** `printKitchenReceiptFor` already
    grouped items by resolved destination printer before this — the only change
    needed was firing one `submitJob` (`jobType: 'kitchen'`, no beep, matching
    existing behavior) per destination group instead of calling `_connectAndPrint`
    directly, reusing every piece of plumbing built for the cashier path above with
    no new message types, no new state-machine code, no new schema.
  - **A real behavior change made deliberately, not incidentally:** the old loop
    printed each destination printer *sequentially* and `return`ed at the first
    failure, silently never even attempting the remaining printers in that ticket.
    That was fine when every attempt was fast (bounded TCP retries or an immediate
    local USB check) but becomes a real problem now that one destination can be a
    relayed job taking up to ~26s to resolve — sequential-with-early-return would
    delay (or skip entirely) an unrelated, unaffected printer's urgent kitchen
    ticket behind a single slow/failing one. Changed to fire every destination's
    `submitJob` concurrently (`Future.wait`, no `await` between the calls) and
    report **every** failure independently rather than stopping at the first —
    strictly more information surfaced, not less, and no kitchen printer's ticket
    is now held hostage by another's relay latency.
  - **Disclosed tradeoff:** because `submitJob` doesn't resolve until the relay
    concludes, a failure toast for a *relayed* print can now arrive up to
    ~26s after the check was closed (claim-wait + lease, doubled by the one retry)
    instead of near-instantly — acceptable given every call site was already
    fire-and-forget/unawaited before this (per the research above, two of the three
    weren't even wrapped in `unawaited()`), so nothing was blocking on this result
    either before or after.
  - *Verification:* `test/print_queue_service_test.dart` (8 tests) — real
    `PrinterService`/`CacheService` instances throughout, no mocking framework, same
    project convention as the LAN tests. Two outcomes are conveniently deterministic
    on this (non-Windows) dev/CI machine without needing any fakery: a `usb`-type
    print always fails immediately with a `Platform.isWindows` check
    (distinguishes "claimed but the owner's print itself failed" from "never
    claimed" cleanly), and a `cable`-type print against a real local loopback
    `ServerSocket` always succeeds. Covers: a TCP job needing no relay; a USB job
    this terminal owns printing locally with **zero broadcasts sent** (asserted
    directly, not just inferred from the result); a USB job relayed end-to-end
    between two `PrintQueueService` instances wired directly into each other's
    `onRemote*` methods (bypassing the WebSocket transport, which is separately
    covered — see below); the unclaimed-timeout-then-one-retry path; the
    claimed-but-no-result lease-timeout-then-one-retry path; stale-job recovery on
    init; and — the kitchen-wiring addition — a slow relayed job and a fast local
    job submitted concurrently, with the fast one asserted **already `printed`**
    while the slow one is still `queued` mid-flight (not just "both eventually
    succeed," which wouldn't distinguish concurrent from sequential execution).
    That last test deliberately exercises `PrintQueueService.submitJob` directly
    rather than through `PrinterService.printKitchenReceiptFor` itself — the latter
    reaches `CacheService`/`UserBloc` via ad-hoc `inject()` calls (pre-existing
    pattern, not introduced by this slice) that would need the full DI graph
    standing up just for this test; the concurrency risk actually being tested
    lives entirely in `submitJob`/`Future.wait`, not in that dispatch loop itself,
    so testing at that level was the better cost/value trade rather than building
    out unrelated DI scaffolding to reach the same coverage indirectly.
    Two new tests also added to `test/lan_hub_test.dart` (now 9, all still passing)
    covering the wire-level pieces this file doesn't touch: the new
    `printJobAnnounce`/`printJobClaim`/`printJobResult` message types actually
    round-tripping through the real WebSocket JSON envelope between two real
    clients, and — specifically — the new `onBroadcast` callback firing for the
    server's own app layer (the blind-spot fix above), proven with a real
    server+client pair, not just read from the code. Full suite: 32/33 (the one
    failure is `widget_test.dart`'s pre-existing, unrelated counter-app boilerplate,
    flagged in every session's run so far). `flutter analyze`: 69 issues, unchanged
    baseline.
  - *Verification still needed:* same category of gap as every other LAN-relay
    piece so far — no test against two actual separate running app instances/
    devices, and specifically for this slice: no real Windows-USB-printer hardware
    test at all (this dev/CI environment is Linux, so the Win32 spooler path itself
    has never actually run against a physical printer in any test this session has
    written, only exercised via its `!Platform.isWindows` early-return).
- *Acceptance:* closing a check on a terminal with no physically attached receipt
  printer produces exactly one printout on the owning terminal — including across a
  simulated claim-timeout (kill the owner mid-print: confirm one eventual reprint,
  never zero, never two). **Met for cashier/shift-close and kitchen tickets alike**
  per the claim/lease design and tests above — every print path this phase named
  is now backed by a persisted, retryable, claim/lease-protected job. What remains
  is the real-hardware/real-two-terminal verification flagged throughout, not
  further scope.

**Phase 6 — Offline auth hardening, observability, testing — complete
2026-08-05: revocation-lag bounding, secure-storage migration, the
sync-status UI, deterministic resilience tests, offline privileged-action
authorization + audit logging, and the full-shift soak test**
- Secure-storage migration for cached credentials, privileged-action offline
  audit log.
- Real sync-status UI: outbox depth, cluster role/peers, printer reachability,
  last-sync time, quarantine list with manual resolution — replacing today's binary
  banner. **Done — see the dedicated bullet below for what "printer
  reachability" ended up meaning in practice (inferred from failed-job
  evidence, not an active health check).**
- Deterministic tests: partition simulation, clock-skew, leader-kill-during-open-
  transaction, duplicate-delivery, full-shift offline-then-reconnect soak test —
  filling today's zero-coverage gap.
- **Research done before writing any code, found the offline-auth cache had no
  bound at all:** a full read of `OfflineAuthCache` and every login path
  (`LoginPinCubit`, `AuthCubit`, `UserBloc`) confirmed the original prompt's own
  "revocation lag" question (§1 "Offline authentication and authorization") was
  never answered in code — a cached PIN/brand credential authenticated offline
  **forever**, with no TTL, no expiry field, and no re-validation trigger of any
  kind. `UserModel.isActive` was decoded from every login response and stored in
  the cache but never once read back by any auth flow. Separately (a related but
  distinct gap, noted and left open): manager-pincode-gated actions (void, shift
  open/close) are online-only today with no offline fallback at all —
  `VerifyManagerPincodeUsecase` hits the live endpoint unconditionally, so on a
  genuinely offline terminal a manager currently **cannot** authorize a void or a
  shift close, which cuts against the original prompt's framing of "privileged
  actions performed offline" needing an audit trail — right now there's nothing to
  audit there because the action can't happen offline at all. Out of scope for
  this slice; flagged for whoever picks up the audit-log piece next, since it
  changes what "privileged action while offline" even means in this codebase.
- **Decision: no time-based TTL.** Asked directly (a genuine tradeoff the original
  prompt's own "how long must an outage survive" question left unanswered, and
  picking a wrong duration unilaterally risked either locking out legitimate staff
  during a real outage or leaving a real security hole open) — **the answer was no
  fixed expiry at all: a cached credential stays valid until the next time the
  terminal gets an actual, authoritative answer from the server about it, and that
  answer says no.** Not a 24h/72h/one-shift cutoff. This reframes "bounding
  revocation lag" from a clock problem into a **connectivity-and-correctness**
  problem: make sure every place that already talks to the server about a
  credential (a) never lets a confirmed rejection get overridden by a stale cache
  hit, and (b) actually happens often enough (not just at login) that a revoked
  credential doesn't sit undetected for the entire session.
- **Done: a shared `Failure.isDefiniteAuthRejection` classification**
  (`lib/core/error/failure.dart`), the mechanism the whole design rests on —
  distinguishes a real, authoritative "no" from the server (`ValidationFailure`,
  `UnauthorizedFailure`, `UnauthenticatedFailure`, `NotFoundFailure`,
  `MessageFailure` — the backend actually answered, and the answer was reject)
  from simply failing to get one at all (`ConnectionFailure`, `TimeoutFailure`,
  `ServerFailure`, `UnknownFailure`/`ParsingFailure`/`OtherFailure` — inconclusive,
  by design still falls back to cache exactly like before). `ServerFailure` (5xx)
  is deliberately classified as inconclusive, not a rejection — a backend bug or
  outage says nothing about whether a specific credential is still valid, and
  treating it as one would lock out a legitimate cached user over a server-side
  problem that has nothing to do with them.
- **Done: a real, pre-existing bug found and fixed, not incidental to this
  design.** `LoginPinCubit.login()`'s online branch fell back to the offline cache
  on **any** `LoginUsecase` failure, not just connection-class ones — meaning even
  when the terminal *was* online and the server *did* authoritatively reject a
  pincode (wrong code, inactive user), the code silently tried the unchecked
  offline cache anyway and could still log the person in. This existed
  independently of the "no TTL" design above; it would have undermined *any*
  revocation mechanism, TTL-based or not, since the whole point of "ask the server
  when you can" is defeated if a real rejection still falls through to cache.
  Fixed by gating the fallback on `!failure.isDefiniteAuthRejection`
  (`AuthCubit.loginWithBrandId` already had a narrower, correct-in-spirit version
  of this — `if (failure is ConnectionFailure)` — widened it to the same shared
  classification for consistency, since a bare timeout or a server 500 shouldn't
  lock out a legitimate cached brand-login either, and `UserBloc._getUser`'s
  session-restore path had the identical narrow check, widened the same way).
- **Done: cache invalidation on a confirmed rejection** — `OfflineAuthCache`
  gained `removeUser(brandId)`/`removeForPin(brandId, pincode)` (it previously had
  no delete/remove capability at all, only overwrite). Wired into all three login
  paths: a definite rejection during PIN login, brand login, or session-restore
  now purges the matching cache entry instead of just showing an error — so the
  *next* offline attempt with that same credential fails too, not just the
  in-the-moment one.
- **Done: reconnect-triggered session re-validation**, closing the gap for a
  session that's *already* logged in when the underlying user gets deactivated —
  without this, only *new* login attempts would ever re-check the server;
  someone already mid-shift would keep working until they logged out or the app
  restarted, no matter how many times connectivity came back. `AppScaffold
  ._syncOnReconnect` (the same reconnect-edge handler that already drives
  `SyncEngine.tick()` on every reconnect, from Phase 0) now also dispatches
  `UserEvent.getUser()` — reusing `UserBloc._getUser`'s already-correct-shaped
  fold (confirmed rejection → force logout + purge cache; inconclusive → fall back
  to cache as before) rather than adding new logic for this path. Checked this
  wouldn't cause a disruptive UI flash on every reconnect: the two `BlocListener
  <UserBloc, UserState>`s in the app (`main_screen.dart`, `waiter_screen.dart`)
  are both `listenWhen`-gated on `userMOdel` actually *changing* (null→non-null,
  or a different user id), and `_getUser`'s `LOADING`/`SUCCESS` emissions in the
  unchanged-user case never clear or replace `userMOdel` with a different value —
  freezed structural equality means a same-user refresh is a silent no-op to both
  listeners, confirmed by reading both gates rather than assumed.
- *Verification:* `test/offline_auth_revocation_test.dart` (new, 10 tests) — the
  `isDefiniteAuthRejection` classification exercised against every `Failure`
  subtype in the codebase (not just a sample), and `OfflineAuthCache.removeUser`/
  `removeForPin` against real `SharedPreferences` (mocked in-memory via
  `SharedPreferences.setMockInitialValues`, not a mocking framework for the class
  under test itself) — covering removal, no-op-on-already-absent, isolation (
  removing one brand/pincode never touches another cached entry), and re-caching
  after removal (the re-hire/re-approved case). **Deliberately not covered:**
  `LoginPinCubit`/`AuthCubit`/`UserBloc` at the cubit level — each would need a
  real `LoginUsecase`/`AuthRepository`/`DioClient` chain standing up to exercise
  end to end, disproportionate to what's actually new in them (a few lines of
  branching over the two primitives that *are* tested); verified by code review
  instead, the same tradeoff already made for `PrinterService
  .printKitchenReceiptFor`'s DI-entangled call sites in Phase 5. `flutter
  analyze`: 69 issues, unchanged baseline. Full suite: 38/39 (the one failure is
  `widget_test.dart`'s pre-existing, unrelated counter-app boilerplate, flagged in
  every session run so far).
- **Residual gap, disclosed:** this closes the *logic* side of revocation lag but
  not the *opportunity* side — a terminal that genuinely never regains
  connectivity (not "offline right now," but offline for its entire remaining
  service life before being retired/replaced) still can't learn about a
  revocation, by construction, since there's no time-based fallback to catch that
  case. This was an explicit, informed tradeoff in the "no TTL" decision above,
  not an oversight — the alternative (a hard cutoff) trades a rare, extreme case
  for locking out staff during any ordinary outage that merely outlasts the
  chosen TTL. Revisit only if real field use shows the extreme case actually
  happening, with a concrete incident in hand rather than speculatively (same
  "escalation condition, not a default" posture as Phase 3's own deferral).
- **Done (2026-08-05, second slice): secure-storage migration.** All
  credential-bearing storage — access/refresh tokens, the brand_id+password
  pair, the last-used pincode, and both `OfflineAuthCache` blobs (brand-level
  and per-pincode) — moved off plaintext `SharedPreferences` into OS-backed
  secure storage via `flutter_secure_storage` (Keychain on iOS/macOS,
  EncryptedSharedPreferences on Android, DPAPI-backed Credential Manager on
  Windows, libsecret on Linux). Non-sensitive config (`appLanguage`,
  `keyboardLanguage`, `posIsInitialized`) deliberately stayed in
  `SharedPreferences` — `AppTokenStorage.isPosInitialized` is read
  synchronously in several places, and secure storage has no synchronous read
  API on any platform, so moving it would have forced those call sites into
  async for no security benefit (that key holds no credential). Chose
  `flutter_secure_storage` specifically because its two best-supported
  backends (Windows DPAPI, Android EncryptedSharedPreferences) are exactly
  the two platforms §1 Q2 identified as the actual POS/waiter targets;
  Linux/macOS/web get a backend too (libsecret / Keychain / a weak
  browser-storage fallback) but per §1 Q2 those aren't confirmed real
  deployment targets, so their weaker guarantees (web in particular) weren't
  litigated further here.
  - **API ripple, deliberate:** `OfflineAuthCache`'s four read methods
    (`getCachedUser`, `getForPin`, `validateAndGetUser`, plus the internal
    `_readAll`/`_readPins`) had to become `Future`-returning — they were
    synchronous under `SharedPreferences` but secure storage has no sync read
    on any platform. Updated the five call sites this touched
    (`AuthCubit.loginWithBrandId`, `UserBloc._tryOfflineUser` ×2,
    `LoginPinCubit.login` ×2) to `await` them; all five were already inside
    `async` functions, so this was a mechanical, zero-risk change, not a
    structural one.
  - **Done: a one-time upgrade path**, not a breaking change for existing
    installs. `AppTokenStorage.migrateLegacyPlaintext` and
    `OfflineAuthCache.migrateLegacyPlaintext` (both static, called
    unconditionally from `initDi()` before anything reads a credential) check
    each legacy plaintext key, move its value into secure storage if present,
    and delete the plaintext copy. Idempotent by construction (a no-op once
    the plaintext keys are gone), so it needs no "have I migrated" flag of
    its own and is safe to run on every single startup. Without this, every
    existing install would have been silently logged out and lost its
    offline-auth cache on the first launch after upgrading — judged
    unacceptable given this app's own "outage may be unbounded" premise (§1
    Q4): the upgrade itself could land mid-outage.
  - **Testing note:** the `flutter_test` sandbox has no OS keychain, so
    `flutter_secure_storage`'s real backends can't run there (same category
    of gap as the LAN/print-relay tests needing real sockets instead of real
    hardware). Rather than reaching for a mocking framework, wrote
    `test/support/in_memory_secure_storage.dart` —
    `InMemorySecureStoragePlatform`, a real, small, correct implementation of
    the plugin's own `FlutterSecureStoragePlatform` interface (six methods:
    `read`/`write`/`delete`/`deleteAll`/`containsKey`/`readAll`, confirmed
    stable by reading the installed `flutter_secure_storage_platform_interface`
    package source directly), backed by a plain `Map`, installed via
    `FlutterSecureStoragePlatform.instance = ...`. This is the same category
    of stub `shared_preferences`'s own `setMockInitialValues` already
    performs under the hood, just written out explicitly because
    `flutter_secure_storage` doesn't ship an equivalent convenience helper.
    Added `flutter_secure_storage_platform_interface` as a direct
    dev-dependency (previously only transitive) since the fake needs to
    import its types directly.
  - *Verification:* `test/secure_storage_migration_test.dart` (new, 7 tests)
    — asserts credential values written through `AppTokenStorage`/
    `OfflineAuthCache` never appear in a plaintext dump of the underlying
    `SharedPreferences` instance (the actual point of the migration, checked
    directly rather than assumed from the routing code), confirms
    non-sensitive keys still land in plain prefs, confirms `deleteAll` wipes
    both backends, and covers `migrateLegacyPlaintext` for both classes
    (moves-and-deletes-plaintext, safe no-op when nothing to migrate,
    idempotent on a second run). `test/offline_auth_revocation_test.dart`
    updated in place for the new async signatures and the
    `InMemorySecureStoragePlatform` fake — all 10 of its existing cases still
    pass unchanged in substance. `flutter analyze`: 69 issues, same baseline
    (one incidental new info-level lint from `OfflineAuthCache(secureStorage)`
    not being `const` was fixed immediately, not left as noise). Full suite:
    45/46 (38/39 before this slice, plus the 7 new tests; the one failure is
    still `widget_test.dart`'s pre-existing, unrelated counter-app
    boilerplate).
  - **Residual gap, disclosed:** verified against the in-memory fake only —
    no real Windows/Android hardware run yet confirmed DPAPI/
    EncryptedSharedPreferences actually round-trip correctly end to end, or
    that `flutter_secure_storage`'s Windows backend behaves correctly across
    a full app reinstall/machine-rename (Credential Manager entries can be
    scoped in ways that matter for a kiosk-style always-on terminal). Same
    "real hardware, not just real sockets" gap flagged for the LAN/print
    subsystem in Phases 4-5 — deferred to the same eventual hardware pass
    rather than blocking this slice on it.
- **Done (2026-08-05, third slice): the real sync-status UI**, replacing the
  original scope bullet's binary banner with actual numbers pulled from the
  services that already track them, plus manual resolution for the two
  places work could otherwise get silently stuck.
  - **New: a quarantine mechanism for the offline outbox**, the single
    biggest gap this slice found. `OfflineQueueService.syncAll`/`relayViaLan`
    previously handled a terminal 4xx (or a LAN-relay `terminalFailure`)
    identically to a real success: `_box.delete(op.id)`, no trace kept of
    what was dropped or why — confirmed by reading the code, not assumed,
    since the plan's own §5 already flagged "the silent drop that happens
    today on any 4xx" as a known gap. Fixed with a new
    `QuarantinedOperation` Hive model (typeId 13,
    `lib/core/services/offline_queue/quarantined_operation.dart`) and box
    (`offline_queue_quarantine`), a private `OfflineQueueService._quarantine`
    helper fed by a shared `_dropped(reason)` helper that every one of the
    six `_exec*` methods' drop sites (both exception-based and the three
    early-return "this data is stale" cases) now funnels through instead of
    returning `OpOutcome.dropped` directly, and two new public methods for
    manual resolution — `retryQuarantined(id)` (re-enqueues under the same
    id) and `dismissQuarantined(id)` (discards for good). The LAN-relay
    path's `terminalFailure` case gets a generic reason string rather than
    the server's actual error text — `LanHubMessage.relayOpResult` only ever
    carried a bare `RelayOpResult` enum over the wire (see §7), not an error
    string, and widening that wire format was judged out of scope for this
    slice; flagged rather than silently accepted.
  - **New: reactive backing on every service this screen reads**, added as
    thin, additive getters rather than changing any existing behavior —
    `OfflineQueueService.listenable`/`quarantineListenable` (`Box
    .listenable()`, already reactive by construction, just not previously
    exposed), `PrintQueueService.listenable` plus `queuedCount`/
    `claimedCount`/`failedCount` (trivial filters over the existing `jobs`
    getter), `LanHubServer.clientCountNotifier` (a `ValueNotifier<int>` — the
    peer-connect/disconnect set had no notification hook at all before this,
    a real gap since `LanNetworkSection`'s existing UI worked around the
    same absence with a 2s polling `Timer` instead), `LanHubService
    .onModeChanged`/`clientCountListenable` (mode changes had no stream
    either — `LanSoloBanner`'s own doc comment already noted this and
    piggybacked on the connection-state stream instead; a status screen
    showing role text in *every* mode, not just detecting "solo," needed the
    real thing), and `SyncEngine.lastSyncAt` (a `ValueNotifier<DateTime?>`,
    persisted to `SharedPreferences` so a cold start doesn't show "never
    synced" — the same persisted-timestamp idiom `CacheService` already uses
    for goods-cache staleness, just not previously applied to the sync pass
    as a whole). `SyncEngine.tick()` also gained an optional `force` param
    (threaded to `OfflineQueueService.syncAll`'s existing `force`) so the
    screen's "Hozir sinxronlash" button can bypass backoff — a manual retry
    that still waits out a previous failure's exponential backoff defeats
    the point of a manual retry.
  - **New: print-job manual resolution** — `PrintQueueService
    .retryFailedJob(id)` (rebuilds the original `PrinterConfig` from the
    persisted `PrintJob` fields and resubmits under a fresh id, leaving the
    original row as history rather than mutating it — the same "new row,
    old row stays" pattern `retryQuarantined` uses) and `.dismissFailedJob
    (id)`, closing the loop `_recoverStaleJobs`'s own doc comment already
    promised ("visible for manual retry once Phase 6's print-status screen
    exists"). **Scoping decision on "printer reachability"** (the original
    scope bullet's own word choice): there is still no active health-check/
    ping anywhere in `PrinterService` — building one (per-printer periodic
    probes, a reachable/unreachable state machine) was judged a materially
    bigger feature than this slice, and not obviously worth it against a
    thermal receipt printer's actual failure mode (it's either plugged in
    and working, or a job fails and says why). What the screen shows instead
    is the evidence that already exists: queued/claimed/failed counts plus,
    for each failed job, its `lastError` text — reachability *inferred* from
    recent failures, not measured directly. Revisit only if real use shows
    this inference is too slow to surface a genuinely offline printer.
  - **New Settings section**, not a new top-level route:
    `lib/features/view/main/presentation/pages/settings/sections
    /sync_status_section.dart`, wired into `SettingsScreen`'s existing
    `SettingsSection` enum/switch (same pattern every other section already
    follows). Deliberately additive to the existing `OfflineBanner`/
    `LanSoloBanner` rather than replacing them — those stay as the always-on
    glanceable indicator; this is the detail view for someone actually
    investigating a problem, reachable the same way every other settings
    section is.
  - *Verification:* `flutter analyze` unchanged at 69 (one incidental new
    info-level lint, a missing `const`, fixed immediately). Full suite:
    59/60 (46/47 before this slice, plus 15 new tests — the one failure is
    still `widget_test.dart`'s pre-existing, unrelated counter-app
    boilerplate). New coverage: `test/offline_queue_quarantine_test.dart`
    (9 tests) exercises quarantining end-to-end through
    `relayViaLan` (a `terminalFailure`/`synced`/`retryLater` result each
    behaves correctly, `retryQuarantined`/`dismissQuarantined`,
    newest-first ordering, both listenables firing) — deliberately *not*
    through `syncAll`'s direct-to-cloud path, since that needs a real
    `DioClient` backed by a real `ConnectivityCubit` (itself backed by
    `connectivity_plus`'s platform channel, unavailable in this test
    sandbox) to exercise end to end — the same class of gap already
    disclosed for `LoginPinCubit`/`AuthCubit`/`UserBloc` earlier in this
    phase, verified by code review instead (every `_exec*` drop site funnels
    through the same shared `_dropped()` helper that the tested `relayViaLan`
    path also uses, so the capture mechanism itself is exercised even though
    the direct-to-cloud call sites aren't). `test/print_queue_service_test
    .dart` gained 5 tests for the count getters and manual-retry/dismiss
    methods, reusing the file's existing real-`PrinterService`,
    deterministic-USB-failure harness. `test/lan_hub_test.dart` gained 1
    test connecting two real loopback clients and disconnecting one,
    asserting `clientCountNotifier` fires `[1, 2, 1]` in order.
    `LanHubService.onModeChanged`/`clientCountListenable` and
    `SyncEngine.lastSyncAt`'s persistence aren't covered by a dedicated
    test — both are thin wrappers over already-tested or trivial primitives
    (`BehaviorSubject`/`ValueNotifier`/`SharedPreferences` string round-trip)
    sitting behind the same `ConnectivityCubit`/full-DI-graph wall as
    `syncAll`'s direct path; verified by code review.
  - **Residual gap, disclosed — interactive UI verification not done.**
    Could not visually exercise the new screen in a running app at the time
    this bullet was originally written: the Linux desktop build failed
    outright without the `libsecret-1-dev` system package (a genuinely new
    native build requirement introduced by `flutter_secure_storage`'s Linux
    backend), and the Chrome web build fails on a pre-existing, unrelated
    issue (`win32`, imported unconditionally by `printer_service.dart`,
    doesn't compile for web at all — confirmed this predates this slice, not
    caused by it, still open). The Linux half of this gap is now closed —
    see **"Linux build fix"** below, added the same day once the user hit
    this exact wall trying to run the app themselves. The web half remains:
    neither Linux nor web is the confirmed real target anyway (§1 Q2:
    Windows desktop, Android secondary) — same "real hardware, not just real
    sockets/analyze" gap already flagged repeatedly for Phases 4-6.
  - **Linux build fix (2026-08-05, same day, user-triggered):** installing
    `libsecret-1-dev` (`sudo apt-get install libsecret-1-dev libjsoncpp-dev`)
    got past the CMake configure step but hit a second, separate failure:
    `flutter_secure_storage_linux` 1.2.3 vendors an old `nlohmann/json.hpp`
    using spaced literal-operator syntax (`operator "" _json`) that this
    environment's Clang 21 hard-errors on
    (`-Wdeprecated-literal-operator`+`-Werror`) — not something to patch by
    hand (it's inside the plugin's own vendored header, would be clobbered
    by the next `pub get`). Fixed by upgrading `flutter_secure_storage` from
    `^9.2.4` to `^10.3.1` (`flutter_secure_storage_linux` 1.2.3 → 3.0.1),
    whose changelog confirms the Linux native side was rewritten in 10.0.0
    specifically to "remove and replace" that dependency — confirmed via the
    actual changelog before upgrading across a major version, not assumed.
    No breaking changes to the `read`/`write`/`delete`/`deleteAll` surface
    this app uses; `flutter_secure_storage_platform_interface` bumped
    `^1.1.2` → `^2.0.2` alongside it (the test fake's abstract interface is
    unchanged between those versions — confirmed by diffing the actual
    source, not assumed either — so `test/support/in_memory_secure_storage
    .dart` needed no changes). **One real, disclosed follow-on
    consequence:** `flutter_secure_storage` 10.x's Android module declares
    `minSdkVersion = 23` in its own `build.gradle` — confirmed by reading
    the installed plugin's source directly, not assumed — which fails
    Gradle's manifest merge against this app's previous minSdk of 21 (the
    Flutter default, kept for `flutter_local_notifications`' own 21+
    requirement). Fixed by raising `android/app/build.gradle.kts`'s
    `minSdk` to `23` explicitly, dropping Android 5.0/5.1 (2014-2015)
    support — not expected to matter given §1 Q2's read that Android here is
    a secondary waiter handheld, not a target for decade-old hardware, but
    **not verified against a real Android build in this environment** (the
    Android SDK's license status is unresolved here, and accepting it
    without being asked felt like the wrong call) — flag if this needs a
    real Android build check. `flutter build linux --debug` now succeeds
    end to end; `flutter analyze` (69, unchanged) and the full test suite
    (66/67, same pre-existing unrelated failure) still pass after the
    upgrade.
- **Done (2026-08-05, fourth slice): a first deterministic resilience test
  pass**, covering three of the five categories the original scope bullet
  named — partition simulation, leader-kill-mid-transaction, and duplicate-
  delivery — plus an explicit finding on the fourth (clock-skew) rather than
  silently skipping it. All new tests run against the same real-socket
  harness (`dart:io` `HttpServer`/`WebSocket` over loopback, real Hive boxes)
  the rest of this phase's tests already use — no new test infrastructure,
  no mocking framework.
  - **Partition simulation:** `test/lan_hub_test.dart` gained
    "partition-then-heal" — a real client connects, the server is stopped
    (simulating the leader dropping off the LAN entirely, not just a slow
    reply), the client's `isConnected` is confirmed to flip to `false`, the
    server restarts on the same port, and the client is confirmed to
    reconnect **on its own** within its existing exponential-backoff window
    — no test code drives the reconnect. This is genuinely new coverage:
    `LanHubClient`'s reconnect loop (`_scheduleReconnect`/`_doConnect`) had
    never been exercised end-to-end by any prior test — every existing
    connect test used a single connect-and-stay-connected (or
    connect-and-get-rejected, which never recovers since the credentials
    stay bad) path.
  - **Leader-kill-mid-transaction:** `test/lan_hub_test.dart` gained
    "leader-kill-mid-relay" — distinct from the pre-existing "relay times
    out cleanly if the leader never replies" test (which keeps the server
    process alive with a handler that just never answers). This one starts
    a `relayOp`, then calls `server.stop()` while it's in flight — a real
    process/connection loss, not a slow handler — and confirms the call
    still resolves to `null` at its own `timeout` bound (asserted via a
    `Stopwatch`, not just "eventually"), never hanging on the dropped
    socket. Confirms by test what `LanHubClient.relayOp`'s own doc comment
    already argued: there's no separate "give up early on disconnect" path,
    the explicit timeout is the only bound, and that's an accepted design
    choice (giving up early only changes retry cost, not correctness, since
    an unresolved op just stays in the outbox either way).
  - **Duplicate delivery:** split across both files, since the transport and
    application layers each have their own claim here. `test/lan_hub_test
    .dart` gained one test proving the transport layer makes **no**
    at-most-once guarantee — the same broadcast sent twice really does
    arrive twice at the app layer — establishing that dedup has to live
    above the transport. `test/print_queue_service_test.dart` gained three
    tests proving it does: a duplicate `onRemoteClaim` for an
    already-claimed job doesn't reset the lease clock (which would let a
    late/duplicate claimant repeatedly steal a job from whoever claimed it
    first), a duplicate `onRemoteResult` for an already-resolved job can't
    flip a real `printed` outcome back to `failed`, and — the strongest
    version of this — a genuine race where **two** terminals both own the
    same USB printer name and both claim the same announced job
    concurrently, proving only the winner's claim is ever honored. All three
    guards were already implemented (each with its own "first claim/result
    already won" doc comment) before this slice — this pass is what actually
    proved they hold, rather than trusting the comments.
  - **Clock-skew — investigated, found not applicable to this codebase's
    current design, not built as a test.** Read through every place a
    timestamp affects correctness: `PrintJob`'s claim-wait/lease bounds are
    `Timer`s (event-loop-scheduled — immune to `DateTime.now()` changes,
    unlike a deadline computed by comparing two stored timestamps),
    offline-auth has no TTL to skew after Phase 6's own no-TTL decision
    (first slice), and `client_created_at` sent with a queued order is for
    the **backend** to reconcile server-side, never compared against a local
    clock. There is currently no wall-clock-dependent correctness left in
    this client for a clock-skew test to exercise — noted here so the next
    person doesn't rediscover the same absence and wonder if it was missed,
    and so this conclusion gets revisited if a future change (e.g. a
    client-side HLC for order numbering, §1 Q7) reintroduces the dependency.
  - *Verification:* `flutter analyze` unchanged at 69. Full suite: 66/67
    (59/60 before this slice, plus 7 new tests — the one failure is still
    `widget_test.dart`'s pre-existing, unrelated counter-app boilerplate).
    One real bug caught and fixed during writing, not shipped: an early
    draft of the duplicate-`onRemoteResult` test called `submitJob` without
    awaiting it (deliberately, to drive the claim/result sequence manually
    while the job was still `queued`) but then called `onRemoteResult`
    synchronously right after — before `submitJob`'s own async continuation
    had reached the line registering the job's pending completer — so the
    completer was never found and the test hung until the 30s framework
    timeout. Fixed with an explicit yield (`await Future.delayed(...)`)
    between submitting and manually driving the job, matching a pattern the
    adjacent claim-duplicate test already used (there, incidentally, for a
    different reason) — flagged here because the same race would bite any
    future test written in this "submit without awaiting, then drive
    `onRemoteClaim`/`onRemoteResult` by hand" style, not just this one.
  - **Done (2026-08-05, sixth and final Phase 6 slice) — the full-shift
    soak test.** Revisits the "not done" call above: it turned out not to
    need the feared fake-clock/dependency-injection refactor after all.
    `test/full_shift_soak_test.dart` compresses a simulated 8-hour shift
    into a sub-second test run using `package:fake_async`, which fakes
    `Timer`/`Timer.periodic` transparently via zone overrides — every
    timing-sensitive mechanism in this codebase (print-job claim/lease,
    LAN reconnect backoff, the sync engine's periodic tick) is already
    `Timer`-driven, not wall-clock-polled, so all of that falls out for
    free with zero production changes. The one genuine exception —
    `OfflineQueueService`'s retry backoff, which compares
    `DateTime.now().difference(_lastAttemptAt!)` against a computed backoff,
    real wall-clock arithmetic rather than a `Timer` — got a minimal,
    surgical fix instead of a broad refactor: swapped its two `DateTime
    .now()` calls for `clock.now()` (`package:clock`, added as a normal
    dependency), which `fake_async`'s `getClock`/`withClock` pairing can
    fake in lockstep with the same simulated time `elapse()` advances.
    Every other `DateTime.now()` call in the offline/print/LAN/audit
    services was left alone — they're all record-keeping timestamps
    (`createdAt`, `claimedAt`, quarantine/audit entry times), not inputs to
    any elapsed-time decision, so faking them would have added risk for no
    test value.
    - **A real Hive-backend incompatibility found and worked around:**
      `fake_async`'s `elapse()` only advances Timers and zone-scheduled
      microtasks — it cannot advance real `dart:io` file I/O, which is what
      Hive's disk-backed boxes use under the hood
      (`RandomAccessFile.writeFrom` in `StorageBackendVm.writeFrames`). A
      disk-backed box's `put`/`delete` would simply never resolve inside a
      fake-time `elapse()`. Fix: every box this test opens uses Hive's
      in-memory backend (`Hive.openBox(name, bytes: Uint8List(0))`) instead,
      whose `writeFrames` is a plain `Future.value()` — a microtask,
      which `elapse()` handles correctly. Confirmed by reading
      `Keystore.beginTransaction` that the key/value map updates
      synchronously on `put`/`delete`, before that Future even resolves —
      the same "value visible immediately, Future completion is separate"
      behavior already documented for the disk backend elsewhere in this
      phase, so synchronous post-`elapse()` assertions against box state
      are safe.
    - **Also newly unblocks a gap disclosed repeatedly across this whole
      phase:** a real `DioClient`/`ConnectivityCubit` pair, previously
      "unavailable in this sandbox" because `connectivity_plus` needs a
      platform channel. Its platform-interface package exposes a settable
      `ConnectivityPlatform.instance` for exactly this purpose — the same
      pattern `flutter_secure_storage_platform_interface` already used for
      `InMemorySecureStoragePlatform` — so `test/support
      /fake_connectivity_platform.dart` does the equivalent for
      connectivity. Paired with `test/support/fake_http_client_adapter.dart`
      (a real `HttpClientAdapter` implementation swapped onto
      `DioClient.dio`'s already-public `httpClientAdapter` setter, so no
      production constructor changed and no real socket ever opens), this
      is the first test in this phase to exercise a genuine
      `OfflineQueueService.syncAll` round trip end to end rather than
      deferring the DioClient-dependent path to "verified by code review."
      One incidental real-app wiring detail surfaced by actually
      constructing a `DioClient` outside `di.dart`: its constructor
      unconditionally adds `aliceDioAdapter` as an interceptor, which
      throws `LateInitializationError` on every request until some `Alice`
      instance calls `addAdapter` on it (`di.dart` does this today, so
      production is unaffected) — the test mirrors that same wiring.
    - **What the soak test actually covers**, three scenarios:
      1. *Offline queue drain under repeated LAN partitions* — ~320 mixed
         operations enqueued over a simulated 8h shift via `relayViaLan`,
         against a leader connection that drops for three separate windows
         (20min/15min/40min). Asserts every operation is eventually synced
         or quarantined exactly once by shift end (no loss, no duplicate
         processing), and that a deliberately-always-rejected operation
         (every 37th) lands in quarantine, not silently dropped.
      2. *Retry backoff over simulated hours* — a real `syncAll` against a
         cloud endpoint that fails with `DioExceptionType.connectionError`
         for 20 simulated minutes: asserts the op is never terminally
         dropped (a connection error isn't a 4xx), and that backoff
         actually suppresses most retries (well under 20 naive
         5-second-interval attempts, but still making forward progress).
         Then flips the fake network to succeed and asserts the op drains
         within one bounded backoff window, and that a fresh failure right
         after resets to the small base backoff rather than staying near
         the 2-minute cap — proving `_consecutiveFailures` actually resets
         on success, not just in theory.
      3. *Print queue under volume* — 240 jobs submitted over a simulated
         8h shift, each scripted into one of four outcomes (claimed &
         printed promptly; never claimed by anyone, both retry attempts;
         claimed but the claimer vanishes — lease expires, resolves on the
         automatic retry; claimed then an explicit terminal failure).
         Asserts every single job ends `printed` or `failed` — none left
         `queued`/`claimed` — and that each job's actual outcome matches
         its scripted variant.
    - *Verification:* all 3 new tests pass, stable across 5 repeated runs
      (backoff timing uses generous, non-flaky bounds precisely because the
      backoff formula includes randomized jitter — see `_currentBackoff`).
      `flutter analyze`: 69, unchanged. Full suite: 74/75 (70/71 before this
      slice, plus 4 net new — the one failure is still `widget_test.dart`'s
      pre-existing, unrelated counter-app boilerplate).
    - **Residual gaps, disclosed:** this covers the mechanisms that matter
      most under sustained real-world stress (queue drain, backoff, print
      volume) but is still not the literal real-hardware, real-clock,
      many-hour run — LAN partition timing here is scripted, not the
      product of an actual flaky Wi-Fi network, and the printer claims are
      simulated rather than real USB/TCP round trips (already covered
      separately, without `fake_async`, in `print_queue_service_test.dart`
      and `lan_hub_test.dart`). That real-hardware pass remains the one
      thing this whole phase has consistently deferred, not newly
      introduced here.
- **Done (2026-08-05, fifth and final slice): offline privileged-action
  authorization + audit logging.** Put the blocking policy question to the
  user directly rather than assuming, the same way the no-TTL auth decision
  was: **should a manager be able to authorize a void/shift-close entirely
  offline?** Answer: yes, build it — the biggest-scope of the three options
  offered (the alternative was auditing only the online-only status quo, or
  deferring the whole item).
  - **Offline manager-pincode verification** — `AuthDatasourceImpl
    .verifyPincodeRole` (`lib/features/view/auth/data/data_sources
    /auth_datasource.dart`) previously hit the live login-pincode endpoint
    unconditionally, and `requireManagerPincode`'s `result.fold((_) =>
    false, ...)` treated **any** failure — including a bare connection
    error — identically to a wrong pincode. Confirmed by reading the code
    directly before asking the user, not assumed. Fixed by reusing the
    exact "no TTL, revoked only by the next definite server rejection"
    mechanism the first Phase 6 slice already built, rather than inventing
    a second one: checks `_client.isOnline` first (skips the network call
    entirely when offline, mirroring `LoginPinCubit.login()`'s shape),
    caches via `OfflineAuthCache.saveForPin` on every online success,
    purges via `removeForPin` on a definite rejection
    (`Failure.isDefiniteAuthRejection`), and falls back to the cache on an
    inconclusive failure or while offline. Deliberately shares the *same*
    per-pincode cache regular PIN login already populates — a manager who's
    ever logged into or been verified on this terminal while online can be
    verified offline later, whether that happened via a full login or via a
    prior override check.
  - **Widened `verifyPincodeRole`'s return type from `UserRole` to the full
    `UserModel`**, threaded through `AuthRepository`/`AuthRepositoryImpl`/
    `VerifyManagerPincodeUsecase` — a deliberate scope decision, not
    incidental. An audit log that only knows "someone with the right role
    approved this" isn't much of an audit log; recording *who* (the
    approver's id/name) is the single most valuable field it can capture,
    and the backend already returns the full user on this endpoint — it was
    just being discarded down to a bare role. No other behavior change:
    `role.isManagerOrAdmin` is now read off `user.role` at the call site
    instead of the usecase returning it pre-extracted.
  - **New: `PrivilegedActionAuditLogService`** (`lib/core/services/audit/`)
    — a new `PrivilegedActionAuditEntry` Hive model (typeId 14, append-only,
    nothing in the app ever deletes or edits an entry) recording the action
    (`PrivilegedAction.shiftOpen/shiftClose/voidOrderItem`, a new small enum
    in `constants.dart`), timestamp, approved/denied, whether it was
    resolved offline, a denial reason, and both identities — who approved
    and who requested (very often different people; the whole point of an
    override is one person authorizing another's action). **Local-only, by
    necessity, not by choice:** confirmed via `ListAPI` that no backend
    endpoint exists yet to submit these for real off-device review — this
    is a device-local record a manager/admin can review on this terminal
    (surfaced read-only in the sync-status section, see below), not yet a
    synced entity. Flagged, not silently accepted.
  - **Recording centralized in one place, not scattered across call
    sites:** `requireManagerPincode` (`lib/core/widgets
    /manager_pincode_dialog.dart`) gained a required `action:
    PrivilegedAction` parameter and now records exactly one audit entry
    per attempt itself, inside the same `onConfirm` closure that already
    resolves the pincode — every one of this gate's 4 existing call sites
    (shift open/close toggle, close-shift screen, waiter bill panel,
    order-item void) was updated to pass its `PrivilegedAction`, but none
    of them had to be taught how to log anything. Auditing by construction
    of the gate, not by convention every caller has to remember.
  - **New card in the sync-status section** (§11 Phase 6, third slice) —
    `_AuditLogCard`, read-only (nothing here needs manual resolution, these
    are historical records), newest-10 shown with a total count, each row
    showing the action, elapsed time, an `offline` badge when relevant, and
    either the approver+requester or the denial reason.
  - *Verification:* `test/privileged_action_audit_log_test.dart` (new, 5
    tests) — approved/denied entry shape, newest-first ordering, multiple
    independent entries, `listenable` firing. **Not covered:**
    `AuthDatasourceImpl.verifyPincodeRole`'s online/offline/purge
    orchestration and `requireManagerPincode`'s recording wiring — both
    need a real `DioClient`/`ConnectivityCubit` (platform channel,
    unavailable here) or a full widget+DI-graph test respectively; same
    class of gap already disclosed multiple times this phase, verified by
    code review instead — the primitives this orchestration is built from
    (`OfflineAuthCache`'s per-pincode methods, `isDefiniteAuthRejection`)
    are already fully tested elsewhere, and the new orchestration mirrors
    `LoginPinCubit.login()`'s already-reviewed shape closely enough that
    reviewing it side by side was the actual verification step. `flutter
    analyze`: 69, unchanged. Full suite: 70/71 (66/67 before this slice,
    plus 5 new tests — the one failure is still `widget_test.dart`'s
    pre-existing, unrelated counter-app boilerplate).
  - **Residual gaps, disclosed:** no backend endpoint to sync the audit log
    off-device (noted above — a manager/admin can only review it on the
    specific terminal it happened on, and only for as long as the local
    Hive box survives an app reinstall); no retention/pruning policy for
    this box yet (unbounded growth is the same open question flagged for
    `PrintJob`/`QuarantinedOperation` in earlier slices — revisit together,
    not separately, once real usage shows a pattern worth pruning against);
    and the same "no real hardware run" caveat as the rest of this phase.
  - Phase 6's original scope was fully done except the full-shift soak
    test at this point — see the soak-test entry above (done later the
    same day) for how that was closed out without the feared fake-clock
    refactor.

**Phase 6 status: complete.** Every item from the original Phase 6 scope —
offline auth revocation, secure storage, the sync-status UI, deterministic
resilience tests, offline privileged-action authorization + audit logging,
and the full-shift soak test — shipped 2026-08-05. The one thing genuinely
left for later is a *real-hardware* pass (Android/Windows secure storage,
sync-status UI, reconnect/partition-healing, print claim/lease, all only
verified via loopback/desktop/`fake_async` so far, never actual target
devices on an actual flaky network) — not a Phase 6 checklist item, just
the natural next validation step before relying on this in the field.

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
   POSTs (unambiguous per-request status, at the cost of more round-trips). ~~Whether
   resending the same client order id is actually deduped server-side remains
   unverified — a cross-team question I can't resolve from the client alone.
   Order-item-level and non-order mutations (shift open/close, item cancel) have no
   id-based dedup at all yet, only the outbox's own at-least-once replay.~~
   **Resolved 2026-08-06 — see §14: read the actual backend source instead of
   guessing.** `/orders/batch`'s response turned out to already carry per-order
   results (`CreateOrderBatchItemResult{Index, Status, Order, Error}`) — the
   `{status, message}` this bullet describes was based on stale documentation,
   not the real handler. Still not adopted (serial single POSTs remain simpler
   and are already correct), but the actual dedup gaps this bullet worried about
   were real and are now fixed server-side: `CreateOrder`'s client-id check had
   a TOCTOU race, and `AddOrderItems`/`CancelOrderItem`/`CloseShift` had no
   idempotency guard at all. All four fixed in the backend repo — full writeup
   in §14.
3. **Fiscal compliance (§1 Q6) — explicitly deferred, not currently blocking.** No
   fiscal/OKKM integration exists today, and per discussion this isn't being designed
   for right now; Phase 7 (§11) is paused rather than executed. Flagging so it isn't
   forgotten later: if fiscal integration gets scoped, revisit Phase 5's
   cashier-receipt design (§8) against whatever legal constraint applies — nothing
   built in Phases 0-6 assumes this is solved.

---

## 14. Backend idempotency hardening (2026-08-06)

With every Phase 0-6 item done, went back to §13 risk #2's "unverified — a
cross-team question I can't resolve from the client alone" and actually
resolved it: read the backend's Go source directly (`~/Documents/work/MARY_AI/back`,
a separate repo from this Flutter app) instead of leaving it as a guess. Checked
every one of the six mutation types the offline queue relays
(`createOrder`, `addItems`, `payOrder`, `openShift`, `closeShift`,
`cancelLineItems`) for how each handles a retry whose *previous* attempt
already committed server-side but whose response never reached this client
(the exact case an at-least-once outbox exists to survive — a LAN relay
drop, a timeout, an app crash mid-request).

**Findings — three were already correct, three were real bugs:**

- **Already correct, no changes:** `MarkOrderPaid` (order.go:1247) and
  `CancelOrder` (order-level, order.go:1644) both have an explicit
  "idempotent: if already done, return success" guard with a comment
  naming this exact scenario. `OpenShift` (cash_register_shift.go:64) uses
  a DB partial-unique-index instead of check-then-act and translates the
  constraint violation into a clean error — the right way to do it.
- **Bug: `CancelOrderItem`** (order.go, was line 3707) had no such guard —
  "already cancelled" was a plain error, and the handler mapped every
  service error to 500. The offline queue only ever treats 404 as "already
  gone, move on"; a 500 is retried forever, so a cancel-line-item op whose
  first response got lost sat in the outbox indefinitely, never resolving
  (not data-corrupting, just permanently stuck).
- **Bug: `CloseShift`** (cash_register_shift.go, was line 80) — the SQL's
  `WHERE closed_at IS NULL` guard was already correct (no double-close
  data corruption possible), but a retry matching zero rows just became a
  generic error → 500 → same "stuck forever" outcome as above.
- **Bug (self-healing): `CreateOrder`'s client-id dedup** (order.go, was
  lines 211-222) reads "does this id already exist" in one transaction,
  then inserts later — check-then-act, not atomic. A genuine race between
  two concurrent attempts with the same client-generated order id could
  both pass the check before either commits. Not data-corrupting (`id` is
  the primary key, so the second insert fails with a constraint violation
  rather than duplicating a row) but did surface as a spurious failed
  request instead of the idempotent response the check was trying to give.
- **Bug (not self-healing): `AddOrderItems`** (order.go, was line 140) —
  every item got `ID: uuid.New()` with **no client-supplied idempotency
  key anywhere in the request at all**. A lost-response retry didn't error
  out — it silently created a second, fully duplicate set of items: double
  quantity, double stock deduction, double totals on the bill. This was
  the specific gap §13 risk #2 flagged as unverified; now confirmed with
  code and fixed.

**Fixes shipped, in the backend repo:**

- `CancelOrderItem` and `CloseShift` now both return the existing
  record instead of erroring when the target is already in its final
  state — the exact pattern `MarkOrderPaid`/`CancelOrder` already used,
  just applied consistently.
- `CreateOrder`'s insert now catches a unique-violation on the id column
  and, for a client-supplied id specifically, re-fetches and returns the
  existing order instead of propagating the constraint error — closes the
  TOCTOU window's failure mode without needing a heavier locking scheme.
- **New: `order_items.client_item_id`** (migration
  `70_order_items_client_id.up.sql` — `ALTER TABLE ... ADD COLUMN
  client_item_id UUID`, plus a partial unique index on `(order_id,
  client_item_id) WHERE client_item_id IS NOT NULL`). Optional — rows
  without one are never deduplicated, so this doesn't constrain any
  caller that doesn't opt in. `AddOrderItems` now checks for an existing
  item by `(order_id, client_item_id)` before creating one, skipping
  validation/stock-deduction/modifiers entirely on a dedup hit; the
  create call itself is wrapped in a SQL savepoint
  (`withOrderBatchSavepoint`, already used elsewhere in this file for
  exactly this reason) so that the same check-then-act race window
  `CreateOrder` has, if it happens here too, doesn't abort the rest of
  the items in the same request — the unique-violation is caught and
  turned into the same idempotent response the pre-check gives.
- **Verified against real Postgres, not just `go build`:** stood up a
  throwaway `postgres:15-alpine` container, applied all 70 migrations in
  order (confirmed the full chain applies cleanly — first time this was
  actually exercised end to end rather than assumed), then proved the new
  constraint directly: two inserts with the same `(order_id,
  client_item_id)` — the second genuinely fails with `duplicate key value
  violates unique constraint`, exactly the case `AddOrderItems`'s recovery
  path now catches; two inserts with `client_item_id IS NULL` for the same
  order don't collide (the partial index correctly leaves non-opted-in
  rows unconstrained); the down-migration cleanly drops both the index and
  the column. Container discarded after.
- Regenerated sqlc output for the schema change using the *pinned* sqlc
  version (`v1.30.0`, read off the existing generated files' header
  comment) rather than whatever `@latest` resolved to — an earlier attempt
  with a newer sqlc pulled in ~40 unrelated files' worth of incidental
  type-shape churn (`NullTableStatus` → `*TableStatus` and similar) from a
  codegen behavior change between versions, which was reverted before
  anything was committed. Matching the exact pinned version kept the diff
  to exactly the two files the schema change actually touches
  (`models.go`, `order.sql.go`).
- `go build ./...`, `go vet ./...`, and the existing `internal/service`
  test package all pass unchanged.

**Fixed on the Flutter side too — the backend fix alone doesn't help
without a matching client-generated id:** all three call sites that
enqueue an `addItems` offline-queue operation
(`create_order_bloc.dart`, `waiter_cubit.dart`, `detail_bloc.dart`) now
generate a `client_item_id` per item and send it in the request. The
important detail is *when* that id gets generated: in every one of these
three call sites, there's an online attempt first, and only on
`ConnectionFailure`/timeout does the offline-queue fallback kick in. If
the id were generated fresh at enqueue time (as an earlier draft of this
fix did), it wouldn't match whatever id the *lost-response* online attempt
already used server-side — defeating the entire point. Fixed by
generating the id(s) once, before the online attempt, and threading the
same id(s) through to the offline-queue fallback if it falls through —
mirroring `clientOrderId`'s already-established reasoning in
`create_order_bloc.dart` ("Generated once per create attempt so a
connection-failure retry replays under the SAME id"), just applied at the
item level. `flutter analyze`: 69, unchanged. `flutter test`: 74/75 (same
pre-existing unrelated `widget_test.dart` failure).

**Residual/still open:** whether the backend's `/orders/batch` response
shape being richer than assumed changes the earlier decision not to adopt
it — not revisited here, serial single POSTs are still simpler and were
already correct; only worth reconsidering if round-trip count becomes an
actual measured problem. `payOrder`'s idempotency guard was reviewed and
found correct but not independently load-tested for the same race window
`CreateOrder`/`AddOrderItems` had (same check-then-act shape, just already
guarded) — lower priority since it was already correct, not newly touched.

### 14.1 Floor Map "wrong hall, zero tables" bug (2026-08-06, same day)

Reported live via screenshot: Floor Map showed correctly-named hall tabs
("1", "Zal") but every hall at `(0)` and "No tables" in the body. Traced
to `CacheService` (`lib/core/services/cache/cache_service.dart`): its
single Hive box (`pos_cache`) has **no per-brand/per-branch scoping at
all**, and `AuthCubit.logoutFromApp` — the full re-provision flow that
also drops `brand_id`/`pos_password` for onboarding a different
restaurant onto this same terminal (`AuthRepositoryImpl.logoutFromApp`
→ `AppTokenStorage.deleteAll()`) — never cleared it. A terminal reused
across tenants would carry the previous tenant's cached halls/tables/goods
straight into the new one: a stale table whose `hall_id` no longer matches
any current hall simply vanishes from every hall-filtered view (matching
the screenshot exactly — real hall names, zero matching tables), while
`getHalls()`'s own network fetch (correctly scoped to whichever brand the
current token belongs to) shows the right hall names regardless.

Fixed two ways:
- **Root cause:** `CacheService.clearAll()` (wipes the whole box — every
  cached entity, not just halls/tables) called from
  `AuthCubit.logoutFromApp` right after the token-storage wipe succeeds.
  Regular staff `logout()` (same brand/branch, session-only) deliberately
  does **not** call this — that cache is still valid and clearing it would
  just force an unnecessary full re-fetch on the next login.
- **Defense in depth:** `MainCubit.loadAllHallsTables` now filters its
  cache-first table read down to rows whose `hallId` is among the
  *current* halls before ever displaying them, rather than showing
  whatever raw content the box happens to hold. This catches the same
  orphaned-row symptom from any cause, not just a tenant switch, and as a
  side effect stops a fully-orphaned cache from tripping the 30s "don't
  refetch" throttle (an empty filtered result no longer counts as "cache
  already has this hall's data").

Not independently verified against a real device mid-bug (no access to
the terminal in the screenshot, no logs beyond the one screenshot) — this
is the most concrete, evidenced-from-source root cause found (confirmed
no clear-on-logout path exists anywhere for this cache), not a confirmed
reproduction. If a device is stuck in this state on a build that predates
this fix, the existing manual refresh button only force-refetches tables
for whatever hall ids are already in memory — it does not clear the
underlying cache, so it will not recover a device whose in-memory `halls`
state is itself derived from stale cache. A full logout-from-app +
re-login is the only recovery path pre-fix. `flutter analyze`: 69,
unchanged. `flutter test`: 74/75 (same pre-existing failure).
