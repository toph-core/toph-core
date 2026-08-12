# Architecture Compliance Review

Reviewed against: **MASTER ARCHITECTURE SPECIFICATION** (local-first POS; UI reads only
the local database; networking isolated in a Sync Engine; Lease Manager for shared
resources only; Leader/Follower with automatic failover).

Reviewed: `lib/` at commit `ca88ed3`, all 416 Dart files, with emphasis on the four
components the spec defines (UI, Local Database, Synchronization Engine, Lease Manager).

---

## Final Question

> Does this implementation preserve the architecture exactly as specified?

# NO

The architecture is **broken**. Not "mostly preserved," not "close" — there are ten
distinct classes of violation, several of which are explicitly named on the
specification's own Forbidden list.

Two of them are structural, not incidental:

1. **The application owns two databases, not one.**
2. **The Leader never distributes data updates to Followers** — the message type does
   not exist. Followers stay current by talking to the Cloud themselves, which the
   specification forbids outright.

The core cashier flow (table map, order detail, payment, waiter, table timer) *has* been
rebuilt local-first and is genuinely compliant. That work is real and it is not what
fails this review. Everything below is what remains.

---

## What is compliant (stated so the NO is precise, not blanket)

These are correct and should not be touched during remediation — they are the reference
pattern the rest must be brought to:

- **`MenuRepositoryImpl`** (`lib/features/view/main/data/repository/menu_repository_impl.dart`)
  and **`TablesRepositoryImpl`** (`.../tables_repository_impl.dart`) are pure local
  database facades — `watchX()` / `getX()` over `LocalDatabase`, zero network. This is
  exactly what the spec's Component 1/2 boundary requires.
- **`MainCubit`** (table map) subscribes to `watchHalls()` / `watchAllTables()` —
  reactive, local, no fetch (`main_cubit.dart:31-42`).
- **`DetailBloc`** drives categories, goods, and bill detail off `watchCategories()`,
  `watchGoodsForCategory()`, `watchOrderDetail()` subscriptions
  (`detail_bloc.dart:134, 175, 820`). No fetch on screen open.
- **`WaiterLocalRepositoryImpl.createOrder`** takes the lease, writes the local bill,
  enqueues, and flips table status locally (`waiter_local_repository_impl.dart:317-354`).
  Correct ordering.
- **`LeaseManager`** exposes exactly one operation — `acquireTableLease(tableId)`
  (`lease_manager.dart:99`) — and never writes business data. Component 4 is scoped
  correctly: tables only, nothing else.
- **The outbox** (`OfflineQueueService`) has retry, exponential backoff, quarantine, and
  nine queued operation types covering the whole cashier write path.
- **`SyncEngine.start()`** centralizes all sync triggers in one place — periodic, startup,
  internet reconnect, LAN reconnect, local-write, manual (`sync_engine.dart:102-115`).

---

## Violations

### V1 — The application owns two databases

**Rule:** *"Every application owns exactly ONE database. Never two. Never cache +
database."* Forbidden: *"❌ More than one database per application"*, *"❌ Any bypass
around the local database."*

There are two independent Hive stores holding the same entities:

| | `CacheService` | `LocalDatabase` |
|---|---|---|
| Storage | one flat box `pos_cache` (`cache_service.dart:20`) | 17 typed boxes (`local_database.dart:104-123`) |
| Categories | `saveCategories` :25 | `saveCategories` :168 |
| Goods | `saveGoods` :31 | `saveGoods` :239 |
| Goods by category | `saveGoodsForCategory` :50 | `saveGoodsForCategory` :266 |
| Departments | :66 | :181 |
| Users | :77 | :230 |
| Halls | :152 | :190 |
| Tables | :158 | :200 |
| Order detail | `saveOrderDetail` :164 | `saveOrderDetail` :340 |
| Service charge | :113 | :314 |
| Transaction groups | :88 | :295 |
| Ingredients / compounds | :100 / :105 | :279 / :286 |
| Archives | :185 | :407 |

`SyncEngine._hydrateReferenceData` **writes both on every pass** —
`sync_engine.dart:254-273` is a literal pair of writes per entity:

```dart
await _cache.saveCategories(categories.map((c) => c.toJson()).toList());
await _localDb.saveCategories(categories);
```

repeated for departments, halls, tables, users, and again in
`_hydrateIngredientsAndCompounds` (:317-336), `_hydrateTransactionGroups` (:360-370),
`_hydrateServiceCharge` (:397-409), `_hydrateGoodsByCategory` (:414-435),
`_hydrateOpenOrderDetails` (:449-468).

And the UI reads from **both**, arbitrarily:

- `detail_bloc.dart:348, 752` — `_cache.getGoods()`
- `payment_bloc.dart:280, 350` — `inject<CacheService>().getGoods()`
- `waiter_cubit.dart:384` — `inject<CacheService>().getGoods()`
- `payment_screen.dart:342` — `inject<CacheService>().getGoods()`
- `tab_filter.dart:58` — `inject<CacheService>()`
- `printers_section.dart:48` — `inject<CacheService>().getCategories()`

`local_database.dart:24-28` still carries its original header comment — *"Nothing reads
from `LocalDatabase` yet"* — which is now false, but the migration it describes was never
finished. The result is not one database with a cache in front of it; it is two
sources of truth for the same entities, dual-written, and read from
interchangeably. That is precisely the shape the specification names and rejects.

**Why this breaks the architecture:** the spec's guarantee is that the UI observing the
local database sees all changes. With two stores, a write that lands in one is invisible
to any screen reading the other. `CacheService` is also non-reactive — a flat box with no
`watch()` surface — so every read through it is a point-in-time snapshot, which is why
the screens above use imperative `getGoods()` instead of a stream.

---

### V2 — Screens fetch from the network directly

**Rule:** *"The UI displays information. The UI never fetches information."* Forbidden:
*"❌ Screen loading data from network"*, *"❌ Repository fetching for UI"*,
*"❌ Widget making HTTP request."*

Seven screen files inject the network-backed `MainRepository` straight into the widget:

| File | Line |
|---|---|
| `pages/transactions/sections/transactions_list_section.dart` | 73 |
| `pages/transactions/sections/transaction_categories_section.dart` | 25 |
| `pages/settings/sections/users_section.dart` | 32 |
| `pages/settings/sections/halls_tables_section.dart` | 28 |
| `pages/settings/sections/printers_section.dart` | 26 |
| `pages/menu/menu_manage_screen.dart` | 41 |
| `pages/menu/menu_meals_list_screen.dart` | 36 |

`MainRepositoryImpl` is a direct pass-through to `MainDataSources` (Dio) for almost every
read — `getAllTables` :85, `getHalls` :107, `getCategories` :112, `getDepartments` :117,
`getGoodsByCategoryId` :122, `getArchives` :134, `getAdminUsers` :302, `getTransactions`
:266, `searchGoodsAdmin` :356, `getGoodById` :369. No local database involved at any
point.

The pattern in every one of these screens is the forbidden one, verbatim.
`transactions_list_section.dart`:

```dart
void initState() {
  super.initState();
  _loadOptions();
  _load(page: 1);        // :104-107  — network fetch on screen open
}

Future<void> _load({required int page}) async {
  setState(() { _loading = true; });          // :138-141 — UI blocks on network
  final result = await _repository.getTransactions(...);   // :143
  result.fold(
    (failure) => setState(() { _loading = false; ... }),   // :152 — error state from network
    (data)    => setState(() { ... _loading = false; }),   // :156
  );
}
```

Same shape in `users_section.dart:70-98`, `printers_section.dart:43-65`,
`menu_meals_list_screen.dart:128-152`, `halls_tables_section.dart:38-52`.

**Review question the spec mandates:** *"Can this screen fully function with the internet
disconnected?"* For all seven: **no**. They open to a spinner and settle on an error
state. Reject.

---

### V3 — Refresh buttons that fetch

**Rule:** Forbidden: *"❌ Refresh button fetching data."*

- `transactions_list_section.dart:394` — `onPressed: () => _load(page: _page)`
- `halls_tables_section.dart:200` — `onPressed: _load`
- `printers_section.dart:80` — `_loadAll()` on user action
- `menu_meals_list_screen.dart:164` — `await _loadGoods(page: _page)`

Pagination is the same violation by another name — `transactions_list_section.dart:454`
(`_load(page: i + 1)`), `:496` (page-size change), `:264` and `:334` and `:362` (search
and filter changes) each issue a network round-trip the user waits on.

---

### V4 — "Try server first," then fall back to cache

**Rule:** Forbidden: *"❌ 'Try server first'"*, *"❌ 'Fetch if local empty'"*,
*"❌ Waiting for downloads."*

Nine call sites implement exactly this, including in classes named `Local`:

| File | Lines |
|---|---|
| `main_repository_impl.dart` (`getUsers`, `getServiceCharge`, `getTransactionGroups`, `getIngredients`, `getCompounds`) | 65, 193, 235, 413, 428 |
| `menu_local_repository_impl.dart` | 22, 42 |
| `archives_local_repository_impl.dart` | 53, 85 |

The canonical instance, `main_repository_impl.dart:60-82`:

```dart
if (_connectivity.isOnline) {
  final result = await _dataSources.getUsers();   // server first
  ...
  return result;                                  // UI waits on the network
}
final cached = _cache.getUsers();                 // fallback only when offline
if (cached.isEmpty) return const Left(ConnectionFailure());
```

Online, the UI blocks on the network on every call and the local data is never consulted.
The local store is demoted to a disaster fallback — the exact inversion of the specified
architecture, where the local database is the only thing the UI ever reads and the
network only ever writes *into* it.

---

### V5 — Widgets perform HTTP requests inside `FutureBuilder`

**Rule:** Forbidden: *"❌ FutureBuilder performing API calls"*, *"❌ Widget making HTTP
request."*

`lib/core/common/custom_network_image.dart:47-48` — a `StatelessWidget` whose `build()`
issues a network fetch:

```dart
return FutureBuilder<Uint8List?>(
  future: MinioService.instance.getImageByObjectName(minioObjectName!),
```

and `:76` falls through to `CachedNetworkImage(imageUrl: imageUrl!)` — a second HTTP path
from inside a widget. This is a shared component; every screen rendering a menu image
inherits the violation.

`menu_manage_screen.dart:2481` — `FutureBuilder(future: _fetchAndCacheImage(menuRepo, ref))`,
reached when `LocalDatabase` has no bytes for the object name. The in-code comment
(`:2455-2460`) argues it "only ever runs for the one case hydration can't cover yet." The
specification does not admit that argument — *"❌ 'Fetch if local empty'"* is listed
without exception, and *"Do NOT introduce 'temporary solutions'"* is in the preamble.
Reject.

---

### V6 — The Leader never distributes data updates to Followers

**Rule:** *"Leader distributes updates."* / *"Leader broadcasts updates immediately.
Followers apply updates immediately."* / *"Updates propagate through LAN almost
immediately."*

`LanHubMessageType` (`lan_hub_message.dart:3-17`) has fifteen variants. Exactly one
carries business data: `tableStatus`. The rest are transport, auth, op-relay, print-job,
and lease messages.

There is **no message type for propagating categories, goods, menus, departments, halls,
users, orders, bills, payments, or timers from Leader to Follower.** Not unimplemented —
unrepresentable. Nothing in the codebase can encode such a broadcast.

Consequence: when the Leader downloads a menu change from the Cloud, the Followers do not
learn about it over the LAN at all. `BACKEND_SYNC_PLAN.md` §5 Gap 3 identifies this
correctly and leaves it open. It is the single largest gap between this codebase and the
specification, and it is load-bearing — "Followers synchronize with the Leader" is a
Required Property.

---

### V7 — Followers communicate directly with the Cloud

**Rule:** *"Followers never communicate with the Cloud."* Forbidden: *"❌ Followers
communicating directly with the Cloud."*

`sync_engine.dart:149-163`, the `LanMode.client` (Follower) branch:

```dart
if (_lanHub.mode == LanMode.client) {
  if (_queue.hasItems) {
    await _queue.relayViaLan(...);       // correct — writes go via the Leader
  }
  if (_connectivity.isOnline) {
    await _cache.prefetchAllGoods(_client);   // :157 — Follower → Cloud, directly
    await _mirrorGoodsIntoLocalDb();
    await _hydrateReferenceData();            // :159 → MainRepository → Dio → Cloud
    _refreshUserProfile();                    // :160 → Cloud
  }
```

A Follower with its own internet fetches the entire catalog, reference data, open-order
details, table timers and menu images straight from the Cloud, bypassing the Leader
entirely. `_hydrateReferenceData` reaches the Cloud through the same `MainRepository` the
UI uses (`:237`).

This is V6's consequence made concrete: because the Leader cannot push data, each
Follower was given its own Cloud uplink to compensate. The two violations are one design
decision. A Follower **without** its own internet — the deployment shape the whole
Leader/Follower design exists to serve — receives no reference-data updates at all, since
line 156 gates all of it behind `_connectivity.isOnline`.

---

### V8 — Leader failover is not automatic

**Rule:** *"If the Leader disappears... Another terminal becomes Leader. Automatically.
No manual intervention."* Required Property: *"✅ Leader failover is automatic."*

`LeaderElectionService` is a complete implementation — epoch fencing, priority,
heartbeat liveness, jittered claims. It is also **off**:

- `leader_election_service.dart:73` — `bool get isEnabled => _prefs.getBool(electionEnabledKey) ?? false;`
- `di.dart:154-159` — registered with the comment *"disabled by default... `start()` itself
  no-ops unless a branch has explicitly opted in via `setEnabled(true)`"*
- `leader_election_service.dart:23-24` — *"Flipping `setEnabled` is the one manual step
  needed to turn this on for a branch"*
- `lan_hub_service.dart:114` — the UDP conflict watcher stays on the warn-only path
  whenever the flag is false, i.e. in every default build

The only thing that ever sets it is a settings toggle a human must find and flip
(`sync_status_section.dart:341-392`, *"Avtomatik yetakchi saylovi"*, default OFF).

In a default installation, if the Leader disappears, **no terminal becomes Leader.** The
spec's requirement is "no manual intervention"; the implementation's own documentation
describes a required manual intervention.

---

### V9 — The UI knows who the Leader is

**Rule:** *"Leadership is an implementation detail. The cashier must never know who the
Leader is."* Required Property: *"✅ UI never knows Leader changed."*

`sync_status_section.dart` renders cluster role directly to screen:

- `:362` — `ElectionRole.leader => 'Bu terminal yetakchi'` ("this terminal is the leader")
- `:301-324` — *"Klaster — Hub"* / *"Klaster — Client"* status cards, connection counts
- `:391` — the leader-election toggle itself
- `:388` — role-dependent icon color

The spec permits no surface for this. Leadership is meant to be invisible; here it is a
settings page with a switch.

---

### V10 — Writes that never touch the local database

**Rule:** *"Write locally first. Synchronize afterward. Never wait for networking."*

The outbox covers nine operation types (`pending_operation.dart:6-36`) — the cashier
path. Everything else writes straight to the network and is lost when offline:

`main_repository_impl.dart` — `pushPrinterSetting` :221, `deletePrinterSetting` :225,
`createTransactionGroup` :250, `updateTransactionGroup` :254, `deleteTransactionGroup`
:258, `createIncomeExpenseTransaction` :284, `createTransferTransaction` :289,
`updateTransaction` :294, `deleteTransaction` :298, `createUser` :316, `updateUser` :320,
`deleteUser` :324, `deleteHall` :328, `createHall` :332, `updateHall` :336, `createTable`
:340, `updateTable` :344, `deleteTable` :348, `createCategory` :352, `createTranslation`
:386, `updateTranslation` :391, `saveGoodWithCalculations` :397, `deleteGood` :408.

Twenty-three write operations, none local-first, none queued.

`service_charge_cubit.dart:58-64` makes the rejection explicit in the UI layer:

```dart
if (!_connectivity.isOnline) {
  emit(state.copyWith(error: "Ulanish yo'q — o'zgartirish uchun internet talab qilinadi."));
  return false;
}
```

The in-code comment calls this *"Deliberately online-only, not queued."* Deliberate or
not, the specification does not carve out low-volume config values.

**Review question the spec mandates:** *"Does this feature still work if synchronization
is delayed?"* For all twenty-three: **no**. Reject.

---

## Summary

| # | Violation | Spec rule broken | Severity |
|---|---|---|---|
| V1 | Two databases (`CacheService` + `LocalDatabase`), dual-written, both read by UI | "exactly ONE database" | **Structural** |
| V2 | 7 screens fetch from network in `initState`/`setState` | "UI never fetches" | **Structural** |
| V3 | Refresh buttons, pagination, filters all trigger fetches | "❌ Refresh button fetching data" | High |
| V4 | 9 "try server first, fall back to cache" call sites | "❌ 'Try server first'" | High |
| V5 | `FutureBuilder` + Minio/HTTP inside widgets | "❌ Widget making HTTP request" | High |
| V6 | No Leader→Follower data broadcast message type exists | "Leader distributes updates" | **Structural** |
| V7 | Followers fetch catalog/reference data from Cloud directly | "❌ Followers communicating directly with the Cloud" | **Structural** |
| V8 | Leader election disabled by default, manual toggle to enable | "✅ Leader failover is automatic" | **Structural** |
| V9 | Cluster role and leader identity rendered in settings UI | "UI never knows Leader changed" | Medium |
| V10 | 23 admin/config writes bypass the outbox entirely | "Write locally first" | High |

**Required Properties status:**

| Property | Status |
|---|---|
| UI always reads from local database | ❌ V2, V4, V5 |
| Networking completely isolated | ❌ V2, V5 |
| Synchronization automatic | ✅ |
| Synchronization invisible | ❌ V9 |
| Synchronization never blocks UI | ❌ V2, V4, V10 |
| Every instance owns exactly one database | ❌ V1 |
| Leader owns exactly one database | ❌ V1 |
| Followers own exactly one database | ❌ V1 |
| Leader synchronizes with Cloud | ✅ |
| Followers synchronize with Leader | ❌ V6, V7 (writes only; reads bypass Leader) |
| Updates propagate through LAN almost immediately | ❌ V6 (table status only) |
| Leader failover automatic | ❌ V8 |
| UI never knows Leader changed | ❌ V9 |
| Table ownership coordinated | ✅ |
| Everything else local-first | ❌ V2, V4, V10 |

**4 of 15 Required Properties hold.**

---

## What remediation requires

Ordered by dependency, not by effort. Nothing below is a suggestion about code style; each
item is the removal of a specific violation above.

1. **Collapse to one database.** Migrate the remaining `CacheService` readers onto
   `LocalDatabase` (`detail_bloc`, `payment_bloc`, `waiter_cubit`, `payment_screen`,
   `tab_filter`, `printers_section`), delete the dual writes in `SyncEngine`, delete
   `CacheService`. The device-scoped USB printer-name map is the one entry that is not
   duplicated data — it belongs in the printer config store, not a second database. (V1)

2. **Add a Leader→Follower data broadcast.** A new `LanHubMessageType` variant carrying
   an entity kind plus payload, leader-side fan-out on every applied Cloud change,
   follower-side apply straight into `LocalDatabase`. Nothing in the UI changes — screens
   are already watching the boxes this writes to. (V6)

3. **Cut the Follower's direct Cloud uplink.** Once (2) exists, delete
   `sync_engine.dart:156-161` — the client-mode branch keeps only the outbox relay. (V7)

4. **Give the back-office screens local boxes and reactive repositories.** Transactions,
   admin users, halls/tables management, printer settings, menu management need the
   `MenuRepositoryImpl`/`TablesRepositoryImpl` treatment: `watchX()` over `LocalDatabase`,
   hydrated by `SyncEngine`. Then delete every `inject<MainRepository>()` from the widget
   layer. Paginated/searched server queries have no bounded local mirror today — that is a
   real product decision (mirror a bounded window locally, or accept these screens as
   non-compliant), and it needs to be made rather than left implicit. (V2, V3, V4)

5. **Move image loading behind the local database.** `CustomCachedNetworkImage` becomes a
   `StreamBuilder` over `LocalDatabase.watchImage()`; `SyncEngine._hydrateMenuImages`
   already populates that box. Delete both `FutureBuilder`s and the `CachedNetworkImage`
   fallback. (V5)

6. **Queue the remaining 23 writes.** Extend `PendingOperationType` to cover admin and
   config mutations, write local first, enqueue, let the outbox replay. (V10)

7. **Enable leader election by default and remove the toggle.** The service is complete;
   the flag is the only thing standing between this codebase and automatic failover.
   Removing the toggle also removes most of V9. (V8, V9)

8. **Remove cluster role from the UI.** The sync-status section may show queue depth and
   last-sync time — never who the Leader is. (V9)

---

## Note on process

Items 2, 3, 4, and 6 are design-and-build work, not wiring fixes, and item 4 contains a
product decision (bounded local mirrors for paginated back-office reads) that has been
deferred repeatedly across `BACKEND_SYNC_PLAN.md`, `CLIENT_FACING_OFFLINE_PLAN.md`, and
`EXECUTION_CONCERNS.md` without being made. The specification instructs: *"If you cannot
preserve it, STOP and explain why. Do NOT silently compromise."* This document is that
stop. No code was changed in this pass.
