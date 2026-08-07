# LAN Synchronization Architecture Audit

**Date:** 2026-08-07. **Branch:** `offline-again`.
**Scope:** the Main-Instance/Satellite LAN model specifically — `lib/core/services/lan_hub/`
(`lan_hub_service.dart`, `lan_hub_server.dart`, `lan_hub_client.dart`, `lan_hub_message.dart`)
and every place the presentation layer touches it.
**Companion docs:** `offline-first-compliance-audit.md` (2026-08-06, general offline-first
grade) and `offline-first-violations-audit.md` (2026-08-07, stricter re-read of the same
ground). Neither of those docs audits the LAN leader/satellite model against the specific
"one DB per instance, Main Instance DB = global LAN DB, satellites never talk to each other"
rules this file checks against — that's what's new here.

---

## VERDICT

**Does this implementation preserve the offline-first architecture while using the Main
Instance as the authoritative LAN synchronization hub? NO.**

The write side is close: a Satellite's queued write is relayed through the Main Instance
(`LanHubService.relayOperation` → `_handleRelayOp`) rather than posting to the cloud
directly, and the Main Instance never talks peer-to-peer — every fan-out goes through its
own WebSocket server (`lan_hub_server.dart:167-179`, `_broadcastExcept`), which is the
correct star topology.

The read side is not built at all, and — worse than merely missing — the thing standing in
for it hands live network data straight to a Bloc, which mutates UI state directly from a
socket message without ever touching the local database. That is the single specific
failure mode this rule set calls out by name: **"If network data reaches the UI directly...
you broke the architecture."** It happens here, concretely, twice.

---

## Quick-reference violation table

| # | Severity | Rule violated | Where |
|---|---|---|---|
| L1 | 🔴 Critical | "If network data reaches the UI directly, you broke the architecture" — remote table-status updates are applied straight to Bloc state, never written to the local DB | [main_cubit.dart:43-53](lib/features/view/main/presentation/cubit/main/main_cubit.dart#L43-L53) |
| L2 | 🔴 Critical | "UI requesting data from another application" / "Controller talking to sockets" — a Cubit and a Bloc hold a direct `LanHubService` reference and call it | [main_cubit.dart:17-41,110-114](lib/features/view/main/presentation/cubit/main/main_cubit.dart#L17-L41), [create_order_bloc.dart:41,232,273](lib/features/view/main/presentation/cubit/create_order/create_order_bloc.dart#L41) |
| L3 | 🔴 Critical | "Main Instance's local database is the global LAN database" — no such mechanism exists; there is no read-side sync from leader DB to follower DB at all | [sync_engine.dart:99-129](lib/core/sync/sync_engine.dart#L99-L129) |
| L4 | 🟠 High | "No screen should suddenly become unusable... if the Main Instance temporarily disconnects" — a `client`-mode terminal's reference-data hydration is gated on *its own* internet, not on reaching the leader, so it silently gets none | [sync_engine.dart:103-116](lib/core/sync/sync_engine.dart#L103-L116) |
| L5 | 🟡 Medium | Same "network data reaches [consumer] directly" pattern, applied to print coordination instead of a Bloc — lower stakes but same shape | [lan_hub_service.dart:261-297](lib/core/services/lan_hub/lan_hub_service.dart#L261-L297) |

What is **not** a violation, checked and confirmed clean:

- **No satellite-to-satellite direct connection.** `LanHubServer` holds one `Set<WebSocket>`
  of client connections and fans a message out via `_broadcastExcept` (`lan_hub_server.dart:181-193`)
  — every satellite talks only to the Main Instance's socket; the Main Instance relays.
  Satellites never open a socket to each other. This is the one part of the design that
  matches "the only synchronization path is Satellite ↔ Main Instance" exactly.
- **The Main Instance is the only thing that talks to the global backend for relayed
  writes** — `_handleRelayOp` (`lan_hub_service.dart:210-237`) executes a follower's queued
  operation against the cloud through the leader's own `DioClient`/`OfflineQueueService`;
  the follower's outbox bookkeeping is untouched until the leader replies. This matches
  "Only the Main Instance communicates with the global backend server" for the write path.

---

## L1 — Remote table-status updates bypass the local database and land directly in UI state

**File:** `main_cubit.dart:24,43-53,110-114`

```dart
StreamSubscription<({String tableId, String status})>? _lanSub;

MainCubit(...) : super(const MainState()) {
  _lanSub = _lanHub.onRemoteTableUpdate.listen(_applyRemoteTableUpdate);
}

void _applyRemoteTableUpdate(({String tableId, String status}) event) {
  final newStatus = TableStatus.values.where((s) => s.name == event.status).firstOrNull;
  if (newStatus == null) return;
  updateTableStatus(event.tableId, newStatus);   // mutates Bloc state directly
}

void updateTableStatus(String id, TableStatus status) {
  if (state.tables != null) {
    final index = state.tables!.indexWhere((v) => v.id == id);
    if (index != -1) {
      final newTables = List<CafeTableModel>.from(state.tables!);
      newTables[index] = newTables[index].copyWith(status: status);
      emit(state.copyWith(tables: newTables));   // no CacheService write anywhere in this path
    }
  }
}
```

**What's wrong:** when another terminal changes a table's status, the message arrives over
the LAN socket, `LanHubService` republishes it on `onRemoteTableUpdate`, and `MainCubit`
patches its own in-memory `state.tables` list directly. `CacheService.saveTables(...)` is
never called anywhere in this path. Compare to every other table write in this same file
(`_getTablesByHallId`, `loadAllHallsTables`) which *do* call `_cache.saveTables(...)` before
emitting.

**Why this is a violation, precisely as stated in the rules:** *"Every network path ends by
writing into a local database before the UI observes it. If network data reaches the UI
directly... you broke the architecture."* This is exactly that failure, not an analogy of
it — a message that originated on another application's socket connection is applied to
this application's UI state with the local database step skipped entirely.

**Consequence beyond the architecture violation itself:** because the local DB was never
updated, this fix is not even durable — restart the app, or trigger any other cache-backed
tables read (`loadAllHallsTables`'s own cache-first emit, `_getTablesByHallId`'s cache-first
emit), and the status silently reverts to whatever was last actually written to
`CacheService`, until the next full network refetch happens to overwrite it correctly. The
in-memory patch is a visual illusion of consistency, not real consistency.

**Which component is responsible:** the LAN synchronization engine (`LanHubService`), not
`MainCubit`. `MainCubit` should not be a message consumer at all.

**Correct architecture:** `LanHubService`'s message handler writes the incoming table-status
change into `CacheService`/local DB directly (the same call `_getTablesByHallId` already
makes), and does nothing else. `MainCubit` has no `onRemoteTableUpdate` subscription, no
`_applyRemoteTableUpdate`, no `updateTableStatus` called from outside a local-DB read — it
only ever re-reads from `CacheService` (ideally reactively, off a Hive `listenable()`) the
same way it does for every other table update.

## L2 — Presentation-layer Blocs hold a direct `LanHubService` reference and drive it

**Files:** `main_cubit.dart:17-41,110-114`, `create_order_bloc.dart:13,41,232,273`

`MainCubit` constructor takes `LanHubService` as a dependency (L22,38), calls
`_lanHub.tableStatusChanged(...)` from `broadcastTableStatus()` (L111-114), and — per L1 —
subscribes to its stream. `CreateOrderBloc` does the same:
`_lanHub.tableStatusChanged(state.tableId, TableStatus.busy.name)` at L232 and L273, called
straight out of the order-creation/add-item success handlers.

**Why this is a violation:** *"The UI knows nothing about networking. It never talks to...
Main Instance... satellite instances... sockets... If the UI knows another application
exists, the architecture is already broken."* `MainCubit` and `CreateOrderBloc` are
presentation-layer classes (they extend `Cubit`/`Bloc`, are provided via `BlocProvider`, and
are read directly by widgets via `context.read`/`context.select`). Both hold a field typed
`LanHubService`, both call a method on it whose entire job is to serialize a message onto a
socket. That is the UI layer knowing a socket-based peer exists and directly operating it —
one import away from `Widget opening sockets`, and no better for it being a Bloc instead of
a widget.

**Which component is responsible:** whatever currently calls `broadcastTableStatus`/
`tableStatusChanged` (order creation, payment success, item add) should instead write the
new table status into the local database. The LAN sync engine already watches that
database for changes it needs to propagate to the Main Instance — see L3/correct-architecture
below — so no Bloc needs to know `LanHubService` exists at all.

**Correct architecture:** `MainCubit`/`CreateOrderBloc` write `TableStatus.busy` (etc.) to
`CacheService` like any other local mutation. `LanHubService` (or something in the sync
layer) watches that same local table for writes and is the thing that calls
`tableStatusChanged` outward — the Bloc never imports `LanHubService`, never has a field of
that type, never calls a method on it.

## L3 — "Main Instance's local database is the global LAN database" isn't implemented

**File:** `sync_engine.dart:99-129`, `lan_hub_service.dart` (entire file)

**What's wrong:** the rules describe one specific pipeline for reference data: `Global
Backend → Main Sync Engine → Main Instance Local Database → LAN Synchronization → Satellite
Local Database → Satellite UI`. Search the LAN layer for anything that pushes the leader's
local `CacheService` contents (categories, goods, halls, tables, users) down to a follower's
own `CacheService` — it does not exist. `LanHubMessageType` (`lan_hub_message.dart:3-14`) has
exactly ten variants: `tableStatus`, `ping`, `auth`, `authOk`, `authFail`, `relayOp`,
`relayOpResult`, `printJobAnnounce`, `printJobClaim`, `printJobResult`. None of them carry a
category, a good, a hall, a table row, or a user record. There is no `referenceDataSync`
message type, no "leader pushes its cache to a newly-connected follower" handshake step
anywhere in `LanHubServer`'s connection-accept path (`lan_hub_server.dart:73-159`).

**Why this is a violation:** the Main Instance's local database is never treated as
authoritative for the LAN in any way the code actually implements. The only two things that
flow from leader to follower are (a) relayed-write results (`relayOpResult`) and (b) live
ephemeral broadcasts (table status, print coordination) that skip the database entirely
(L1, L5). Reference data has no LAN sync mechanism at all — a follower's copy of categories/
goods/halls/tables/users comes exclusively from that follower's own, entirely independent
call to `SyncEngine._hydrateReferenceData()`/`prefetchAllGoods` against the cloud (see L4)
— i.e. from the *global* backend directly, never mediated through the Main Instance's
database as the rules require.

**Which component is responsible:** the LAN sync engine (`LanHubService` + `SyncEngine`
together) — this is squarely their job, and neither does it.

**Correct architecture:** on follower connect (or on a bulk-hydration tick), the leader reads
its own `CacheService` and pushes categories/goods/halls/tables/users to the follower, who
writes them into its own `CacheService`. The follower's UI still only ever reads its own
local DB — this is purely a leader-DB-to-follower-DB sync step, invisible to any Bloc.

## L4 — A LAN-connected follower with no WAN of its own gets zero reference-data sync

**File:** `sync_engine.dart:99-116`

```dart
Future<void> tick({bool force = false}) async {
  ...
  if (_lanHub.mode == LanMode.client) {
    if (_queue.hasItems) {
      await _queue.relayViaLan(...);          // writes: relayed through leader — fine
    }
    if (_connectivity.isOnline) {              // <-- THIS terminal's own WAN, not the leader's
      await _cache.prefetchAllGoods(_client);
      await _hydrateReferenceData();
    }
    _recordSync();
    return;
  }
  ...
}
```

**What's wrong:** in `client` (follower) mode, the outbox correctly relays through the
leader regardless of this terminal's own connectivity (the comment at
`sync_engine.dart:86-93` explicitly says so, and means it — that part is right). But the
*read* side — `prefetchAllGoods` and `_hydrateReferenceData`, i.e. every bit of
categories/departments/halls/tables/users/goods sync — is gated on `_connectivity.isOnline`,
which is this device's own direct WAN reachability, unrelated to whether the leader (with
its own WAN) is reachable over LAN.

**Why this is a violation:** this is the exact scenario the "Main Instance" concept exists
to solve — a follower terminal with LAN but no WAN of its own — and per the rules, "If the
Main Instance temporarily disconnects... satellite instances continue using their own local
databases. No screen should suddenly become unusable." Here the failure mode is different
but just as bad: a follower that *never had* its own WAN (LAN-only by design, exactly the
deployment this whole mechanism targets) never populates its reference-data cache via the
leader at all — L3 confirms there's no such path — and this `if (_connectivity.isOnline)`
guard confirms it also can't fall back to fetching it directly either, since it has no WAN.
Net result: a pure-LAN follower terminal's categories/goods/halls/tables/users are frozen at
whatever the app shipped with or last had cached before losing WAN, forever, even while
happily relaying writes through a leader that has full internet access one hop away.

**Which component is responsible:** `SyncEngine.tick()`'s `client`-mode branch.

**Correct architecture:** once L3 exists (leader pushes reference data to followers over
LAN), this branch's read-side gate should be "is the leader reachable over LAN," not "does
this terminal have its own WAN" — mirroring exactly how the write-side relay already ignores
this terminal's own connectivity and correctly checks `_lanHub.isClientConnected` instead
(`sync_engine.dart:106`).

## L5 — Print-job coordination messages land directly in a service, bypassing persisted state, same shape as L1

**File:** `lan_hub_service.dart:261-297` (`_handleRemoteMessage`)

**What's wrong:** `printJobAnnounce`/`printJobClaim`/`printJobResult` messages are handed
straight to `PrintQueueService.onRemoteAnnounce`/`onRemoteClaim`/`onRemoteResult` from inside
the socket message handler — the same "live network message drives application state
directly" shape as L1, just aimed at a service instead of a Bloc.

**Why this is lower severity than L1:** `PrintQueueService` already persists print job state
to its own store on the claiming/originating side (per the print-queue mechanism confirmed
in `offline-first-compliance-audit.md` §6) and this is coordinating a one-shot physical
action (which terminal prints this receipt) rather than data the UI displays and must stay
consistent with — there's no "UI reads stale print-job status from cache" failure mode the
way there is for tables. Still flagged because it's architecturally the identical pattern
this rule set names as the cardinal sin, just with a smaller blast radius.

**Correct architecture:** same principle as L1 — the handler should write the incoming
announce/claim/result into `PrintQueueService`'s own persisted store first, and
`PrintQueueService` should react to its own store changing, rather than being called as a
direct RPC target from the socket layer. Whether this is worth restructuring depends on
whether `PrintQueueService`'s internals already amount to the same thing under a different
name — not independently re-verified in this pass, flagged for follow-up rather than as a
confirmed structural fix needed.

---

## Correct data flow (for reference, per the rules being audited against)

```
Global Backend
      ↓
Main Sync Engine
      ↓
Main Instance Local Database  (= the global LAN database)
      ↓
LAN Synchronization
      ↓
Satellite Local Database
      ↓
Satellite UI
```

## Actual data flow found in this codebase

```
Global Backend
      ↓ (only when a leader, OR when a follower happens to have its own WAN — L4)
SyncEngine._hydrateReferenceData / prefetchAllGoods
      ↓
CacheService (per-instance, independent — no leader→follower DB sync exists — L3)
      ↓
Bloc/Cubit (cache-first read, per offline-first-violations-audit.md V4/V5)
      ↓
UI

                    ...meanwhile, in parallel, unconditionally...

Another terminal's LanHubService.tableStatusChanged() / broadcastPrintJob*()
      ↓ (WebSocket, correctly star-routed through the Main Instance — no P2P — confirmed clean)
This terminal's LanHubService._handleRemoteMessage
      ↓
MainCubit._applyRemoteTableUpdate  /  PrintQueueService.onRemote*   ← skips the local DB (L1, L5)
      ↓
UI state / service state, directly
```

The two pipelines coexist and don't agree with each other: the cache-first pipeline is the
one the rules describe (partially — L3/L4 show its LAN leg is missing); the live-broadcast
pipeline is a second, faster, un-persisted channel that reaches the UI without ever going
through the step the rules say is mandatory. A screen open at the moment both fire can show
a table status that traces back to a socket message the local database doesn't know about.
