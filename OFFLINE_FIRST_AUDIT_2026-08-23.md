# Offline-First Architecture Audit

**Date:** 2026-08-23  
**Scope:** `Mary-Ai-POS` (Flutter POS client) and `back` (Go backend), working tree  
**Method:** five parallel area audits, then two independent verification passes per claim

---

## The requirement being audited

After a terminal is provisioned, the client side must never make a request to the global backend server. The UI reads only the local SQLite replica; every write commits a local row and an outbox operation in one transaction and returns without awaiting the network. All networking belongs to the sync layer.

**Sanctioned exceptions:** first-time provisioning; LAN traffic between terminals; entities with no backend change-log trigger (menu image blobs, `table_time_sessions`); the connectivity reachability probe; token refresh.

**Owner-accepted debt (not re-litigated here):** printer-settings push is fire-and-forget with device-local storage authoritative; menu-image upload and fetch-on-miss require connectivity.

---

## Verdict

**For reads, the requirement holds.** Every read path in the presentation layer terminates in a local query. There is no `FutureBuilder` in the tree, no repository injected into a widget, and `OutboxDrainer.drain()` has exactly one caller. Roughly 20 methods on the network-backed `MainRepository` now have no caller at all. That is a real and unusual achievement.

**For writes, the primitive is sound but the surrounding lifecycle is not.** Every user mutation goes through `LocalWriter`; no bloc, cubit or repository calls the network directly outside the accepted exceptions. What fails is everything around it: the operator cannot see the queue, quarantined writes are unrecoverable, and two code paths destroy undrained writes outright.

**Three areas do not meet the requirement.** Followers still talk to the cloud on several paths while their LAN write-relay is orphaned; the change-feed cursor can silently lose committed rows; and the auth layer contains a one-tap action that makes an offline terminal unusable.

---

## How to read this

66 claims were checked. Each was verified twice by independent readers, both instructed to **refute rather than agree** and to default to REFUTED when a claim could not be reproduced from source. The second reader saw the first reader's verdict and evidence and was told to break it.

- **First pass:** 52 confirmed, 13 partial, 1 refuted
- **Disputed** marks a finding where the second reader changed the verdict or severity. Both are shown; neither is averaged away.
- **Severity** in the heading is the *second* reader's, which is the more conservative of the two in every disputed case.
- **In flight** marks a finding resting on another session's uncommitted work — re-check these after that work lands.

Only one claim was refuted outright. That is not a sign the verifiers were lenient — the 13 partials are mostly severity downgrades where the mechanism was real but the blast radius was overstated, which is exactly what the second pass was for.

---

## Summary

| # | Finding | Area | Severity | Verdict | Notes |
|---|---|---|---|---|---|
| `A1` | The PIN-screen Logout button destroys the offline credential store | Auth, session & startup | **HIGH** | PARTIAL | disputed |
| `A3` | A profile-refresh rejection purges the cache and exits to brand login | Auth, session & startup | **HIGH** | PARTIAL | disputed |
| `A5` | Unbounded recursion in the 401 retry | Auth, session & startup | **HIGH** | CONFIRMED | — |
| `LA` | LAN listener leak — duplicated message handling after failover | LAN / leader-follower | **HIGH** | CONFIRMED | — |
| `LB` | Orphaned reconnect loop and racing sockets | LAN / leader-follower | **HIGH** | CONFIRMED | — |
| `S1a` | The change-feed cursor can permanently skip committed rows | Sync & replica integrity | **HIGH** | PARTIAL | disputed |
| `S5a` | The change feed is not branch-scoped, but the client assumes it is | Sync & replica integrity | **HIGH** | CONFIRMED | — |
| `W1` | A new menu item can never be saved, online or offline | Write path & outbox | **HIGH** | CONFIRMED | disputed |
| `W2` | The real outbox is invisible; quarantined writes are unrecoverable | Write path & outbox | **HIGH** | CONFIRMED | — |
| `A10` | No cancel during setup, and a false failure from a concurrent drain | Auth, session & startup | **MEDIUM** | PARTIAL | from this session |
| `A12` | Optimistic isOnline at cold start | Auth, session & startup | **MEDIUM** | CONFIRMED | — |
| `A13` | Brand login performs no verification at all | Auth, session & startup | **MEDIUM** | PARTIAL | — |
| `A14` | No PIN attempt throttling anywhere | Auth, session & startup | **MEDIUM** | PARTIAL | from this session |
| `A16` | Secure-storage failure is indistinguishable from "not provisioned" | Auth, session & startup | **MEDIUM** | CONFIRMED | — |
| `A2` | Over-broad 4xx classification silently purges cached PINs | Auth, session & startup | **MEDIUM** | PARTIAL | disputed, from this session |
| `A4` | Refresh-failure cascade evicts the cashier mid-order | Auth, session & startup | **MEDIUM** | CONFIRMED | — |
| `A6` | A brand switch wipes replica and outbox before checking reachability | Auth, session & startup | **MEDIUM** | CONFIRMED | — |
| `A7` | The LAN hub rejects followers whose access token has expired | Auth, session & startup | **MEDIUM** | CONFIRMED | — |
| `A8` | The connectivity probe raises an error toast every 20 seconds | Auth, session & startup | **MEDIUM** | CONFIRMED | — |
| `A9` | Un-provisioned terminals hit the setup screen on every login | Auth, session & startup | **MEDIUM** | CONFIRMED | from this session |
| `C3` | An uncached manager PIN blocks on the network | Client reachability | **MEDIUM** | CONFIRMED | from this session |
| `C4` | The floor-plan refresh button awaits a full sync pass | Client reachability | **MEDIUM** | CONFIRMED | — |
| `C6` | The api.dart barrel is a hole through both architecture guards | Client reachability | **MEDIUM** | CONFIRMED | guard gap, from this session |
| `C7` | The offline suite is structurally blind to POST traffic | Client reachability | **MEDIUM** | PARTIAL | guard gap |
| `C8` | Rendering an uncached image offline raises a connection-error toast | Client reachability | **MEDIUM** | CONFIRMED | — |
| `L2a` | No LAN backfill — a briefly disconnected follower permanently misses rows | LAN / leader-follower | **MEDIUM** | PARTIAL | disputed |
| `L2b` | First-time provisioning is cloud-only | LAN / leader-follower | **MEDIUM** | CONFIRMED | — |
| `L3` | Followers contact the cloud on several paths, not just the justified one | LAN / leader-follower | **MEDIUM** | CONFIRMED | — |
| `L4` | The LAN op-relay for follower writes is orphaned | LAN / leader-follower | **MEDIUM** | PARTIAL | disputed |
| `L5` | The manual Hub/Client picker can silently isolate a terminal | LAN / leader-follower | **MEDIUM** | PARTIAL | disputed, in flight |
| `L7` | No epoch on the data plane; the split-brain warning is dead by default | LAN / leader-follower | **MEDIUM** | CONFIRMED | — |
| `L8` | Table leasing degrades correctly when the leader is unreachable | LAN / leader-follower | **MEDIUM** | PARTIAL | — |
| `LC` | Followers never re-point on an equal-epoch leader IP change | LAN / leader-follower | **MEDIUM** | CONFIRMED | — |
| `S1c` | Adding an entity to the registry ships an empty table | Sync & replica integrity | **MEDIUM** | PARTIAL | disputed, in flight |
| `S1d/S3a` | Pull rows skipped as pending are never re-delivered | Sync & replica integrity | **MEDIUM** | PARTIAL | disputed, in flight |
| `S3b` | clearPending fires on the first ack, not the last | Sync & replica integrity | **MEDIUM** | CONFIRMED | disputed, in flight |
| `S3c` | synchronous = NORMAL can lose a committed outbox row | Sync & replica integrity | **MEDIUM** | CONFIRMED | in flight |
| `S4b` | snapshot_required and /sync/snapshot are ignored by the client | Sync & replica integrity | **MEDIUM** | CONFIRMED | — |
| `S5b` | Replicated entities with no reader | Sync & replica integrity | **MEDIUM** | PARTIAL | — |
| `S5c` | Migration-71 backfill row cap | Sync & replica integrity | **MEDIUM** | CONFIRMED | — |
| `S6b` | Whole-row replace is the default write mode | Sync & replica integrity | **MEDIUM** | CONFIRMED | in flight |
| `S6c` | A null in a merge patch clears a stored field | Sync & replica integrity | **MEDIUM** | PARTIAL | — |
| `S7` | No pruning of any kind; bootstrap replays all history | Sync & replica integrity | **MEDIUM** | PARTIAL | disputed, in flight |
| `S8a` | lastSyncAt reports success while replication is failing | Sync & replica integrity | **MEDIUM** | CONFIRMED | — |
| `S8b` | The outbox card reads a dead queue and "Sync now" is permanently disabled | Sync & replica integrity | **MEDIUM** | CONFIRMED | — |
| `S8c` | The quarantine card reads the same dead queue | Sync & replica integrity | **MEDIUM** | CONFIRMED | — |
| `W3` | clearAll destroys undrained writes | Write path & outbox | **MEDIUM** | PARTIAL | disputed |
| `W4` | A cancel of an offline-added line is lost within one drain pass | Write path & outbox | **MEDIUM** | PARTIAL | disputed, in flight |
| `W5` | The legacy queue is a live trapdoor | Write path & outbox | **MEDIUM** | CONFIRMED | — |
| `W6` | Shift open/close is not atomic | Write path & outbox | **MEDIUM** | CONFIRMED | — |
| `W7` | Non-order creates can duplicate on a lost response | Write path & outbox | **MEDIUM** | CONFIRMED | — |
| `A11` | An unknown manager PIN cannot authorize anything offline | Auth, session & startup | **LOW** | CONFIRMED | from this session |
| `A15` | The audit trail misreports cache-served approvals | Auth, session & startup | **LOW** | CONFIRMED | from this session |
| `C1` | PIN login fires a background revalidation POST | Client reachability | **LOW** | CONFIRMED | from this session |
| `C2` | The manager prompt fires the same background POST | Client reachability | **LOW** | CONFIRMED | from this session |
| `C5` | The menu editor can render a remote URL directly | Client reachability | **LOW** | CONFIRMED | — |
| `CX` | MinIO images are served by the global backend, not a separate host | Client reachability | **LOW** | CONFIRMED | — |
| `L1` | Leader→Follower change-feed broadcast works, but the seam is untested | LAN / leader-follower | **LOW** | CONFIRMED | guard gap |
| `L2c` | Menu images never cross the LAN | LAN / leader-follower | **LOW** | CONFIRMED | — |
| `L6` | LanSoloBanner exposes cluster state to the cashier | LAN / leader-follower | **LOW** | CONFIRMED | — |
| `LD` | Possible double UDP bind on port 8766 | LAN / leader-follower | **LOW** | PARTIAL | — |
| `S1b` | Row-level apply failures advance the cursor | Sync & replica integrity | **LOW** | PARTIAL | disputed, in flight |
| `S4a` | A delete skipped as pending never returns | Sync & replica integrity | **LOW** | PARTIAL | disputed, in flight |
| `S6a` | validateRegistry does not check numericKeys against promoted columns | Sync & replica integrity | **LOW** | PARTIAL | guard gap |
| `W8` | The write-path census has structural blind spots | Write path & outbox | **LOW** | CONFIRMED | guard gap |
| `S2` | users/create replay duplication | Sync & replica integrity | **NONE** | REFUTED | — |

### Findings that break the offline rule specifically

These are the ones that contradict *"the client never talks to the backend"* or make an offline terminal degrade. The rest are general correctness or operability problems that would matter even with a perfect connection.

- `A1` **HIGH** — The PIN-screen Logout button destroys the offline credential store
- `A3` **HIGH** — A profile-refresh rejection purges the cache and exits to brand login
- `A12` **MEDIUM** — Optimistic isOnline at cold start
- `A2` **MEDIUM** — Over-broad 4xx classification silently purges cached PINs
- `A6` **MEDIUM** — A brand switch wipes replica and outbox before checking reachability
- `A7` **MEDIUM** — The LAN hub rejects followers whose access token has expired
- `A9` **MEDIUM** — Un-provisioned terminals hit the setup screen on every login
- `C3` **MEDIUM** — An uncached manager PIN blocks on the network
- `C8` **MEDIUM** — Rendering an uncached image offline raises a connection-error toast
- `L2a` **MEDIUM** — No LAN backfill — a briefly disconnected follower permanently misses rows
- `L2b` **MEDIUM** — First-time provisioning is cloud-only
- `L3` **MEDIUM** — Followers contact the cloud on several paths, not just the justified one
- `L4` **MEDIUM** — The LAN op-relay for follower writes is orphaned
- `L5` **MEDIUM** — The manual Hub/Client picker can silently isolate a terminal
- `S8b` **MEDIUM** — The outbox card reads a dead queue and "Sync now" is permanently disabled
- `W3` **MEDIUM** — clearAll destroys undrained writes
- `A11` **LOW** — An unknown manager PIN cannot authorize anything offline
- `C1` **LOW** — PIN login fires a background revalidation POST
- `C2` **LOW** — The manager prompt fires the same background POST
- `L2c` **LOW** — Menu images never cross the LAN

---

## Findings in full


# HIGH

## `A1` — The PIN-screen Logout button destroys the offline credential store

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / CRITICAL  
**Second pass:** PARTIAL / HIGH  ← **disputed**  

### Evidence

login_pin_screen.dart:59-70 — `CustomButton(text: S.current.strLogout, onTap: () => cubit.logoutFromApp(() { Navigator.pushNamedAndRemoveUntil(context, AppRoutes.loginScreen, (route) => false); }), ... rightW: SvgPicture.asset(AppIcons.icLogout))` — onTap fires the destructive call directly; no `showDialog`, no confirm state, nothing between tap and wipe.
login_pin_cubit.dart:247-260 `void logoutFromApp(Function() onLogout) async { ... await _logoutUseCase.call(NoParams());` → logout_from_app_usecase.dart:12 `_repository.logoutFromApp();` → login_repository_impl.dart:52-56 `Future<Either<Failure,bool>> logoutFromApp() async { try { await _tokenStorage.deleteAll();`.
token_storage_impl.dart:245-248 `Future<void> deleteAll() async { await _prefs.clear(); await _secure.deleteAll(); }`.
di.dart:179-193 — `final SharedPreferences prefs = ...; const secureStorage = FlutterSecureStorage(); ... final AppTokenStorage tokenStorage = AppTokenStorage(prefs, secureStorage); ... inject.registerSingleton<OfflineAuthCache>(const OfflineAuthCache(secureStorage));` — one instance handed to both.
offline_auth_cache.dart:47-51 `static const _key = 'offline_users_v1';` / `static const _pinKey = 'offline_pin_users_v1';` read/written via `_secure` — both erased by `_secure.deleteAll()`.
prefs-backed keys erased by `_prefs.clear()`: printer_config_storage.dart:22 `'printer_settings_entries_v2_json'` and its `_usbNamesKey` (line 80), lan_hub_service.dart:32-33 `'lan_mode'`/`'lan_server_ip'`, leader_election_service.dart:45 `'lan_election_epoch'`, print_queue_service.dart:41 `'print_terminal_id'`, token_storage_impl.dart:22 `posIsInitialized('pos_is_initialized')` (written via `_prefs.setBool`, line 175), shift_bloc.dart `prefs.setString(localShiftPrefsKey, jsonEncode(shift.toJson()))` (open-shift record).
In-app logout is genuinely different: logout_dialog.dart:73-82 `context.read<AuthCubit>().logout(onSuccess: ...)` → auth_cubit.dart:52-54 `_logoutUsecase.call(NoParams())` → logout_usecase.dart:11 `_repository.logout()` → login_repository_impl.dart:64-68 `await _tokenStorage.deleteUserSession();` which (token_storage_impl.dart:168-171) deletes only authToken + posUser.
Offline recovery is impossible after the wipe: auth_cubit.loginWithBrandId's cached branch (auth_cubit.dart:88-104) needs `_offlineAuthCache.validateAndGetUser` — now empty — and login_pin_cubit.dart:72-97 returns `const ConnectionFailure()` when `getForPin` misses and `!_connectivity.isOnline`.

### Correction to the original claim

Two precisions, neither weakening the finding. (1) The "ONE shared FlutterSecureStorage instance" framing is incidental, not causal: `flutter_secure_storage`'s `deleteAll()` clears the app's whole secure-storage namespace, so even two separate instances would lose `offline_users_v1`/`offline_pin_users_v1`. (2) This PIN-screen path does NOT clear the replica DB — `AuthCubit.logoutFromApp` (auth_cubit.dart:115-140) is the variant that calls `inject<replica.LocalDatabase>().clearAll()`, and grepping the tree its only UI caller is login_pin_screen.dart:61 going through LoginPinCubit, so the AuthCubit variant is dead code and the terminal is left with a full tenant replica it can no longer log into. `lan_hub_service.dart`/`leader_election_service.dart` are being edited by the other session, but the key names and their SharedPreferences backing are pre-existing, so the conclusion does not rest on in-flight work.

### User impact

One mis-tap on a red button on the idle PIN screen (no confirm) wipes every cashier's offline PIN, the brand credential, the open-shift record, all printer/USB mappings, the LAN mode + server IP, the terminal id and the election epoch. Offline, that terminal is dead: the brand login screen needs a provisioning credential the cashier does not have, and even with it the PIN cache is gone, so nobody can log in until the uplink returns — and the printers and LAN role must be re-provisioned by hand afterwards.

### Second reader

MECHANISM — reproduced exactly as claimed, at HEAD (not in-flight).

lib/features/view/auth/presentation/pages/login_pin/login_pin_screen.dart:59-72 — unconditional child of `build()`, no role/state gate:
  `CustomButton(text: S.current.strLogout, onTap: () => cubit.logoutFromApp(() { Navigator.pushNamedAndRemoveUntil(context, AppRoutes.loginScreen, (route) => false); }), ... rightW: SvgPicture.asset(AppIcons.icLogout), textColor: context.colors.systemError)`.
I checked for a guard inside the button: lib/core/common/custom_button.dart:27 `this.isActive = true,` and :57/:65 `onTap: isActive ? onTap : null` — the call site passes no `isActive`, so the tap fires the first time and every time. No `showDialog`, no long-press, no `isLoading` disable (the screen's `isLoading` at login_pin_screen.dart:41 only swaps a Text for a spinner, it never touches this button).

login_pin_cubit.dart:247-260 `void logoutFromApp(Function() onLogout) async { emit(...LOADING); var result = await _logoutUseCase.call(NoParams());` — identical at HEAD (`git show HEAD:...login_pin_cubit.dart` lines 170-183), so this does NOT rest on the concurrent session's rewrite of that file.
→ domain/usecases/logout/logout_from_app_usecase.dart:12 `_repository.logoutFromApp();`
→ data/repositories/login_repository_impl.dart:52-56 `await _tokenStorage.deleteAll();`
→ lib/core/auth/storage/token_storage_impl.dart:246-250 `Future<void> deleteAll() async { await _prefs.clear(); await _secure.deleteAll(); }` — purely local, no network call, so it succeeds offline. `_prefs.clear()` runs first and unconditionally.

One store each, shared by everything: lib/di.dart:179-193 `final SharedPreferences prefs = await SharedPreferences.getInstance(); const secureStorage = FlutterSecureStorage(); ... inject.registerSingleton<OfflineAuthCache>(const OfflineAuthCache(secureStorage));`. `git diff lib/di.dart` shows ZERO changes on any SharedPreferences/FlutterSecureStorage/OfflineAuthCache/AppTokenStorage line, so the in-flight di.dart edits are irrelevant here. `grep -rn 'SharedPreferences.getInstance\|FlutterSecureStorage(' lib` returns only di.dart:179-180 — one instance of each in the whole app; di.dart:288, :308, :376 hand that same `prefs` to LanHubService, LeaderElectionService and PrinterConfigStorage.

OFFLINE LOCKOUT — confirmed. token_storage_impl.dart:56-61 `_secureKeys = { authToken, brandId, posUser, lastPincode }` are all in secure storage, and offline_auth_cache.dart:47-51 `_key = 'offline_users_v1'` / `_pinKey = 'offline_pin_users_v1'` are too — all erased by `_secure.deleteAll()`. login_pin_cubit.dart:63-67 `final BrandIdTokenPair? brandIdTokenPair = await _secureStorage.readBrandIdToken(); if (brandIdTokenPair == null) { emit(state.copyWith(status: Status.UNKNOWN)); return; }` — the PIN pad is inert with no brand token, before the PIN cache even matters. auth_cubit.dart:88-104's offline branch needs `_offlineAuthCache.validateAndGetUser(req.brandId, req.password)`, now empty. So offline the terminal cannot be logged into by any means.

IN-APP LOGOUT CONTRAST — confirmed. app_sidebar.dart:133-141 `showDialog(... builder: (_) => const LogoutDialog(...))` → logout_dialog.dart:76-83 `context.read<AuthCubit>().logout(...)` → login_repository_impl.dart:64-68 `_tokenStorage.deleteUserSession()` → token_storage_impl.dart:178-181 deletes only authToken + posUser. Same word "Logout", two very different actions.

WHERE THE CLAIM IS WRONG — the final impact sentence, "the printers and LAN role must be re-provisioned by hand afterwards":
1. Printer routing entries come back automatically. user_bloc.dart:84-85 `unawaited(_syncPrinterSettingsUsecase.call(NoParams()).then(...))` on every successful `getUser` → sync_printer_settings_usecase.dart:15-20 `_repository.getPrinterSettings()` then `_storage.applyPrinterSettingsList(list)` → printer_config_storage.dart:27-29 rewrites `printer_settings_entries_v2_json`. Only entries never pushed to the backend, plus the device-local USB map (`_usbNamesKey = 'printer_usb_names_json'`, printer_config_storage.dart:77, explicitly "never synced to the backend"), are lost for good.
2. LAN mode and server IP are re-derived, not hand-set. leader_election_service.dart:85 `static const enabledByDefault = true;` and :95-96 `static bool isEnabledIn(SharedPreferences prefs) => prefs.getBool(electionEnabledKey) ?? enabledByDefault;` — wiping prefs restores the default ON. The election then writes both keys itself: :305-306 `await _lanHub.setServerIp(leaderIp); await _lanHub.setMode(LanMode.client);` and :342 `await _lanHub.setMode(LanMode.server);`. The lost epoch (`lan_election_epoch`) just restarts the protocol at 0.

Also worth recording, since it bounds the blast radius: the replica database is NOT wiped on this path. The only code that calls `inject<replica.LocalDatabase>().clearAll()` is auth_cubit.dart:114-137 `AuthCubit.logoutFromApp`, and `grep -rn 'logoutFromApp' lib` finds exactly one UI call site — login_pin_screen.dart:61, which resolves to `LoginPinCubit`, not `AuthCubit`. AuthCubit.logoutFromApp has zero callers. Orders, outbox and catalog survive the tap.

Genuinely lost with no automatic recovery: the offline PIN cache, the brand credential, the USB printer-name map, the terminal id (`print_terminal_id`, print_queue_service.dart:41), and the open-shift record (shift_bloc.dart:69 `localShiftPrefsKey = 'pos_local_active_shift'`, and shift_bloc.dart:37-42 documents `_checkShift` as local-only with no server reconciliation — so a shift open at the moment of the tap is forgotten by the terminal).

**Second reader's correction:** The mechanism, the reachability, the absence of any confirm, and the offline lockout are all reproduced exactly — the code citations in the original are accurate. Two items in the claimed impact are wrong: (1) printer routing entries are NOT lost — user_bloc.dart:85 re-syncs them from the backend into printer_config_storage on the next successful online getUser; only backend-unknown entries and the device-local USB name map (printer_usb_names_json) are permanently gone; (2) the LAN role is NOT re-provisioned by hand — LeaderElectionService is on by default (leader_election_service.dart:85, and wiping the flag restores that default) and rewrites lan_mode/lan_server_ip itself at :305-306 and :342, so the venue re-elects and reconfigures without an operator. Severity downgraded CRITICAL→HIGH: recovery does not need a rebuild or a support visit, it needs the manager's brand-id/pos-password and an uplink; no order, outbox or catalog data is destroyed (the replica clearAll lives only in AuthCubit.logoutFromApp, which has zero callers). It would be CRITICAL at a venue currently offline, where there is no recovery at all until the uplink returns. NOT in-flight: login_pin_screen.dart, login_pin_cubit.dart's logoutFromApp (identical at HEAD), token_storage_impl.dart, login_repository_impl.dart and offline_auth_cache.dart are all clean, and di.dart's storage wiring is unchanged in the concurrent session's diff.

**Second reader's impact assessment:** A cashier standing at the locked PIN screen at end of shift taps the red "Logout" button top-right — the same word the sidebar uses for an ordinary session logout — and with no confirmation the terminal is de-provisioned: every cashier's cached PIN and the brand credential are erased, so the PIN pad is dead (it returns Status.UNKNOWN with no brand token) and the app drops to the brand-login screen asking for a brand id and POS password no cashier carries. Offline, nobody can log in at all until the uplink returns. Online, service stops until a manager arrives with the provisioning credentials. Any shift open at that moment is forgotten locally with no server-side reconciliation, and the terminal's USB printer-name mapping and terminal id must be set up again by hand; orders and queued writes survive, and the printer routing table and LAN role restore themselves.

---

## `A3` — A profile-refresh rejection purges the cache and exits to brand login

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / HIGH  ← **disputed**  

### Evidence

sync_engine.dart:294-315 `DateTime? _lastProfileRefreshAt; static const _profileRefreshInterval = Duration(minutes: 5); void _refreshUserProfile() { ... if (now.difference(_lastProfileRefreshAt!) < _profileRefreshInterval) return; _lastProfileRefreshAt = now; ... inject<UserBloc>().add(const UserEvent.getUser());` — dispatched from both tick branches (:251 and :265), tick itself running on `static const tickInterval = Duration(seconds: 60)` (:73), so the 60s tick is throttled to one profile refresh every 5 minutes exactly as claimed.
user_bloc.dart:49-52 `if (!inject<ConnectivityCubit>().isOnline) { await _tryOfflineUser(emit); return; }` — the branch below is online-only.
user_bloc.dart:55-77 `response.fold((l) async { if (!l.isDefiniteAuthRejection) { await _tryOfflineUser(emit); return; } ... await _purgeOfflineCacheForCurrentUser(); Navigator.pushNamedAndRemoveUntil(navigatorKey.currentContext!, AppRoutes.loginScreen, (route) => false); ...`.
user_bloc.dart:136-148 `_purgeOfflineCacheForCurrentUser` — `await cache.removeUser(brandPair.brandId);` (brand-level) and `final pincode = await storage.readLastPincode(); if (pincode != null && pincode.isNotEmpty) { await cache.removeForPin(brandPair.brandId, pincode); }` (per-pin). Both, as claimed.
Destination is the brand/provisioning screen: app_pages.dart:27-28 `case AppRoutes.loginScreen: return simpleRoute(const LoginScreen(), ...)`, and login_screen.dart:257-268 submits `cubit.loginWithBrandId(req: BrandIdTokenPair(brandId: _brandIdController.text, password: _passwordController.text), ...)`.
Same over-broad classifier: the request is main_datasources.dart:465-470 `final response = await _client.get(ListAPI.user); ... on DioException catch (exception) { return Left(handleDioException(exception)); }` → failure.dart:166-170.

### Correction to the original claim

None material. One addition the claim does not mention: because `/user` carries an Authorization header, a plain 401 first goes through dio_interceptor.dart:51-89 (refresh + retry); the purge-and-kick therefore fires when the REFRESH also fails (expired/rotated refresh token) or on a non-401 definite code (404 from a wrong BASE_URL, 400/422 or any 4xx `error` body). That makes it a superset of, not a duplicate of, A2's trigger set. Also note the interceptor has already run `deleteUserSession()` and pushed to the PIN screen in the refresh-failure case, so the user sees a PIN screen replaced a moment later by the brand screen.

### User impact

A backend-side rejection while the terminal is merely idle and online — no user action at all — destroys both the brand-level and the current cashier's per-PIN offline credentials and throws the terminal onto the brand provisioning screen, which asks for a brand id and POS password no cashier carries. Service stops at that terminal until a manager with the provisioning credential arrives, and the terminal is now also unable to fall back offline.

### Second reader

MECHANISM — every cited line reproduces exactly.

lib/core/sync/sync_engine.dart:73 `static const tickInterval = Duration(seconds: 60);`; :135 `_ticker ??= Timer.periodic(tickInterval, (_) => tick());`; :251 and :265 both call `_refreshUserProfile();` (LAN-client branch and direct-cloud branch); :294-311 `DateTime? _lastProfileRefreshAt; static const _profileRefreshInterval = Duration(minutes: 5); ... if (now.difference(_lastProfileRefreshAt!) < _profileRefreshInterval) return; _lastProfileRefreshAt = now; ... inject<UserBloc>().add(const UserEvent.getUser());`.

REACHABILITY (a) — lib/di.dart:441 `syncEngine.start();` is unconditional inside initDi, and lib/di.dart:650 registers `UserBloc` as a lazySingleton, so `inject<UserBloc>()` resolves. `SyncEngine.stop()` has ZERO callers (grep for `.stop()` across lib/ returns only LanHub/AnimationController hits), so the ticker never stops for the app's lifetime, logged in or not. No user action required — confirmed.

NO GUARD (b) — usecase→repo→datasource is pass-through with no cache interception: get_user_usecase.dart:13 `await repository.getUser();` → main_repository_impl.dart:44-45 `getUser() async => await _dataSources.getUser();` → main_datasources.dart:465-470 `final response = await _client.get(ListAPI.user); ... on DioException catch (exception) { return Left(handleDioException(exception)); }`. dio_client.dart:216-217 only blocks WRITES when offline, so reads pass. The one real gate found is upstream: dio_interceptor.dart:51-82 — a 401 with an auth header first attempts a token refresh and `handler.resolve(response)` on success, so a merely expired access token never reaches UserBloc. The failure only surfaces when refresh itself fails (:83-86 `_logoutAndRedirectToLogin(); return handler.next(err);`) or when the status is a non-401 4xx.

PURGE + DESTINATION — user_bloc.dart:49-52 online-only branch, :57-62 non-definite → `_tryOfflineUser`, :71-76 `await _purgeOfflineCacheForCurrentUser(); Navigator.pushNamedAndRemoveUntil(navigatorKey.currentContext!, AppRoutes.loginScreen, (route) => false);`. :136-148 removes BOTH `cache.removeUser(brandPair.brandId)` and `cache.removeForPin(brandPair.brandId, pincode)`. app_pages.dart:27-28 maps loginScreen→LoginScreen; login_screen.dart:35-36 declares `_brandIdController`/`_passwordController` with no prefill from storage, and its only outbound nav is login_screen.dart:257-268 (submit brandId+password). Note the interceptor's own redirect goes to `loginPinScreen` (dio_interceptor.dart:160) but UserBloc's pushNamedAndRemoveUntil runs after it and wins.

CLASSIFIER IS WORSE THAN CLAIMED — failure.dart:166-170 `isDefiniteAuthRejection => this is ValidationFailure || this is UnauthorizedFailure || this is NotFoundFailure || this is MessageFailure;` and dio_exception_handler.dart:39-42 maps ANY 4xx carrying an `error` body to `MessageFailure`. Backend side: app/internal/handler/user.go:33-37 `user, err := h.service.Auth().GetUserByID(...); if err != nil { return c.JSON(http.StatusNotFound, model.NewErrorResponse(message, err.Error(), 404)) }` and service/auth.go:985-989 returns `fmt.Errorf("failed to fetch user: %w", err)` for ANY db/tenant error, not just pgx.ErrNoRows. So a transient Postgres blip on /api/v1/user/me is served as 404 + `error` field → MessageFailure → definite rejection → purge + eviction.

**Second reader's correction:** Two impact details in the original are wrong, one in each direction.

OVERSTATED: "Service stops at that terminal until a manager with the provisioning credential arrives." An app restart recovers without the provisioning credential. The purge touches only OfflineAuthCache rows; login_repository_impl.dart:17-23 `haveUserData()` returns `readBrandIdToken() != null`, and neither the purge nor `deleteUserSession()` (token_storage_impl.dart:178-181, which deletes only authToken and posUser) removes the brand token. So splash_screen.dart:45-56 routes a restart to `loginPinScreen` when the access token was cleared, or straight to `mainScreen` when it survived. Also, in the non-401 case (404/400 with an error body) the session tokens are untouched, so the very next successful profile refresh — at most 5 minutes later — re-saves both cache entries via user_bloc.dart:100-129 `_updateOfflineCache`. The purge self-heals in exactly the transient case; it is permanent only for a genuine 401-with-failed-refresh, which is the intended revocation.

UNDERSTATED (and why severity stays HIGH): the original frames this as hitting a logged-in idle terminal. It also fires when the terminal is LOGGED OUT. The ticker never stops, `_getUser` has no logged-in guard, and with no token dio_interceptor.dart:64-66 `if (!hasAuthHeader && !isRefreshCall) return handler.next(err);` passes the backend's 401 (middleware.go:92-95 `"You are not logged in"`) straight through as UnauthorizedFailure → definite. So a provisioned terminal sitting on the PIN screen, online, wipes its brand-level and last-PIN offline credentials and is bounced from loginPinScreen to the brand-provisioning LoginScreen within 5 minutes of app start, with nobody touching it. That is the path that genuinely strands a venue: if the link then drops, offline PIN login is gone.

**Second reader's impact assessment:** Two distinct hits. (1) A transient backend/DB error on /user/me — served as 404 with an error body — evicts an idle, logged-in terminal from the order screen to the brand-provisioning screen mid-service; the cashier has no in-app path forward (that screen only accepts brand id + POS password) and must restart the app to get back, though the wiped offline credentials do restore themselves on the next successful refresh. (2) Worse and not in the original claim: a provisioned terminal parked on the PIN screen while online destroys its brand and last-PIN offline auth cache within 5 minutes unattended, so a later network outage leaves nobody able to log in at that terminal at all — the exact failure the offline cache exists to prevent.

---

## `A5` — Unbounded recursion in the 401 retry

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / HIGH  
**Second pass:** CONFIRMED / HIGH  

### Evidence

dio_interceptor.dart:73-89 — `try { await (_refreshFuture ??= _refreshAccessToken()); final newTokenPair = await _tokenStorage.readAuthToken(); if (newTokenPair != null && newTokenPair.accessToken.isNotEmpty) { err.requestOptions.headers['Authorization'] = 'Bearer ${newTokenPair.accessToken}'; final response = await _dio.fetch(err.requestOptions); return handler.resolve(response); } } catch (e) { ... } finally { _refreshFuture = null; }` — no retry counter, no marker on `requestOptions.extra`, and the `finally` cannot run while `await _dio.fetch` is pending, so a nested 401 sees `_refreshFuture` still non-null and already completed and immediately retries again.
`fetch` really does re-enter the full chain, in the resolved version (pubspec.lock:379 `version: "5.9.2"`): ~/.pub-cache/hosted/pub.dev/dio-5.9.2/lib/src/dio_mixin.dart:378 `Future<Response<T>> fetch<T>(RequestOptions requestOptions) async {`, :471-475 `for (final interceptor in interceptors) { ... future = future.then(requestInterceptorWrapper(fun)); }`, :502-506 `for (final interceptor in interceptors) { final fun = ... interceptor.onError; future = future.catchError(errorInterceptorWrapper(fun)); }` — and the interceptor is registered on the very Dio it holds: dio_client.dart:52 `_dio.interceptors.add(MySmartDioInterceptor(_dio, _tokenStorage));`.
The `!hasAuthHeader` escape does not apply to the manager prompt, exactly as claimed: dio_interceptor.dart:29-31 attaches `Authorization` to every request while a session exists, and line 78 re-attaches it explicitly before the retry. The request in question is auth_datasource.dart:116-124 `final Response response = await _client.post(ListAPI.loginPinCode, data: LoginRequestModel(brandId:..., password:..., pincode: pincode).toJson())` — reached only after `getForPin` misses (:102-113), i.e. an uncached (wrong) PIN, and `_client.post` is a plain `_dio.post` (dio_client.dart:118-123).
The server answers 401 for a wrong pincode: back/app/internal/handler/auth.go:95-102 `resp, err := h.service.Auth().LoginWithPincode(...); if err != nil { ... return c.JSON(http.StatusUnauthorized, model.NewErrorResponse("Pincode login failed", err.Error(), http.StatusUnauthorized)) }`.
The trigger has live call sites: manager_pincode_dialog.dart:33-46 `requireManagerPincode` → order_side_bar_widget.dart:770, bill_detail_panel.dart:32, close_shift_screen.dart:1901, w_shift_bottom.dart:63.

### Correction to the original claim

One refinement to the predicted symptom. The loop is unbounded in the code, but in practice it usually terminates: the retried POST hits back/app/internal/middleware/middleware.go:59-76 `LoginRateLimiter` (`Rate: 5, Burst: 5` per `c.RealIP()`), whose 429 is not a 401, so the innermost `_dio.fetch` throws, that exception unwinds into every enclosing `catch (e)` at dio_interceptor.dart:83-86, and each level calls `_logoutAndRedirectToLogin()`. So the observed behaviour is a burst of duplicate login-pincode requests followed by a forced session logout and navigation to the PIN screen mid-order (repeated N times), rather than a permanent hang — and if round-trips are slower than 5/s the limiter never trips and the loop does run indefinitely. Note also the same loop is reachable silently from the background revalidation paths of A2 whenever the server answers 401, which is why those 401s never reach A2's purge.

### User impact

A manager mistyping their PIN on a void/discount prompt mid-order, while the terminal is online, sends the terminal into a self-retrying request storm against the login endpoint and then — via the rate-limiter's 429 unwinding into the refresh catch — clears the cashier's session and replaces the whole navigation stack with the PIN screen, in the middle of an open order. From the floor it looks like the terminal froze during a manager approval and then logged itself out.

### Second reader

MECHANISM — /home/spike/Documents/work/MARY_AI/Mary-Ai-POS/lib/core/api/dio_interceptor.dart:73-89 is quoted accurately:
```
      try {
        await (_refreshFuture ??= _refreshAccessToken());
        final newTokenPair = await _tokenStorage.readAuthToken();
        if (newTokenPair != null && newTokenPair.accessToken.isNotEmpty) {
          err.requestOptions.headers['Authorization'] = 'Bearer ${newTokenPair.accessToken}';
          final response = await _dio.fetch(err.requestOptions);
          return handler.resolve(response);
        }
      } catch (e) { ... await _logoutAndRedirectToLogin(); return handler.next(err); }
      finally { _refreshFuture = null; }
```
No retry counter, no `requestOptions.extra` marker, and `finally` is unreachable while `await _dio.fetch` is pending.

RE-ENTRY IS REAL — resolved dio is 5.9.2 (pubspec.lock:369 `version: "5.9.2"`). ~/.pub-cache/hosted/pub.dev/dio-5.9.2/lib/src/dio_mixin.dart:378 `Future<Response<T>> fetch<T>(RequestOptions requestOptions) async {`, :503-506 `for (final interceptor in interceptors) { final fun = ... interceptor.onError; future = future.catchError(errorInterceptorWrapper(fun)); }` — `fetch` rebuilds the whole chain, error interceptors included. The interceptor holds that same Dio: dio_client.dart:53 `_dio.interceptors.add(MySmartDioInterceptor(_dio, _tokenStorage));`.

EMPIRICAL REPRODUCTION — I built a standalone dio-5.9.2 harness (/tmp/claude-1000/-home-spike-Documents-work-MARY-AI/6a378252-2d95-40a7-b2d1-5cafc5228262/scratchpad/a5/bin/main.dart) replicating dio_interceptor.dart:44-89 verbatim against a fake adapter that 401s login-pincode and 200s refresh. With the server 401ing indefinitely: `loginHits=301 refreshHits=1 logoutCalls=300`. With the real limiter modelled (429 after 5): `loginHits=6 refreshHits=1 logoutCalls=5`. The loop and the multi-level logout-on-unwind are both real, not theoretical.

ESCAPE HATCH DOES NOT APPLY — dio_interceptor.dart:29-31 `if (tokenPair != null && tokenPair.accessToken.isNotEmpty) { options.headers['Authorization'] = 'Bearer ${tokenPair.accessToken}'; }` runs on every request while a session exists, so dio_interceptor.dart:64 `if (!hasAuthHeader && !isRefreshCall) return handler.next(err);` (the guard whose comment names "wrong pin on login-pincode") is bypassed for a manager prompt taken mid-shift. auth_datasource.dart:117-124 posts with no `Options`, and dio_client.dart:118-123 is a plain `_dio.post`.

SERVER 401s A WRONG PIN — back/app/internal/handler/auth.go:96-102 `resp, err := h.service.Auth().LoginWithPincode(...); if err != nil { ... return c.JSON(http.StatusUnauthorized, ...) }`.

REACHABILITY — grepped the whole tree for `requireManagerPincode`: 4 live call sites (order_side_bar_widget.dart:770, bill_detail_panel.dart:32, close_shift_screen.dart:1901, w_shift_bottom.dart:63), all post-login screens. auth_datasource.dart:101-108 serves cached PINs locally, so a typo (never cached) always reaches the network at :117; auth_datasource.dart:112-114 `if (!_client.isOnline) return const Left(ConnectionFailure());` limits it to online terminals, as claimed.

DAMAGE IS REAL — token_storage_impl.dart:178-181 `deleteUserSession()` deletes `authToken` and `posUser`; dio_interceptor.dart:157-162 `Navigator.pushNamedAndRemoveUntil(navigatorKey.currentState!.context, AppRoutes.loginPinScreen, (route) => false)`, with navigatorKey wired at main.dart:144.

**Second reader's correction:** Four corrections, none of which break the finding. (1) "Request storm" is overstated: back/app/internal/middleware/middleware.go:59-64 `Rate: 5, Burst: 5, ExpiresIn: time.Minute` on the route at handler.go:39 caps it at ~6 requests, sub-second — my harness measured exactly 6. Nothing on the floor "freezes"; the visible event is a 'too many attempts' toast followed instantly by the login screen. (2) The claim implies one logout; `_logoutAndRedirectToLogin()` fires once per nesting level as the 429 unwinds — 5 stacked `pushNamedAndRemoveUntil` calls in the modelled run, 300 in the uncapped run. (3) The `_refreshFuture`-still-non-null detail is accurate but not load-bearing: I re-ran with `_refreshFuture` cleared before each retry and the loop persists (one extra /refresh per iteration). The actual defect is the total absence of a retry marker on `requestOptions`, not the future's lifetime. (4) The claim misses a second, worse trigger that needs no user error at all: auth_datasource.dart:174-186 `_revalidateInBackground` fires `unawaited` on every cache-HIT manager PIN (called at :106), posting the same login-pincode with the session's Authorization header; if the server has since revoked that PIN it returns 401 and enters the identical loop — so a manager whose PIN the dialog just ACCEPTED can still log the cashier out, silently, from a background call.

**Second reader's impact assessment:** A manager mistyping the approval PIN on a void/discount/shift action, on an online terminal, does not just get 'wrong PIN': the interceptor silently re-fires the login-pincode request until the server rate-limits it, then unwinds by clearing the cashier's session (`authToken` + `posUser`) and replacing the entire navigation stack with the PIN screen — mid-open-order. The cashier must log back in and re-find the order. Same outcome, with no typo at all, whenever a cached manager PIN has been revoked server-side, via the unawaited background revalidation.

---

## `LA` — LAN listener leak — duplicated message handling after failover

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / HIGH  
**Second pass:** CONFIRMED / HIGH  

### Evidence

lan_hub_service.dart:128-129 `await _client.connect(ip, getCredentials: _readOwnCredentials); _client.onMessage.listen(_handleRemoteMessage);` — return value discarded, no field, no cancel anywhere in the file. `restart()` :456-464 ends with `await init();`, re-entering that same branch. `onMessage` is a broadcast stream (lan_hub_client.dart:33-34 `StreamController<LanHubMessage>.broadcast()`), and the controller is closed only in `dispose()` (:270), which has no production caller (grep for `.dispose()` on LanHubService/LanHubClient in lib: none). Every follower adoption runs it: leader_election_service.dart:299-308 `_becomeFollower` -> `setMode(LanMode.client); await _lanHub.restart();`. The manual settings path adds more: lan_network_section.dart:48 and :60 both call `lanHub.restart()`. No dedup on the print path — print_queue_service.dart:366-389 `onRemoteAnnounce` goes straight from the printer-ownership check at :372-373 to `_broadcastClaim(jobId)` and `_printerService.printRenderedBytes(config, bytes)` with no seen-job set and no jobId bookkeeping.

### Correction to the original claim

The leak is pre-existing at HEAD, not the other session's doing (`git show HEAD:lib/core/services/lan_hub/lan_hub_service.dart` contains the identical un-stored `listen` line). What IS in-flight is the blast radius: the concurrent session added `case LanHubMessageType.localChange: inject<LocalChangeRelay>().apply(msg)` and `timerAction -> applyTimer(msg)` at lan_hub_service.dart:313-325, so every duplicated dispatch now also re-applies peer rows and double-counts the LocalChangeRelay sent/received counters that sync_status_section.dart:381 renders. Note also that `relayOp` and `requestLease` (lan_hub_client.dart:198, :236) DO cancel their own onMessage subscriptions in a finally — line 129 is the only leaking one.

### User impact

After two leader failovers (or two visits to Settings > Network that press Save), a follower that owns a USB printer prints every relayed kitchen ticket/receipt three times — one physical duplicate per past adoption — and fires a claim/result broadcast for each, which the originating terminal also processes repeatedly.

### Second reader

MECHANISM (verified in working tree AND at HEAD, so not an artifact of the other session):

lib/core/services/lan_hub/lan_hub_service.dart:125-131 (HEAD: :126-128, identical)
```
case LanMode.client:
  final ip = serverIp;
  if (ip.isNotEmpty) {
    await _client.connect(ip, getCredentials: _readOwnCredentials);
    _client.onMessage.listen(_handleRemoteMessage);   // return value discarded
  }
```
No StreamSubscription field, no cancel: `grep -n 'StreamSubscription' lan_hub_service.dart` yields only `_discoverySub` (:41), cancelled at :153/:459/:469.

lan_hub_service.dart:456-464 `restart()` -> `_server.stop(); _client.disconnect(); ... await init();` — re-enters that same branch. `_client` is a `final` field (:39) constructed once, and its `_controller` (lan_hub_client.dart:33 `StreamController<LanHubMessage>.broadcast()`) is closed only in `LanHubClient.dispose()` (:270). `disconnect()` (:258-263) closes only the socket, never the controller. Grep across lib+test for a production disposer of LanHubService/LanHubClient: none.

REACHABILITY (a):
- di.dart:293 `inject.registerSingleton<LanHubService>(lanHubService)` — one instance for app lifetime; di.dart:446 `await lanHubService.init()`; di.dart:456 `await leaderElection.start()`.
- Election is ON by default: leader_election_service.dart:87 `static const enabledByDefault = true;` :97 `isEnabledIn(prefs) => prefs.getBool(...) ?? enabledByDefault`.
- leader_election_service.dart:299-308 `_becomeFollower` -> `await _lanHub.setMode(LanMode.client); await _lanHub.restart();` (HEAD :255-263, same).
- Manual path is real UI: settings_screen.dart:167 renders `LanNetworkSection`; lan_network_section.dart:48 (`_onModeChanged`) and :60 (`_onIpSaved`) each `await lanHub.restart()`.
- Mode persists (`_prefs.setString(_keyMode, ...)` :82), so a terminal that was a follower yesterday starts with listener #1 already attached at boot — the claim's "two failovers -> three copies" arithmetic is correct for that (normal) case.

EMPIRICAL PROOF (ran the real LanHubServer/LanHubClient over loopback, replicating init/restart exactly): after 2 restarts, one `server.broadcast(printJobAnnounce)` produced `HANDLER INVOCATIONS FOR ONE BROADCAST: 3`.

NO GUARD ON THE PRINT PATH (b): print_queue_service.dart:366-389 (file is git-clean) goes straight from the ownership check `final windowsName = _printerConfigStorage.getUsbPrinterName(entryId); if (windowsName == null || windowsName.isEmpty) return;` (:372-373) to `_broadcastClaim(jobId)` (:374) and `await _printerService.printRenderedBytes(config, bytes)` (:383). No seen-jobId set, no `_box.get(jobId)` check, no state machine on the receiving side.

**Second reader's correction:** Two corrections, neither of which rescues the finding.

1) The trailing clause "which the originating terminal also processes repeatedly" is literally true but implies harm that does not exist: the originator IS idempotent. print_queue_service.dart:302-306 `onRemoteClaim` returns early unless `job.stateEnum == PrintJobState.queued`, and :336-338 `onRemoteResult` returns unless state is `claimed`. So duplicate claims/results are no-ops; the job row and the completer stay correct. The damage is purely the duplicated physical print (and duplicated `_printerService` calls), not corrupted job bookkeeping.

2) Accumulation is bounded more tightly than "any adoption": leader_election_service.dart:293-295 `_adopt` returns early when `_lanHub.mode == LanMode.client && _lanHub.serverIp == a.ip && _role == follower`, so re-hearing the SAME leader does not restart. A restart requires a genuine epoch bump (real failover), a leader-IP change, a stand-down from candidate/leader, or a Settings > Network save. That still leaves every real failover adding one listener — it just means flaky UDP alone does not inflate the count.

NOT flagged by the original but found while verifying, and it makes this worse not better: `disconnect()` triggers `_onDisconnected` -> `_scheduleReconnect()` (lan_hub_client.dart:133-139, 152-162) with no cancellation, so ~2-30s after each restart a stale `Future.delayed(delay, _doConnect)` opens an ADDITIONAL live WebSocket and overwrites `_ws` while the old socket keeps feeding `_controller`. My second run showed the server log `Client authorized (total: 2)` for a single logical LanHubClient after one restart — a second delivery multiplier stacked on top of the listener leak.

Line numbers cited by the first verifier match the working tree; the identical code is at HEAD lan_hub_service.dart:127-128 and leader_election_service.dart:255-263.

**Second reader's impact assessment:** On a follower terminal that owns a USB printer (the exact topology Phase 5's relay exists for), every relayed kitchen ticket or receipt prints once per past LAN restart: 2 physical copies after one leader failover, 3 after two, and the same again after a manager visits Settings > Network and presses Save. The kitchen gets duplicate tickets for one order and cooks the food twice; a customer receipt prints in multiples. Nothing in the UI signals it — the originating till sees exactly one successful job (its state guards swallow the duplicate claim/result), so the cashier has no way to tell the relay fired N times. The same stacking also re-applies each `localChange`/`timerAction` N times through LocalChangeRelay and re-emits each `tableStatus` N times.

---

## `LB` — Orphaned reconnect loop and racing sockets

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / HIGH  
**Second pass:** CONFIRMED / HIGH  

### Evidence

lan_hub_client.dart:258-263 `Future<void> disconnect() async { await _ws?.close(); _ws = null; ... }` — closing the socket completes the stream registered at :88-115 whose `onDone: _onDisconnected`. :133-139 `_onDisconnected()` ends in `_scheduleReconnect();`, and :152-153 `void _scheduleReconnect() { if (_disposed) return; ... }` then :161 `Future.delayed(delay, _doConnect);`. `_disposed` is written only at :267 inside `dispose()`, and grep finds no production caller of `LanHubService.dispose()`/`LanHubClient.dispose()` in lib. `_serverIp` is never cleared by `disconnect()`, so `_doConnect`'s guard at :79 `if (_disposed || _serverIp == null) return;` does not stop it. Promotion path: leader_election_service.dart:342-343 `await _lanHub.setMode(LanMode.server); await _lanHub.restart();` -> lan_hub_service.dart:457-458 `_server.stop(); _client.disconnect();`. The double-socket race is real too: `_doConnect` (:78-131) unconditionally assigns `_ws = await WebSocket.connect(...)` with no cancellation of any in-flight attempt, and each attempt installs its own `_ws!.listen(... _controller.add(msg))`, so an orphaned socket keeps feeding the message controller while `_ws` points at the newer one.

### Correction to the original claim

One detail worth adding rather than correcting: because the reconnect loop survives promotion AND the LA listener leak keeps the old handler attached, a promoted leader still ingests `localChange`/`timerAction`/print messages from whatever it reconnects to (lan_hub_service.dart:313-325 apply in every role), while `changeFeed` is dropped by the `mode == LanMode.client` guard at :306. It is not merely a wasted loop.

### User impact

A terminal that takes over as leader spends the rest of the shift dialing the dead terminal's IP on a 2-30s backoff, and if that old leader ever comes back the new leader silently becomes its client on the data plane while still telling its own followers it is the hub. The orphaned-socket race means a single inbound frame can be applied twice with no failover involved.

### Second reader

I could not break this one — I reproduced BOTH halves against real dart:io sockets.

(1) `disconnect()` self-heals into a reconnect. lan_hub_client.dart:258-263 `Future<void> disconnect() async { await _ws?.close(); _ws = null; _authorized = false; _emitConnectionState(); }`. The socket registered at :88-115 carries `onDone: _onDisconnected`; :133-139 `_onDisconnected()` ends `_scheduleReconnect();`; :152-153 `void _scheduleReconnect() { if (_disposed) return; ...}` and :161 `Future.delayed(delay, _doConnect);`. `_disposed` is written only at :267 in `dispose()`. Grep over all of lib/ for a production dispose caller: the ONLY hit is lan_hub_service.dart:468 `await _client.dispose();` inside `LanHubService.dispose()`, and `grep -rn 'lanHubService|lanHub|leaderElection' lib/ | grep dispose` returns nothing — `LanHubService.dispose()` has zero production callers. Nothing clears `_serverIp` either: `grep -rn setServerIp lib/` gives only lan_hub_service.dart:88 (the setter), leader_election_service.dart:305, lan_network_section.dart:59 — all set a non-empty IP, none clear it. So `_doConnect`'s guard at :79 `if (_disposed || _serverIp == null) return;` never fires.

PROBE 1 (flutter test, real LanHubServer+LanHubClient on loopback): after `await client.disconnect()` the server's clientCount went 1 -> 0, then unprompted:
`[LanHub] Reconnecting in 2416ms (attempt 1)` / `[LanHub] Client authorized (total: 1)` / `PROBE: 5s after disconnect clientCount=1 isConnected=true`. Test assertion `expect(server.clientCount, 0)` FAILED with Actual: <1>.

(2) Promotion path is committed, not in-flight. leader_election_service.dart:342-343 `await _lanHub.setMode(LanMode.server); await _lanHub.restart();` -> lan_hub_service.dart:456-464 `restart() { await _server.stop(); await _client.disconnect(); ... await init(); }`. Election is live in production: leader_election_service.dart:87 `static const enabledByDefault = true;` and di.dart:456 `await leaderElection.start();`. There is a SECOND, purely manual trigger the original claim missed: lan_network_section.dart:45-53 `_onModeChanged` -> `await lanHub.setMode(mode); await lanHub.restart();`, and :55-62 `_onIpSaved` -> `setServerIp(ip); await lanHub.restart();`.

(3) The orphan-socket race is real AND far more reachable than claimed. PROBE 2 mirrored `restart()` exactly (`disconnect()` then `connect()` on the same client, same port). Output: `PROBE2: right after restart clientCount=1` ... 5s later `[LanHub] Client authorized (total: 2)` / `PROBE2: 5s later clientCount=2` / `PROBE2: one broadcast delivered 2 time(s)`. Both assertions failed (ORPHANED SOCKET, DOUBLE DELIVERY). Mechanism: `disconnect()` schedules a reconnect, `connect()` overwrites `_serverIp` (:72) and opens socket A, then the pending `Future.delayed(delay, _doConnect)` fires and opens socket B to the NEW ip, leaving A live with its own `_ws!.listen(... _controller.add(msg))` at :88-110.

(4) Production scenario needing no promotion at all: on any failover, a surviving FOLLOWER runs leader_election_service.dart:299-308 `_becomeFollower` -> `setServerIp(leaderIp); setMode(client); await _lanHub.restart();`, which is exactly PROBE 2. It ends with two sockets to the new leader.

(5) Double delivery hits a non-idempotent handler. lan_hub_service.dart:129 `_client.onMessage.listen(_handleRemoteMessage);` — return value discarded, never cancelled, and `init()` re-runs on every `restart()`, so handler subscriptions ALSO accumulate. print_queue_service.dart:366-389 `onRemoteAnnounce` has no jobId/state guard at all — only `final windowsName = _printerConfigStorage.getUsbPrinterName(entryId); if (windowsName == null || windowsName.isEmpty) return;` then `_broadcastClaim(jobId); ... await _printerService.printRenderedBytes(config, bytes);`. Contrast its neighbours which DO guard: :304 `if (job == null || job.stateEnum != PrintJobState.queued) return;` and :338 `if (job == null || job.stateEnum != PrintJobState.claimed) return;`.

(6) Not in-flight. `git diff --stat lib/core/services/lan_hub/` shows lan_hub_service.dart +24 and leader_election_service.dart +46, but `git diff ... | grep 'restart|onMessage.listen|disconnect|_client.connect|setMode|setServerIp'` returns EMPTY for both — every line cited is committed. lan_hub_client.dart, where the defect lives, is not modified at all.

**Second reader's correction:** The verdict stands, but two parts of the claimed impact are overstated and one part of the reasoning is incomplete.

OVERSTATED — "the new leader silently becomes its client on the data plane". In server mode the zombie socket is receive-only. `_sendOrBroadcast` (lan_hub_service.dart:371-382) routes `case LanMode.server: _server.broadcast(msg);` and never touches `_client.send`. `LeaseManager` gates on mode (lease_manager.dart:105-110 `case LanMode.server:` / `case LanMode.client:`). `changeFeed` is explicitly dropped for a non-client (lan_hub_service.dart:306 `if (mode == LanMode.client && ...)`). And `relayOperation`/`relayViaLan` are dead in production — grep finds no lib/ caller, and sync_engine.dart:218 states the call site was removed. So the promoted leader ingests only localChange/timerAction/tableStatus/printJob frames; it does not relay ops, request leases, or apply the cloud feed as a follower. It is a leak, not a role inversion.

OVERSTATED — "spends the rest of the shift dialing the dead terminal's IP". True, but on its own that costs one failed TCP connect per 2-30s with a 5s timeout (:82-83, :144-149). Log and battery noise, zero data impact. This half alone would be LOW.

INCOMPLETE REASONING — the data-plane half of the original claim never established WHY inbound frames still reach app code after promotion. They do, but only because of a fact the claim never cites: lan_hub_service.dart:129's `_client.onMessage.listen(_handleRemoteMessage)` from the terminal's earlier client-mode `init()` is never cancelled and survives the mode switch. Without that line the zombie socket would be inert.

UNDERSTATED — the claim frames the orphan-socket race as a bonus that needs failover ("with no failover involved" was right, but it understated how routine the trigger is). It fires on a plain `restart()` in client mode: a manager toggling the mode picker, saving a new hub IP, or any follower adopting a new leader. I reproduced it with nothing but `disconnect(); connect();`. And it lands on `PrintQueueService.onRemoteAnnounce`, which has no dedup — so the concrete failure is a duplicated physical receipt, not just a doubled row write. Note the localChange path is likely benign: `applyFromPeer` (apply_change.dart:343-360) delegates to `applyOne`, an id-keyed upsert, so applying the same row twice converges — though that file IS in the other session's edit set, so treat that mitigation as provisional.

HOLDING HIGH — but on the orphan-socket half, not the failover story the claim leads with.

**Second reader's impact assessment:** A leader terminal dies mid-service. Every surviving till adopts the new leader and ends up with two live WebSockets to it plus a duplicated message handler, so every frame the new hub fans out is processed 2-4 times on each follower. The till that owns the kitchen USB printer gets the same printJobAnnounce twice and prints the ticket twice, because onRemoteAnnounce has no jobId guard — the kitchen sees two copies of one order and can cook it twice. Same thing happens with no failover at all if a manager changes the LAN mode or hub IP in settings. Separately, the terminal that took over as leader keeps dialing the dead till's IP on a 2-30s backoff for the rest of the shift, and if that dead till reboots (its saved mode is still `server`, so it starts its WS server before election stands it down) the new leader spends the next few seconds ingesting order and timer rows from a terminal it has already replaced.

---

## `S1a` — The change-feed cursor can permanently skip committed rows

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / CRITICAL  
**Second pass:** PARTIAL / HIGH  ← **disputed**  

### Evidence

back/app/migrations/tenants/8_movements.up.sql:28-36 — `CREATE TABLE IF NOT EXISTS change_log ( id BIGSERIAL PRIMARY KEY, ... changed_at TIMESTAMPTZ DEFAULT NOW() );`. back/app/internal/service/sync.go:56-62 — the query is exactly `SELECT id, brand_id, entity, action, entity_id, payload FROM change_log WHERE id > $1 ORDER BY id ASC LIMIT $2`; sync.go:80 sets `nextCursor = id` on every scanned row and sync.go:138 returns it as `NextSyncCursor`. No `changed_at` predicate, no lag/overlap window, no `pg_snapshot`/xmin watermark anywhere in Pull. back/app/internal/handler/sync.go:37-44 wraps it in a plain `BeginTenantTx` read-only tx with no isolation pinning — the tx does not help, because the missing row simply is not committed yet at read time. The only extra column returned is `SnapshotRequired` (sync.go:136-140), which is a retention/compaction check (`oldestID > 0 && lastCursor < oldestID-1`), not a gap guard. Client side: Mary-Ai-POS/lib/core/sync/sync_api_client.dart:90-97 takes `next_sync_cursor` verbatim; lib/core/sync/replication_service.dart:153-154 sends `_db.syncCursor` and lib/core/db/apply_change.dart:158-162 monotonically advances it (`if (next > _db.syncCursor) _db.syncCursor = next;`). Nothing re-requests a lower range. Triggers fire inside the business transaction (e.g. `MarkOrderPaid`, order.go:1235+, does GetOrderByID → PayOrderBill → SetTableFree → GetBillDetails → CreateTransaction before commit), so multi-tens-of-ms commit-order inversions are routine, and lib/core/sync/sync_engine.dart:73/181 pulls every 60s plus a 750ms nudge after every local write — i.e. pulls land precisely during other terminals' in-flight writes.

### User impact

On a multi-terminal venue, a row written by a slower transaction (an order, an order line, a bill payment, a stock movement) can commit after a pull has already advanced past its id. That terminal never receives it and never asks again: the check on screen is permanently missing a line or a payment relative to the server, with no error, no retry and no way for the cashier to notice.

### Second reader

MECHANISM CONFIRMED. back/app/internal/service/sync.go:57-63 — `rows, err := tx.Query(ctx, ` / `SELECT id, brand_id, entity, action, entity_id, payload` / `FROM change_log` / `WHERE id > $1` / `ORDER BY id ASC` / `LIMIT $2`. No changed_at predicate, no lag window. sync.go:85 `nextCursor = id` on every scanned row; sync.go:142 `NextSyncCursor: nextCursor`. back/app/migrations/tenants/8_movements.up.sql:29 `id BIGSERIAL PRIMARY KEY` — sequence assigned at INSERT inside the business txn (triggers 8_movements.up.sql:151 `trg_change_log_order_items`, :154 `trg_change_log_orders`, 41_modifier_calculation.up.sql:25 `transactions`), so a lower id can commit after a higher one. back/app/internal/handler/sync.go:37 `txCtx, tx, err := h.service.BeginTenantTx(...)` and service/service.go:827-830 `tx, err := s.repo.PgRepo.TenantPool.Begin(ctx)` — no pgx.TxOptions, so default READ COMMITTED, no isolation pinning. Grep for xmin/txid/pg_snapshot/advisory over back/ hits only app/vendor/. sync.go:144 `SnapshotRequired: oldestID > 0 && lastCursor < oldestID-1` is a retention check, and grep of the whole Flutter tree for snapshot_required/snapshotRequired returns ZERO hits — the one signal the server does emit is never read. Client: sync_api_client.dart:90-97 takes next_sync_cursor verbatim; replication_service.dart:153 `final cursor = _db.syncCursor;`; apply_change.dart:162 `if (next > _db.syncCursor) _db.syncCursor = next;` — monotonic, never rewinds. No re-bootstrap exists: nothing in lib/ ever clears the bootstrap flag (local_database.dart:749 `bool get isBootstrapped => getMeta(_bootstrapKey) == '1';` has no writer that unsets it). sync_engine.dart:73 `static const tickInterval = Duration(seconds: 60)` and :181 `static const nudgeDelay = Duration(milliseconds: 750)` confirm pull cadence. IMPACT OVERSTATED — the named rows have a second, cursor-independent delivery path: local_change_relay.dart `broadcast(...)` wired at di.dart:221-234 + di.dart:323-335 (`send: lanHubService.broadcastLocalChange`), fed by apply_change.dart:381 (applyLocalWrite) and :405 (applyLocalDelete), applied by peers via apply_change.dart:343 `applyFromPeer`. Orders/lines/payments ARE local-first writes: orders_repository_impl.dart:282,386 and payment_repository_impl.dart:149,174 call `_writer.write(entity: 'orders'/'order_items', ...)`. lan_hub is on by default: leader_election_service.dart:87 `static const enabledByDefault = true;`. orders_repository_impl.dart has no network call in 467 lines, so the check does read the replica — but the replica has two feeds, not one.

**Second reader's correction:** Two things are wrong. (1) The stated user impact — 'the check on screen is permanently missing a line or a payment' — does not follow for the scenario named (two terminals in one venue). Orders, order_items and payments are written local-first and broadcast peer-to-peer over the LAN hub (local_change_relay.dart broadcast, di.dart:221-234/323-335, applied by apply_change.dart:343 applyFromPeer), a path that never consults syncCursor. A cloud-pull skip of those rows does not remove them from a peer's screen. The permanently-lost set is narrower: rows with no LAN origin — server-computed transactions / ingredient_stock_movements / bill_daily_counters produced inside MarkOrderPaid (order.go:1235), back-office menu and price edits, rows from another branch of the same brand, and any row written while a terminal was off the hub. Note cloud-pulled rows are NOT re-broadcast (_applyUpsert never calls _emitLocalChange), so the leader's gap is every follower's gap. (2) 'Permanently' is only true for append-only rows and deletes: payloads are whole rows (to_jsonb(NEW)) applied as INSERT OR REPLACE (apply_change.dart _applyUpsert), so any later UPDATE of a skipped row heals it — which covers `orders` (repeatedly updated) but not `transactions`, `ingredient_stock_movements`, or a skipped delete, which is never re-emitted. Minor citation drift: the query is sync.go:57-63 not 56-62; `nextCursor = id` is line 85 not 80; NextSyncCursor is line 142 not 138. IN_FLIGHT NOTE: the defect itself is backend-only and independent of the other session. But the mitigation that drives this downgrade (local_change_relay.dart, lan_hub/*, apply_change.dart) sits entirely in the concurrently-edited set — if that session removes or gates the peer broadcast, the severity returns to the claimed level.

**Second reader's impact assessment:** On a busy brand, a terminal's local replica can permanently miss server-originated rows a pull raced past: a payment transaction row, an ingredient stock movement, a price or menu change made in the back office, or a delete. Concretely — a till keeps selling at a price the office already changed, stock-on-hand and the shift's transaction list on that terminal disagree with the server's, and a deleted item stays on the menu. No error, no retry, no re-bootstrap path (snapshot_required is never read client-side), so only a reinstall clears it. The order lines and payments a cashier sees on an open check are largely protected by the LAN peer broadcast, so this is a silent bookkeeping/pricing drift rather than the missing-line scenario originally claimed.

---

## `S5a` — The change feed is not branch-scoped, but the client assumes it is

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / HIGH  
**Second pass:** CONFIRMED / HIGH  

### Evidence

SCHEMA — back/app/migrations/tenants/8_movements.up.sql:28-35 `CREATE TABLE IF NOT EXISTS change_log ( id BIGSERIAL PRIMARY KEY, brand_id TEXT, entity TEXT NOT NULL, action TEXT NOT NULL ..., entity_id TEXT NOT NULL, payload JSONB, changed_at TIMESTAMPTZ DEFAULT NOW() );` — there is no branch_id column, and the only indexes are on (entity,entity_id), changed_at and brand_id (lines 38-40). The backend says so itself in 71_change_log_triggers_batch2.up.sql:101: `-- Nothing filters change_log by brand_id (tenancy is by schema)`. No RLS anywhere: `grep -rn 'ROW LEVEL SECURITY|CREATE POLICY' app/migrations/` returns nothing.

PULL QUERY — back/app/internal/service/sync.go:56-62: `SELECT id, brand_id, entity, action, entity_id, payload FROM change_log WHERE id > $1 ORDER BY id ASC LIMIT $2`. One predicate, on the cursor. No brand and no branch clause, and `brand_id` is scanned into a variable that is never used for filtering.

CONTRAST — every REST read IS branch-scoped: sqlc/tenants/queries/transaction_category.sql:30 `AND branch_id IS NOT DISTINCT FROM NULLIF(current_setting('app.branch_id', true), '')::uuid`; cash_register.sql:13,18,28; group_transactions.sql:10,16; order.sql:34,59,106,116,125,136. And the tables all carry the column: 9_extras.up.sql:49 `branch_id UUID NOT NULL REFERENCES branches(id)` (cash_registers), :62 (group_transactions), 11_transaction_category.up.sql:22 `branch_id UUID REFERENCES branches(id)` (transactions).

THE THREE FALSE ASSERTIONS — lib/core/db/entity_registry.dart:528 `// branch-scoped on the backend (change_log.branch_id), so the local reads`; lib/core/db/transaction_pickers_query.dart:9 `/// is branch-scoped on the backend (change_log.branch_id), so — like`; lib/core/db/menu_admin_query.dart:97 `/// change_log.branch_id scopes the feed, so a terminal only ever receives` `/// its own branch's visibility rows.` The column they all name does not exist.

THE THREE UNFILTERED WHERE CLAUSES — archives_query.dart:50-104 `_where` builds `final where = <String>['o.deleted_at IS NULL'];` and adds only bill_no, bill_status, start, end; `git show HEAD:lib/core/db/archives_query.dart | grep -n branch` returns nothing, and neither does the working tree. transactions_query.dart:70-105 `_filter` builds `final clauses = <String>['deleted_at IS NULL'];` plus optional type / cash_register_id / search. transaction_pickers_query.dart:87-89 `List<Map<String, dynamic>> _liveByName(String table) => _db.selectData('SELECT data FROM $table WHERE deleted_at IS NULL ORDER BY name');`.

AND IT IS NOT JUST THOSE THREE — `grep -rn "branch_id" lib/core/db/*.dart` finds branch_id only as a PromotedColumn declaration in entity_registry.dart and in the three false comments. No query anywhere in lib/ has a branch predicate. menu_admin_query.dart:106-113 `ingredients()` uses `EXISTS (SELECT 1 FROM ingredient_visibility v WHERE v.ingredient_id = i.id AND v.is_visible = 1)` with no branch clause — so an ingredient visible in ANY branch of the brand shows here, which is exactly the leak its own comment at :93-94 claims to have replaced.

AND THE SCREENS ARE LIVE, not dormant: transactions_list_controller.dart:69-81 `getTransactions(...) => _local.getTransactions(...)` where `_local` is TransactionsRepository → transactions_repository_impl.dart:68 `_query = TransactionsQuery(replicaDb)`; called from transactions_list_section.dart:107. archives_local_repository_impl.dart:42 `_archives = ArchivesQuery(replica)`. Pickers: transactions_repository_impl.dart:85,96 `_pickers.transactionGroups()` / `_pickers.cashRegisters()`.

### User impact

On a brand with more than one branch (one tenant schema, many branches — the schema's own design), every terminal replicates and then displays every branch's data as its own: the Archives screen lists other venues' bills and their money in its summary, the transactions ledger shows other branches' income and expenses, the cash-register and transaction-group pickers offer registers that belong to another site, and the tech-card ingredient picker shows the whole brand's catalogue. A cashier reconciling a till against the ledger, or a manager reading the archive summary, is reading numbers from venues they do not work at, with nothing on screen to indicate it. It is also a data-exposure issue, not only a wrong-total issue.

### Second reader

SCHEMA — back/app/migrations/tenants/8_movements.up.sql:28-40: `CREATE TABLE IF NOT EXISTS change_log ( id BIGSERIAL PRIMARY KEY, brand_id TEXT, entity TEXT NOT NULL, action TEXT NOT NULL ..., entity_id TEXT NOT NULL, payload JSONB, changed_at TIMESTAMPTZ DEFAULT NOW() );` — no branch_id column; indexes only on (entity,entity_id), changed_at, brand_id. `grep -rniE 'row level security|create policy' app/migrations/` → no output (verified myself).

TENANCY IS PER BRAND, NOT PER BRANCH — back/app/internal/service/service.go:827-847 `BeginTenantTx`: `schemaName, err := tenantSchemaName(brandID)` … `SET LOCAL search_path TO "%s", public` … `SET LOCAL app.brand_id`, then `SET LOCAL app.branch_id` only as a GUC. back/app/migrations/tenants/1_core.up.sql:24 `CREATE TABLE IF NOT EXISTS branches (` — many branches live inside one brand schema, so change_log holds every branch's rows.

PULL — back/app/internal/service/sync.go:56-62 `SELECT id, brand_id, entity, action, entity_id, payload FROM change_log WHERE id > $1 ORDER BY id ASC LIMIT $2`. Single predicate on the cursor; `brandID` is scanned (sync.go:75,81) and never used in Pull. Handler back/app/internal/handler/sync.go:44 `resp, err := h.service.Sync().Pull(txCtx, req.LastSyncCursor, req.Limit)` — no branch argument exists to pass.

TRIGGERS COVER THE LEAKING TABLES — 8_movements.up.sql:151,154 `trg_change_log_order_items` / `trg_change_log_orders`; 71_change_log_triggers_batch2.up.sql:25,28,31,34 transactions / group_transactions / cash_registers / ingredient_visibility. So other branches' orders, ledger rows, registers and visibility rows really do arrive.

NO CLIENT-SIDE FILTER — lib/core/db/apply_change.dart:132-166 `applyPullResponse` iterates `changes.entries` and applies every known entity; `_applyUpsert` (:225-241) only checks `isPending`. `grep -n branch lib/core/sync/*.dart lib/core/outbox/*.dart` returns only unrelated comments.

THE UNFILTERED READS — lib/core/db/archives_query.dart:51 `final where = <String>['o.deleted_at IS NULL'];` (only bill_no/bill_status/start/end added, :59-104) and its joins are LEFT JOINs (:130-131), so nothing narrows incidentally; summary() reuses the same `_where` (:195-196). lib/core/db/transactions_query.dart:78 `final clauses = <String>['deleted_at IS NULL'];` plus optional type/cash_register_id/search. lib/core/db/transaction_pickers_query.dart:87-89 `_liveByName(String table) => _db.selectData('SELECT data FROM $table WHERE deleted_at IS NULL ORDER BY name')`. lib/core/db/menu_admin_query.dart:106-113 `EXISTS (SELECT 1 FROM ingredient_visibility v WHERE v.ingredient_id = i.id AND v.is_visible = 1)` — no branch clause.

THE FALSE COMMENTS — entity_registry.dart:528-529 `// branch-scoped on the backend (change_log.branch_id)`; transaction_pickers_query.dart:9-10 same; menu_admin_query.dart:96-98 `change_log.branch_id scopes the feed`. Column does not exist. The backend says so itself: 71_change_log_triggers_batch2.up.sql:101 `-- Nothing filters change_log by brand_id (tenancy is by schema)`.

CONTRAST VERIFIED — back/sqlc/tenants/queries/order.sql:33 `AND branch_id = NULLIF(current_setting('app.branch_id', true), '')::uuid` (repeated at :105,:116,:125,:136); cash_register.sql:13,18,28,34; group_transactions.sql:10,16; transaction_category.sql:30 `AND branch_id IS NOT DISTINCT FROM NULLIF(...)::uuid`. And the local replica even carries the column: entity_registry.dart:472 `PromotedColumn('branch_id', SqlType.text, indexed: true)` on `orders`, :558 on `transactions`, :427 on `ingredient_visibility` — the data to filter on is present and indexed, and no query uses it.

REACHABILITY (checked from code, not comments) — transactions_list_controller.dart:25-38 `TransactionsListController({required TransactionsRepository local, MainRepository? remote}) : _local = local;` and :68-81 `getTransactions(...) => _local.getTransactions(...)`; di.dart:582 `() => TransactionsListController(local: inject())`; transactions_list_section.dart:107 calls `_controller.getTransactions(...)` in `initState`. transactions_repository_impl.dart:68-69 `_query = TransactionsQuery(replicaDb), _pickers = TransactionPickersQuery(replicaDb)`. di.dart:475-476 `registerLazySingleton<ArchivesLocalRepository>(() => ArchivesLocalRepositoryImpl(inject<replica.LocalDatabase>()))`, consumed by archives_bloc.dart:51/64 and archive_bloc.dart:15/17; archives_local_repository_impl.dart:42 `_archives = ArchivesQuery(replica)` with no network fallback left. menu_admin_local_repository_impl.dart:90 `getIngredients() => _query.ingredients()`. Gating exists but does not save it: transactions_screen.dart:49-50 `role.canManageTransactions`, which user_role_permissions.dart:32-35 grants to cashier, manager and admin.

**Second reader's correction:** Directionally and factually correct on every load-bearing point I could re-derive; three refinements. (1) The menu_admin overstatement: the comment at menu_admin_query.dart:88-94 claims fail-closed visibility, and that part still works — an ingredient with no visibility row anywhere is hidden. The residual leak is narrower than 'the whole brand's catalogue': it is exactly the ingredients some OTHER branch marked visible. Separately and worse, lib/core/db/menu_query.dart:74 `List<Map<String, dynamic>> ingredients() => _live('ingredients');` has no visibility join at all and is live via menu_repository_impl.dart:72 — that is a wider hole, but it is a different finding, not this one. (2) The archives fix is not purely client-side: back/app/internal/service/order.go:159,548,3241 set orders.branch_id only when branch_id is present in context, so rows written without a branch-scoped token carry NULL and a strict local equality filter would hide them. (3) entity_registry.dart:540-549 still asserts 'the ledger screen does not read this table yet … TransactionsQuery … a finished read path with no caller' — that comment is stale and the cited controller code refutes it; the previous verifier was right to ignore it. Severity stays HIGH rather than CRITICAL: it is intra-brand, not cross-tenant (schema-per-brand holds, verified in BeginTenantTx), and the blast radius is exactly zero for a single-branch brand, which is likely the common small-venue deployment.

**Second reader's impact assessment:** On any brand with more than one branch — which the backend is explicitly built for (branch-scoped tokens in middleware/terminal_auth.go:29, an X-Branch-ID header for brand superadmins in middleware/tenant.go:31-37, and branch predicates on every REST read) — each terminal replicates the whole brand's change_log and then renders it as its own. The Archives list and its header summary count and sum other venues' bills (SUM over grand_total/table_charge, archives_query.dart:197-205), so a cashier reconciling a till or a manager reading the shift total reads money taken at a site they do not work at, with nothing on screen saying so. The transactions ledger shows other branches' income, expense and transfer rows to any cashier/manager/admin. The cash-register and transaction-group pickers offer another site's registers, so a transaction can be filed against a register that is not in the building. The tech-card ingredient picker shows ingredients another branch enabled. It is a data-exposure problem as much as a wrong-total problem, and no local guard, early return or caller-side check anywhere in lib/ narrows it.

---

## `W1` — A new menu item can never be saved, online or offline

**Area:** Write path & outbox  
**First pass:** CONFIRMED / CRITICAL  
**Second pass:** CONFIRMED / HIGH  ← **disputed**  

### Evidence

lib/features/view/main/presentation/pages/menu/menu_manage_screen.dart:307-325 — `String? _upsertTranslation(String? existingId, {required String en, required String ru, required String uz}) { if (en.trim().isEmpty && ru.trim().isEmpty && uz.trim().isEmpty) { return existingId; } ... if (existingId != null && existingId.isNotEmpty) { ... return existingId; } _cubit.createTranslation(body); throw const MessageFailure(_needsConnectionForNewTranslation);` — the throw is the unconditional tail of the null/empty-existingId branch; there is no connectivity check anywhere in the method or in `_submit`.
Same file:355-360 — `final nameTransId = _upsertTranslation(_nameTranslationId, en: nameEn, ru: nameRu, uz: name);` and :341 `if (name.isEmpty || category == null || price == null || price <= 0) { showErrorMessage(...); return; }` so `uz: name` is non-empty by validation and the empty-guard cannot fire.
Same file:53-54, 198-199, 461-462 — `_nameTranslationId` is only ever assigned from `_applyGoodForForm` (`final ni = (good['name_i18n'] ?? '').toString(); _nameTranslationId = ni.isNotEmpty ? ni : null;`), from `_clearForm` (null) and from line 397 after a save that can never be reached. A new meal (`_editMealId == null`, :70) never runs `_loadMealForEdit`, so it is null.
The throw precedes `_cubit.saveGood(...)` at :388, so no `goods` op is ever enqueued.
lib/core/error/failure.dart:25-31 — `class MessageFailure extends Failure { final String message; ... String getLocalizedMessage(BuildContext context) => message; }` and :323 the message is the literal `'new-translation'` (`static const _needsConnectionForNewTranslation = 'new-translation';` :303). :412-414 `on Failure catch (e) { ... showErrorMessage(context, e.getLocalizedMessage(context)); }`.
Orphan per retry: menu_admin_local_repository_impl.dart:174-183 `createTranslation` → `_writer.create(entity: 'translations', row: body, request: body);` which (local_writer.dart:96-118) mints a fresh `localId`/`opId` and enqueues on every call. menu_admin_outbox.dart:113-123 registers `translations/create` returning `succeeded()` with **no** serverRow, so outbox_drainer.dart:181-198 `_reconcile` deletes the local provisional row — the translation lands on the server referenced by nothing.
Route is live: lib/core/routes/app_pages.dart:71-76 `case AppRoutes.menuManageScreen: return simpleRoute(const MenuManageScreen(), ...)`.

### User impact

A manager can never add a menu item on this build — online or offline. The save button shows the untranslated token 'new-translation' every time, and each press silently posts another orphan translation row to the server on the next drain.

### Second reader

lib/features/view/main/presentation/pages/menu/menu_manage_screen.dart:307-324 — `String? _upsertTranslation(String? existingId, {required String en, required String ru, required String uz}) { if (en.trim().isEmpty && ru.trim().isEmpty && uz.trim().isEmpty) { return existingId; } final body = {'en': en, 'ru': ru, 'uz': uz}; if (existingId != null && existingId.isNotEmpty) { ... return existingId; } _cubit.createTranslation(body); throw const MessageFailure(_needsConnectionForNewTranslation);` — I re-read the whole method and `_submit`; there is no connectivity check, no `Connectivity`/`isOnline`/`hasNetwork` reference anywhere in the file. The throw is the unconditional tail of the null-existingId branch, so it fires online and offline alike.

Empty-guard cannot fire: :341 `if (name.isEmpty || category == null || price == null || price <= 0) { showErrorMessage(context, S.current.strRequiredFields); return; }` and :355-360 `_upsertTranslation(_nameTranslationId, en: nameEn, ru: nameRu, uz: name)` — `uz` is the validated non-empty `name`.

`_nameTranslationId` is null for a new meal. Full grep of the file (only 6 assignment sites): :53 declaration, :198 `_nameTranslationId = ni.isNotEmpty ? ni : null;` inside `_applyGoodForForm` (reached only from `_loadMealForEdit`, :287-292), :397 post-save, :461 `_clearForm`. `_loadMealForEdit` is called only from :257 and :277, both guarded by a non-empty `_editMealId`, which is set only at :276 from route arguments in `didChangeDependencies` (:262-278).

Reachability is real and unconditional: lib/features/view/main/presentation/pages/menu/menu_meals_list_screen.dart:180 `onNew: () => _openManage(),` → :86-94 `Navigator.pushNamed(context, AppRoutes.menuManageScreen, arguments: mealId == null ? null : {'meal_id': mealId})`; lib/core/routes/app_pages.dart:72-77 `case AppRoutes.menuManageScreen: return simpleRoute(const MenuManageScreen(), args: args, ...)`; lib/core/widgets/app_sidebar.dart:95-103 the Menu nav item (behind `canManageMenu`) routes to `menuMealsScreen`. Save button: menu_manage_screen.dart:1057-1067 `onTap: _isSubmitting ? null : () { context.unfocusKeyboard(); _submit(); }`.

No guard elsewhere. `saveGood` has exactly one caller tree-wide (menu_manage_screen.dart:388), and it sits after both `_upsertTranslation` calls, so no `goods` op is enqueued.

Raw token confirmed: :304 `static const _needsConnectionForNewTranslation = 'new-translation';`; lib/core/error/failure.dart:25-30 `class MessageFailure extends Failure { final String message; ... String getLocalizedMessage(BuildContext context) => message; }`; :412-414 `on Failure catch (e) { ... showErrorMessage(context, e.getLocalizedMessage(context)); }`. lib/core/components/flush_bars.dart:69-81 → `_sanitizeErrorText` (:23-67) only strips HTML and maps 4xx/5xx/Dio text; `new-translation` passes through verbatim. `grep -rn "new-translation"` over the whole tree (dart + md + arb) returns exactly one hit — the constant itself — so it is not an l10n key.

Orphan-per-press confirmed: menu_admin_local_repository_impl.dart:174-183 `createTranslation` → `_writer.create(entity: 'translations', row: body, request: body);`; lib/core/outbox/local_writer.dart:97-120 mints a fresh `localId`/`opId` and `_outbox.enqueue(...)` on every call; menu_admin_outbox.dart:115-122 `send: (op) async { final result = await remote.createTranslation(op.payload); return result.fold(_outcome, (_) => const OutboxExecutionResult.succeeded()); }` — no `serverRow`; lib/core/outbox/outbox_drainer.dart:178-198 `final serverId = row?['id'] as String?; if (serverId == null || serverId.isEmpty) { _applier.applyOne(entity: op.entity, action: 'delete', entityId: provisionalId); _db.clearProvisional(...); return; }`.

No test contradicts: test/offline_screen_suite_test.dart:481 only asserts `expectUsableFrame(tester, app, screen: MenuManageScreen)` — it never drives `_submit`.

Working tree is clean for every file the blocking path runs through: `git status --porcelain` shows menu_manage_screen.dart, menu_admin_local_repository_impl.dart, menu_manage_cubit.dart and menu_admin_outbox.dart all unmodified.

**Second reader's correction:** The mechanism is fully reproducible; I could not find any guard, early return, caller-side check or gate that prevents it. Three corrections to the original write-up. (1) Severity is overstated at CRITICAL. This is a total outage of one permission-gated admin function (`canManageMenu`), not of the till: order taking, payment, printing and shift close never touch `_upsertTranslation`, and `saveGood` has no other caller. `goods` also replicate inbound (lib/core/db/entity_registry.dart:339, sync_engine.dart:396), so items created through the backend still reach the POS — the device is not the only creation surface. HIGH, not CRITICAL. (2) The claim that line 397 sits 'after a save that can never be reached' is wrong as stated. In edit mode on a good whose `name_i18n` is non-empty, `_upsertTranslation` takes the `existingId` branch at :317-321 and returns without throwing, so :388 `saveGood` and :397 both execute normally. Editing an already-translated meal works. (3) The original understates the blast radius in one place: because `_nameTranslationId` is null whenever `good['name_i18n']` is empty (:196-198), *editing* any legacy good that carries no translation reference throws on the same line — so the break is 'every create, plus every edit of a good with no name_i18n', not creates only. On the orphan sub-claim: outbox_drainer.dart and local_writer.dart ARE modified by the concurrent session, so the exact provisional-row disposal could change under me; I verified against the current working-tree text, which still deletes the provisional row when the handler returns no serverRow. The blocking throw itself rests entirely on committed, untouched files.

**Second reader's impact assessment:** A user with menu-management permission cannot create a menu item from the POS at all — the Save button fails on every press, online or offline, and shows the untranslated developer token 'new-translation' as the whole error message with no hint of what to do. The same failure hits editing any existing good that has no name_i18n reference. Nothing about the item is saved, and each press silently queues one more `translations/create`, so a manager retrying five times pushes five orphan translation rows to the server on the next drain, each referenced by nothing and each deleted from the local DB after it lands. Ordering, payment and shift operations are unaffected.

---

## `W2` — The real outbox is invisible; quarantined writes are unrecoverable

**Area:** Write path & outbox  
**First pass:** CONFIRMED / HIGH  
**Second pass:** CONFIRMED / HIGH  

### Evidence

lib/features/view/main/presentation/pages/settings/sections/sync_status_section.dart:211-216 — `final queue = inject<OfflineQueueService>(); ... ValueListenableBuilder<Box<PendingOperation>>(valueListenable: queue.listenable, builder: (context, box, _) { final depth = box.length;` and :232-234 `subtitle: depth == 0 ? "Barcha operatsiyalar sinxronlangan" : '$depth ta operatsiya kutilmoqda'`. :537-542 the quarantine card reads `queue.quarantined` — the Hive `QuarantinedOperation` box, not `OutboxStore`.
Grep of lib/ for each OutboxStore member outside outbox_store.dart itself returns nothing: `.quarantined(` → 0 hits; `quarantineDepth` → only its own definition (outbox_store.dart:250); `hasWork` → only outbox_store.dart:252; `OutboxStore.retryQuarantined`/`dismissQuarantined` → only outbox_store.dart:317/328 (the UI's :583/:588 calls resolve to `OfflineQueueService`'s same-named methods, offline_queue_service.dart:102/111); `depth` → no call site (the only `.depth` in a screen is `box.length` above). Nothing enqueues into the Hive box: `_box.put` is reached only from `enqueue` (offline_queue_service.dart:71-83), whose sole caller is `retryQuarantined` at :105.
lib/core/sync/sync_engine.dart:243 and :262 — `await _outbox.drain();` in both branches, result unassigned, while `OutboxDrainResult` carries `final int quarantined;` (outbox_drainer.dart:16).
OutboxStore rows can be quarantined with no path out: outbox_drainer.dart:96-99 and :121-124 call `_fail(..., permanent: true)` → outbox_store.dart:299-313 `_quarantine`; `ready()` (outbox_store.dart:136-144) filters `WHERE status = ?` with `pending`, and `clearBackoff()` (:339-345) also only touches `pending`.

### User impact

The settings screen's outbox card is hard-wired to a queue nothing writes to, so it always reads 'Barcha operatsiyalar sinxronlangan' (all synced) — including when the real SQLite outbox holds undrained payments. A write that burns its 8 attempts or is rejected 4xx is quarantined with no UI, no counter, and no reachable retry/dismiss, and quarantining also releases the row's pending guard (outbox_drainer.dart:246), so the operator watches their change silently revert with no explanation anywhere.

### Second reader

UI reads the Hive queue, not the SQLite outbox — sync_status_section.dart:211-216 `final queue = inject<OfflineQueueService>(); ... ValueListenableBuilder<Box<PendingOperation>>(valueListenable: queue.listenable, builder: (context, box, _) { final depth = box.length;` and :232-236 `subtitle: depth == 0 ? "Barcha operatsiyalar sinxronlangan" : '$depth ta operatsiya kutilmoqda'`. Quarantine card at :537/:541 `final queue = inject<OfflineQueueService>(); ... final items = queue.quarantined;` over `ValueListenable<Box<QuarantinedOperation>>`.

Nothing writes either Hive box in production. `_box.put` occurs exactly once, offline_queue_service.dart:82 inside `enqueue` (:71); `grep -rn "enqueue(" lib/core/services/offline_queue/` returns only :71 (definition) and :105 (`await enqueue(q.toRetryable());` inside `retryQuarantined`) — a closed loop. Tree-wide `.enqueue(` on the service hits only test/ (offline_queue_quarantine_test.dart, full_shift_soak_test.dart, write_path_guard_test.dart:1409). `_quarantineBox.put` occurs once, :97 in `_quarantine`, reachable only from `syncAll` (:204) and `relayViaLan` (:259); grep of lib/ for `syncAll(`/`relayViaLan(` finds zero production call sites — only the definitions at :156/:236 and doc comments. sync_engine.dart:218-222 states the call was deleted. `inject<OfflineQueueService>()` survives in only two places: lan_hub_service.dart:250 (`executeRelayedOp`, leader-side, executes immediately and never touches `_box`) and this settings section.

The real queue is invisible: `grep -rn "OutboxStore" lib/` outside its own file yields di.dart:250-260, outbox_drainer, local_writer, local_database, sync_engine, table_timer_local_repository_impl, transactions_repository_impl — no presentation-layer file. Per-member greps across lib/ AND test/: `.quarantined(` → test/outbox_test.dart only; `quarantineDepth` → outbox_store.dart:250 + tests; `hasWork` → :252 + tests; `.depth` → tests only; `OutboxStore.retryQuarantined` (:317) / `dismissQuarantined` (:328) → tests only (the UI's :583/:588 resolve to OfflineQueueService's same-named methods at :102/:111).

The outbox is fully in service, so quarantine is live: di.dart:422-432 registers handlers for users, halls_tables, menu_admin, transactions, branches, orders, timer/shift. sync_engine.dart:243 and :262 both `await _outbox.drain();` with the result discarded, while `OutboxDrainResult` carries `quarantined`. Quarantine paths: outbox_drainer.dart:96 `_fail(op, 'no executor registered for ...', permanent: true)` and :122 `_fail(op, result.error ?? 'rejected', permanent: true)` → outbox_store.dart:300 `markPermanentlyFailed` → :306 `_quarantine`. orders_outbox.dart:263-268 `_mapDioError`: `if (code != null && code >= 400 && code < 500) return OutboxExecutionResult.permanent(...)` — every 4xx, including 401/403/429, quarantines on the first attempt. No path out: `ready()` (outbox_store.dart:136-141) filters `WHERE status = ? AND next_attempt_at <= ?` with `pending`, and `clearBackoff()` (:339-344) also updates only `status = pending`. outbox_drainer.dart:246 `_db.clearPending(op.entity, entityId);` releases the local-authority guard on quarantine.

**Second reader's correction:** Three refinements, none fatal to the claim. (1) The evidence understates it: because `depth` is structurally always 0, `onTap: depth == 0 ? null : _syncNow` (:239) leaves the card's 'Hozir sinxronlash' button permanently disabled — the section's own manual-sync affordance is dead. (Other force-ticks still exist: main_cubit.dart:99/:118, menu_meals_list_screen.dart:61, close_shift_screen.dart:82, so `clearBackoff()` is still reachable — but only for `pending` rows, never quarantined ones.) (2) 'always reads all-synced' is true for a clean install; on a terminal upgraded from a build that still enqueued, leftover Hive rows would show a count that nothing can ever drain (`syncAll` unreachable), which is wrong in the opposite direction. (3) 'watches their change silently revert' is exact only for updates/pays against a row the server already has; for an offline create the server never accepted there is no server row to overwrite, so clearPending leaves a phantom local row instead of a revert. Access is also narrower than 'the operator': settings_screen.dart:102 `final allowed = role.canAccessSettings;` and user_role_permissions.dart:12-15 restrict it to admin/manager/superadmin — a cashier has no such screen at all, which makes the observability gap worse, not better. Severity HIGH stands: a 401/403 on a queued payment quarantines it on attempt one, drops the local guard, and leaves no counter, no list entry and no retry/dismiss anywhere in the app.

**Second reader's impact assessment:** An admin or manager opening Sozlamalar → Sinxronizatsiya holati is told 'Barcha operatsiyalar sinxronlangan' with a greyed-out sync button while the SQLite `_outbox` holds undrained payments and orders, and the Karantin card reads "Rad etilgan operatsiyalar yo'q" no matter how many writes the server has rejected. A payment queued offline that comes back 4xx (expired token, order already closed, stale table) is quarantined on its first attempt, its local guard is released so the cashier sees the bill flip back to unpaid, and there is no screen showing why and no button to retry or dismiss it — the write is unrecoverable except by re-entering it by hand.

---


# MEDIUM

## `A10` — No cancel during setup, and a false failure from a concurrent drain

**Area:** Auth, session & startup  
**First pass:** PARTIAL / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

Part 1 confirmed: lib/features/view/auth/presentation/pages/initial_setup/initial_setup_screen.dart:111-130 `_progress` contains only title, subtitle, `LinearProgressIndicator` and a row count — no cancel; the Retry/Continue buttons exist only in `_failure` (:132-162), shown after the await returns. The request is a POST (lib/core/sync/sync_api_client.dart:76-79 `_client.post(pullPath, data: {...})`) and `connectTimeout: Duration(seconds: 30)` (lib/core/api/dio_client.dart:40); with an optimistic `isOnline` the `_OfflineInterceptor` lets it through (dio_client.dart:216) so it blocks for the full connect timeout per batch. Part 2 mechanism is wrong: lib/core/sync/replication_service.dart:138-144 does return `alreadyRunning` when `_running`, and lib/core/sync/sync_engine.dart:73 `tickInterval = Duration(seconds: 60)` with :136 `_ticker ??= Timer.periodic(tickInterval, (_) => tick())` started at startup (lib/di.dart:441 `syncEngine.start();`) against the same shared ReplicationService (login_data_scope_service.dart:175 `_syncEngine.replication`) — but `result.ok` is NOT what produces `incomplete`. login_data_scope_service.dart:181 uses `result.ok` only for `if (result.ok) _pendingReset = false;`; the outcome is decided at :194 `if (result.outcome == ReplicationOutcome.caughtUp && filled)`.

### Correction to the original claim

`result.ok` false is not the cause of the `incomplete` return — `outcome != caughtUp` is (login_data_scope_service.dart:194-198). The conclusion still holds: `alreadyRunning` is not `caughtUp`, so a healthy online terminal that collides with the 60s tick is shown "Setup failed". What `result.ok == false` actually does is leave `_pendingReset` true (line 181), so on a brand switch the collision means clearAll already ran, no data was pulled, and pressing Retry wipes the (empty) database again — a strictly worse outcome than the claim describes.

### User impact

A cashier on a working online terminal can be shown "Setup failed" purely because a background sync tick was in flight, and during a brand switch that same collision leaves the replica empty with no way to interrupt the wait.

---

## `A12` — Optimistic isOnline at cold start

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/services/connectivity/connectivity_cubit.dart:25 `ConnectivityCubit(this._connectivity) : super(true)`; :29-32 `_init` does `_linkUp = _isLinkUp(results); emit(_linkUp);` where `_isLinkUp` (:83-90) only inspects `ConnectivityResult.wifi/ethernet/mobile/vpn/other` — the OS interface, not reachability, exactly as the class's own doc comment at :10-14 warns against. The first reachability answer arrives only from `_probe()`, kicked at :55 from `attachProbeClient` (called at lib/di.dart:286) or by the 20s timer. Consumer: lib/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart:91 `if (!_connectivity.isOnline) {` — true means the POST at :100 is attempted, `_OfflineInterceptor` permits it (dio_client.dart:216 checks the same optimistic flag), and `connectTimeout: Duration(seconds: 30)` (dio_client.dart:40) applies. The keypad is locked meanwhile: login_pin_cubit.dart:206 `if (state.status == Status.LOADING) return;` with LOADING emitted at :60.

### Correction to the original claim

"For the first seconds" understates it. The probe itself inherits the 30s connect timeout (it overrides only send/receive, connectivity_cubit.dart:67-72), so on a venue LAN whose uplink blackholes packets the optimistic `true` can persist for a full 30 seconds after startup, not a few seconds — and every 20s probe thereafter re-emits `true` only on success, so the window is bounded by the first probe's failure, not by app startup.

### User impact

A cashier who starts a shift on a terminal whose uplink is down, using a PIN not yet cached on that terminal, gets a dead keypad for up to 30 seconds before the error appears, instead of the immediate offline refusal the same code gives once the probe has answered.

---

## `A13` — Brand login performs no verification at all

**Area:** Auth, session & startup  
**First pass:** PARTIAL / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/features/view/auth/data/repositories/login_repository_impl.dart:37-49 — the whole body of `loginWithBrandId` is `try { await _tokenStorage.writeBrandIdToken(req); return const Right(true); } catch (e) { return const Left(CacheFailure()); }`. No datasource call: `_datasources` is untouched here, unlike `login` at :74-80. The usecase is a pass-through (lib/features/view/auth/domain/usecases/login_with_brand/login_with_brand_usecase.dart:12-13 `_repository.loginWithBrandId(params)`), and AuthCubit's caller is lib/features/view/auth/presentation/cubit/auth/auth_cubit.dart:73 `var result = await _loginWithBrandUsecase.call(req);`.

### Correction to the original claim

"Unreachable dead code" is wrong. The Left branch IS reachable: `writeBrandIdToken` → `_write` → `_secure.write` (token_storage_impl.dart:66-70, `brandId` is in `_secureKeys` at :57-62) throws on a locked or broken keyring, yielding `CacheFailure()`. `CacheFailure` is not in `isDefiniteAuthRejection` (lib/core/error/failure.dart:166-170: ValidationFailure/UnauthorizedFailure/NotFoundFailure/MessageFailure), so control reaches the cache-fallback at auth_cubit.dart:90-105 and can log the operator in from `validateAndGetUser` — the branch is not dead, it is reachable exactly in the keyring-failure case A16 describes. Also worth stating: the credentials are not unverified forever — the brand id and password are replayed on the first PIN login (login_pin_cubit.dart:100-106 → auth_datasource.dart:33-38), so a wrong pair fails there, not here.

### User impact

Any string typed into the brand-login screen is accepted and persisted, so a typo'd brand id looks like a successful login and only fails later at the PIN keypad with an unrelated-looking error — and offline it fails with a bare connection error the cashier cannot act on.

---

## `A14` — No PIN attempt throttling anywhere

**Area:** Auth, session & startup  
**First pass:** PARTIAL / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

No client-side throttle exists: `grep -rniE 'throttl|lockout|attempt|backoff|rateLimit|cooldown|failedCount|tries' lib/features/view/auth lib/core/widgets/app_pincode_dialog.dart lib/core/widgets/manager_pincode_dialog.dart lib/core/services/auth` returns three hits, all prose comments (auth_datasource.dart:98, login_pin_cubit.dart:56, login_data_scope_service.dart:188). lib/core/widgets/app_pincode_dialog.dart:117-131 `_verify()` on failure only plays a 420ms shake (not awaited — `_shakeCtrl.forward(from: 0)`) and immediately sets `_verifying = false`, so the next attempt can start at once; there is no counter or delay. The cache-first path is purely local: auth_datasource.dart:101-108 `getForPin` → lib/core/services/auth/offline_auth_cache.dart:171-174 `(await _readPins())['${brandId}_$pincode']`, a secure-storage read and a JSON map lookup. Same shape in login_pin_cubit.dart:73-87.

### Correction to the original claim

The "SECURITY REGRESSION" framing is wrong for the offline case, which is the one the claim calls purely local. `git show HEAD:lib/.../auth_datasource.dart` shows the pre-change code opened with `if (!_client.isOnline) { return _verifyFromCache(brandIdToken.brandId, pincode); }` — offline enumeration was already fully local and unthrottled before the cache-first change, so nothing was lost there. What actually changed is online-only: previously every online prompt hit `POST /login-pincode`, which the backend rate-limits at 5 req/s per IP (back/app/internal/middleware/middleware.go:59-77 `Rate: 5, Burst: 5, ExpiresIn: time.Minute`, applied at back/app/internal/handler/handler.go:39), and now an already-cached PIN is answered with no round trip. Also note enumeration is not scriptable: every attempt is four taps through `AppPincodeDialog`'s on-screen keypad, so 10^4 candidates is hours of manual entry, and only PINs already cached on that terminal answer locally — an uncached candidate still round-trips (or, offline, returns ConnectionFailure).

### User impact

Someone with unsupervised physical access to a terminal can try manager PINs on the approval dialog as fast as they can tap, with no lockout and, for PINs already cached on that terminal, no server record of the attempts — enough to eventually self-authorize a void or a shift close.

---

## `A16` — Secure-storage failure is indistinguishable from "not provisioned"

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/services/auth/offline_auth_cache.dart:58-72 `_readAll` and :130-141 `_readPins` both end `catch (_) { return {}; }` — a keyring failure is indistinguishable from an empty cache; every consumer (`validateAndGetUser` :106-110, `getCachedUser` :114-117, `getForPin` :171-174) therefore returns null. lib/core/auth/storage/token_storage_impl.dart:77-87 `readBrandIdToken` likewise ends `catch (e) { return null; }`, which login_pin_cubit.dart:64-67 reads as "not provisioned" (`emit(state.copyWith(status: Status.UNKNOWN))`). No logging in any of the four. The unguarded startup calls: lib/di.dart:185-186 `await AppTokenStorage.migrateLegacyPlaintext(prefs, secureStorage); await OfflineAuthCache.migrateLegacyPlaintext(prefs, secureStorage);` with no try/catch, and both helpers await a bare `secure.write` (token_storage_impl.dart:268-273; offline_auth_cache.dart:192-197). The caller is equally unguarded: lib/main.dart:103 `await initDi();` sits between `Hive.initFlutter()` and `runApp(const MyApp())` with no surrounding try/catch and no `runZonedGuarded` (main body, main.dart:39-106).

### Correction to the original claim

One qualifier on the second half: both migrations are `for (final key in ...) { final plain = prefs.getString(key); if (plain == null) continue; await secure.write(...); }`, so a fresh install or an already-migrated install never reaches the write and cannot throw there. The startup crash requires an install that still holds a legacy plaintext key AND a failing keyring — real, but not every broken-keyring device. The silent-degradation half of the claim is unqualified and correct.

### User impact

On a machine whose keyring is locked or unavailable, the terminal either presents itself as brand-new and un-provisioned with no error explaining why (the cashier's cached PINs and brand binding simply appear gone), or, on an install upgrading from the plaintext era, fails to start at all with no message.

---

## `A2` — Over-broad 4xx classification silently purges cached PINs

**Area:** Auth, session & startup  
**First pass:** PARTIAL / CRITICAL  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  
**Origin:** introduced or touched by changes made in this session  

### Evidence

failure.dart:166-170 `bool get isDefiniteAuthRejection => this is ValidationFailure || this is UnauthorizedFailure || this is NotFoundFailure || this is MessageFailure;`.
dio_exception_handler.dart:39-58 — `if (statusCode >= 400 && statusCode < 500 && data is Map<String,dynamic>) { if (data['error'] != null) return MessageFailure(...); }` then `case 400: case 422: return const ValidationFailure(); case 401: return const UnauthorizedFailure(); case 404: return const NotFoundFailure();`. So 400/401/404/422 and any 4xx with an `error` body are "definite".
The backend populates `error` on every 4xx from this endpoint: back/app/internal/model/response.go:82-89 `NewErrorResponse` sets `Error: errorDetails`, used by handler/auth.go:76-97 for all 400s and the 401.
Silent path 1 — login_pin_cubit.dart:73-86 serves the cached PIN then calls `_revalidateInBackground(...)`; :169-205 `unawaited(() async { final result = await _loginUsecase.call(LoginRequestModel(brandId: brandId, password: password, pincode: pincode)); ... if (failure.isDefiniteAuthRejection) { await _offlineCache.removeForPin(brandId, pincode); } } catch (_) {} }())`.
Silent path 2 — auth_datasource.dart:102-108 `final cached = await _offlineAuthCache.getForPin(...); if (cached != null) { _revalidateInBackground(brandIdToken, pincode); return Right(...); }` and :174-205 `unawaited(... on DioException catch (exception) { if (handleDioException(exception).isDefiniteAuthRejection) { await _offlineAuthCache.removeForPin(brandIdToken.brandId, pincode); } }`. Its callers are real: manager_pincode_dialog.dart:33-46 `requireManagerPincode` → close_shift_screen.dart:1901, w_shift_bottom.dart:63, order_side_bar_widget.dart:770, bill_detail_panel.dart:32.
Both re-post the STORED brand password (`brandIdTokenPair.password` / `brandIdToken.password`), and that password is never verified: login_repository_impl.dart:37-47 `loginWithBrandId` only does `await _tokenStorage.writeBrandIdToken(req); ... return const Right(true);` — no network call at all, so AuthCubit's `isDefiniteAuthRejection` branch on that call (auth_cubit.dart:77) is unreachable.
BASE_URL is live-switchable and was just switched: constants.dart:2 `const BASE_URL = 'https://api.maryaidev.uz/';` (commit 4d33ddc "Point the app and its docs at the dev backend").

### Correction to the original claim

Two details are wrong. (1) "A mistyped brand password at provisioning produces the same silent purge" is FALSE. A PIN only enters the cache after a 200 (auth_datasource.dart:133-140 `saveForPin` sits after the successful `_client.post`), so with a wrong brand password nothing is ever cached, `getForPin` misses, and the cashier gets a normal visible ERROR on the PIN screen (login_pin_cubit.dart:112-116) — there is nothing to purge. The real variant of this scenario is a brand/role password ROTATED server-side after PINs were already cached; then every background revalidation 401s or gets an `error` body and purges. (2) "with no user-visible signal" is overstated: dio_interceptor.dart:98-107 shows a global toast for any 4xx except 401 (`showApiErrorOverlayIfPossible(msg)` → api_error_overlay.dart:10-17 `showErrorMessage(ctx, trimmed, duration: 6)`), so a 400/404/422 purge is accompanied by a toast — the toast just does not say a credential was destroyed, and the purge itself is unattributed. Two more precisions in the app's favour: a 429 from the login rate limiter (back/app/internal/middleware/middleware.go:59-76, body `ErrorResponse{Message}` with json tag `message`, auth.go:71-73) is NOT classified as definite — no `error` key and 429 is not in the switch, so it falls to `UnknownFailure`; and a 401 on these background calls does not reach the purge at all, because it carries an Authorization header and is swallowed by the interceptor's refresh/retry loop (see A5) instead.

### User impact

A backend deploy that adds a required field (400/422) or a build shipped against the wrong BASE_URL (404) makes each terminal's first cache-served login or manager prompt silently delete that cashier's offline PIN. The current login still succeeds, so nobody notices; the NEXT login has no cached answer and must reach a server that rejects it — the cashier is locked out both online and offline, one cashier at a time across the fleet, and the only remedy is the brand provisioning credential.

### Second reader

MECHANISM EXISTS (as quoted):
- lib/core/error/failure.dart:166-170 — `bool get isDefiniteAuthRejection => this is ValidationFailure || this is UnauthorizedFailure || this is NotFoundFailure || this is MessageFailure;`
- lib/core/api/dio_exception_handler.dart:39-43 — `if (statusCode >= 400 && statusCode < 500 && data is Map<String, dynamic>) { if (data['error'] != null) { return MessageFailure(data['error'].toString()); } }`, then :46-57 `case 400: case 422: return const ValidationFailure(); case 401: ... case 404: return const NotFoundFailure();`. So every 4xx from this endpoint classifies as "definite".
- Backend confirmed: back/app/internal/model/response.go:82-89 `NewErrorResponse` sets `Error: errorDetails`; back/app/internal/handler/auth.go:75,79,87,92,96-100 use it for all four 400s and the 401 — `error` is always non-nil.
- Purge sites: lib/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart:191-198 and lib/features/view/auth/data/data_sources/auth_datasource.dart:198-201 `if (handleDioException(exception).isDefiniteAuthRejection) { await _offlineAuthCache.removeForPin(...); }`.
- Callers of the second path are real: verify_manager_pincode_usecase.dart:13 -> login_repository_impl.dart:84-85 -> auth_datasource.dart:87; requireManagerPincode used at close_shift_screen.dart:1901, w_shift_bottom.dart:63, order_side_bar_widget.dart:770, bill_detail_panel.dart:32.
- login_repository_impl.dart:38-50 `loginWithBrandId` really is storage-only (`await _tokenStorage.writeBrandIdToken(req); return const Right(true);`) — no network call, so auth_cubit.dart:77's `isDefiniteAuthRejection` branch is indeed unreachable.

WHAT REFUTES THE FINDING — the guard elsewhere the first verifier missed: dio_client.dart:52 `_dio.interceptors.add(MySmartDioInterceptor(_dio, _tokenStorage));` puts every one of these calls through dio_interceptor.dart, and that interceptor makes both "silent" paths loud.
  (1) Non-401 4xx (the 400/422/404 scenarios the claim leads with): dio_interceptor.dart:96-107 `if (resp != null && sc != null && sc >= 400 && sc != 401 && !err.requestOptions.path.endsWith(ListAPI.refresh)) { var msg = messageFromDioErrorData(resp.data); if (msg.isEmpty) { msg = _fallbackMessageForStatus(sc); } showApiErrorOverlayIfPossible(msg); }`. `_fallbackMessageForStatus` (dio_interceptor.dart:166-178) returns non-empty text for 400/404/422, and api_error_overlay.dart:10-17 -> flush_bars.dart:69-81 renders a real 6-second overlay toast. The background revalidation therefore shows the cashier an on-screen error.
  (2) 401: the request DOES carry an Authorization header — login_pin_cubit.dart:75 `await _enterSession(...)` writes the token pair (line 137-141) BEFORE line 81 calls `_revalidateInBackground`, and the manager-PIN path runs mid-session; dio_interceptor.dart:19-32 `onRequest` adds `Bearer` whenever a token exists. So dio_interceptor.dart:60-64's `if (!hasAuthHeader && !isRefreshCall) return handler.next(err);` escape does NOT apply, and control reaches :72-84 refresh-then-`_dio.fetch` retry; the retried login-pincode 401s again, throwing into `catch (e) { await _logoutAndRedirectToLogin(); return handler.next(err); }` — dio_interceptor.dart:145-162 `deleteUserSession()` + `Navigator.pushNamedAndRemoveUntil(..., AppRoutes.loginPinScreen, (route) => false)`. The cashier is ejected to the PIN screen mid-order.

SECOND PILLAR REFUTED: the "password is never verified" argument does not carry the weight given it. A per-PIN cache entry is written ONLY inside the 200 branch — auth_datasource.dart:53-69 `final user = model.user; if (user != null) { await _offlineAuthCache.saveUser(...); await _offlineAuthCache.saveForPin(...); }` and :128-140. So a cache entry can only exist because the server already accepted that exact brandId+password+pincode triple online. A wrong stored password cannot produce a cached PIN to purge.

REMEDY CLAIM WRONG: offline_auth_cache.dart:178-182 `removeForPin` deletes only `'${brandId}_$pincode'`, and after the purge the next PIN login takes login_pin_cubit.dart:100-106's online path. Re-entering the brand credential does nothing for it — `loginWithBrandId` never touches the network (login_repository_impl.dart:38-50) — so the only actual remedy is a working server, not "the brand provisioning credential".

**Second reader's correction:** IN_FLIGHT / UNCOMMITTED: both cited `_revalidateInBackground` methods exist only in the dirty working tree. `git grep` of HEAD finds neither — `git show HEAD:.../login_pin_cubit.dart | grep -n 'revalidate\|unawaited'` and the same for auth_datasource.dart both return nothing. In committed code the purge sits on the FOREGROUND online-first path and is immediately followed by `emit(state.copyWith(failure: failure, status: Status.ERROR, pin: ''))`, i.e. already user-visible. The entire 'silent' premise is a property of unpushed edits. (These two files are outside the file list given for the concurrent session, but they are uncommitted in the same tree.)

WRONG IN DETAIL #1 — 'silently delete' / 'nobody notices' / 'the current login still succeeds, so nobody notices' is refuted. Every trigger produces a visible signal: a 6s error toast for 400/422/404 (dio_interceptor.dart:96-107), and for 401 a forced `deleteUserSession()` + redirect to the PIN screen (dio_interceptor.dart:72-84, 145-162). The doc comment at login_pin_cubit.dart:173-175 claiming it 'never touches the running session — a cashier is not thrown out mid-order' is factually false because of that interceptor — the real defect here is the opposite of silence.

WRONG IN DETAIL #2 — 'that password is never verified' is misleading. Only a previously server-accepted brandId+password+pincode triple ever produces a cache entry (auth_datasource.dart:53-69). The realistic 401 trigger is an admin rotating the brand role password or deactivating the cashier — which is the revocation this mechanism is deliberately for, not a false positive.

WRONG IN DETAIL #3 — the stated remedy ('the brand provisioning credential') does not work; brand login is storage-only.

SEVERITY DOWNGRADED CRITICAL -> MEDIUM. The genuine residual defect is narrow: the over-broad classification means a backend that 4xx's this one endpoint (bad deploy, wrong BASE_URL build) burns the offline grace period one PIN at a time. But that state already means online login is broken fleet-wide, the cashier sees an error or a forced logout when it happens, and the 401 case is intended behaviour.

**Second reader's impact assessment:** Narrow and visible, not silent. If the backend starts returning 400/422/404 on POST api/v1/auth/login-pincode (a bad deploy or a build shipped against a wrong BASE_URL), each cache-served PIN login or manager-PIN prompt purges that one cashier's offline PIN — costing them the ability to log in later when the terminal goes offline — but the cashier sees an error toast at the moment it happens. On a 401 (brand role password rotated, cashier deactivated) the cashier is force-logged-out and bounced to the PIN screen mid-order, which is disruptive but is the intended revocation path. Recovery requires the server to answer correctly again; re-provisioning the brand credential does not restore the PIN.

---

## `A4` — Refresh-failure cascade evicts the cashier mid-order

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

First half — dio_interceptor.dart:19-37 `onRequest` attaches `options.headers['Authorization'] = 'Bearer ${tokenPair.accessToken}'` to every request when a token exists; :51-66 `if (statusCode == 401) { ... final bool hasAuthHeader = authHeader != null && authHeader.isNotEmpty && authHeader != 'Bearer '; if (!hasAuthHeader && !isRefreshCall) { return handler.next(err); }` — so any 401 on a request carrying the header proceeds; :68-71 `if (isRefreshCall) { await _logoutAndRedirectToLogin(); return handler.next(err); }`; :83-86 `catch (e) { debugPrint('Refresh failed: $e'); await _logoutAndRedirectToLogin(); return handler.next(err); }`; :153-163 `Future<void> _logoutAndRedirectToLogin() async { await _tokenStorage.deleteUserSession(); Navigator.pushNamedAndRemoveUntil(navigatorKey.currentState!.context, AppRoutes.loginPinScreen, (route) => false); }` — whole stack replaced, no check for an order in progress. The refresh POST itself goes through the same interceptor (dio_client.dart:52 `_dio.interceptors.add(MySmartDioInterceptor(_dio, _tokenStorage))`, interceptor :128-132 `_dio.post(ListAPI.refresh, ...)`), and `ListAPI.refresh = "api/v1/auth/refresh"` (list_api.dart:6) makes `path.endsWith(ListAPI.refresh)` true, so a 401 on refresh logs out from the nested onError AND again from the outer catch via the rethrow at :148-149.
Second half — grepping the whole tree, the only `exp`-checking helper is jwt_utils.dart:8-24 `bool isJwtExpired(String token)`, and its ONLY call site is lan_hub_service.dart:223 `return !isJwtExpired(token);` (the LAN follower-auth check). Nothing on the auth path calls it: login_pin_cubit.dart:73-86 serves a cached PIN with no token inspection, user_bloc.dart:49-52 goes straight to the cache when offline, and `cash_register_id` is pulled from the raw payload with no exp check — login_data_scope_service.dart:74-88 `_jwtClaim` (base64 decode of `parts[1]`, `return v.toString()`) used at :109 `_jwtClaim(token, 'cash_register_id') ?? ''`, duplicated at shift_bloc.dart:95-115 `return _jwtClaim(token, 'cash_register_id') ?? '';`. Offline, non-GET requests never even reach the network (dio_client.dart:214-227 `_OfflineInterceptor` rejects with `DioExceptionType.connectionError`), so no 401 can be produced while offline.

### Correction to the original claim

None — both halves hold as stated. Worth adding for completeness: the logout here is `deleteUserSession()`, not `deleteAll()`, so the offline PIN cache and the brand credential survive and the cashier can get back in by re-entering their PIN — which is why this is a mid-order disruption rather than a lockout. The failure mode the two halves combine into is the reconnect: an access token that expired during a long offline stretch 401s on the first request back online, and if the refresh token has also aged out, the refresh 401s and the session is cleared mid-order.

### User impact

A cashier with a half-built order is thrown to the PIN screen with the whole navigation stack removed the moment a refresh fails — typically on the first request after coming back online with stale tokens. They re-enter their PIN and continue, so it is disruptive rather than fatal. The second half is good news, correctly stated: days offline do not by themselves lock anyone out.

---

## `A6` — A brand switch wipes replica and outbox before checking reachability

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/services/auth/login_data_scope_service.dart:120-146 — `if (brandChanged) { ... await _storage.setPosInitialized(false); }` then `if (brandChanged || firstTime) { _pendingReset = brandChanged; return LoginDataScope.initialSetup; }`. lib/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart:148-163 routes to `AppRoutes.initialSetupScreen`. lib/features/view/auth/presentation/pages/initial_setup/initial_setup_screen.dart:60 `inject<LoginDataScopeService>().runInitialSetup(...)`. login_data_scope_service.dart:176-178 `_pendingReset ? await replication.resetAndBootstrap(...)`. lib/core/sync/replication_service.dart:244-249 — `Future<ReplicationResult> resetAndBootstrap(...) async { _db.clearAll(); return bootstrap(...); }` — clearAll IS the first statement, before any request. lib/core/db/local_database.dart:762-781 `clearAll()` deletes every replicated table AND `for (final table in LocalTables.all) _db.execute('DELETE FROM $table')`; lib/core/db/entity_registry.dart:227-235 `all = {meta, outbox, pending, tableStatus, provisional, tableTimers, images}` — so `_outbox`, `_pending`, `_table_status`, `_table_timers` all go. The refill is a POST (lib/core/sync/sync_api_client.dart:76 `_client.post(pullPath, ...)`) which lib/core/api/dio_client.dart:214-227 rejects outright while offline, so drain returns `failed` and nothing is refilled. AuthCubit.logoutFromApp: lib/features/view/auth/presentation/cubit/auth/auth_cubit.dart:115-141 calls `inject<replica.LocalDatabase>().clearAll()` unconditionally on the success branch; `grep -rn logoutFromApp lib/` returns only the declaration plus LoginPinCubit's own same-named method (login_pin_cubit.dart:247) which is what login_pin_screen.dart:61 calls (`cubit` there is `context.read<LoginPinCubit>()`, login_pin_screen.dart:36). AuthCubit's version has zero call sites.

### Correction to the original claim

Two scoping points the claim omits. (1) The wipe is not conditional on being offline at all — it also lands when the server answers 5xx, so "before finding out whether the network is reachable" is right and is the real defect; the purely-offline variant is narrower than implied because it additionally requires a PIN already cached for the *target* brand (login_pin_cubit.dart:73-98: a cache miss offline returns ConnectionFailure and `onSuccessfulLogin` is never reached), and the PIN-screen Logout button clears that cache (`deleteAll()` → `_secure.deleteAll()`, token_storage_impl.dart:247-250). (2) Related and worse than the claim states: after that same Logout, `lastAuthContext` is gone, so `last == null` → `brandChanged` is false → `_pendingReset` stays false → the next brand's bootstrap runs with NO wipe and merges into the previous tenant's rows. AuthCubit.logoutFromApp having no call site is confirmed exactly as claimed.

### User impact

A cashier switching the terminal to another brand loses the outbox — unsent orders and payments queued for the brand being left — plus live table occupancy and running table timers, and if the pull then fails (server down or no uplink) the terminal is left with an empty database and a "Setup failed" screen.

---

## `A7` — The LAN hub rejects followers whose access token has expired

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/services/lan_hub/lan_hub_service.dart:201-224 — `_validateIncomingAuth` does the cloud round trip only `if (_connectivity.isOnline)`, and every other path ends at line 223 `return !isJwtExpired(token);`. lib/core/utils/jwt_utils.dart:8-25 — every failure branch returns true (`parts.length < 2`, non-Map payload, non-num `exp`, and `catch (_) { return true; }`), so a parse error is "expired" and the caller rejects. Wired as the server's gate: lan_hub_service.dart:98 `authValidator: _validateIncomingAuth` → lib/core/services/lan_hub/lan_hub_server.dart:123 `final ok = await (_authValidator?.call(...`. The follower presents its stored access token: lan_hub_service.dart:189-193 `_readOwnCredentials` reads `_tokenStorage.readAccessToken()`, passed at line 128 `_client.connect(ip, getCredentials: _readOwnCredentials)`. Backend TTL: back/app/internal/config/config.yml:90 `expires-in: 86400` (24h) for the access token, back/app/internal/service/auth.go:121 `time.Duration(jwtCfg.AccessToken.ExpiresIn)*time.Second`, back/app/pkg/utils/auth.go:80 `claims["exp"] = now.Add(ttl).Unix()`. Nothing refreshes a token without the uplink — the only refresh is the 401 path in lib/core/api/dio_interceptor.dart:120-151, which is itself a network call.

### Correction to the original claim

Nothing material wrong. Worth making concrete: the horizon is 24 hours of access-token life, and rejection also happens when the LEADER has an uplink — the leader's `verifyDio.get(ListAPI.user)` with the follower's expired token gets a 401, which throws, and the catch at lan_hub_service.dart:217-221 falls through to the same `!isJwtExpired(token)`. So it is not only the no-uplink case.

### User impact

A venue whose internet has been down for more than a day: terminals whose tokens have aged out can no longer join the LAN hub, so peer replication and print relay stop — orders opened on one terminal are invisible on the others and kitchen tickets stop being relayed — and it cannot be fixed on site until the uplink returns.

---

## `A8` — The connectivity probe raises an error toast every 20 seconds

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/services/connectivity/connectivity_cubit.dart:22 `_probeInterval = Duration(seconds: 20)`; :33-35 `Timer.periodic(_probeInterval, (_) { if (_linkUp) unawaited(_probe()); })` — gated on the OS link, not on reachability, so it keeps firing after the state has gone false; :66-73 `client.dio.get('', options: Options(sendTimeout:..., receiveTimeout:..., validateStatus: (_) => true))` goes through the full interceptor stack (dio_client.dart:52-54). lib/core/api/dio_client.dart:212-227 `_readMethods = {'GET','HEAD'}` and the reject only fires for non-read methods, so the probe GET is permitted while offline and reaches transport. lib/core/api/dio_interceptor.dart:108-114 — `else if (resp == null && !err.requestOptions.path.endsWith(ListAPI.refresh))` → `showApiErrorOverlayIfPossible(fallback)`; the probe's path is `''`, so the only exclusion (refresh) does not apply. dio 5.9.1 maps a failed connect to `connectionError`/`connectionTimeout` (~/.pub-cache/hosted/pub.dev/dio-5.9.1/lib/src/adapters/io_adapter.dart:125,131), and dio_interceptor.dart:181-195 returns a non-empty string for exactly those types. lib/core/api/api_error_overlay.dart:16 `showErrorMessage(ctx, trimmed, duration: 6)` → lib/core/components/flush_bars.dart:69-80 `autoDismissMs: duration * 1000`. Grepping the tree, `showApiErrorOverlayIfPossible` has exactly two call sites, both in dio_interceptor.dart, neither with a probe carve-out.

### Correction to the original claim

One detail: the probe overrides only `sendTimeout`/`receiveTimeout` (5s) and inherits `connectTimeout: 30s` from dio_client.dart:40, so a probe that hangs on connect outlives its own interval — probes overlap rather than serialise. The 20s cadence of toasts is right; the individual probe can take 30s.

### User impact

In the exact deployment this offline work exists for — venue LAN up, internet down — a red 6-second error toast appears over the order screen every 20 seconds for the whole outage, covering UI and training cashiers to dismiss real errors.

---

## `A9` — Un-provisioned terminals hit the setup screen on every login

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

lib/core/services/auth/login_data_scope_service.dart:112 `final firstTime = last == null || !_storage.isPosInitialized;` and :139 `if (brandChanged || firstTime) { ... return LoginDataScope.initialSetup; }`. `grep -rn 'setPosInitialized' lib/` gives exactly two writers: login_data_scope_service.dart:131 (sets it FALSE on a brand switch) and :195 `await _storage.setPosInitialized(true);`, reached only under :194 `if (result.outcome == ReplicationOutcome.caughtUp && filled)` inside `runInitialSetup`. The former writer at login time is gone and documented as such: lib/features/view/auth/data/repositories/login_repository_impl.dart:41 `// NOT setPosInitialized(true) here anymore`. Offline the pull cannot produce `caughtUp`: sync_api_client.dart:76 uses `_client.post`, and dio_client.dart:216-226 rejects non-GET while offline, so drain hits its catch (replication_service.dart:194-203) and returns `failed`. The screen then shows the failure state (initial_setup_screen.dart:68-75) whose only escape is `_continue()` behind `S.current.strSetupContinueAnyway` (initial_setup_screen.dart:153-161), which navigates away without touching the flag.

### Correction to the original claim

Accurate as written. Worth adding that the flag is in plain SharedPreferences (token_storage_impl.dart:184-190, `posIsInitialized` is not in `_secureKeys`), so it survives a session logout but not the PIN-screen Logout button, which calls `_prefs.clear()` (token_storage_impl.dart:247-250) — that button therefore also re-arms this loop.

### User impact

A terminal provisioned somewhere with no connectivity shows the setup progress screen and then a "Setup failed" screen at every single shift change, and the cashier must press "Continue anyway" each time, until the terminal completes one clean online catch-up.

---

## `C3` — An uncached manager PIN blocks on the network

**Area:** Client reachability  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

lib/features/view/auth/data/data_sources/auth_datasource.dart:110-121 — after the cache miss: `if (!_client.isOnline) { return const Left(ConnectionFailure()); } try { final Response response = await _client.post(ListAPI.loginPinCode, data: LoginRequestModel(...).toJson());`. The dialog genuinely blocks on it: lib/core/widgets/app_pincode_dialog.dart:117-119 `Future<void> _verify() async { setState(() => _verifying = true); final ok = await widget.onConfirm(_pin);` and manager_pincode_dialog.dart:45-47 `onConfirm: (pin) async { final result = await usecase(pin); ...`. Timeouts are 30s connect / 30s receive (lib/core/api/dio_client.dart:40-41).

### Correction to the original claim

None. Worth adding: the wait applies to any PIN with no local answer, which includes a PIN that was previously cached and then purged by a definite rejection (auth_datasource.dart:147), not just a never-used PIN.

### User impact

A manager approving a void/discount/shift action with a PIN this terminal has never seen sits on a spinner in the PIN dialog for as long as the server takes — up to ~30s per timeout on a reachable-but-slow backend, since only hard offline short-circuits.

---

## `C4` — The floor-plan refresh button awaits a full sync pass

**Area:** Client reachability  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Chain: lib/features/view/main/presentation/pages/main/waiter_floor_plan_screen.dart:137-139 `_RefreshButton(loading: state.status == Status.LOADING, onTap: _confirmRefresh)` -> :78-88 `_confirmRefresh` (confirm dialog) -> :73-76 `await context.read<MainCubit>().refreshTables(force: true);` -> lib/features/view/main/presentation/cubit/main/main_cubit.dart:126 `Future<void> refreshTables({bool force = false}) => getHalls(force: force);` -> :116-120 `if (force) { await inject<SyncEngine>().tick(force: true); }`. tick (lib/core/sync/sync_engine.dart:213, 257-263): `if (force) _outboxStore.clearBackoff(); await _outbox.drain(); await _replication.drain(); await _fillFeedGaps();`. _fillFeedGaps:324-327 `await _hydrateTableTimers(); await _hydrateMenuImages();`. Timer GET per table :347-370 (`final raw = await repo.getOrderTableTimer(orderId)` -> main_datasources.dart:845 `await _client.get(ListAPI.orderTableTimer(orderId))`). Sequential image loop :391-408 `for (final ref in refs) { final bytes = await MinioService.instance.getImageByObjectName(ref); ...` with no failure memo — only `have = db.cachedImageNames()` is skipped. MinioService drops its memo on failure: lib/core/service/minio/minio_service.dart:74-82 `if (bytes == null) { _imageFutureByObjectName.remove(key); } ... catch (_) { _imageFutureByObjectName.remove(key); return null; }`. 60s clock: sync_engine.dart:73 `static const tickInterval = Duration(seconds: 60);` and :136 `_ticker ??= Timer.periodic(tickInterval, (_) => tick());`.

### Correction to the original claim

Three details, one of which makes it worse. (1) '_full_ replication pull' is loose — `_replication.drain()` is an incremental cursor drain, not a full refetch. (2) The timer GET is not 'per busy time-based table' unconditionally: only tables that are busy AND time_based AND have a live order AND are not outbox-shielded (sync_engine.dart:347-364). (3) Worse than claimed: a permanently-missing blob returns HTTP 404 from the backend (back/app/internal/handler/minio.go:58-62 `echo.NewHTTPError(http.StatusNotFound, "file_not_found")`), which DioClient.post turns into a DioException with a response, so MySmartDioInterceptor's toast branch fires (lib/core/api/dio_interceptor.dart:98-107, message "Ma'lumot topilmadi (404).") — a user-visible error toast every 60 seconds, forever, while online. Also: MainCubit.getHalls never emits Status.LOADING (main_cubit.dart has no LOADING emit; only :36/:39/:51/:130/:142), so `_RefreshButton(loading: ...)` never spins for a manual refresh — the awaited pass is invisible. Mitigation the claim omits: `if (_tickRunning) return;` (sync_engine.dart:214) makes a refresh during a running tick a no-op.

### User impact

Tapping refresh on the floor plan silently awaits an outbox drain, a cursor pull, one GET per busy time-based table and a serial download of every menu image the replica lacks — with no spinner and no way to tell it is running. Any menu row whose picture_url no longer resolves in MinIO re-fires every 60s tick and every manual refresh forever, and each failure pops a '404' error toast over whatever screen the cashier is on.

---

## `C6` — The api.dart barrel is a hole through both architecture guards

**Area:** Client reachability  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

lib/core/api/api.dart:1-8 re-exports `dio_client.dart`, `dio_interceptor.dart`, `list_api.dart`, `dart:async`, `dart:io`, constants, `package:dio/dio.dart`, `package:flutter/material.dart`. Guard regex 1, test/architecture_guard_test.dart:174-177: `RegExp(r"^\s*import\s+'package:(dio|http|minio|connectivity)", multiLine: true)`. Guard regex 2, :235-239: `RegExp(r"^\s*import\s+'(?:package:mary_ai_pos/|[./]+)(?:core/)?(?:api/(?:dio_client|list_api)|service/minio/minio_service)\.dart'|^\s*import\s+'package:cached_network_image", multiLine: true)`. Both require `import`, and neither alternation contains `api/api`. I ran both regexes against the synthetic source `import 'package:mary_ai_pos/core/api/api.dart';` + `inject<DioClient>().post(ListAPI.login);` — rule1 False, rule2 False. api.dart itself escapes for the same reason (it uses `export`, not `import`, so it is not even on either allowlist). I ran the suite: `flutter test test/architecture_guard_test.dart` — 11/11 green today with those importers in place.

### Correction to the original claim

The count is off by one and the claim understates the barrel: there are 17 importers, not ~16 (all in lib/, none in test/), and the '14 in presentation' figure is exactly right. The barrel also re-exports dio_interceptor.dart, flutter/material, constants, dart:async and dart:io. Also worth naming: the third test ('no feature-layer file speaks HTTP', :245-255) reuses regex 1, so it misses the barrel too — three checks, not two.

### User impact

A developer can add `inject<DioClient>().post(ListAPI.x)` to any of the 14 presentation files that already import the barrel, with no new import line, and all three architecture ratchets stay green — reintroducing exactly the await-on-the-network-in-a-screen defect the guard exists to prevent.

---

## `C7` — The offline suite is structurally blind to POST traffic

**Area:** Client reachability  
**First pass:** PARTIAL / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Mechanism confirmed: test/support/offline_app_harness.dart:195 `FakeConnectivityPlatform.install(initial: const [ConnectivityResult.none]);` and no test in test/offline_screen_suite_test.dart ever flips it back (grep for ConnectivityResult/FakeConnectivityPlatform in that file returns nothing). lib/core/api/dio_client.dart:208-227 — `_OfflineInterceptor` is registered first (:52-54, before MySmartDioInterceptor) and `if (!_connectivity.isOnline && !_readMethods.contains(options.method.toUpperCase())) { handler.reject(DioException(...), true); return; }` with `_readMethods = {'GET','HEAD'}`. That rejection is pre-transport, so DeadNetworkAdapter.fetch (offline_app_harness.dart:80-95, `requests.add(options)`) never sees it, and kScreenNetworkReach/kActionNetworkReach (offline_screen_suite_test.dart:70, 189, both `{}`) read only `app.network.paths`. WRONG PARTS: (a) non-GET UI-reachable calls are not all POSTs — printers_controller.dart:40/44 reaches main_datasources.dart:955/957 (`_client.post` / `_client.put`) and :971 (`await _client.delete('${ListAPI.printerSettings}/$id')`); (b) GET-backed backend reads still exist in quantity — 26 `_client.get`/`_client.dio.get` sites in lib/features/view/main/data/data_source/main_datasources.dart (e.g. :467 `_client.get(ListAPI.user)`, :845 `_client.get(ListAPI.orderTableTimer(orderId))`, :274 printerSettings) — and a GET passes _OfflineInterceptor untouched, so DeadNetworkAdapter WOULD record it; (c) MinioService's primary image path is `_client.post(ListAPI.mediaImage, ...)` on the injected DioClient (minio_service.dart:12, 61-66), whose adapter IS replaced by the harness (lib/di.dart:282-283 `if (adapterOverride != null) dioClient.dio.httpClientAdapter = adapterOverride;`); the second Dio (minio_service.dart:17-26 `_externalHttp`) is used only when the key is a full http(s) URL (:52-56 `_isExternalUrl`).

### Correction to the original claim

The conclusion (the two ratchets are empty for a reason unrelated to the code being clean) is right, but the stated reason is wrong in a way that matters. The ratchets are NOT structurally blind: a new GET added to a screen or a user action would be recorded and would fail them. They read empty today because the surviving GET callers are themselves isOnline-gated and so never fire under an offline boot — SyncEngine.tick returns at sync_engine.dart:256 `if (!_connectivity.isOnline) return;` before _hydrateTableTimers, and UserBloc._getUser bails to cache at user_bloc.dart:49-52 before the GET /user (which is only ever dispatched from SyncEngine:311 anyway). Second correction: MinioService's second Dio is the exception path, not the norm — the normal minio-key fetch does go through the overridden adapter (and is then blocked earlier still, being a POST). Third: this is not an undiscovered hole — offline_screen_suite_test.dart:72-88 documents the POST short-circuit explicitly.

### User impact

'Every screen renders offline' and 'no user action touches the wire' are proved only for GET traffic. A regression that makes a screen await a POST/PUT/DELETE — which is what every write and most reads in this app are — passes the offline suite silently, so a cashier could hit an await-on-network freeze that CI reported as green.

---

## `C8` — Rendering an uncached image offline raises a connection-error toast

**Area:** Client reachability  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/media/local_image_cache.dart:88-97 — `LocalImage state(String key) { final cached = _read(key); ... unawaited(_fetchOnce(key)); return (status: ImageStatus.loading, bytes: null); }` with no connectivity check anywhere in the file. Wired to the network at lib/di.dart:490-497 `LocalImageCache(... fetch: MinioService.instance.getImageByObjectName)`, which for a minio key does `await _client.post(ListAPI.mediaImage, ...)` (minio_service.dart:61-66). Offline that hits dio_client.dart:216-224 `handler.reject(DioException(... type: DioExceptionType.connectionError ...), true)` — the `true` is callFollowingErrorInterceptor, and dio 5.9.1's interceptor.dart:81-92 confirms following error interceptors then run. MySmartDioInterceptor.onError, lib/core/api/dio_interceptor.dart:108-115: `} else if (resp == null && !err.requestOptions.path.endsWith(ListAPI.refresh)) { final fallback = _fallbackMessageForDioType(err.type); if (fallback.isNotEmpty) { showApiErrorOverlayIfPossible(fallback); } }` with :187-188 `case DioExceptionType.connectionError: return "Server bilan ulanib bo'lmadi. Internetni tekshiring.";`. Consumers that render grids: custom_network_image.dart:53 and menu_manage_screen.dart:2111.

### Correction to the original claim

One refinement that bounds it and one that widens it. Bounding: it is once per key per PROCESS, not per render — _fetchOnce memoizes failures in `_unavailable` (local_image_cache.dart:100-115), and `forgetFailures()` (:121) has zero production callers (grep finds it only in test/local_image_cache_test.dart:159), so the failed key never retries until app restart. Widening: the toast controller has no dedupe — flush_bars.dart:234-235 `_currentState?.dismiss();` then inserts a new entry — so N uncached images produce N sequential toasts rather than one. Does not apply to a picture_url that is a full http(s) URL: that path uses MinioService._externalHttp, which has no interceptors.

### User impact

A cashier opening the menu on an offline terminal that has not yet cached its images gets a burst of red 'Server bilan ulanib bo'lmadi. Internetni tekshiring.' toasts — one per uncached meal, each replacing the last — over a screen that is otherwise working correctly from the replica.

---

## `L2a` — No LAN backfill — a briefly disconnected follower permanently misses rows

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  

### Evidence

No backfill request exists in the protocol: lib/core/services/lan_hub/lan_hub_message.dart:3-21 is the complete enum — `tableStatus, ping, auth, authOk, authFail, relayOp, relayOpResult, printJobAnnounce, printJobClaim, printJobResult, leaseRequest, leaseGranted, leaseRejected, leaseRelease, changeFeed, localChange, timerAction`. No "pull since cursor" verb, and `changeFeed` is one-directional by construction (lan_hub_service.dart:390-394 `if (mode != LanMode.server) return;`).
Gap handling: lib/core/sync/change_feed_relay.dart:61-64 `final gap = fromCursor > _db.syncCursor; if (gap) _needsBackfill = true; return _applier.applyPullResponse(decoded, advanceCursor: !gap);` — rows apply, cursor held.
Only clearer: `grep -rn "backfillDone" lib/` → exactly two lib hits, the definition (change_feed_relay.dart:46 `void backfillDone() => _needsBackfill = false;`) and lib/core/sync/sync_engine.dart:244-249, inside the client-mode branch and inside `if (_connectivity.isOnline)` (line 229):
```
if (_feed.needsBackfill) {
  final result = await _replication.drain();
  if (result.outcome == ReplicationOutcome.caughtUp) { _feed.backfillDone(); }
}
```
`_replication.drain()` goes to `SyncApi.pull` and the only implementation in lib is `SyncApiClient implements SyncApi` (lib/core/sync/sync_api_client.dart:54) doing `_client.post('/api/v1/sync/pull', ...)` (lines 63, 76). The only other `implements SyncApi` in the tree is test/replication_service_test.dart:15 `FakeSyncApi`.
Note `hydrateNow()` (sync_engine.dart:283-292) also drains replication but never calls `backfillDone()`, so it does not clear the flag either.

### Correction to the original claim

Accurate as stated. One precision: the follower is not frozen — it keeps applying later `changeFeed` batches (rows land, cursor stays put) and keeps receiving peer `localChange`/`timerAction` frames, so the venue's *live* writes still show up. What is unrecoverable without its own uplink is specifically the rows that changed during the disconnect window and never change again. The comment at sync_engine.dart:238-241 states the reason outright: "the leader cannot replay its change log, it keeps current rows, not history."

### User impact

A follower that drops its hub link for a minute (app restart, WiFi blip, leader restart) and has no internet of its own permanently misses every row the leader pulled in that window — a menu price change, a hall/table added, a user deactivated, an order closed on another terminal. It shows a green 'connected' LAN state the whole time, so the cashier has no signal that their screen is wrong, and the only fix in the shipped code is giving that terminal internet.

### Second reader

MECHANISM — I could not break it, it reproduces exactly:

1. Protocol has no pull/backfill verb. lib/core/services/lan_hub/lan_hub_message.dart:3-20 is the complete enum (tableStatus…timerAction); no 'pull since cursor'. The feed is one-directional by construction: lan_hub_service.dart:390-394 `void broadcastChangeFeed({...}) { if (mode != LanMode.server) return; if (_server.clientCount == 0) return;` and the receive side is follower-only, lan_hub_service.dart:303-311 `case LanHubMessageType.changeFeed: if (mode == LanMode.client && ...) inject<ChangeFeedRelay>().apply(...)`.

2. Gap held, not filled. lib/core/sync/change_feed_relay.dart:61-64 `final gap = fromCursor > _db.syncCursor; if (gap) _needsBackfill = true; return _applier.applyPullResponse(decoded, advanceCursor: !gap);` and lib/core/db/apply_change.dart:158-164 `if (cursor is num && advanceCursor) { ... if (next > _db.syncCursor) _db.syncCursor = next; }` — rows apply, cursor frozen.

3. Wiring is live, not dead. lib/di.dart:341-343 `onBatchApplied: (body, fromCursor) => inject<LanHubService>().broadcastChangeFeed(body: jsonEncode(body), fromCursor: fromCursor)` and lib/core/sync/replication_service.dart:153-159 `final cursor = _db.syncCursor; final page = await _api.pull(...); final stats = _applier.applyPullResponse(page.body); onBatchApplied?.call(page.body, cursor);` — fromCursor is genuinely the leader's pre-apply cursor.

4. Only clearer requires the terminal's own cloud pull. `grep -rn "backfillDone" lib/` → exactly 2 hits: change_feed_relay.dart:46 (definition) and sync_engine.dart:244-249, nested inside `if (_lanHub.mode == LanMode.client)` (line 214) AND `if (_connectivity.isOnline)` (line 229). `_replication.drain()` → SyncApi.pull; `grep -rn "implements SyncApi" lib/ test/` → only sync_api_client.dart:54 SyncApiClient (`/api/v1/sync/pull`) in lib, plus test/replication_service_test.dart:15 FakeSyncApi. No leader-relayed pull exists.

5. No snapshot-on-connect. lan_hub_server.dart auth path sends only `ws.add(LanHubMessage.authOk().toJson())` (line 140); nothing pushes state to a newly-joined client. No manual resync exists either: `grep -rn syncCursor lib/` shows the only writer anywhere is apply_change.dart:162.

6. hydrateNow (sync_engine.dart:283-292) is gated on `if (!_connectivity.isOnline) return;` and is reached only from login_data_scope_service.dart:151,185 — so it is also useless to a WAN-less follower.

WHERE THE CLAIM IS WRONG — the impact narrative:

A. "shows a green 'connected' LAN state the whole time, so the cashier has no signal" is false. A terminal that cannot reach the backend flips ConnectivityCubit false (connectivity_cubit.dart:31-42, and it probes the backend, not the interface — line 10-14 comment plus `_probe()`), which renders a persistent yellow strip: offline_banner.dart:14-16 `height: isOnline ? 0 : 36`, mounted always at app_scaffold.dart:93. While actually off-hub, lan_solo_banner.dart:28 also shows an orange strip. What is missing is a *data-hole* indicator, not all signal.

B. The stated scenario is conjunctive and the second half is not the common case. A gap can only be created by a leader that is successfully pulling from the cloud, i.e. the shared LAN has WAN; any follower whose own backend reachability works self-heals on the very next tick (≤60s, sync_engine.dart:244-249, tickInterval ticker at line 135). Permanent loss needs a follower persistently unable to reach the backend while the leader can — a per-device misconfiguration (no gateway/DNS, MDM/proxy block), not "a WiFi blip" or "app restart".

**Second reader's correction:** Two corrections plus one extension. (1) Impact overstated on visibility: an internet-less follower shows the permanent OfflineBanner (lib/core/widgets/offline_banner.dart:14-16, mounted at lib/core/widgets/app_scaffold.dart:93) — the cashier is told the terminal is offline, just not that its replica has a hole. Also note sync_engine.dart:253 calls `_recordSync()` unconditionally in the client branch, so the settings 'last sync' timestamp does refresh every 60s even when nothing synced — that part of the 'looks healthy' argument holds, the LAN-green part does not. (2) Preconditions overstated: a hub drop alone is harmless — the follower re-detects the gap and, if it can reach the backend at all, clears it within one 60s tick; permanent loss additionally requires that terminal's own backend reachability to be persistently broken while the leader's works. That bounds the blast radius to a misconfigured or deliberately WAN-less follower, hence MEDIUM not HIGH. (3) Extension the claim missed, which broadens the trigger: `fromCursor > _db.syncCursor` (change_feed_relay.dart:61) is not disconnect-specific — it also fires whenever a follower's bootstrap cursor is merely behind the leader's, which is the normal state for terminals that logged in at different times. So needsBackfill is true on most followers most of the time, and the 'follower with no uplink stays current via broadcasts' promise in sync_engine.dart:230-241 is weaker than the comment claims. IN-FLIGHT CAVEAT: the decisive logic lives in change_feed_relay.dart and sync_engine.dart, neither of which is in the other session's edit set, so the verdict does not rest on their work — but two supporting files (lib/core/db/apply_change.dart, lib/core/services/lan_hub/*) are being edited concurrently, so the `advanceCursor` handling and the enum could shift under this finding.

**Second reader's impact assessment:** On a follower terminal that can talk to the leader over LAN but cannot reach the backend itself (static IP without a gateway, blocked/proxied device, dead DNS), every row the leader pulled while that terminal was off-hub — or between its own login bootstrap and the moment it joined the hub — is never delivered and never re-requested: a price edited on the manager's terminal, a hall or table added, a deactivated user still able to log in, an order closed elsewhere still showing as busy. It keeps receiving all *newer* broadcasts, so the screen looks alive and only the hole is wrong, and the cashier's only visible cue is the generic yellow 'offline' strip. The only recovery in shipped code is restoring that terminal's own internet.

---

## `L2b` — First-time provisioning is cloud-only

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart:151 `if (scope == LoginDataScope.initialSetup) {` — the branch taken when lib/core/services/auth/login_data_scope_service.dart:139-145 decides `if (brandChanged || firstTime) { ... return LoginDataScope.initialSetup; }`, with `firstTime = last == null || !_storage.isPosInitialized` (line 113).
lib/features/view/auth/presentation/pages/initial_setup/initial_setup_screen.dart:60 `final outcome = await inject<LoginDataScopeService>().runInitialSetup(...)`.
lib/core/services/auth/login_data_scope_service.dart:176-178 `final result = _pendingReset ? await replication.resetAndBootstrap(...) : await replication.bootstrap(onProgress: onProgress);` then line 182 `await _syncEngine.hydrateNow(includeGoods: true);`.
`ReplicationService.bootstrap` → `drain` → `_api.pull` (replication_service.dart:220) → the only lib implementation, `SyncApiClient implements SyncApi` (sync_api_client.dart:54), `_client.post(pullPath...)` with `pullPath = '/api/v1/sync/pull'` (line 63). There is no LAN-backed `SyncApi` anywhere in lib — the doc comment at sync_api_client.dart:46-49 explicitly describes a follower-source implementation as future work ("in Phase 5 a follower's source becomes the leader's LAN relay ... which is then a new implementation of this interface"), and no such class exists.
Failure is terminal for the session: login_data_scope_service.dart:190-197 marks `setPosInitialized(true)` only `if (result.outcome == ReplicationOutcome.caughtUp && filled)`, otherwise returns `InitialSetupOutcome.incomplete`, and initial_setup_screen.dart:68-75 then does `setState(() { _running = false; _failed = true; })` instead of `_continue()` — the operator is parked on the setup screen.

### Correction to the original claim

Correct. Sharpen one point: it is not only 'cannot be provisioned' — the terminal is held on a dedicated full-screen setup/failure page and never reaches the app, because `_continue()` (initial_setup_screen.dart:79) runs only on `InitialSetupOutcome.ready`. Also note `hydrateNow()` (line 182) is itself gated on `if (!_connectivity.isOnline) return;` (sync_engine.dart:284), so the gap-fill half is cloud-only too.

### User impact

A newly deployed till that can see the leader over the LAN but has no internet path of its own cannot be brought into service at all — it sits on the setup screen with a failure state. Provisioning a replacement terminal during an outage is impossible, even with three working tills on the same switch holding a complete replica.

---

## `L3` — Followers contact the cloud on several paths, not just the justified one

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/sync/sync_engine.dart:217-254, client-mode branch:
```
if (_lanHub.mode == LanMode.client) {
  ...
  if (_connectivity.isOnline) {
    if (force) _outboxStore.clearBackoff();
    await _outbox.drain();                       // (a)
    if (_feed.needsBackfill) {                   // (b)
      final result = await _replication.drain();
      if (result.outcome == ReplicationOutcome.caughtUp) { _feed.backfillDone(); }
    }
    await _fillFeedGaps();                       // (c)
    _refreshUserProfile();                       // (d)
  }
  _recordSync();
  return;
}
```
(c) `_fillFeedGaps()` = `_hydrateTableTimers(); _hydrateMenuImages();` (lines 324-327). `_hydrateTableTimers` selects `status == 'busy' && type == 'time_based'` tables (lines 348-352) and per table calls `await repo.getOrderTableTimer(orderId)` (line 367) — one backend request each. `_hydrateMenuImages` loops uncached `goods.picture_url` refs and calls `MinioService.instance.getImageByObjectName(ref)` per ref (lines 396-405).
(d) `_refreshUserProfile()` (lines 303-315) dispatches `inject<UserBloc>().add(const UserEvent.getUser())`.
Triggers: `Timer.periodic(tickInterval, (_) => tick())` with `tickInterval = Duration(seconds: 60)` (lines 73, 136), plus a connectivity-edge and a LAN-reconnect-edge listener (lines 137-142) and a 750ms-debounced `nudge()` (lines 170-181).
Probe: lib/core/services/connectivity/connectivity_cubit.dart:22 `static const _probeInterval = Duration(seconds: 20);` and lines 33-35 `_probeTimer = Timer.periodic(_probeInterval, (_) { if (_linkUp) unawaited(_probe()); });`, with `_probe()` doing `client.dio.get('')` against BASE_URL (lines 66-73). It is constructed unconditionally in lib/di.dart:205-207 and armed unconditionally at di.dart:286 `connectivityCubit.attachProbeClient(dioClient);` — no reference to `LanHubService` or `LanMode` anywhere in the file.

### Correction to the original claim

All four sub-points reproduce. Two details the claim glosses: (d) is throttled to once per 5 minutes, not once per tick — `_profileRefreshInterval = Duration(minutes: 5)` with an early return at sync_engine.dart:304-308 — so it is ~12x cheaper than 'every tick'; and the 20s probe fires only while the OS reports a live link (`if (_linkUp)`, connectivity_cubit.dart:34), so a terminal on a LAN-only switch with no WAN still probes (link is up, probe fails) rather than staying silent. Neither changes the conclusion. Worth adding: the follower branch deliberately does NOT gate `_outbox.drain()` on LAN — the block comment at lines 218-228 concedes the sole-uplink relay is gone and 'a follower's outbox still drains only through this terminal's own connectivity'.

### User impact

The 'one uplink per venue' property the LAN hub was built for does not hold: every terminal independently hits the backend at least every 20s for the reachability probe, and every 60s for a per-open-time-based-table timer GET, Minio image fetches and (5-minutely) a profile GET. On a 6-till venue that is ~6x the intended cloud chatter and 6 sets of credentials that must stay valid against the server; on a metered/flaky link it is 6 devices competing for the same bandwidth instead of one.

---

## `L4` — The LAN op-relay for follower writes is orphaned

**Area:** LAN / leader-follower  
**First pass:** PARTIAL / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  

### Evidence

`LanHubService.relayOperation` — zero callers anywhere. `grep -rn "relayOperation" lib test` returns only the definition (lib/core/services/lan_hub/lan_hub_service.dart:272 `Future<RelayOpResult?> relayOperation(PendingOperation op) async {`) and the doc reference at line 284.
`OfflineQueueService.relayViaLan` (lib/core/services/offline_queue/offline_queue_service.dart:236) — zero *production* callers, but NOT zero callers: test/offline_queue_quarantine_test.dart calls it 7 times (lines 58, 73, 90, 104, 139, 145, 171) and test/full_shift_soak_test.dart:139 drives it on a 30s cadence.
The removal is documented at its former call site: lib/core/sync/sync_engine.dart:218-221 "The legacy queue's `relayViaLan` call used to sit here ... It is gone with the queue's last producer: nothing enqueues a `PendingOperation` any more, so it relayed an empty box."
`PendingOperation` enqueue — one lib caller survives: `OfflineQueueService.retryQuarantined` (offline_queue_service.dart:100-106 `await enqueue(q.toRetryable());`), reachable from the settings UI at lib/features/view/main/presentation/pages/settings/sections/sync_status_section.dart:583 `await inject<OfflineQueueService>().retryQuarantined(widget.op.id);`. And `syncAll` — the thing that would send such an op — has zero production callers either (`grep -rn "syncAll" lib` yields only doc comments plus test/full_shift_soak_test.dart:234).
OutboxDrainer: lib/core/outbox/outbox_drainer.dart:105 `result = await handler.send(op);`, handlers coming from `OutboxExecutors` registered at lib/di.dart:422-433 — `registerUsersOutboxHandlers(..., inject<MainRepository>())`, `...HallsTables...`, `...MenuAdmin...`, `...Transactions...`, `...Branches...`, `registerOrdersOutboxHandlers(outboxExecutors, inject<DioClient>())`, `registerTimerShiftOutboxHandlers`. Every one is HTTP: e.g. lib/core/outbox/orders_outbox.dart:41 `void registerOrdersOutboxHandlers(OutboxExecutors executors, DioClient dio)` → line 59 `await dio.post(ListAPI.orders, data: payload);`. No executor consults `LanHubService`.
And the leader does not adopt a peer's write: lib/core/db/apply_change.dart:334-341 "it does not re-emit ... Note what this deliberately does *not* do — mark the row pending, or enqueue anything", implemented by `applyFromPeer` setting `_fromPeer = true` so `_emitLocalChange` short-circuits (line 107 `if (sink == null || _fromPeer) return;`); nothing in `applyOne`/`applyFromPeer` touches `OutboxStore`.
Follower drain is uplink-gated: sync_engine.dart:229 `if (_connectivity.isOnline)` wrapping line 243 `await _outbox.drain();`.

### Correction to the original claim

PARTIAL on two factual details, CONFIRMED on the conclusion. (1) `relayViaLan` does not have ZERO callers — it has zero *production* callers but is exercised by two test files (offline_queue_quarantine_test.dart, full_shift_soak_test.dart), which is why the dead code still passes CI and why a reader grepping for callers can be misled into thinking it is live. `relayOperation` genuinely has zero callers, tests included. (2) 'Nothing enqueues a PendingOperation any more' is true for every write path but overlooks `retryQuarantined` (offline_queue_service.dart:105) behind the settings 'retry' button (sync_status_section.dart:583). That path is worse than dead: it re-enqueues into a Hive box that nothing drains, since `syncAll` also has zero production callers — the button silently moves an op from the quarantine list into a queue no code will ever send. The final conclusion stands unchanged: with all outbox executors on DioClient/MainRepository and `_outbox.drain()` behind `_connectivity.isOnline`, plus `applyFromPeer` refusing to enqueue on the leader, a follower with no uplink has no route to the backend.

### User impact

In the topology the LAN hub was designed for (one till with internet, the rest LAN-only), a follower's orders, payments and shift closures accumulate in its local outbox indefinitely and never reach the server — other tills see them via the peer `localChange` broadcast, so the venue looks consistent, but nothing is recorded in the cloud and no report or second-device replay contains those sales. Separately, a manager pressing 'retry' on a quarantined operation in Settings gets no error and no send: the op leaves the quarantine list and is never transmitted, which reads as success.

### Second reader

MECHANICAL FACTS — CONFIRMED.
(1) `LanHubService.relayOperation` is dead. `grep -rn "relayOperation" lib test` → only lan_hub_service.dart:272 `Future<RelayOpResult?> relayOperation(PendingOperation op) async {` plus two doc mentions (271, 284). Its only would-be caller `OfflineQueueService.relayViaLan` (offline_queue_service.dart:236) has zero lib callers — the only hits tree-wide are test/offline_queue_quarantine_test.dart (7 calls) and test/full_shift_soak_test.dart:139. The leader half IS still wired (`_handleRelayOp` → lan_hub_service.dart:250 `await inject<OfflineQueueService>().executeRelayedOp(...)`), but nothing on any follower ever sends the `relayOp` message.
(2) Follower drain is uplink-gated, on COMMITTED code (sync_engine.dart is not in the other session's modified set; `git status` shows it clean). sync_engine.dart:216 `if (_lanHub.mode == LanMode.client) {` → :229 `if (_connectivity.isOnline) {` → :243 `await _outbox.drain();`.
(3) `isOnline` is a real backend-reachability probe, not a link check — connectivity_cubit.dart:65 `await client.dio.get('', ... validateStatus: (_) => true)` with `emit(false)` on throw. So a LAN-only follower is genuinely `false` and never drains.
(4) client mode is genuinely reachable at runtime: leader_election_service.dart:97 `prefs.getBool(electionEnabledKey) ?? enabledByDefault` with :85 `static const enabledByDefault = true;`, and :306 `await _lanHub.setMode(LanMode.client);` — no manual step required.
(5) `_outbox.drain()` has exactly two callers, both in sync_engine.dart (:243, :262), both inside an `isOnline` guard; grep confirms no other caller in lib.

WHERE THE PREVIOUS VERDICT IS WRONG — see `correction`.

**Second reader's correction:** Three material errors, all in the direction of overstating impact.

A. "accumulate indefinitely and never reach the server" is wrong. Nothing burns the operation's retry budget while offline, because drain() is only ever called inside an `isOnline` guard (sync_engine.dart:243, :262) and OutboxStore.markFailed/_quarantine (outbox_store.dart:277-283, `if (attempts >= maxAttempts)` with `maxAttempts = 8` at :45) only fire on an actual send attempt. The outbox is durable SQLite (outbox_store.dart:3 "Backed by the `_outbox` table in the same SQLite file as the replica"), so a follower's orders/payments/shift closures sit intact and flush in full the moment THAT terminal reaches the backend. The defect is therefore a missing feature (borrow the leader's uplink) producing DELAY, not loss — and permanent stranding only in a deliberately-built sole-uplink topology (leader on a tether/SIM, followers LAN-only), which nothing in the code sets up or steers an operator toward. In the ordinary one-AP venue every terminal is online or offline together and all drain on reconnect.

B. The quarantine-retry impact is nearly non-existent as described, and the previous verifier flagged the wrong quarantine. The legacy Hive quarantine box has NO producer in current code: `_quarantine` is called only at offline_queue_service.dart:204 (inside `syncAll`) and :259 (inside `relayViaLan`), both of which have zero production callers. So the Settings quarantine card (sync_status_section.dart:540 `valueListenable: queue.quarantineListenable`) renders empty and the "Qayta urinish" button never appears, except on a device carrying leftover Hive rows from an older build. The live problem is the opposite one, and it was missed: the REAL outbox's quarantine is unreachable from the UI entirely — `OutboxStore.quarantined()` (:239), `quarantineDepth` (:250) and `retryQuarantined` (:317) have zero callers anywhere in lib, and `_OutboxCard` reads the legacy box instead (sync_status_section.dart:211 `final queue = inject<OfflineQueueService>();` → :213 `valueListenable: queue.listenable` → :225 `final depth = box.length;`), so with a full real outbox the card still says "Barcha operatsiyalar sinxronlangan" and disables its own sync button (:239 `onTap: depth == 0 ? null : _syncNow`). (`tick(force: true)` itself is not dead — main_cubit.dart:99/118, close_shift_screen.dart:82, menu_meals_list_screen.dart:61 all call it.)

C. The leader-does-not-adopt-a-peer's-write leg rests on the other session's uncommitted work: `git show HEAD:lib/core/db/apply_change.dart | grep -c applyFromPeer` returns 0 — `applyFromPeer` (apply_change.dart:343, `_fromPeer = true`, short-circuiting :107 `if (sink == null || _fromPeer) return;`) and lib/core/sync/local_change_relay.dart (untracked) exist only in the working tree. The peer-broadcast half of the claimed user impact is IN_FLIGHT and cannot be treated as shipped behaviour. The load-bearing half (sync_engine gating, dead relayOperation, the Settings UI wiring) is committed and clean.

One finding the previous verdict missed that partly supports it: in client mode `_recordSync()` at sync_engine.dart:253 runs OUTSIDE the `isOnline` block, so an offline follower refreshes its "last sync" timestamp every tick and Settings (sync_status_section.dart:262-272 `valueListenable: syncEngine.lastSyncAt`) shows a fresh sync time while nothing was sent.

**Second reader's impact assessment:** In a normal venue (all tills on one AP behind one router), impact is delay only: while the internet is down a follower keeps taking orders locally, its outbox holds them durably in SQLite without burning retries, and everything uploads once the venue is back online. Real harm needs a deliberate sole-uplink setup — one till tethered to mobile data, the rest LAN-only — where that follower's orders, payments and shift closures never leave the device, so cloud reports and any second-device replay omit those sales even though the tills look consistent to each other. Separately and more likely to bite: a venue whose real outbox operations get quarantined (8 failed attempts, a server 4xx, or a missing executor) has no way to see or retry them — the Settings sync screen reads the retired Hive queue, so it reports "everything synced" and greys out its own sync button while the SQLite outbox holds stuck sales; and an offline follower's Settings screen still shows a just-now "last sync" time.

---

## `L5` — The manual Hub/Client picker can silently isolate a terminal

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

CLEAN half verified. leader_election_service.dart:87 `static const enabledByDefault = true;`; :97-98 `static bool isEnabledIn(SharedPreferences prefs) => prefs.getBool(electionEnabledKey) ?? enabledByDefault;` and lan_hub_service.dart:121 `if (!LeaderElectionService.isEnabledIn(_prefs)) { await _watchForConflicts(); }` — one accessor, both readers. di.dart:453 `await leaderElection.start();` is unconditional. `setEnabled` grep over the whole tree (lib+test) returns only leader_election_service.dart:30 (doc) and :106 (definition) — zero callers, confirmed. test/leader_takeover_test.dart exists and passes (ran `flutter test test/leader_takeover_test.dart test/leader_election_test.dart` -> 20/20 pass).
FOOTGUN verified. lan_network_section.dart:99-107 still offers `_Option(value: LanMode.disabled/server/client)` with `onChanged: _onModeChanged`, and settings_screen.dart:167 mounts `LanNetworkSection`. `_onModeChanged` (lan_network_section.dart:44-51) does `setMode(mode); await lanHub.restart();` only — it never touches LeaderElectionService. Picking Hub -> lan_hub_service.dart:96-124 server branch starts the WS server but the UDP beacon is behind `if (!LeaderElectionService.isEnabledIn(_prefs))`, which is false by default, so nothing announces: undiscoverable by `discoverHubs`. And leader_election_service.dart:239-263: `if (heardEpoch < _epoch) return; ... if (heardEpoch > _epoch) { _adopt(...); return; } ... if (_role != ElectionRole.leader) { _currentLeaderIp = a.ip; return; }` — an equal-epoch leader announcement is recorded and dropped, so the terminal never joins the real leader.

### Correction to the original claim

Two qualifications. (1) The 'never joins the real leader' half only holds when this terminal's persisted `lan_election_epoch` already equals the live leader's; a terminal whose epoch is lower (fresh install, epoch 0 vs a leader at epoch>=1) DOES get dragged back via `_adopt`/`_becomeFollower` (:245-248, :299-308), which silently overwrites the manual Hub choice — a second, opposite footgun on the same picker. (2) IN_FLIGHT: at HEAD the election never runs at all — `git show HEAD:lib/.../leader_election_service.dart` has `if (branchId.isEmpty) return;` and di.dart:403-406 calls `start()` inside `initDi()`, before `UserEvent.started()` populates UserBloc, so branchId is always empty. The `_armBranchWait` retry (leader_election_service.dart:175-224) is the concurrent session's uncommitted work. So 'failover is automatic' is only true with their in-flight change; at HEAD it is inert. Also `leader_takeover_test.dart` drives a `FakeLanHub` (test/leader_takeover_test.dart:158, `final hub = FakeLanHub();`), so it covers election arithmetic, not the real restart/socket path where LA and LB live.

### User impact

A manager who picks 'Hub' in Settings > Network on a terminal already synced to the current epoch turns that till into an island: nothing broadcasts its existence over UDP so no other terminal can discover it, `_sendOrBroadcast` (lan_hub_service.dart:371-382) routes its writes to `_server.broadcast` with zero connected clients so its orders never reach the venue, and it never adopts the real leader. On a terminal with a lower epoch the opposite happens — the setting the manager just chose is silently reverted to Client within seconds.

### Second reader

MECHANISM — confirmed as far as it goes.

(1) Manual mode picker is live and unguarded. lan_network_section.dart:98-109 `_SegmentedPicker<LanMode>(value: _mode, options: [_Option(value: LanMode.disabled…), _Option(value: LanMode.server, label: S.current.strHub), _Option(value: LanMode.client…)], onChanged: _onModeChanged)`; :45-53 `_onModeChanged` is exactly `await lanHub.setMode(mode); await lanHub.restart(); setState(...)` — no LeaderElectionService reference anywhere in the file (grep: the file never imports leader_election_service.dart). Mounted at settings_screen.dart:167 `return const LanNetworkSection(key: ValueKey('lanNetwork'));`, reachable from `...SettingsSection.values.map(` at settings_screen.dart:269, so no per-section gating.

(2) A manual Hub does not announce. lan_hub_service.dart:121-123 `if (!LeaderElectionService.isEnabledIn(_prefs)) { await _watchForConflicts(); }`, and `_watchForConflicts` (:146-159) is the ONLY `startAnnouncing` call in LanHubService. leader_election_service.dart:87 `static const enabledByDefault = true;` / :97-98 `?? enabledByDefault` make that branch false on a fresh install. The election's own beacon starts only at leader_election_service.dart:344 inside `_claimLeadership`. So a manually-picked Hub emits nothing on UDP 8766 → invisible to `discoverHubs` (:170-187) and the `_ConflictCard` (lan_network_section.dart:133-136) can never render, since `_hubConflictController` is only fed from `_watchForConflicts`.

(3) Equal-epoch does not correct it. leader_election_service.dart:242-262: `if (heardEpoch < _epoch) return; ... if (heardEpoch > _epoch) { unawaited(_adopt(a, heardEpoch)); return; } ... if (_role != ElectionRole.leader) { _currentLeaderIp = a.ip; return; }` — a follower at the venue's current epoch records the leader's IP and drops it; nothing calls `_lanHub.setMode`. Grep for `setMode(` across lib+test returns only lan_hub_service.dart:81 (definition), leader_election_service.dart:306/342, lan_network_section.dart:47 and two test fakes.

CORRECTION 1 — the election half is NOT reachable on committed code; it rests on the concurrent session's uncommitted work. `git diff lib/core/services/lan_hub/leader_election_service.dart` shows the working tree ADDS `_armBranchWait` / `branchWaitInterval`. HEAD reads `Future<void> start() async { if (!isEnabled || _isRunning) return; final branchId = _myBranchId(); if (branchId.isEmpty) return;`. The only caller in the whole tree is `git show HEAD:lib/di.dart` line 406 `await leaderElection.start();`, inside `initDi()`, while the branch id comes from `UserBloc`, hydrated at main.dart:128 `inject<UserBloc>()..add(const UserEvent.started())` — i.e. after `initDi()` returns. So on HEAD the branch id is always empty, `start()` bare-returns, and no `_onAnnouncement` ever fires: the election never runs at all. Everything in the previous verdict about "equal-epoch dropped" and "silently reverted to Client" only becomes live once the other session's `_armBranchWait` lands.

CORRECTION 2 — "its orders never reach the venue" is false whenever the terminal has internet. sync_engine.dart:217 `if (_lanHub.mode == LanMode.client) {` … the LAN-gated branch `return`s at :255. A terminal in `server` mode falls through to :256-263 `if (!_connectivity.isOnline) return; ... await _outbox.drain(); await _replication.drain(); await _fillFeedGaps();` — full bidirectional cloud sync, driven by the periodic ticker (:135 `_ticker ??= Timer.periodic(tickInterval, ...)`) and the debounced `nudge()` (:170-176, `nudgeDelay = 750ms`). The real leader then re-broadcasts what it pulls (`broadcastChangeFeed`, lan_hub_service.dart:390-399). So orders propagate via cloud with sync latency; the true-island outcome needs a venue with no uplink, which is a subset of the claimed scenario.

CORRECTION 3 — not silent, and not a cashier. settings_screen.dart:102 `final allowed = role.canAccessSettings;` with user_role_permissions.dart:12-15 restricting that to `admin || manager || superadmin`. And the status card gives honest feedback: lan_network_section.dart:476-479 `statusText = count == 0 ? 'Kutilmoqda — hech qanday qurilma ulanmagan' : ...`. Manual configuration is also not wholly broken — the WS server does start (lan_hub_service.dart:97-110) and another terminal pointed at its IP by hand (`_onIpSaved`, :55-62) would connect; only auto-discovery is dead.

AGGRAVATOR the original missed: the flipped terminal becomes a SECOND lease authority. lease_manager.dart:105-107 `case LanMode.server: // This terminal already IS the leader — arbitrate against its own state directly, no network round trip. return _arbitrate(tableId, claimant: _myTerminalId);` — so it grants table leases locally, concurrently with the real leader, bounded only by how fresh its cloud-pulled replica is.

**Second reader's correction:** Three things are wrong. (a) IN_FLIGHT: the entire "election refuses to correct the manual pick / silently reverts it to Client" half is unreachable on committed HEAD — `start()` bare-returns on an empty branch id (HEAD leader_election_service.dart) and its sole caller di.dart:406 runs before UserBloc is hydrated (main.dart:128), so the election never starts and `_onAnnouncement` never runs. It only becomes live with the other session's uncommitted `_armBranchWait`. What IS committed and real is narrower: because `isEnabledIn` returns true while the election is inert, a manual Hub skips `_watchForConflicts` and therefore never announces at all — LAN auto-discovery and split-brain warning are both dead with nothing replacing them. (b) "its orders never reach the venue" is refuted for an online terminal: sync_engine.dart:256-263 gives `server` mode a full outbox drain + replication pull, so writes reach the cloud and come back to the venue via the real leader's `broadcastChangeFeed`; only a no-uplink venue is a genuine island. (c) The action needs admin/manager/superadmin (settings_screen.dart:102 + user_role_permissions.dart:12-15), not a cashier, and the UI does say "0 devices connected" rather than failing silently. Unmentioned but real: lease_manager.dart:105-107 makes the flipped terminal a second table-lease arbiter.

**Second reader's impact assessment:** An admin/manager who picks "Hub" in Settings > Network on a terminal that is already part of a venue turns that till into a second, undiscoverable hub: nothing broadcasts on UDP 8766, so no other terminal can find it via "Lokal tarmoqdan qidirish", the split-brain warning card can never fire, its LAN client link to the real leader is dropped, and `_sendOrBroadcast` (lan_hub_service.dart:371-382) sends its real-time table-status/print/local-change traffic into a server with zero connected sockets. It also starts granting table leases on its own authority (lease_manager.dart:105-107), so the same table can be opened on two tills inside one sync window. With internet the damage is degradation, not loss — orders still reach the venue via the cloud on the next sync tick — and the status card does read "0 devices connected". Without internet, which is the exact case LAN hub mode exists for, the till is fully isolated until someone flips it back. Once the other session's branch-wait fix lands, the same pick also becomes non-deterministic: it sticks forever at the current epoch, but gets silently reverted to Client the moment any real leader failover bumps the epoch.

---

## `L7` — No epoch on the data plane; the split-brain warning is dead by default

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

`grep -n epoch lib/core/services/lan_hub/lan_hub_message.dart lib/core/services/lan_hub/lan_hub_server.dart` returns nothing — the wire format carries no epoch. Handshake: lan_hub_server.dart:116-131 accepts only `LanHubMessageType.auth` then `_authValidator?.call(msg.token ?? '', msg.branchId ?? '')`, and lan_hub_service.dart:201-224 `_validateIncomingAuth` checks only token liveness plus `branchId != myBranchId`. Nothing identifies which leader/epoch is speaking. Fencing exists only on UDP: leader_election_service.dart:242 `if (heardEpoch < _epoch) return; // stale`. Second half also confirmed: lan_hub_service.dart:121-123 gates `_watchForConflicts()` on `!isEnabledIn(_prefs)` (false by default), and `_hubConflictController` is fed at exactly one place, :157 inside `_watchForConflicts`, plus a `.add(null)` reset at :462 — so `conflictingHubIp` (:56) is permanently null, and lan_network_section.dart:130 `if (_mode == LanMode.server && lanHub.conflictingHubIp != null) ... _ConflictCard(...)` is unreachable.

### Correction to the original claim

Two mitigations the claim omits. The stale-leader changeFeed window is bounded, not open-ended: a stale leader hearing the higher epoch on UDP adopts within ~3 beats (`_adopt`, :245-248), and a follower only applies `changeFeed` while `mode == LanMode.client` (lan_hub_service.dart:306). And ChangeFeedRelay.apply (change_feed_relay.dart:59-64) detects `fromCursor > _db.syncCursor` and refuses to advance the cursor, so a batch from the wrong source cannot silently strand rows — the damage is bounded to upserting stale rows and possibly rewinding the cursor, forcing a re-pull.

### User impact

During the few-second window between a partition healing and the old leader hearing the new epoch, a still-attached follower will upsert the old leader's stale batch over fresher local rows — a table's items or status can flicker backwards on one till. Separately, the split-brain warning card in Settings > Network is dead code: if two terminals really are both configured as Hub, no operator is ever told.

---

## `L8` — Table leasing degrades correctly when the leader is unreachable

**Area:** LAN / leader-follower  
**First pass:** PARTIAL / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

The block-only-on-rejected policy is confirmed at all three sites with identical code: create_order_bloc.dart:131-139 `final lease = await _leaseManager.acquireTableLease(state.tableId); if (!lease.isGranted && !lease.isUnreachable) { showErrorMessage(...); return; }`; waiter_local_repository_impl.dart:288-293 `if (!lease.isGranted && !lease.isUnreachable) { return const Left(MessageFailure("Bu stol allaqachon boshqa terminalda ochilgan.")); }`; table_timer_local_repository_impl.dart:293-298, identical. `acquireTableLease` (lease_manager.dart:99-127) returns `LeaseResult.unreachable` both when `!_lanHub.isClientConnected` and when the leader does not reply within 5s. Grep for `acquireTableLease` finds exactly those three production call sites.

### Correction to the original claim

'allow-with-warning at all three' is wrong: only ONE of the three warns. create_order_bloc.dart:140-147 has `if (lease.isUnreachable) { showInfoMessage(..., "Stol egaligi tekshirilmadi (yetakchiga ulanish yo'q) — buyurtma baribir ochildi."); }`. The waiter path (waiter_local_repository_impl.dart:288 onward) and the timed-order path (table_timer_local_repository_impl.dart:293 onward) have no `isUnreachable` branch at all — they fall straight through to `_orders.createOrder(...)`. This is the same 'fix landed on one path, not its duplicate' pattern those files' own comments claim to have closed. Given LB and LC, `isClientConnected` can be false for a long time, so this is not a rare path.

### User impact

On the waiter screen and on time-based tables, when the hub is unreachable a table opens with zero indication that ownership was never verified — the cashier and waiter both believe the table is cleanly theirs. If another terminal opened the same table during the outage, the double-open surfaces only later at the outbox 409-merge, with two staff having taken orders on one table and no one warned. The cashier dine-in path does warn, so the inconsistency also trains staff to expect a warning that two of three paths never show.

---

## `LC` — Followers never re-point on an equal-epoch leader IP change

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

leader_election_service.dart:255-263: `if (a.terminalId == _myTerminalId()) return; if (_role == ElectionRole.candidate) {...} if (_role != ElectionRole.leader) { _currentLeaderIp = a.ip; return; }` — the equal-epoch path assigns and returns; the only call to `_becomeFollower` outside it is from `_adopt` (:296), reached only via `if (heardEpoch > _epoch)` at :245 or the leader-vs-leader tiebreak at :279. `_becomeFollower` (:299-308) is the sole writer of `_lanHub.setServerIp(...)`. Reader check: grepping lib+test for `currentLeaderIp` yields the getter at leader_election_service.dart:137, the writes at :261/:291/:341, and reads ONLY in test/leader_election_test.dart:203 and :256 — zero production readers. Likewise `onRoleChanged` (:140) has no subscriber in lib.

### Correction to the original claim

None on substance. Add that the failure is silent by construction: the leader's UDP heartbeat still arrives from the new IP, so `_missedBeats = 0` at :243 keeps resetting and the watchdog at :310-318 never starts an election — the follower has no path at all back to a correct IP short of an app restart or a manual edit in Settings > Network.

### User impact

If the hub terminal's LAN address changes while its process stays up (DHCP lease renewal, Wi-Fi/ethernet swap), every follower keeps dialing the old address forever: no peer replication, no lease arbitration (LeaseManager falls to `unreachable`, lease_manager.dart:109-113), the orange solo banner pinned on every screen, and no election triggered to fix it.

---

## `S1c` — Adding an entity to the registry ships an empty table

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

lib/core/db/apply_change.dart:173-180 — `final spec = kEntitiesByName[entity]; if (spec == null) { ... return stats._add(skippedUnknown: n); }` — counted, not deferred; the cursor still advances at :158-162. lib/core/db/local_database.dart:180-192 — `_migrate()` loops `for (final spec in kReplicatedEntities)` issuing `CREATE TABLE IF NOT EXISTS ${spec.name} (...)`; the only version-gated step is :205-207 (`if (priorVersion < 5) repairBlankedOrderTimestamps();`) and nothing anywhere writes `syncCursor` back down — grep shows `syncCursor` is set only in apply_change.dart:162 (monotonic) and reset only by `clearAll()` (local_database.dart:762), reachable only via `ReplicationService.resetAndBootstrap` on a brand/branch switch (replication_service.dart:244-249). Backfill mitigation is real but is exactly a convention: back/app/migrations/tenants/71_change_log_triggers_batch2.up.sql:55-90 writes 'One `create` row per currently-live row' for nine tables, and is explicitly capped — 'each table is backfilled only if its live row count is at or below a cap (default 50 000 ...). Anything skipped is reported by a NOTICE and must be backfilled out of band'.

### Correction to the original claim

Worth adding: the backfill mitigation is weaker than the claim implies. Migration 71 silently skips any table over the 50k-row cap with only a NOTICE, so on an established tenant the convention can fail even when someone remembers to follow it.

### User impact

Ship a client that adds an entity to the registry and every existing terminal gets an empty table for it — the transaction ledger, register picker or modifier list renders blank — until someone remembers to write a matching backfill migration, and even then only if that tenant's table is under the row cap.

### Second reader

MECHANISM — confirmed exactly at the cited lines (working tree). apply_change.dart:173-180: `final spec = kEntitiesByName[entity]; if (spec == null) { final n = _lengthOf(changes['created']) + _lengthOf(changes['updated']) + _lengthOf(changes['deleted']); return stats._add(skippedUnknown: n); }` — rows are counted and dropped, never deferred. apply_change.dart:158-162 advances the cursor in the same transaction regardless: `if (cursor is num && advanceCursor) { final next = cursor.toInt(); if (next > _db.syncCursor) _db.syncCursor = next; }`. The pull request carries no entity list — sync_api_client.dart:76-79 posts only `{'last_sync_cursor': cursor, 'limit': limit}` — so the server sends every logged entity and the client is the only filter. local_database.dart:181-204 builds schema from `for (final spec in kReplicatedEntities) ... CREATE TABLE IF NOT EXISTS ${spec.name}`, and the only version-gated step is :206-207 (`if (priorVersion < 5) repairBlankedOrderTimestamps();`). Nothing lowers the cursor: `syncCursor` is written only at apply_change.dart:162 (monotonic) and via `clearAll()` wiping `_sync_meta` (local_database.dart:762-780, LocalTables.all at entity_registry.dart:229-237 includes `meta`).

REACHABLE TODAY, and the previous verdict understated this: back/app/migrations/tenants/71_change_log_triggers_batch2.up.sql:40-54 arms `trg_change_log_*` on `table_time_sessions`, `modifiers`, `goods_modifiers`, `printer_settings`, `cash_register_shifts` — five tables with no `EntitySpec` (grep of `name: '` in entity_registry.dart:247-570 shows none of the five). test/registry_backend_pin_test.dart:55-88 lists exactly those five in `kIntentionallyNotReplicated`. So `spec == null` fires in production right now and migration 71's backfill rows for those five are already sliding behind every terminal's cursor.

RECOVERY PATHS — I grepped for them and they do not exist for an already-provisioned terminal. `clearAll()` has two call sites: replication_service.dart:247 (`resetAndBootstrap`) and auth_cubit.dart:136 (`AuthCubit.logoutFromApp`). `AuthCubit.logoutFromApp` has ZERO callers — the logout button at login_pin_screen.dart:61 reads `context.read<LoginPinCubit>()` (line 36) and calls the identically-named `LoginPinCubit.logoutFromApp` (login_pin_cubit.dart:247-259), which never touches the replica; the in-app logout dialog (logout_dialog.dart:77) calls `AuthCubit.logout` (auth_cubit.dart:52), which also never touches it. And `resetAndBootstrap` runs on brand change only: login_data_scope_service.dart:144 `_pendingReset = brandChanged;` → :177, while :147-152 branch-change explicitly "keep existing local data". The client never calls `/sync/snapshot` (grep of lib/core/sync: replication_service.dart:117 still calls it a "backend ask", though back/app/internal/service/sync_snapshot.go implements it).

**Second reader's correction:** Directionally right, three details wrong. (1) The cursor-reset claim is imprecise in both directions: `clearAll()` has a second call site the verdict missed (auth_cubit.dart:136) — but that method is dead, and `resetAndBootstrap` fires on brand change ONLY, not "brand/branch" (login_data_scope_service.dart:147-152 keeps local data on a branch change). Net: the escape hatch is narrower than stated, which strengthens the mechanism. (2) The stated user impact is wrong on two of its three examples. `transactions` (entity_registry.dart:553), `group_transactions` (:532), `cash_registers` (:536) and `ingredient_visibility` (:424) are all already live registry entries, and migration 71's backfill was written FOR them (71...up.sql:83-90 lists them first; registry_backend_pin_test.dart:56-58 says four of the nine "were already in the registry and are what it was written for"). The transaction ledger and register picker are the case that WORKED. Only the modifier list is real, and it is a future case — modifiers/goods_modifiers are the entries the pin test says to "add both together when the order screen grows modifier support". (3) "until someone remembers to write a matching backfill migration" overstates permanence: 73_change_log_retention.up.sql:20-23 keeps "one row per (entity, entity_id) — the newest" beyond the window, so a freshly-provisioned terminal replaying from cursor 0 DOES get those rows. The defect is therefore a divergence between upgraded terminals and new ones in the same venue, and the table also fills incrementally for any row that changes after the upgrade. Severity downgraded HIGH→MEDIUM: no user is harmed by the shipped build today; harm requires a future client release, and it is confined to catalog/reference reads (no orders, money or writes at risk). Note the cited files are on the concurrent session's edit list, but its diff to local_database.dart only relocates the priorVersion lines (206-207) and adds no version-gated step, and its apply_change.dart diff adds the LAN sink, not the unknown-entity branch — so the verdict does not rest on in-flight work.

**Second reader's impact assessment:** When a future release adds one of the five already-triggered tables to the registry (modifiers/goods_modifiers are explicitly planned), terminals that were already provisioned get a permanently empty table for it, populated only as individual rows happen to change, with no operator-reachable fix short of a brand switch or reinstall — while a terminal provisioned after that release sees the full list. Two registers on the same counter show a different modifier catalogue, and the empty one looks exactly like "this venue has no modifiers".

---

## `S1d/S3a` — Pull rows skipped as pending are never re-delivered

**Area:** Sync & replica integrity  
**First pass:** PARTIAL / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

Core mechanism confirmed: lib/core/db/apply_change.dart:237 — `if (_db.isPending(spec.name, id)) return stats._add(skippedPending: 1);` and :213-216 for deletes; the cursor advances regardless (apply_change.dart:158-162), and replication_service.dart:161 only counts `stats.skippedPending`. Nothing re-requests. orders/pay non-self-heal CONFIRMED at back/app/internal/service/order.go:1335-1336 — `if orderBeforePay.Status.Valid && orderBeforePay.Status.OrderStatus == pg.OrderStatus(model.OrderStatusPaid) { return toOrderResponse(orderBeforePay), nil }` — returns before `PayOrderBill`, so no write, so no change_log row. order_items/delete 404 CONFIRMED at lib/core/outbox/orders_outbox.dart:143-146 — `if (e.response?.statusCode == 404) { return const OutboxExecutionResult.succeeded(); }` with no server-side write.

### Correction to the original claim

The `enqueueOnly` clause is wrong. `LocalWriter.enqueueOnly` (lib/core/outbox/local_writer.dart:160-175) calls only `_outbox.enqueue` — it never calls `applyLocalWrite`/`markPending`, so an enqueueOnly op cannot be the cause of a pending-skip in the first place; there is no guard for it to fail to heal. Moreover the three real enqueueOnly call sites (orders_repository_impl.dart:396 transfer, table_timer_local_repository_impl.dart:207 timer sessions, shift_bloc.dart:161/231 shift open/close) all DO produce server-side writes on tables that now carry log_change triggers (migration 71 adds triggers to `table_time_sessions` and `cash_register_shifts`), so they generate change_log rows. Separately, the enqueueOnly transfer at orders_repository_impl.dart:396-401 passes `entity: 'orders', entityId: orderId`, which makes it an S3b-style cross-clear risk — a different defect from the one claimed here.

### User impact

A server-side version of an order or line that arrives while a local write is queued is dropped for good on the paths that produce no server write: a replayed pay on an already-paid check and a 404-tolerated line cancel. The terminal keeps its own version of the row — missing the server's bill_no, computed grand_total or paid_at — and no later pull corrects it.

### Second reader

MECHANISM — CONFIRMED, and it is committed code, not the other session's work. `git show HEAD:lib/core/db/apply_change.dart` still has the guards at lines 166/190/216; in the working tree they are apply_change.dart:213-215 `if (_db.isPending(entity, entityId)) { out = out._add(skippedPending: 1); continue; }` and :237 `if (_db.isPending(spec.name, id)) return stats._add(skippedPending: 1);`. The cursor advances regardless, in the same transaction: apply_change.dart:154-162 `if (cursor is num && advanceCursor) { final next = cursor.toInt(); if (next > _db.syncCursor) _db.syncCursor = next; }` — nothing consults `stats.skippedPending`. Nothing re-requests: replication_service.dart:152-190 loops on the cursor alone; sync_engine.dart:324-326 `_fillFeedGaps()` fetches only table timers and menu images ('an entity belongs here only if the backend logs no change-log trigger for it'); the backend has a resync signal (`SnapshotRequired`, back/app/internal/service/sync.go:144) and a /sync/snapshot service, and `grep -rn snapshot lib/` shows the client never reads either — sync_api_client.dart knows only pullPath/pushPath. `resetAndBootstrap` (replication_service.dart:244) is brand/branch switch only.

MITIGANT THE FIRST VERDICT MISSED — sync_engine.dart:258-263: 'Send before receiving: draining the outbox first means the pull in the same pass already reflects what this terminal just wrote, rather than returning a version `_pending` then has to shield.' `await _outbox.drain(); await _replication.drain();`, and outbox_drainer.dart:141-147 `_succeed` does `_db.clearPending(op.entity, entityId)`. So on the ordinary path the guard is gone before the pull that would carry the server row. Loss needs the op to survive a pull still pending: a lost/timed-out first response (`_mapDioError` → retry, orders_outbox.dart:236-241), an op blocked behind a failing chain-mate (outbox_drainer.dart:120-124 `blockedChains.add(chain)`), or a cashier write racing an in-flight pull.

orders/pay non-self-heal — CONFIRMED at back/app/internal/service/order.go:1334 `if orderBeforePay.Status.Valid && orderBeforePay.Status.OrderStatus == pg.OrderStatus(model.OrderStatusPaid) { return toOrderResponse(orderBeforePay), nil }` (line 1334, not 1335-1336), before `q.PayOrderBill`, so no UPDATE and no trigger row (trg_change_log_orders, app/migrations/tenants/8_movements.up.sql:154). The client also throws the returned order away — orders_outbox.dart `_send` returns `OutboxExecutionResult.succeeded()` with no serverRow, so the response body is not a recovery path either.

order_items/delete 404 — REFUTED. back/app/internal/handler/order.go:2322-2356 `CancelOrderItem` returns 400 for a missing/unparseable id and `http.StatusInternalServerError` for every service error; `grep StatusNotFound app/internal/handler/order.go` shows no 404 anywhere in that handler. So orders_outbox.dart:143-146's 404 branch is unreachable against this backend. The genuine no-write path is the 200 idempotent return at service/order.go:3813-3819 `if existing.Status.Valid && string(existing.Status.OrderItemsStatus) == "cancelled" { ...commit...; return toOrderItemResponse(existing), nil }`.

bill_no — REFUTED. It is assigned at order create, not at pay: service/order.go:514 `billNo, err := q.NextDailyBillNo(txCtx)` and :529 `q.InitOrderBillFields(txCtx, createdOrder.ID, billNo, servicePercent)`; PayOrderBill's UPDATE (repository/pg/tenantsdb/bills_custom.go:288-313) never touches bill_no. paid_at is client-supplied and honoured (`paid_at = COALESCE($12::timestamptz, NOW())`, bills_custom.go:308) and the client freezes it (payment_repository_impl.dart 'paid_at': closedAt).

**Second reader's correction:** Three things are wrong. (1) The order_items/delete evidence is wrong: the cited 404 branch (orders_outbox.dart:143-146) cannot fire — handler/order.go:2322-2356 answers 400 or 500 and never 404 — and the real no-write path there (the 200 already-cancelled early return, service/order.go:3813-3819) has no user-visible effect, because the local row was deleted while the server's is merely status='cancelled', and every local read already discards cancelled lines (order_totals.dart:145, detail_bloc.dart:204,252, payment_right_side_bar.dart:397, archives_query.dart:249, cashier_receipt_builder.dart:667). That half of the finding is refuted. (2) 'missing the server's bill_no' is wrong — bill_no comes from the create (order.go:514/529), not the pay, and PayOrderBill never writes it; paid_at is likewise the client's own value. (3) The verdict ignores sync_engine.dart:258-263, which drains the outbox before every pull and clears pending in _succeed, so this is not 'a pull landing during a queued write' generally — it needs the op to still be pending across a pull (timed-out first pay, blocked chain, or a write racing an in-flight pull). Only the orders/pay half stands, and only in that narrower window; severity HIGH -> MEDIUM. Not IN_FLIGHT: the guards, the cursor advance, sync_engine's ordering and the drainer's clearPending are all in HEAD (verified with git show), though apply_change.dart/outbox_drainer.dart/orders_outbox.dart are being edited around them.

**Second reader's impact assessment:** Narrow but real, on orders/pay only. A pay whose first response is lost (server committed, client saw a timeout) has its server row delivered in the very next pull of the same tick and dropped by the pending guard; the retry then early-returns on the already-paid check, writes nothing, and no later pull carries that row again. The archive page renders the order's whole stored JSON blob (archives_query.dart:126-136 selects `o.data`), so that terminal keeps its own numbers forever: no cashier_id/cash_register_id/food_cost (the client's pay row, payment_repository_impl.dart:115-148, never writes them), and a grand_total/table_charge that differs from the server's wherever the backend's under-payment settlement branch (settled_grand_total / settled_table_charge, bills_custom.go:272-286) or a differing item set applied. Same divergence if a second terminal settles the check first. Bill number, paid time and paid/closed status are unaffected. Every other terminal and the back office show the correct figures, so the symptom is one till disagreeing with the rest on a handful of closed bills, not a lost payment.

---

## `S3b` — clearPending fires on the first ack, not the last

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / HIGH  
**Second pass:** CONFIRMED / MEDIUM  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

lib/core/outbox/outbox_drainer.dart:139-147 — `void _succeed(OutboxOperation op, ...) { _db.transaction(() { _store.markSucceeded(op.id); final entityId = op.entityId; if (entityId != null && entityId.isNotEmpty) { _db.clearPending(op.entity, entityId); }` — no query against the outbox for other queued ops on the same (entity, entityId). lib/core/db/local_database.dart:706-711 — `clearPending` is a bare `DELETE FROM pending WHERE entity = ? AND entity_id = ?`, no refcount, and `markPending` (:696-702) is `INSERT OR REPLACE` with no counter. Both ops do carry the order id: orders_repository_impl.dart:285-290 — `_writer.write(entity: 'orders', id: orderId, action: 'create', ...)`, and payment_repository_impl.dart:148-155 — `_writer.write(entity: 'orders', id: orderId, action: 'pay', merge: true, ...)`; `LocalWriter.write` (local_writer.dart:70-78) passes `entityId: id` to `enqueue`, so both ops share entityId = orderId. Same chain (`chainKeyOf` falls back to entityId, outbox_executor.dart:95-101), so they drain in the same pass. The revert path is one tick long: sync_engine.dart:262-263 — `await _outbox.drain(); await _replication.drain();`.

### Correction to the original claim

One refinement to the failure trace: the reverting row need not come from a later edit — the order's own `create` that just acked produces a change_log row carrying the order as unpaid, so the very next pull in the same tick is what overwrites the paid state. This makes the window far easier to hit than the claim implies. The bug bites whenever orders/pay does not also succeed in that same drain pass (transient network drop after the create's 200, or a 4xx quarantine, which also clears pending at outbox_drainer.dart:246).

### User impact

An order created and paid offline, replayed when the network returns: the create acks, drops the guard, and if the pay does not land in the same pass the immediately following pull reopens a bill the cashier has already settled and handed change for. The payment screen shows an unpaid check for a closed table.

### Second reader

MECHANISM CONFIRMED, line cites drift 1-3 lines.

1) The premature clear. lib/core/outbox/outbox_drainer.dart:139-147:
  `void _succeed(OutboxOperation op, Map<String, dynamic>? serverRow) {
     _db.transaction(() {
       _store.markSucceeded(op.id);
       final entityId = op.entityId;
       if (entityId != null && entityId.isNotEmpty) {
         _db.clearPending(op.entity, entityId);   // line 146`
No query against the outbox for other queued ops on the same (entity, entityId). Confirmed.

2) No refcount. lib/core/db/local_database.dart:696-702 `markPending` is `INSERT OR REPLACE INTO pending (entity, entity_id, since) VALUES (?,?,?)` — one row per (entity,entityId), no counter. :706-711 `clearPending` is a bare `DELETE FROM pending WHERE entity = ? AND entity_id = ?`. Confirmed.

3) Both ops share entityId. orders_repository_impl.dart:282-288 `_writer.write(entity: 'orders', id: orderId, action: 'create', row: orderRow, request: body)` (auditor said 285-290). payment_repository_impl.dart:149-156 `_writer.write(entity: 'orders', id: orderId, action: 'pay', merge: true, ...)` (auditor said 148-155). local_writer.dart:70-78 passes `entityId: id`; :72 `_applier.applyLocalWrite(...)` -> apply_change.dart:377 `_db.markPending(entity, id)`. Confirmed.

4) Same chain. outbox_executor.dart:95-101 `chainKeyOf`: orders/create registers no `chainKey`, so `final entityId = op.entityId; if (entityId != null && entityId.isNotEmpty) return entityId;`. Both = orderId. Confirmed.

REFUTATION ATTEMPTS THAT FAILED:
(a) Reachable? Yes. createOrder/createTakeawayOrder -> _writeOrderWithItems (orders_repository_impl.dart:278) reached from create_order_bloc / waiter_local_repository_impl.dart:300; pay reached from payment_bloc.dart:42,81 `final PaymentRepository _paymentRepository`.
(b) Guard elsewhere? None. apply_change.dart:237 `if (_db.isPending(spec.name, id)) return stats._add(skippedPending: 1);` is the ONLY defence in `_applyUpsert` — no updated_at/version compare. Proven live by test/payment_close_bill_test.dart:239-267 (guard set -> `stats.skippedPending == 1`, row stays 'paid') vs :282-300 (`db.clearPending('orders','o1')` -> server row takes over).
(c) Does the server feed skip our own changes? No. back/app/internal/service/sync.go:57-63 `SELECT id, brand_id, entity, action, entity_id, payload FROM change_log WHERE id > $1 ORDER BY id ASC LIMIT $2` — no device/origin filter. back/app/migrations/tenants/8_movements.up.sql:154 `CREATE TRIGGER trg_change_log_orders AFTER INSERT OR UPDATE OR DELETE ON orders FOR EACH ROW EXECUTE FUNCTION log_change('id')`. So our own create replay produces the change_log row the next pull hands back as `created` with bill_status='opened'.
(d) Does the create's ack apply a corrective server row? No. orders_outbox.dart orders/create returns `const OutboxExecutionResult.succeeded()` with no serverRow, so `_succeed` only clears the guard.
(e) One tick. sync_engine.dart:259-260 `await _outbox.drain(); await _replication.drain();`. Backing-off pay is excluded from the retry pass: outbox_store.dart:136-141 `WHERE status = ? AND next_attempt_at <= ?`.
(f) In-flight? No. `git diff -U0 outbox_drainer.dart` = one hunk at _reconcile (line 184+); _succeed untouched. `git diff local_database.dart | grep Pending` = empty. orders_repository_impl.dart hunks jump 275 -> 312, skipping the create write at 282-288. payment_repository_impl.dart is not modified at all.

**Second reader's correction:** Two corrections, both downgrading. (1) SCOPE OF INCREMENTAL HARM. In the permanent-failure case the guard is released BY DESIGN anyway — outbox_drainer.dart:230-249 `_fail(..., permanent: true)` calls `_db.clearPending(op.entity, entityId)` with the comment 'Deliberate: a quarantined write releases its local row.' So on a 4xx pay (orders_outbox.dart `_mapDioError`: 4xx -> permanent) the missing refcount contributes NOTHING. The bug's real contribution is confined to the transient-retry case (5xx/timeout/dropped connection -> `OutboxExecutionResult.retry`), where correct behaviour would be to hold the guard and never show a revert at all. (2) NOT PERMANENT. The reopened state self-heals: the pay endpoint updates `orders`, the trigger logs it, and the next pull delivers bill_status='paid'. Bounded by outbox_store.dart:37-45 (baseBackoff 5s, maxBackoff 2min, maxAttempts 8, ~10 min) against sync_engine.dart:73 `tickInterval = Duration(seconds: 60)`. So the exposure is a wrong display of roughly 1-10 minutes, not a lost payment — the pay op stays queued and the server pay is idempotent, so no double charge occurs absent a cashier manually re-collecting. That transience plus the partial-failure precondition is why HIGH is overstated; MEDIUM. One thing the auditor UNDERSTATED: the defect is not pay-specific. Any second queued op sharing an entityId is exposed — orders/transfer (orders_repository_impl.dart:386, entityId = orderId) and order_items create+delete (both keyed on the line id, local_writer.dart create/delete), where a line cancelled offline reappears on the open check once the add acks.

**Second reader's impact assessment:** A check created and settled offline, replayed when the network returns: the create acks and drops the pending guard while the pay is still queued. If the pay hits a 5xx or a timeout in that same pass, the immediately following `_replication.drain()` pulls back the server's still-open order and overwrites the local paid row — the table goes from settled back to busy and the payment screen shows an unpaid check for a bill the cashier has already taken cash for and handed change on. It reverts to paid on its own once the pay lands (typically within 1-2 sync ticks, at most ~10 minutes of backoff). The operational risk is a cashier acting on the wrong display in that window — re-ringing the table or physically collecting a second time — not a lost or doubled server-side payment.

---

## `S3c` — synchronous = NORMAL can lose a committed outbox row

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  
**In flight:** rests on another session's uncommitted work  

### Evidence

lib/core/db/local_database.dart:87-89 — `_db.execute('PRAGMA journal_mode = WAL'); _db.execute('PRAGMA synchronous = NORMAL'); _db.execute('PRAGMA foreign_keys = OFF');`. The outbox is in this same database and gets no separate durability treatment: local_database.dart:108-126 creates `CREATE TABLE IF NOT EXISTS ${LocalTables.outbox} (...)` alongside the replica tables, and `LocalWriter.write` commits the row and the queue entry in one `_db.transaction` (local_writer.dart:67-79). In WAL mode `synchronous = NORMAL` skips the fsync at COMMIT and syncs only at checkpoints, so commits since the last checkpoint are not durable across an OS crash or power cut. Nothing else in the file re-raises durability — grep for `synchronous`/`PRAGMA` returns only lines 87-89.

### Correction to the original claim

Slight scoping correction: WAL + NORMAL is durable across an *application* crash (the WAL is intact in the page cache and replayed on next open); the loss window is specifically OS crash or power loss, which is the case the claim names. So the claim is right about the consequence but it is not a general 'crash' hazard.

### User impact

A POS terminal on an unreliable mains supply — a venue with no UPS — can lose the last seconds of committed writes on a power cut. A queued payment or order vanishes from both the replica and the outbox with no error and no record that it ever existed.

---

## `S4b` — snapshot_required and /sync/snapshot are ignored by the client

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Server half: back/app/migrations/tenants/73_change_log_retention.up.sql:40-46 documents `p_purge_tombstones ... also drop 'delete' rows older than the window` and :48-52 defaults it TRUE (`p_purge_tombstones BOOLEAN DEFAULT TRUE`); back/app/internal/service/sync.go:169 calls `SELECT compact_change_log($1, $2, TRUE)`. Pull returns the flag — sync.go:136-140 `SnapshotRequired: oldestID > 0 && lastCursor < oldestID-1`, serialized as `snapshot_required` (back/app/internal/model/sync.go:26). The endpoint exists and is routed: back/app/internal/handler/handler.go:79 — `sync.GET("/snapshot", h.SyncSnapshot, mw.CheckLanguage())`, handler/sync_snapshot.go:14-23. Client half: `grep -rn snapshot lib/ test/ --include=*.dart` returns zero hits in lib/core/sync/ other than a stale comment at replication_service.dart:117 ('change_log has no compaction ... see the backend ask for a /sync/snapshot endpoint') — the code contradicts the comment. sync_api_client.dart:90-97 reads only `body['next_sync_cursor']` and `body['changes']`; apply_change.dart:138-139 reads only `body['changes']` and `body['next_sync_cursor']`. `SyncPullPage.body` does carry `snapshot_required` through, but no reader exists. Latency confirmed: back/app/internal/app/cron_change_log.go:20-34 — 'DISABLED BY DEFAULT ... if os.Getenv("CHANGE_LOG_COMPACTION_ENABLED") != "true" { ... return }'.

### User impact

Latent today, catastrophic the day someone sets CHANGE_LOG_COMPACTION_ENABLED=true. A terminal offline longer than the 30-day window gets `snapshot_required: true`, ignores it, keeps pulling from a cursor below the surviving tail, receives a partial catch-up it treats as complete, and silently serves a replica missing every change the compactor removed — with no bootstrap path taken and no indication anything is wrong.

---

## `S5b` — Replicated entities with no reader

**Area:** Sync & replica integrity  
**First pass:** PARTIAL / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Mechanically re-derived: extracted all 38 entity names from lib/core/db/entity_registry.dart and grepped each across lib/ excluding the registry file itself. TWENTY-ONE have zero references of any kind — not merely no reader, but no mention at all: attendances, bill_daily_counters, compound_stock, compounds_details, deduction_act_groups, deduction_item_ingredients, deduction_items, deductions, goods_details, ingredient_groups, ingredient_stock, ingredient_stock_movements, inventories, inventory_items, invoice_detailed, invoices, modifier_calculation, order_item_modifiers, storages, suppliers, user_payments. The other 17 all have references (cash_registers 1, ingredient_visibility 3, calculation 8, group_transactions 11, branches 13, compounds 26, translations 27, departments 28, order_items 34, ingredients 35, transactions 50, users 54, cafe_tables 60, halls 140, orders 210, categories 215, goods 368). Entity count confirmed at 38 (`grep -c "name: '"` = 38).

The repo's own test corroborates two of them — test/registry_backend_pin_test.dart:67-70: "`modifier_calculation` and `order_item_modifiers` are replicated because the tech-card and order-line shapes reference them, but no screen renders a modifier name or price, so a mirror would have no reader."

They are still stored: apply_change.dart:173-180 looks the entity up in kEntitiesByName and applies it regardless of whether anything reads it — `final spec = kEntitiesByName[entity]; if (spec == null) { ... return stats._add(skippedUnknown: n); }` — and local_database.dart creates a table and indexes for every registry entry.

### Correction to the original claim

The count is wrong: it is 21, not 19. The claim's own list expands to 20 (deduction_* is four entities: deduction_act_groups, deduction_item_ingredients, deduction_items, deductions), and it omits `order_item_modifiers`, which also has zero references. The claim also understates the situation — these entities have no reader AND no writer AND no mention anywhere in lib/ outside the registry line that creates them.

### User impact

Every terminal downloads, parses, indexes and stores rows for 21 entities no screen will ever show. The insert-heavy ones (ingredient_stock_movements above all — the backend writes one per ingredient per order line, see order.go:2951-2966) dominate long-run local database growth and bootstrap time on a device that gains nothing from them. Combined with S7's absence of any pruning, this is the bulk of the storage the device will never reclaim.

---

## `S5c` — Migration-71 backfill row cap

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

back/app/migrations/tenants/71_change_log_triggers_batch2.up.sql:110 sets the cap — `v_cap := COALESCE(NULLIF(current_setting('app.change_log_backfill_max', true), '')::BIGINT, 50000);` — and lines 136-142 are the skip: `EXECUTE format('SELECT count(*) FROM %I t WHERE %s', v_tbl, v_where) INTO v_count; IF v_count > v_cap THEN RAISE NOTICE 'change_log backfill: % has % live rows, over the % cap — SKIPPED. Run scripts/change_log_backfill.sql for schema % to finish it.', v_tbl, v_count, v_cap, current_schema(); CONTINUE; END IF;` A RAISE NOTICE is not an error — the migration reports success and the tool moves on.

The affected list is lines 87-91: `v_tables TEXT[] := ARRAY['transactions', 'group_transactions', 'cash_registers', 'ingredient_visibility', 'table_time_sessions', 'modifiers', 'goods_modifiers', 'printer_settings', 'cash_register_shifts'];` — so it is not only `transactions`.

Soft-deleted rows are excluded from the backfill too (lines 127-133 set `v_where := 'deleted_at = 0'`), which is deliberate and documented.

And the consequence is live, not theoretical: the transactions ledger screen reads the local replica now — transactions_list_controller.dart:76 `_local.getTransactions(...)` → transactions_repository_impl.dart:68 `_query = TransactionsQuery(replicaDb)` → transactions_query.dart:49-53 `SELECT data FROM transactions $where ORDER BY date DESC, id LIMIT ? OFFSET ?`.

### Correction to the original claim

Two things the claim leaves out. (1) The cap is not hard-coded at 50000 — it is `app.change_log_backfill_max` with 50000 only as the default, and scripts/change_log_backfill.sql exists as the documented remediation the notice points at. (2) The registry's own comment at entity_registry.dart:546-550 claiming `TransactionsListController.getTransactions` "still pages over REST through MainRepository, so TransactionsQuery ... are a finished read path with no caller" is STALE — the controller now reads the replica, so the gap is user-visible rather than dormant.

### User impact

On a tenant that had more than 50 000 live transactions when migration 71 ran, the ledger screen shows only transactions created or edited after that migration. A manager scrolling back finds the history simply absent — no error, no gap marker, just a list that ends. The same silent truncation applies to cash_registers and group_transactions on a large tenant, which would leave pickers missing entries that exist on the server.

---

## `S6b` — Whole-row replace is the default write mode

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  
**In flight:** rests on another session's uncommitted work  

### Evidence

THE MECHANISM — lib/core/outbox/local_writer.dart:64 `bool merge = false,` and :68 `final payload = merge ? {...?_db.byId(entity, id), ...row} : row;` — the default path passes `row` through untouched. lib/core/db/local_database.dart:351-368 `upsert` then writes the whole blob: `final values = <Object?>[ id, for (final c in spec.promoted) _coerce(data[c.name], c.type), _deletedAt(data), jsonEncode(data), DateTime.now().millisecondsSinceEpoch, ];` followed by `INSERT OR REPLACE INTO ${spec.name} ...`. Every server field absent from `data` becomes NULL in its promoted column and vanishes from the blob. The class's own doc at local_writer.dart:44-47 states it: "A replicated row is stored as one JSON blob and [LocalDatabase.upsert] replaces that blob wholesale".

CURRENT CALLERS ARE SAFE, BY HAND — only 5 sites pass `merge: true` (transactions_repository_impl.dart:200,229; service_charge_repository_impl.dart:50; payment_repository_impl.dart:153,178). The merge:false sites hand-roll the same merge: halls_tables_local_repository_impl.dart:93-98 `final existing = _db.byId(entity, id) ?? const <String, dynamic>{}; _writer.write(entity: entity, id: id, row: {...existing, ...changes, 'id': id}, request: changes);` and menu_admin_local_repository_impl.dart:157. orders_repository_impl.dart:282 and :386 are genuine whole-row writes (a create, and a transfer built from `Map.from(current)..['table_id'] = ...`). So the claim's "all current callers are safe but nothing enforces it and the default is the dangerous one" holds exactly.

THE INCIDENT EVIDENCE — the blanking write is still live in HEAD: `git show HEAD:.../orders_repository_impl.dart` line 120 `_applier.applyOne(entity: 'orders', action: 'create', payload: row);` where line 116 is `final row = Map<String, dynamic>.from(json)..remove('items');` — a bill projection, no created_at/paid_at.

### Correction to the original claim

Two qualifications. (1) The schema-v5 repair the claim cites as proof is NOT landed — `git diff lib/core/db/local_database.dart` shows `-  static const schemaVersion = 4;` / `+  static const schemaVersion = 5;` and `+ void repairBlankedOrderTimestamps()` as UNCOMMITTED work by the other session, alongside the fix in orders_repository_impl.dart. So "schema v5 exists" is true only of the working tree, and the defect it repairs is still shipping in HEAD. (2) The historic blanking came through `ChangeApplier.applyOne`, not literally `LocalWriter.write(merge:false)`; both funnel into the same `LocalDatabase.upsert` whole-blob replace, which is what the claim's first sentence correctly identifies as the root cause.

### User impact

A cashier's paid bill disappears from Archives under Today, Week, Month, Year and any picked range — visible only under "All" — because created_at and paid_at were nulled and ArchivesQuery filters on COALESCE(paid_at, created_at). It looks like the check was deleted. Beyond that specific case, any future repository that calls write() without merge:true silently erases every server field it did not happen to include, with no compile error, no validator and no test to catch it.

---

## `S6c` — A null in a merge patch clears a stored field

**Area:** Sync & replica integrity  
**First pass:** PARTIAL / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

FIRST HALF CONFIRMED — lib/core/outbox/local_writer.dart:68 `final payload = merge ? {...?_db.byId(entity, id), ...row} : row;` A Dart spread overwrites, so a key present with a null value replaces the stored one. Documented at :50-52: "A key present in the patch with a `null` value clears the stored one".

SECOND HALF REFUTED AS STATED — menu_admin_local_repository_impl.dart:157-162 is `final row = {...existing, ...body, 'id': mealId}..remove('calculations'); _writer.write(entity: 'goods', id: mealId, row: row, request: request);` — but `body` is NOT a flat goods row. menu_manage_screen.dart:367-386 builds it nested: `final payload = { 'good': { 'name': name, ..., 'color_code': null }, 'ingredient_calculations': _ingredientCalculations, 'compound_calculations': _compoundCalculations, };` and menu_manage_cubit.dart:82-86 passes it straight through. So the top-level keys spread over the goods row are `good`, `ingredient_calculations` and `compound_calculations` — none of which is a goods column, and `'color_code': null` is nested one level down and never reaches the row. Nothing is cleared.

THE REAL INSTANCE IN THAT FILE IS updateTranslation — menu_admin_local_repository_impl.dart:193-198 `_writer.write(entity: 'translations', id: id, row: {...existing, ...body, 'id': id}, request: body);` with body from menu_manage_screen.dart:315 `final body = {'en': en, 'ru': ru, 'uz': uz};` where the values come from `_nameEnCtrl.text.trim()` / `_nameRuCtrl.text.trim()` (lines 343-344). Leaving the EN and RU boxes blank while editing the Uzbek name spreads `{'en': '', 'ru': '', 'uz': name}` — blanking the stored translations. Empty strings, not nulls, and it is sent to the server too (`request: body`), so it is not a local-only divergence.

### Correction to the original claim

The named example is wrong. `saveGood` spreads a nested `{good:…, ingredient_calculations:…, compound_calculations:…}` envelope whose keys collide with no goods column, so it clears nothing — instead it pollutes the stored row with three junk keys AND leaves the good's name and price un-updated locally (they stay at the `existing` values), so the edit is invisible on the menu list until the server round-trips. Also, neither site uses `merge:` — both hand-roll `{...existing, ...body}` with merge defaulting to false. The claim's pattern is real; the file's real victim is `updateTranslation` (empty strings), not `saveGood` (nulls).

### User impact

Editing a dish's Uzbek name while leaving the English/Russian fields blank wipes the existing English and Russian translations, locally and on the server, with no warning. Separately, saving an edited dish does not update its name or price in the local menu until a pull returns — the opposite of the local-first behaviour the write path promises — and leaves three non-column keys in the stored row.

---

## `S7` — No pruning of any kind; bootstrap replays all history

**Area:** Sync & replica integrity  
**First pass:** PARTIAL / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

NO PRUNING — CONFIRMED RIGOROUSLY. `grep -rni "vacuum" lib/ --include=*.dart` returns zero hits (only `@pragma('vm:prefer-inline')` noise); the only PRAGMAs are local_database.dart:87-89 `journal_mode = WAL`, `synchronous = NORMAL`, `foreign_keys = OFF` — no auto_vacuum. `grep -rn "DELETE FROM" lib/` returns exactly 9 sites, and none is retention: local_database.dart:374 `DELETE FROM $entity WHERE id = ?` (feed-driven deleteRow), :562 pruneTableStatuses (local occupancy only), :610 evictTableTimer, :687/:708 _provisional/_pending guards, :765/:776 clearAll (full tenant wipe on brand/branch switch), outbox_store.dart:267/:331 (outbox rows). No row cap, no age cut-off, no size check anywhere.

SOFT-DELETED ROWS KEEP THEIR BLOB — CONFIRMED. A soft delete arrives as an UPDATE with deleted_at != 0, and local_database.dart:357 stores `jsonEncode(data)` in full with `_deletedAt(data)` set. Only a change_log `delete` action hard-deletes (apply_change.dart:217 `_db.deleteRow(entity, entityId)`).

IMAGE BLOBS NEVER EVICTED — CONFIRMED. local_database.dart:174-176 `CREATE TABLE IF NOT EXISTS ${LocalTables.images} (... bytes BLOB NOT NULL ...)`; the only writer is :639-644 `saveImage` (`INSERT OR REPLACE`), the only readers :627 and :660. No DELETE touches _images except clearAll.

BOOTSTRAP FROM CURSOR 0 — CONFIRMED, AND WORSE THAN CLAIMED. replication_service.dart:219-226 `bootstrap()` just calls `drain(maxBatches: bootstrapMaxBatches)`, and drain reads `final cursor = _db.syncCursor;` (:153) which local_database.dart:742 defines as `int.tryParse(getMeta(_cursorKey) ?? '') ?? 0`. Ceiling is replication_service.dart:120 `static const bootstrapMaxBatches = 20000;` × sync_api_client.dart:61 `static const batchSize = 500` = 10M rows, fetched one awaited round trip at a time (:154 `final page = await _api.pull(...)` inside a `while`). The backend HAS a snapshot path the client never uses: handler.go:79 `sync.GET("/snapshot", h.SyncSnapshot, ...)`, and sync.go:135 returns `SnapshotRequired: oldestID > 0 && lastCursor < oldestID-1` — sync_api_client.dart:88-96 puts the whole `data` map in `body` and apply_change.dart:138-139 reads only `body['changes']` and `body['next_sync_cursor']`, so `snapshot_required` is silently discarded.

PER-ORDER MULTIPLICATION SANITY-CHECK (backend settlement). order.go:2911-2966, per order item, loops `for _, u := range allUsages` (one entry per tech-card ingredient, plus modifier expansions) and per iteration issues: `q.RemoveFromIngredientStock` (UPDATE ingredient_stock), `insertMovementWithFamilyCheck` (INSERT ingredient_stock_movements), then per touched key `anchorRebalanceAfterInsert` → stock_calculation_helper.go:166-190 `recomputeAnchorStockBefore` (UPDATE of a movement row) + `q.UpdateIngredientStockExplicit` (UPDATE ingredient_stock). Both tables carry triggers (8_movements.up.sql: trg_change_log_ingredient_stock, trg_change_log_ingredient_stock_movements), so that is roughly 3-4 change_log rows per (item × ingredient), on top of the orders row's own status transitions. A 5-line order of 4-ingredient dishes is on the order of 60-80 change_log rows.

### Correction to the original claim

The claim is right on every structural point and needs two corrections plus one flag. (1) The SIZE ESTIMATE IS A MODEL, NOT A MEASUREMENT — I did not measure a device, and the claim states no throughput assumption. More importantly its implied mechanism is partly wrong: repeated UPDATEs do NOT grow local storage, because local_database.dart:363 writes `INSERT OR REPLACE INTO ... ` keyed by id, so the thousands of ingredient_stock updates per day collapse onto one row per (ingredient, storage). Local growth is driven only by INSERT-only entities — ingredient_stock_movements above all, plus orders, order_items, transactions, invoices. The update churn inflates FEED volume and bootstrap round trips, not disk. Directionally the ~80%-unread split is plausible (movements outnumber order_items ~4:1 per line and nothing reads them), but treat the GB figure as an unvalidated model. (2) The backend is no longer append-only forever: 73_change_log_retention.up.sql defines `compact_change_log()` keeping one row per (entity, entity_id) beyond a 30-day window — BUT cron_change_log.go:32 gates it `if os.Getenv("CHANGE_LOG_COMPACTION_ENABLED") != "true" { ... return }`, and the variable is set nowhere in docker-compose*.yml, Dockerfile or Makefile, so it is off and the claim's from-the-beginning replay holds today. (3) IN-FLIGHT: local_database.dart is being edited by the other session (schemaVersion 4→5 plus repairBlankedOrderTimestamps); that diff adds no pruning, so the finding is unaffected.

### User impact

A terminal's replica only ever grows: nothing is ever deleted, compacted, aged out or VACUUMed short of a full brand/branch wipe, and most of what accumulates (S5b) no screen reads. On a POS box with limited storage that ends as a device that fills up, and SQLite has no way to reclaim the freed pages of soft-deleted rows without a VACUUM that never runs. Separately, a first login on an established tenant is a foreground wait on thousands of sequential 500-row round trips replaying every mutation the venue has ever made — a new terminal at the counter cannot be used until it finishes, and the server-side snapshot endpoint built to avoid exactly this is never called.

### Second reader

WHAT SURVIVES:
(1) No client-side retention. Re-ran the greps: `vacuum` = 0 hits in lib/; the only PRAGMAs are local_database.dart:85-88 `journal_mode = WAL` / `synchronous = NORMAL` / `foreign_keys = OFF`. `DELETE FROM` = 9 sites, none age- or size-based (local_database.dart:374 feed-driven deleteRow, :562 pruneTableStatuses, :610 evictTableTimer, :687/:708 provisional/pending guards, :765/:776 clearAll; outbox_store.dart:267/:331). A broad grep for `retention|purge|prune|evict|compact|older than|maxRows|rowLimit` over lib/ returns only UI "compact breakpoint" noise and orders_repository.dart:26 `evictOrderDetail`. CONFIRMED.
(2) The real growth driver is stronger than the claim states, and I verified it: entity_registry.dart:381-395 registers `ingredient_stock_movements` as a replicated entity, and back/app/migrations/tenants/8_movements.up.sql:136 `CREATE TRIGGER trg_change_log_ingredient_stock_movements AFTER INSERT OR UPDATE OR DELETE ... EXECUTE FUNCTION log_change('id')`. sync.go:57-61 `SELECT id, brand_id, entity, action, entity_id, payload FROM change_log WHERE id > $1` — no entity filter, no branch filter — so every terminal in the brand receives and stores every settlement movement row forever.
(3) Bootstrap does start at cursor 0 and replays the whole retained feed. replication_service.dart:219-226 bootstrap -> drain; drain reads `final cursor = _db.syncCursor` (:153) = local_database.dart:742 `int.tryParse(getMeta(_cursorKey) ?? '') ?? 0`. CONFIRMED.
(4) `/sync/snapshot` exists (handler.go:79 `sync.GET("/snapshot", h.SyncSnapshot, ...)`, model/sync_snapshot.go) and the client never calls it: sync_api_client.dart:63-64 declares only `pullPath`/`pushPath`, and `grep -rn "snapshot_required\|sync/snapshot" lib/` = 0 hits. CONFIRMED.

WHAT BREAKS:
(A) The VACUUM half is incoherent. "SQLite has no way to reclaim the freed pages of soft-deleted rows without a VACUUM" — a soft-deleted row is a *live* row (local_database.dart:350-367 upsert writes `_deletedAt(data)` + full `jsonEncode(data)` via INSERT OR REPLACE); it occupies live pages, so VACUUM would reclaim nothing from it. And the replica performs no bulk delete outside clearAll (:762-779), which is immediately followed by resetAndBootstrap's refill (replication_service.dart:255-259 `_db.clearAll(); return bootstrap(...)`) that reuses the freed pages. The finding is the absence of *retention*, not the absence of VACUUM; the VACUUM evidence is inert.
(B) The disk math is off by roughly an order of magnitude. The "60-80 change_log rows per order" backend multiplication is evidence for bootstrap *duration*, not for disk. local_database.dart:363-367 `INSERT OR REPLACE INTO ${spec.name} (...)` keyed on `id` means replaying N change_log rows yields at most one local row per distinct entity id. Local size tracks distinct business rows, not change_log volume.
(C) Image blobs are near-irrelevant. sync_engine.dart:392-397 `final have = db.cachedImageNames(); for (final row in db.allOf('goods')) { final ref = row['picture_url']; ... if (!have.contains(ref)) refs.add(ref); }` and local_database.dart:640-644 saveImage is `INSERT OR REPLACE` on `object_name`. The set is bounded by distinct menu picture_urls, not by traffic. Listing it beside unbounded movement rows overstates it.
(D) The foreground-wait impact does not exist at HEAD. `git show HEAD:.../login_data_scope_service.dart` has `if (brandChanged || firstTime) { unawaited(_runFirstTimeSetup()); }` and inside it `unawaited(_syncEngine.replication.bootstrap());` — background, login returns immediately. The blocking path (LoginDataScope enum, runInitialSetup, login_pin_cubit.dart:148-160 `if (scope == LoginDataScope.initialSetup) ... AppRoutes.initialSetupScreen`, and the untracked `lib/features/view/auth/presentation/pages/initial_setup/initial_setup_screen.dart`) is all uncommitted. `git status` shows login_data_scope_service.dart / login_pin_cubit.dart / app_pages.dart / app_routes.dart modified and initial_setup/ untracked.
(E) `snapshot_required` being discarded is currently harmless, and its purpose is misdescribed. cron_change_log.go:32 `if os.Getenv("CHANGE_LOG_COMPACTION_ENABLED") != "true" { ...return }` — and grepping the whole backend outside .go files (.env, .env.example, docker-compose.dev.yml, .gitlab-ci.yml) finds zero occurrences of CHANGE_LOG_*. So compaction never runs, `oldestID` stays 1, and sync.go:144 `SnapshotRequired: oldestID > 0 && lastCursor < oldestID-1` is false on every real pull. Snapshot is a gap-recovery path for compacted feeds, not a bootstrap-speed shortcut.
(F) 10M is a ceiling, not a workload. replication_service.dart:113-120 documents bootstrapMaxBatches as deliberately "generous rather than tight", and :227-231 marks bootstrapped only on `caughtUp`, so exhausting it leaves a usable partial replica.

**Second reader's correction:** Four things are wrong. (1) The VACUUM angle is a red herring and internally contradictory: soft-deleted rows are live rows on live pages that VACUUM cannot reclaim, and the replica never bulk-deletes outside clearAll (which is immediately refilled, reusing the pages). The defect is missing retention, full stop. (2) The per-order change_log multiplication sizes bootstrap TIME, not disk — local upsert is INSERT OR REPLACE keyed on id (local_database.dart:363), so 60-80 change_log rows per order collapse to far fewer stored rows. (3) Image blobs are bounded by distinct goods.picture_url values (sync_engine.dart:392-397 skips what it already has), not by traffic; near-zero blast radius, and it should not sit beside the movements table. (4) IN_FLIGHT: the entire 'a new terminal cannot be used until bootstrap finishes' impact is the concurrent session's uncommitted work. At HEAD login fires `unawaited(_runFirstTimeSetup())` and returns immediately; the blocking InitialSetupScreen, LoginDataScope enum and runInitialSetup are uncommitted (initial_setup_screen.dart is untracked). Even in-flight the screen offers Retry and 'Continue anyway' once the attempt returns — though there is no cancel while a pull is in progress, so the in-flight version does trap the operator for the duration. Also worth correcting the direction of the snapshot_required gap: with CHANGE_LOG_COMPACTION_ENABLED unset everywhere (cron_change_log.go:32; no occurrence in .env/.env.example/docker-compose/.gitlab-ci), oldestID is 1 and the flag is always false today, so discarding it costs nothing now. The latent bug is the inverse of the claim: the day ops enables compaction, a terminal offline past the 30-day window will apply a partial catch-up and treat it as complete, because sync_api_client.dart:88-96 puts the whole data map in `body` and apply_change.dart:139-140 reads only `changes` and `next_sync_cursor`. Severity down to MEDIUM: at HEAD nothing here blocks or breaks a user today; it is slow-burn disk growth plus a first-login that is slow but backgrounded.

**Second reader's impact assessment:** On a busy venue every terminal permanently accumulates one local row per ingredient movement the venue has ever settled (ingredient_stock_movements is replicated, entity_registry.dart:381, and triggered on every settlement), plus every order, order_item and transaction, with no age cut-off, row cap or size check anywhere in the client. Over a year or two on a low-storage POS box that is real disk pressure — but it is proportional to distinct business rows, not to the 60-80 change_log rows per order the finding cites, so the burn rate is roughly an order of magnitude slower than stated, and the missing VACUUM contributes nothing to it. First login on an established tenant does replay the full feed 500 rows at a time; at HEAD that runs behind the app, so the operator sees a slowly-populating floor plan rather than a lockout. Only with the other session's uncommitted change does it become a screen the cashier waits in front of, and that screen ships with Retry and Continue-anyway.

---

## `S8a` — lastSyncAt reports success while replication is failing

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/core/sync/sync_engine.dart:262-266: `await _outbox.drain(); await _replication.drain(); await _fillFeedGaps(); _refreshUserProfile(); _recordSync();` — both drain results are discarded at the statement level, and _recordSync() follows unconditionally.

NEITHER DRAIN THROWS, so the catch at :267 cannot save it. replication_service.dart:198-206 wraps the whole loop: `} catch (e, st) { if (kDebugMode) debugPrint('[Replication] drain failed: $e\n$st'); return ReplicationResult(outcome: ReplicationOutcome.failed, ...); }`. outbox_drainer.dart:103-108 swallows executor throws too: `} catch (e) { result = OutboxExecutionResult.retry('$e'); }`, and its only try has a bare `finally` (:126-128) with no catch that rethrows past the return at :133.

_recordSync writes the timestamp — sync_engine.dart:90-94 `void _recordSync() { final now = DateTime.now(); lastSyncAt.value = now; unawaited(_prefs.setString(_lastSyncKey, now.toIso8601String())); }` — and it is rendered: sync_status_section.dart:261-273 `ValueListenableBuilder<DateTime?>(valueListenable: syncEngine.lastSyncAt, ...)` with title 'Oxirgi sinxronizatsiya' and subtitle `"${lastSync.timeAgo} (${lastSync.toHourMinute})"`.

ReplicationOutcome.failed IS NEVER READ OUTSIDE replication_service.dart — `grep -rn "ReplicationOutcome\." lib/ test/` outside that file returns only two production reads, both of `caughtUp`: sync_engine.dart:246 `if (result.outcome == ReplicationOutcome.caughtUp)` and login_data_scope_service.dart:194 `if (result.outcome == ReplicationOutcome.caughtUp && filled)`. Every other hit is in test/replication_service_test.dart.

### Correction to the original claim

The claim understates one case. In LAN client mode _recordSync is called even with NO connectivity at all: sync_engine.dart:229 opens `if (_connectivity.isOnline) { ... }` and :253-254 sit OUTSIDE it — `_recordSync(); return;`. So a follower with the network down stamps a fresh success every 60-second tick while literally nothing ran, which contradicts the field's own doc at :76-80 ("not merely 'tick() was called'"). The non-client path at least gates on `if (!_connectivity.isOnline) return;` (:256).

### User impact

The settings screen's 'Oxirgi sinxronizatsiya' card reads "just now" while the backend has been rejecting every pull for days, or while a LAN follower has had no network at all. The one card an operator would open to answer "is this terminal actually syncing?" answers yes unconditionally. Nothing anywhere consumes ReplicationOutcome.failed, so a persistently failing feed has no path to any UI, log surface or retry policy.

---

## `S8b` — The outbox card reads a dead queue and "Sync now" is permanently disabled

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

THE CARD READS THE WRONG QUEUE — sync_status_section.dart:211-216 `final queue = inject<OfflineQueueService>(); ... return ValueListenableBuilder<Box<PendingOperation>>(valueListenable: queue.listenable, builder: (context, box, _) { final depth = box.length;` — a Hive box (offline_queue_service.dart:32-34 `static const _boxName = 'offline_queue'; late final Box<PendingOperation> _box;`).

THAT BOX HAS NO PRODUCER — `grep -rn "PendingOperation(" lib/ --include=*.dart` (excluding .g.dart) finds three constructions: offline_queue_service.dart:79 (the constructor), quarantined_operation.dart:69 `toRetryable()`, and lan_hub_service.dart:242 — and that last one is executed, never enqueued: :250 `final result = await inject<OfflineQueueService>().executeRelayedOp(inject<DioClient>(), op);`, and executeRelayedOp (offline_queue_service.dart:280-291) only calls `_executeOp` and maps the outcome; it never touches `_box`. `OfflineQueueService.enqueue` has zero callers in lib/ outside `retryQuarantined` (:105 `await enqueue(q.toRetryable());`), and `syncAll` (:156) and `relayViaLan` (:236) have zero callers anywhere in lib/.

THE BUTTON IS GATED ON THAT DEPTH — sync_status_section.dart:236-241: `trailing: _SmallButton(label: 'Hozir sinxronlash', onTap: depth == 0 ? null : _syncNow, ...)`, and _syncNow (:200-207) is the sole caller of `inject<SyncEngine>().tick(force: true)`. With depth permanently 0, onTap is permanently null. force:true is what reaches `if (force) _outboxStore.clearBackoff();` (sync_engine.dart:242 and :257) — no other call site passes force.

THE REAL OUTBOX IS NEVER SHOWN — outbox_store.dart:248-252 defines `int get depth => _countWhere(OutboxStatus.pending);`, `int get quarantineDepth => _countWhere(OutboxStatus.quarantined);` and `bool get hasWork => depth > 0;`, and `grep -rn "OutboxStore" lib/` returns no hit under presentation/, screen, section or widget. Text confirmed verbatim at :232-234: `subtitle: depth == 0 ? "Barcha operatsiyalar sinxronlangan" : '$depth ta operatsiya kutilmoqda'`. Identical in HEAD (lines 209/228/237), so this does not depend on the other session's in-flight edits to this file.

### Correction to the original claim

One qualification on "permanently 0": the Hive box is persistent and is opened, not cleared (offline_queue_service.dart:40 `final box = await Hive.openBox<PendingOperation>(_boxName);`), and clearAll only wipes the SQLite replica. A terminal upgraded from a build that did enqueue could carry residual rows forever — the card would then show a non-zero depth and enable the button, but nothing drains that box (syncAll has no callers), so those ops would sit there permanently. On a fresh install the claim is exactly right.

### User impact

The card the operator opens to check the outbox always says "Barcha operatsiyalar sinxronlangan" ("all operations are synced") no matter how many real writes are stuck in the SQLite outbox — including quarantined payments. And because the button is disabled whenever that reads 0, the only manual retry in the product is unreachable: a terminal whose outbox operations are all sitting in backoff after an outage that has since ended has no way for a cashier to force a retry, and must wait out the per-operation backoff.

---

## `S8c` — The quarantine card reads the same dead queue

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

sync_status_section.dart:537-542 — `final queue = inject<OfflineQueueService>(); ... return ValueListenableBuilder<Box<QuarantinedOperation>>(valueListenable: queue.quarantineListenable, builder: (context, box, _) { final items = queue.quarantined;` — the same dead service's second Hive box (offline_queue_service.dart:33-35 `static const _quarantineBoxName = 'offline_queue_quarantine'; late final Box<QuarantinedOperation> _quarantineBox;`).

BOTH ACTIONS TARGET IT — :583 `await inject<OfflineQueueService>().retryQuarantined(widget.op.id);` and :588 `await inject<OfflineQueueService>().dismissQuarantined(widget.op.id);`. retryQuarantined (offline_queue_service.dart:105) calls `await enqueue(q.toRetryable());`, which puts the op back into the box that nothing drains — `syncAll` and `relayViaLan` have zero callers in lib/.

THE BOX CAN NEVER FILL — its only writer is offline_queue_service.dart:97 `_quarantineBox.put(op.id, QuarantinedOperation.fromDropped(op, reason));`, reached only from the syncAll/relayViaLan paths that are never invoked.

MEANWHILE THE REAL QUARANTINE IS INVISIBLE — outbox_drainer.dart quarantines into the SQLite outbox (:98 and :123 `quarantined++` via `_fail(op, ..., permanent: true)`), and outbox_store.dart exposes exactly the API this card would need — :239-243 `List<OutboxOperation> quarantined({int limit = 200}) { ... [OutboxStatus.quarantined.name, limit]); }`, :250 `int get quarantineDepth`, :315-323 `requeue` (`[OutboxStatus.pending.name, id, OutboxStatus.quarantined.name]`) and :332 the discard. No presentation code references OutboxStore. Identical in HEAD (lines 473/519/524).

### User impact

A write the server permanently rejected — a payment, a staff create, an order transfer — is quarantined in the SQLite outbox and released from its local pending guard (outbox_drainer.dart:237-244), so the row visibly reverts on screen with no explanation. The 'Karantin' card that exists to explain exactly that reads a different, permanently empty store and reports "Rad etilgan operatsiyalar yo'q" ("no rejected operations"). The retry and dismiss buttons that would resolve it can never appear, and OutboxStore.requeue — the function that would put a rejected operation back in line — has no caller in the app.

---

## `W3` — clearAll destroys undrained writes

**Area:** Write path & outbox  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  

### Evidence

lib/core/db/local_database.dart:761-779 — `void clearAll() { transaction(() { for (final spec in kReplicatedEntities) { _db.execute('DELETE FROM ${spec.name}'); ... } for (final table in LocalTables.all) { _db.execute('DELETE FROM $table'); ... } ... }); }`. lib/core/db/entity_registry.dart:228-236 — `static const all = { meta, outbox, pending, tableStatus, provisional, tableTimers, images };` with `static const outbox = '_outbox';` (:177). So the outbox table is wiped.
Caller 1 — lib/features/view/auth/presentation/cubit/auth/auth_cubit.dart:136 `inject<replica.LocalDatabase>().clearAll();` inside `logoutFromApp`, preceded only by comment prose ("Safe to empty the outbox along with it"); no depth read of any kind in the method (:115-141).
Caller 2 — lib/core/sync/replication_service.dart:244-248 `Future<ReplicationResult> resetAndBootstrap({...}) async { _db.clearAll(); return bootstrap(onProgress: onProgress); }`, whose own doc at :241-243 says "callers must be sure the outbox is drained before switching tenants". Its one production caller, lib/core/services/auth/login_data_scope_service.dart:177 `? await replication.resetAndBootstrap(onProgress: onProgress)`, does no such check — `runInitialSetup` (:163-201) never touches `OutboxStore`, and the flag it keys on is set at :141 `_pendingReset = brandChanged;` purely from brand comparison.
What is destroyed: orders/pay ops live in this table (orders_outbox.dart:155-166 `orders/pay`, enqueued via LocalWriter → outbox_store.dart:52-74 `INSERT ... INTO ${LocalTables.outbox}`).

### User impact

A cashier who logs out (or a manager who logs into a different brand) while the terminal is offline loses every unsent write in one statement — queued payments, cancels, shift open/close, back-office edits — with no warning, no count, and no way to recover them.

### Second reader

WIPE MECHANIC — CONFIRMED, unchanged from HEAD. lib/core/db/local_database.dart:761-779 `void clearAll() { transaction(() { for (final spec in kReplicatedEntities) { _db.execute('DELETE FROM ${spec.name}'); ... } for (final table in LocalTables.all) { _db.execute('DELETE FROM $table'); ... } ... }); }`, and lib/core/db/entity_registry.dart:228-236 `static const all = { meta, outbox, pending, tableStatus, provisional, tableTimers, images };` with `static const outbox = '_outbox';` (entity_registry.dart:177). `git show HEAD:lib/core/db/local_database.dart` renders the identical body at :657-676, so this is committed behaviour, not the other session's edit.

CALLER 1 (logout) — REFUTED, IT IS DEAD CODE. lib/features/view/auth/presentation/cubit/auth/auth_cubit.dart:136 `inject<replica.LocalDatabase>().clearAll();` sits inside `AuthCubit.logoutFromApp` (:115), and `grep -rn "logoutFromApp" --include=*.dart .` over the whole tree (lib + test) returns only three non-plumbing hits: the two definitions (auth_cubit.dart:115, login_pin_cubit.dart:247) and ONE call site, login_pin_screen.dart:61 `onTap: () => cubit.logoutFromApp(...)` — where `cubit` is bound at login_pin_screen.dart:36 `final cubit = context.read<LoginPinCubit>();` under `BlocProvider(create: (context) => inject<LoginPinCubit>())` (:24). `LoginPinCubit.logoutFromApp` (login_pin_cubit.dart:247-259) calls only `_logoutUseCase.call(NoParams())` → `LogoutFromAppUseCase` → login_repository_impl.dart:53-59 `await _tokenStorage.deleteAll(); return const Right(true);` — tokens only, NO clearAll. `AuthCubit.logoutFromApp` has ZERO callers anywhere. The app's real logout button, lib/features/view/main/presentation/pages/main/widgets/logout_dialog.dart:77 `context.read<AuthCubit>().logout(onSuccess: ...)`, routes to `AuthCubit.logout` (auth_cubit.dart:52-65) → `LogoutUsecase` → login_repository_impl.dart:66-72 `await _tokenStorage.deleteUserSession();` — session only, brand preserved, no replica touched.

CALLER 2 (brand switch) — CONFIRMED and unguarded, but narrower than stated. lib/core/sync/replication_service.dart:244-248 `Future<ReplicationResult> resetAndBootstrap({...}) async { _db.clearAll(); return bootstrap(onProgress: onProgress); }` (file is git-clean). Its one production caller is lib/core/services/auth/login_data_scope_service.dart:177 `? await replication.resetAndBootstrap(onProgress: onProgress)`, gated on `_pendingReset`, set at :141 `_pendingReset = brandChanged;` where :113 `final brandChanged = last != null && last.brandId != brandId;`. `runInitialSetup` (:163-201) never reads outbox depth, and no guard exists elsewhere: `grep -rn "\.depth\|hasWork" --include=*.dart lib test` outside outbox_store.dart returns ONLY test files — `OutboxStore.depth` (:248) and `hasWork` (:252) have zero production callers, so nothing anywhere warns, counts, or drains before the wipe. What dies is real: lib/core/outbox/orders_outbox.dart enqueues `orders/pay` through LocalWriter → outbox_store.dart:52-74 `INSERT ... INTO ${LocalTables.outbox}`.

**Second reader's correction:** Two things are wrong. (1) The headline scenario — "a cashier who logs out ... loses every unsent write" — is FALSE. The clearAll on logout lives in `AuthCubit.logoutFromApp`, which has zero callers in the entire tree; both reachable logout buttons (logout_dialog.dart:77 → deleteUserSession, login_pin_screen.dart:61 → LoginPinCubit → deleteAll) clear tokens only and never touch the replica or the outbox. The evidence for Caller 1 was assembled from the method body without grepping for its callers. (2) The surviving path is the brand switch alone, and it is not merely "a manager logs into a different brand" incidentally — it requires `last.brandId != brandId` (login_data_scope_service.dart:113), i.e. an operator deliberately typing a DIFFERENT brand id and password at login_screen. A same-brand re-login yields brandChanged=false; a first-ever login takes the `firstTime` branch and still sets `_pendingReset = brandChanged` = false, so it runs plain `bootstrap()` with no wipe. Offline, the switch is narrower still: AuthCubit.loginWithBrandId falls back to `_offlineAuthCache.validateAndGetUser(req.brandId, req.password)` (auth_cubit.dart:89-95), which is keyed per brand, so an offline switch only works if the destination brand was already logged in on that same terminal. Note also that deleting the old tenant's outbox on a tenant switch is defensible — replaying brand A's payments into brand B's session would be a worse bug; the actual defect is the absence of any pre-switch drain attempt, depth check, or operator warning, not the DELETE itself. Severity downgraded HIGH → MEDIUM: silent unrecoverable loss is real, but it is gated behind one explicit, rare, cross-tenant operator action rather than the routine end-of-shift logout the claim describes. NOT in-flight: local_database.dart is dirty in the working tree but `clearAll` is byte-identical to HEAD, and auth_cubit.dart plus replication_service.dart are git-clean. login_data_scope_service.dart IS being edited by the other session (101 insertions), but its diff shows the brand-switch → resetAndBootstrap wiring pre-exists at HEAD (old comment: "resetAndBootstrap's first act below"), so the finding does not rest on their work.

**Second reader's impact assessment:** Only on a deliberate cross-brand re-provision of a terminal: a manager who signs the terminal into a different brand while its queue still holds unsent writes loses those writes — queued payments, cancels, shift open/close, back-office edits — silently, with no count and no recovery. A normal end-of-shift logout and a same-brand re-login lose nothing; the replica and outbox survive both untouched.

---

## `W4` — A cancel of an offline-added line is lost within one drain pass

**Area:** Write path & outbox  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / MEDIUM  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

Materialized snapshot: lib/core/outbox/outbox_store.dart:136-144 — `List<OutboxOperation> ready({int limit = 100}) { final rows = _db.select(...); return [for (final row in rows) OutboxOperation.fromRow(row)]; }` and outbox_drainer.dart:83 `for (final op in _store.ready(limit: limit)) {` — the whole list is built before the first send.
DB-only rewrite: outbox_drainer.dart:201-210 — `if (serverId != provisionalId) { _applier.applyOne(entity: op.entity, action: 'delete', entityId: provisionalId); _store.rewriteReferences(oldId: provisionalId, newId: serverId); }` then :212-217 `_applier.applyOne(entity: op.entity, action: 'update', entityId: serverId, payload: row!);`. `rewriteReferences` (outbox_store.dart:162-198) issues `UPDATE ${LocalTables.outbox} SET entity_id = ?, payload = ? WHERE id = ?` — it never touches the in-memory `OutboxOperation` objects the loop is holding.
Stale read in the handler: lib/core/outbox/orders_outbox.dart:122-129 — `send: (op) async { final lineId = op.entityId ?? ''; ... await dio.post(ListAPI.orderItemCancel(lineId), ...)` — `op` is the snapshot, so `lineId` is still the provisional P.
404 swallowed: same file :137-140 — `on DioException catch (e) { if (e.response?.statusCode == 404) { return const OutboxExecutionResult.succeeded(); }`.
The reconcile branch is reached even though the line was deleted locally: apply_change.dart:397-407 `applyLocalDelete` does `_db.deleteRow(entity, id); _db.markPending(entity, id);` — it does **not** clear the `_provisional` marker (local_database.dart:671-691), so `_db.isProvisional(op.entity, entityId)` at outbox_drainer.dart:150 is still true when the create acks.
Same pass, same chain, no block: both ops chain on `op.payload['order_id']` (orders_outbox.dart:81 and :121) and `blockedChains` is only populated on retry/permanent (outbox_drainer.dart:120, :124), never on success.

### Correction to the original claim

IN_FLIGHT — this depends entirely on the other session's uncommitted change. `git show HEAD:lib/features/view/main/data/repository/orders_repository_impl.dart` shows `addItems` used `_writer.write` (no provisional id) at HEAD; the working tree at :331-344 now uses `_writer.create(entity: 'order_items', id: ids[i], ...)`, which is what introduces the provisional-id reconcile for lines. The claim's chain of reasoning is otherwise exact.

### User impact

A cashier rings a line while offline, then voids it before the terminal reconnects. On reconnect the add and the void drain in the same pass: the add lands and reconcile re-inserts the line under the server's id, the void posts to the dead client uuid, 404s, and is booked as success. The voided item stays on the check and the guest is charged for it — silently, on both the terminal and the server.

### Second reader

MECHANISM HALF-CONFIRMED. (1) Snapshot is real: outbox_store.dart:136-144 `List<OutboxOperation> ready({int limit = 100}) { final rows = _db.select(...); return [for (final row in rows) OutboxOperation.fromRow(row)]; }` and outbox_drainer.dart:83 `for (final op in _store.ready(limit: limit)) {` — the list is materialized before the first send. (2) rewriteReferences writes only SQL: outbox_store.dart:180-185 `'UPDATE ${LocalTables.outbox} SET entity_id = ?, payload = ? WHERE id = ?'`. (3) The reconcile branch IS reached after a local void: apply_change.dart:397-407 `applyLocalDelete` does `_db.deleteRow(entity, id); _db.markPending(entity, id);` and never touches the `_provisional` table, which is a separate table (local_database.dart:679-683 `isProvisional` → `SELECT 1 FROM ${LocalTables.provisional}`), so outbox_drainer.dart:150 `_db.isProvisional(op.entity, entityId)` is still true. (4) The voided line IS re-inserted locally: outbox_drainer.dart:212-217 `_applier.applyOne(entity: op.entity, action: 'update', entityId: serverId, payload: row!)` → apply_change.dart:225-242 `_applyUpsert` only skips on `isPending(spec.name, id)`, and the server id was never pending.

DECISIVE REFUTATION — the 404 leg does not exist. The cancel endpoint never returns 404 for an unknown item id. back/app/internal/service/order.go:3805-3807: `existing, err := q.GetOrderItemByID(txCtx, id); if err != nil { return nil, fmt.Errorf("failed to get order item: %w", err) }` (the query is `WHERE order_items.id = $1 AND order_items.deleted_at = 0`, order.sql.go:1171-1175, so a client uuid yields ErrNoRows), and the handler maps every service error to 500: back/app/internal/handler/order.go:2348-2356 `item, err := ...CancelOrderItem(...); if err != nil { ... return c.JSON(http.StatusInternalServerError, ...) }`. Grepping the whole CancelOrderItem handler (order.go:2322-2360) for `StatusNotFound` returns nothing; its only non-2xx codes are 400 (missing/malformed uuid — a v4 client uuid parses fine) and 500. So orders_outbox.dart:144 `if (e.response?.statusCode == 404)` is never taken; control reaches :147 `return _mapDioError(e)` → :263-268 `if (code != null && code >= 400 && code < 500) permanent; return retry(...)` → **retry**, not "succeeded". Dio surfaces the 500 as a DioException with a populated response (dio_client.dart:41 `validateStatus: (status) => status != null && status < 400`).

SELF-HEALING, PROVEN BY RUNNING IT. I reproduced the exact scenario (create order_items 'P' via LocalWriter.create, void via LocalWriter.delete, one drain pass with the create returning server id 'S' and the cancel returning retry for any id != 'S'): PASS1 → `OutboxDrainResult(sent: 1, retrying: 1, ...)`, `cancel saw: [P]`, `row S after pass1: {id: S, ... status: pending}`, `pending ops after pass1: [order_items/delete:S]` — the DB row was already repointed. PASS2 → `cancel saw: [P, S]`, `sent: 1`, `pending ops after pass2: []`, `quarantined: 0`. The void reaches the server on the next pass. Additional guard the claim missed: a pay queued after the void cannot overtake it — orders/pay's default chain key is the order id (outbox_executor.dart chainKeyOf) and order_items/delete's is `op.payload['order_id']` (orders_outbox.dart:126), so the retry at outbox_drainer.dart:118-120 `blockedChains.add(chain)` blocks the pay until the cancel lands.

**Second reader's correction:** Two things are wrong. (a) The server returns HTTP 500, not 404, for a cancel against an unknown item id (handler/order.go:2348-2356), so the 404-swallow at orders_outbox.dart:144 is unreachable on this path; the stale send is mapped to `retry` by _mapDioError (orders_outbox.dart:263-268). (b) Because it retries rather than succeeding, the operation stays pending and its DB row has already been repointed to the server id by rewriteReferences, so the next drain pass sends the correct id and the void DOES land on the server — verified by running the scenario end to end. Nothing is 'booked as success', the void is not lost, and the server-side total is correct; a pay is additionally chain-blocked behind the retrying cancel. What survives is a wasted first attempt and a transient local resurrection: _reconcile re-inserts the voided line under the server id with status 'pending', and it stays visible until the cancel retries on the next SyncEngine tick (sync_engine.dart:73 `tickInterval = Duration(seconds: 60)`; backoff for attempt 1 is 5-10s) and the following pull delivers status='cancelled' — roughly one to two minutes, not permanent. Severity HIGH→MEDIUM: transient UI/receipt inaccuracy, not silent money loss on either side. Also note the finding is scoped narrower than stated: it applies only to lines added by addItems (LocalWriter.create, provisional); lines rung as part of the initial order create ride inside the orders/create body (_writeOrderWithItems, orders_repository_impl.dart:289-302) with no provisional marker and no rewriteReferences at all, so a void of one of those keeps the client uuid, 500s eight times and quarantines — a different and arguably worse path this finding does not describe.

**Second reader's impact assessment:** A cashier voids a line that was rung offline via 'add items'. On reconnect the line briefly reappears on the open check at its full price (status 'pending', so it counts toward the on-screen total and would print on a receipt or kitchen ticket issued in that window). Roughly 60-120 seconds later the cancel retries with the correct server id, the server cancels the line, and the next pull marks it cancelled locally. The guest is not overcharged server-side and the void is not lost; a payment taken in the window is chain-blocked behind the cancel, so the settled bill is correct.

---

## `W5` — The legacy queue is a live trapdoor

**Area:** Write path & outbox  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Constructed every cold start: lib/di.dart:267-268 — `final offlineQueue = await OfflineQueueService.init(); inject.registerSingleton<OfflineQueueService>(offlineQueue);`, and `init()` (offline_queue_service.dart:39-44) opens both Hive boxes unconditionally.
Zero production callers for the drains: grep of lib/ for `syncAll` yields only doc comments plus its own definition at offline_queue_service.dart:156; `relayViaLan` only doc comments plus its definition at :236 — the one former call site is now a comment block, sync_engine.dart:217-228 ("The legacy queue's `relayViaLan` call used to sit here... nothing enqueues a `PendingOperation` any more"). The follower half is dead too: `relayOperation` (lan_hub_service.dart:272) has zero callers in lib/. Real call sites exist only in test/offline_queue_quarantine_test.dart and test/full_shift_soak_test.dart.
The retry button feeds the dead queue: sync_status_section.dart:583 `await inject<OfflineQueueService>().retryQuarantined(widget.op.id);` → offline_queue_service.dart:102-107 `final q = _quarantineBox.get(id); ... await enqueue(q.toRetryable()); await _quarantineBox.delete(id);` → :82 `await _box.put(op.id, op);`. Nothing ever reads `_box` again except `syncAll`/`relayViaLan`.
No migration: grep -i 'migrat' over lib/core/services/offline_queue/, lib/core/outbox/, lib/di.dart and lib/main.dart returns only the unrelated token/auth-cache `migrateLegacyPlaintext` calls (di.dart:185-186). Nothing reads the Hive box into `OutboxStore`.
One live entry point survives: lan_hub_service.dart:232-258 `_handleRelayOp` reconstructs a `PendingOperation` from a peer message and calls `inject<OfflineQueueService>().executeRelayedOp(inject<DioClient>(), op)` (:250).

### Correction to the original claim

Minor addition: the class is not fully callerless — `executeRelayedOp` still has one live production call site, the leader-side LAN relay handler (lan_hub_service.dart:250), so a peer on an older build could still drive this code path. That strengthens rather than weakens the claim.

### User impact

On this build both Hive boxes are always empty, so the trapdoor is latent — but an install upgraded from a version that still enqueued `PendingOperation`s keeps those writes on disk forever, and the settings screen's 'Qayta urinish' button on a legacy quarantined op moves it into a queue that nothing drains, presenting recovery that never happens.

---

## `W6` — Shift open/close is not atomic

**Area:** Write path & outbox  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Two stores, no transaction — lib/features/view/main/presentation/cubit/shift/shift_bloc.dart:222-237: `await _writeLocalShift(local);` (which is `await _prefs.setString(localShiftPrefsKey, jsonEncode(shift.toJson()))`, :83-87) followed by `inject<LocalWriter>().enqueueOnly(entity: kShiftEntity, action: kShiftOpen, entityId: cashRegisterId, request: {...})`. Close is the mirror, :183-186: `_enqueueCloseShift(shift.cashRegisterId); await _clearLocalShift();` (`_prefs.remove`, :89-93). SharedPreferences and the SQLite `_outbox` table, sequential, nothing spanning them. `enqueueOnly` (local_writer.dart:161-176) deliberately writes no local row: "the active shift lives in `SharedPreferences`, not the replica" (shift_bloc.dart:156-158).
Empty id is not guarded — shift_bloc.dart:112-116: `Future<String> _resolveCashRegisterId() async { final token = await _tokenStorage.readAccessToken(); if (token == null || token.isEmpty) return ''; return _jwtClaim(token, 'cash_register_id') ?? ''; }` (`_jwtClaim` itself returns null on any parse failure, :95-110). At :211 `final cashRegisterId = await _resolveCashRegisterId();` and the enqueue at :228 runs with no emptiness check.
Rejected as permanent — lib/core/outbox/timer_shift_outbox.dart:255-259 `String _cashRegisterIdOf(OutboxOperation op) { final id = op.entityId; if (id != null && id.isNotEmpty) return id; return op.payload['cash_register_id'] as String? ?? ''; }`, then :173-178 `if (cashRegisterId.isEmpty) { return const OutboxExecutionResult.permanent('open shift without a cash_register_id'); }` (close: :208-213). outbox_drainer.dart:121-124 maps `permanent` straight to `_fail(..., permanent: true)` → quarantined, which W2 establishes is invisible.

### User impact

A crash or kill between the two writes leaves the terminal showing an open shift the server will never hear about (or, on close, a shift closed on screen but still open server-side). And if the JWT is missing its `cash_register_id` claim, the shift opens locally, looks fine to the cashier all day, and its open/close ops go straight to a quarantine no screen displays — the till is never opened or reconciled on the backend.

---

## `W7` — Non-order creates can duplicate on a lost response

**Area:** Write path & outbox  
**First pass:** CONFIRMED / MEDIUM  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

No key on the wire for non-order creates. local_writer.dart:96-118 `create()` puts the invented id only on the **local** row — `_applier.applyLocalWrite(entity: entity, id: localId, payload: {...row, 'id': localId})` — while the queued body is `payload: request ?? row`, i.e. the caller's untouched map. Call sites all pass `request: body`, which never contains an id:
- users_local_repository_impl.dart:51 `_writer.create(entity: _entity, row: body, request: body);`
- halls_tables_local_repository_impl.dart:80 `_writer.create(entity: entity, row: body, request: body);` (both `halls` and `cafe_tables` via `_queueCreate`)
- menu_admin_local_repository_impl.dart:122/144 (goods) and :181 `_writer.create(entity: 'translations', row: body, request: body);`
- transactions_repository_impl.dart:156, :177 (transactions) and :213 `_writer.create(entity: _groups, row: {'name': name}, request: {'name': name});`
- categories go out as a bare name: menu_admin_outbox.dart:97-104 `final name = op.payload['name']; ... remote.createCategory(name)`.
The repo's own code says the same: lib/features/view/main/data/outbox/transactions_outbox.dart:33 — "assigns its own id and takes no client id or idempotency key, so a create...".
Replay is real: a lost response is a `DioException` → retry outcome → the row stays `pending` (outbox_store.dart:275-296 `markFailed`) and `ready()` re-serves it next pass with an identical body.
The two safe paths check out. Orders: orders_repository_impl.dart:282-288 `_writer.write(entity: 'orders', id: orderId, action: 'create', ...)` with a client-supplied PK. Order items: :456-461 `Map<String, dynamic> _createItemBody(String id, OrderItem item) => { 'client_item_id': id, ... }`, and the backend honours it — /home/spike/Documents/work/MARY_AI/back/app/internal/model/order.go:101-108 "optional client-generated idempotency key... a second request with the same (order, client_item_id) pair returns the" existing row, enforced by a unique constraint in service/order.go:170-205 ("Wrapped in a savepoint: a unique-violation on client_item_id").

### User impact

Any create over a flaky link — a new staff member, a hall, a table, a category, a menu item, a cash-in/cash-out transaction — duplicates when the request commits server-side but the response is lost. Duplicated income/expense transactions are the sharp end: they land in the till reconciliation and have to be found and deleted by hand.

---


# LOW

## `A11` — An unknown manager PIN cannot authorize anything offline

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

lib/features/view/auth/data/data_sources/auth_datasource.dart:101-114 — `final cached = await _offlineAuthCache.getForPin(brandIdToken.brandId, pincode); if (cached != null) { ...return Right(...); }` then `if (!_client.isOnline) { return const Left(ConnectionFailure()); }`. The dialog turns any Left into a denial: lib/core/widgets/manager_pincode_dialog.dart:47-57 `(failure) { ...return false; }`. The cache is populated only by a successful server round trip on this terminal (auth_datasource.dart:134-140 `saveForPin` after the POST, and :55-68 on ordinary PIN login).

### Correction to the original claim

Nothing wrong. This is a provisioning constraint, not a defect: it is the same fail-closed rule the file documents, and the alternative (accepting an unknown PIN offline) would be the actual bug.

### User impact

If the venue's designated manager has never entered their PIN on a given terminal while it had connectivity, that terminal cannot void a committed item or open/close a shift during an outage — every manager who might be asked to approve must be walked through one online PIN entry per terminal at install time.

---

## `A15` — The audit trail misreports cache-served approvals

**Area:** Auth, session & startup  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

lib/core/widgets/manager_pincode_dialog.dart:39 `final wasOffline = !inject<ConnectivityCubit>().isOnline;` captured before the dialog opens, then passed unchanged as `verifiedOffline: wasOffline` on both the denial (:52) and approval (:64) records. But the resolution no longer depends on connectivity: lib/features/view/auth/data/data_sources/auth_datasource.dart:101-108 answers from `getForPin` before any `isOnline` check (that check is at :112, after the cache hit has returned). The field's documented meaning contradicts the value: lib/core/services/audit/privileged_action_audit_entry.dart:32-35 `/// True if this was resolved from the offline cache rather than a live server check`. The value is surfaced to operators at lib/features/view/main/presentation/pages/settings/sections/sync_status_section.dart:733 `'${entry.verifiedOffline ? ' · offline' : ''}'`.

### Correction to the original claim

Nothing wrong in the claim. Adding the symmetric case for completeness: the record is also wrong in the other direction only for the reason string, not the flag — a cache hit while offline is correctly `true`, and a cache miss while offline is correctly `true` with `'offline_unverified'`.

### User impact

An owner reviewing the privileged-action log after a disputed void sees an entry with no "offline" marker, and reasonably concludes the server confirmed that manager's PIN at that moment, when in fact it was answered from this terminal's cache and could reflect a role or a PIN the server has since changed.

---

## `C1` — PIN login fires a background revalidation POST

**Area:** Client reachability  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

lib/features/view/auth/presentation/cubit/login_pin/login_pin_cubit.dart:73-86 — cache hit path: `final cached = await _offlineCache.getForPin(brandId, pincode); if (cached != null) { await _enterSession(...); _revalidateInBackground(brandId: ..., password: ..., pincode: pincode); return; }`. Lines 176-203: `void _revalidateInBackground({...}) { if (!_connectivity.isOnline) return; unawaited(() async { try { final result = await _loginUsecase.call(LoginRequestModel(...)); ...`. The call is a POST to the claimed endpoint: LoginUsecase -> AuthRepositoryImpl.login -> AuthDatasourceImpl.login at lib/features/view/auth/data/data_sources/auth_datasource.dart:33-38 `final Response response = await _client.post(ListAPI.loginPinCode, data: req.toJson());`, and lib/core/api/list_api.dart:5 `static const String loginPinCode = "api/v1/auth/login-pincode";` over BASE_URL (lib/core/api/dio_client.dart:39).

### Correction to the original claim

Accurate as stated, but it understates one side effect: unlike C2's variant, this background call goes through AuthDatasourceImpl.login, which at auth_datasource.dart:46 does `await _tokenStorage.writeAuthToken(tokenPair)`. So the 'silent hygiene' request silently rotates the live session's access/refresh tokens (and rewrites the offline cache) on every cached PIN login — the cubit's own doc comment at line 172-175 ('It never touches the running session') is wrong about its own code path.

### User impact

One extra authenticated POST per shift-change PIN entry when the terminal is online; nothing blocks, the cashier is already in. The real exposure is the token rewrite: if that response is slow or partially applied, the session tokens on the terminal are replaced by a request no UI is watching.

---

## `C2` — The manager prompt fires the same background POST

**Area:** Client reachability  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  
**Origin:** introduced or touched by changes made in this session  

### Evidence

lib/features/view/auth/data/data_sources/auth_datasource.dart:100-107 — `final cached = await _offlineAuthCache.getForPin(brandIdToken.brandId, pincode); if (cached != null) { _revalidateInBackground(brandIdToken, pincode); return Right(UserModel.fromJson(cached.userModelJson)); }`. Lines 174-206: `void _revalidateInBackground(BrandIdTokenPair brandIdToken, String pincode) { if (!_client.isOnline) return; unawaited(() async { final response = await _client.post(ListAPI.loginPinCode, data: LoginRequestModel(...).toJson()); ...`. `isOnline` is the connectivity cubit's state (dio_client.dart:72 `bool get isOnline => _connectivity.isOnline;`). Reached on every manager prompt: lib/core/widgets/manager_pincode_dialog.dart:33/45 `final usecase = inject<VerifyManagerPincodeUsecase>(); ... final result = await usecase(pin);` -> AuthRepositoryImpl.verifyPincodeRole (login_repository_impl.dart:84-85) -> this method. Four live call sites of requireManagerPincode: close_shift_screen.dart:1901, waiter/widgets/bill_detail_panel.dart:32, close_shift/widgets/w_shift_bottom.dart:63, detail/widgets/order_side_bar_widget.dart:770.

### Correction to the original claim

None. Note the difference from C1 that the claim glosses: this variant deliberately does NOT write auth tokens (it only re-saves the per-pin cache, lines 190-198), so it really is session-neutral.

### User impact

An extra POST /api/v1/auth/login-pincode every time a manager approves a void, a discount or a shift open/close on an online terminal. Not user-visible; it is network chatter plus a one-attempt-late revocation window.

---

## `C5` — The menu editor can render a remote URL directly

**Area:** Client reachability  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

lib/features/view/main/presentation/pages/menu/menu_manage_screen.dart:2082-2100 — `if (ref.startsWith('http://') || ref.startsWith('https://')) { return Container(... child: CachedNetworkImage(imageUrl: ref, ...))` — LocalImageCache is used only on the non-http branch (:2111 `stream: inject<LocalImageCache>().stream(ref)`). Zero-callers claim verified by grepping the whole tree: `CustomCachedNetworkImage(` has exactly four instantiations — product_grid_card.dart:83, department_selection/widgets/category_selection_grid.dart:311, waiter/widgets/menu_panel.dart:354 and :567 — and every one passes `minioObjectName:`, none passes `imageUrl:`. No test constructs it either. So the imageUrl branch at custom_network_image.dart:79-90 (`CachedNetworkImage(imageUrl: imageUrl!, ...)`) is dead. Grepping `CachedNetworkImage(`/`Image.network` across lib/ returns only those two files.

### Correction to the original claim

None. The architecture guard already records both facts in prose (test/architecture_guard_test.dart:225-234), but as allowlist entries rather than as a rule, so nothing prevents a new caller passing imageUrl.

### User impact

A meal whose picture_url is a full http(s) URL renders through CachedNetworkImage's own HTTP client: nothing is written to the replica, so that image is unavailable offline and re-fetched on cold start — while every other menu image is disk-cached.

---

## `CX` — MinIO images are served by the global backend, not a separate host

**Area:** Client reachability  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Client: lib/core/service/minio/minio_service.dart:61-66 `await _client.post(ListAPI.mediaImage, data: {"object_name": key}, options: Options(responseType: ResponseType.bytes))` on the injected DioClient; lib/core/api/list_api.dart:51 `static const String mediaImage = "api/v1/media/image/download";` — a relative path, resolved against lib/core/api/dio_client.dart:39 `baseUrl: BASE_URL` = lib/core/constants/constants.dart:2 `const BASE_URL = 'https://api.maryaidev.uz/';`. Backend: back/app/internal/handler/handler.go:227 `media.POST("/image/download", h.DownloadImage, mw.CheckLanguage())` and back/app/internal/handler/minio.go:52-64 `func (h *Handler) DownloadImage(c echo.Context) error { ... object, err := h.service.Minio().GetImage(...); ... return h.streamFile(c, object, req.ObjectName) }` — the same Echo app and the same host as every other API route, proxying MinIO server-side. No separate blob host or presigned URL anywhere in the client.

### Correction to the original claim

None. Two consequences the claim leaves implicit: blob fetches carry the API's auth/interceptor stack, so they are POSTs and therefore blocked pre-transport when offline (see C8); and a missing object comes back as 404 'file_not_found' rather than a transport error, which is what makes the C4 retry loop noisy rather than silent.

### User impact

All menu-image bandwidth lands on the same backend host that serves orders and payments, so image hydration on a manual refresh or a 60s tick competes with the POS's own request path; there is no CDN or direct-blob route to move it off.

---

## `L1` — Leader→Follower change-feed broadcast works, but the seam is untested

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Chain verified link by link, all in committed code:
1. lib/core/sync/replication_service.dart:159 `onBatchApplied?.call(page.body, cursor);` — fires after `final stats = _applier.applyPullResponse(page.body);` (line 158), i.e. post-apply, with the pre-batch cursor.
2. lib/di.dart:335-345 `final replicationService = ReplicationService(... onBatchApplied: (body, fromCursor) => inject<LanHubService>().broadcastChangeFeed(body: jsonEncode(body), fromCursor: fromCursor));` — present in HEAD too (`git show HEAD:lib/di.dart` lines 300-301), so not in-flight.
3. lib/core/services/lan_hub/lan_hub_service.dart:390-399 `void broadcastChangeFeed(...) { if (mode != LanMode.server) return; if (_server.clientCount == 0) return; _server.broadcast(LanHubMessage.changeFeed(body: body, fromCursor: fromCursor)); }` — server-mode-only as claimed.
4. lib/core/services/lan_hub/lan_hub_server.dart:200-212 `broadcast()` writes `message.toJson()` to every socket in `_clients` (only auth-validated sockets are added, line 134).
5. lib/core/services/lan_hub/lan_hub_client.dart:110 `_controller.add(msg);` after the `_authorized` gate; lib/core/services/lan_hub/lan_hub_service.dart:128-129 `await _client.connect(ip, ...); _client.onMessage.listen(_handleRemoteMessage);` (client mode, non-empty saved IP).
6. lib/core/services/lan_hub/lan_hub_service.dart:303-312 `case LanHubMessageType.changeFeed: if (mode == LanMode.client && msg.feedBody != null && msg.feedFromCursor != null) { inject<ChangeFeedRelay>().apply(body: msg.feedBody!, fromCursor: msg.feedFromCursor!); }`
7. lib/core/sync/change_feed_relay.dart:61-64 `final gap = fromCursor > _db.syncCursor; if (gap) _needsBackfill = true; return _applier.applyPullResponse(decoded, advanceCursor: !gap);`
8. lib/di.dart:316-317 registers `ChangeFeedRelay(db: replicaDb, applier: changeApplier)`; lib/di.dart:446 `await lanHubService.init();`.
No echo hazard: `applyPullResponse` upserts do not call `_emitLocalChange` (only `applyOne` does, lib/core/db/apply_change.dart:305-312), so a follower applying a feed does not rebroadcast.
TEST COVERAGE: `grep -rn "onBatchApplied" test/` → no hits. `grep -rn "broadcastChangeFeed" test/` → no hits. test/change_feed_relay_test.dart only constructs `ChangeFeedRelay(db: db, applier: ChangeApplier(db))` directly (line 44) and round-trips the message through `LanHubMessage.tryParse` by hand (lines 136-153) — it never instantiates LanHubService, never exercises `_handleRemoteMessage`, never exercises the mode/clientCount gates. test/lan_hub_test.dart's 16 cases (grep of `test(`) cover tableStatus, localChange, timerAction, auth, relayOp, print jobs, clientCount — no changeFeed case. Every other test that touches LanHubService uses a `FakeLanHub implements LanHubService` stub (test/lease_manager_test.dart:32, test/leader_takeover_test.dart:102, test/orders_replica_write_test.dart:29, test/local_change_relay_test.dart:138, test/order_flow_integration_test.dart:47, test/write_path_guard_test.dart:547, test/timer_shift_outbox_test.dart:97, test/leader_election_test.dart:69). test/local_change_relay_test.dart:90-97 literally re-implements the dispatch switch in the test harness ("Mirrors `LanHubService._handleRemoteMessage`'s dispatch") rather than calling it.

### Correction to the original claim

Nothing wrong in the claim. Two refinements the claim omits: (a) `broadcastChangeFeed` has a second early-out beyond server-mode — `if (_server.clientCount == 0) return;` (lan_hub_service.dart:395); (b) the follower-side listener only exists when `mode == client` AND a server IP is already saved (`if (ip.isNotEmpty)`, lan_hub_service.dart:127), so a client-mode terminal with a blank `lan_server_ip` subscribes to nothing at all until `restart()` after the IP is set. Also worth noting `onBatchApplied` fires on every batch of `bootstrap()` too (bootstrapMaxBatches = 20000, replication_service.dart:186), so a leader re-bootstrapping with followers attached will fan out the entire change-log history over the LAN.

### User impact

Behaviourally correct today: followers do converge on the leader's pulled rows without their own cloud poll. The risk is regression, not present failure — the mode gate, the clientCount gate, the client-mode listener subscription and the di.dart closure are all reachable only in a real 2-terminal run, so any future edit that (say) routes broadcastChangeFeed through `_sendOrBroadcast`, drops the `_client.onMessage.listen` line, or reorders di.dart registrations would ship silently. A venue would then see followers showing stale orders/tables with no error anywhere.

---

## `L2c` — Menu images never cross the LAN

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

Only two writers of image bytes exist: lib/core/sync/sync_engine.dart:404-405 `final bytes = await MinioService.instance.getImageByObjectName(ref); if (bytes != null && bytes.isNotEmpty) db.saveImage(ref, bytes);` inside `_hydrateMenuImages`, and lib/di.dart:494-496 `write: (name, bytes) async => inject<replica.LocalDatabase>().saveImage(name, bytes), fetch: MinioService.instance.getImageByObjectName` — the `LocalImageCache` fetch-on-miss. `grep -rn "saveImage" lib` returns only those two call sites plus the definition (lib/core/db/local_database.dart:639).
`_hydrateMenuImages` is reached only from `_fillFeedGaps()` (sync_engine.dart:324-327), which runs inside `if (_connectivity.isOnline)` in the client branch (line 229/250) and after `if (!_connectivity.isOnline) return;` in the leader branch (line 256).
Images are not a replicated entity and so cannot ride the feed or `localChange`: lib/core/db/entity_registry.dart:226 `static const images = '_images';` is a *local* table name in the same list as the other local tables (line 235), not an `EntitySpec`; the class doc at sync_engine.dart:33-34 and 386-389 says the same ("Minio is a blob store, not a logged table").
No LAN message carries bytes for menu images — lan_hub_message.dart:3-21 has only `printPayloadBase64` (base64 ESC/POS for print relay, line 83), nothing for image objects.

### Correction to the original claim

Accurate. Two additions: (a) there is a *second* image path the claim doesn't mention, `LocalImageCache`'s fetch-on-miss wired at di.dart:496, but it is the same MinioService over the same terminal-local connectivity, so it does not change the conclusion; (b) the fetch target is MinioService, not the POS backend, so a follower needs reachability to the object store specifically, not just to the API.

### User impact

A follower with no uplink shows the menu grid with names and prices but blank/placeholder tiles for every item whose image it has not previously cached — slower item selection for cashiers who navigate by picture. Data is correct; only the visuals are missing, and they fill in the moment that terminal gets internet.

---

## `L6` — LanSoloBanner exposes cluster state to the cashier

**Area:** LAN / leader-follower  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

app_scaffold.dart:94 `const LanSoloBanner(),` sits in the shared Column right under `const OfflineBanner()`, so it is on every screen built from AppScaffold. lan_solo_banner.dart:28 `final solo = lanHub.mode == LanMode.client && !(snapshot.data ?? false);` and :40 the literal `"Hub bilan aloqa yo'q — mahalliy rejimda ishlayapsiz"`. The doc claim at lan_solo_banner.dart:9 ("since `client` mode routes all outbox sync through the leader") is false: sync_engine.dart:217-228 `if (_lanHub.mode == LanMode.client) { // The legacy queue's relayViaLan call used to sit here ... It is gone ... The capability it represented is *not* replaced — a follower's outbox still drains only through this terminal's own connectivity`. Grepping the tree for `relayViaLan` finds offline_queue_service.dart:236 (definition) and two doc mentions only — zero call sites. sync_status_section.dart:326-362 confirms the CLEAN half: `_clusterHeader` renders title 'Tarmoq' with mode-dependent subtitles ('N ta terminal bilan sinxron' / 'Filial tarmog'i bilan sinxron') and never names Hub/Client.

### Correction to the original claim

'EVERY screen' is an overstatement: AppScaffold has 12 call sites (main, waiter/admin floor plan, cashier, archive, transactions, settings, menu, notification, close_shift); auth/login screens do not use it. Also the banner is not reachable on a default install at HEAD — `mode` defaults to 'disabled' (lan_hub_service.dart:66) and, per L5, the election that would set client mode does not run at HEAD, so mode==client requires either the manual picker or the other session's in-flight branch-wait fix.

### User impact

When a terminal is in client mode and the WS link is down, an orange strip with LAN jargon is pinned above every working screen a cashier uses, and per LB/LC it can be stuck on permanently. The false doc comment is developer-facing only: it will lead the next reader to believe a follower's outbox drains via the leader when in fact it drains only through that terminal's own internet.

---

## `LD` — Possible double UDP bind on port 8766

**Area:** LAN / leader-follower  
**First pass:** PARTIAL / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

The two instances are real: lan_hub_service.dart:40 `final _discovery = LanDiscoveryService();` and leader_election_service.dart:76 `_discovery = discovery ?? LanDiscoveryService()`, both defaulting to `LanDiscoveryService.defaultPort = 8766` (lan_discovery_service.dart:43). The silent swallow is real: :118-129 `_ensureSocket` wraps `RawDatagramSocket.bind(...)` in a try/catch whose only body is a `kDebugMode` print — `_socket` stays null, `startListening`/`startAnnouncing` still complete normally, and callers get no error. But the two are not normally bound at once: LanHubService's instance binds only inside `_watchForConflicts` (:146-159), which is gated off by default at :121, or inside `discoverHubs` (:170-187), i.e. only while a manager taps Discover on the settings screen. And a duplicate bind does not fail on the platforms that matter: Dart's `RawDatagramSocket.bind` defaults `reuseAddress = true` (dart-sdk/lib/io/socket.dart:1300), and I verified empirically on this Linux host that two UDP sockets with SO_REUSEADDR bind 0.0.0.0:8766 successfully ('SECOND BIND OK (duplicate allowed)').

### Correction to the original claim

The 'double UDP bind' is not a routine failure. It requires the manager to press Discover while the election is running, and even then it succeeds on Linux/Android/Windows (SO_REUSEADDR semantics for UDP) — it would fail only on macOS/iOS, which need SO_REUSEPORT and never get it. What survives verification is the weaker defect: `_ensureSocket` cannot distinguish 'bound' from 'failed to bind', so `discoverHubs` returns an empty list identically for 'no hubs on this LAN' and 'the socket never opened'. Also note the stale reasoning at lan_hub_service.dart:166-169, which asserts the discovery socket 'isn't otherwise in use' in client mode — untrue since the election owns a second instance on the same port.

### User impact

On macOS/iOS builds only, a manager pressing Discover in Settings > Network gets an empty hub list with no error and concludes there is no hub, while the real cause is a port already held by the election socket. On Windows/Android/Linux the scan works.

---

## `S1b` — Row-level apply failures advance the cursor

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / LOW  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

lib/core/db/apply_change.dart:190-194 — `if (row is! Map) { out = out._add(failed: 1); continue; }`; :209-212 — `if (entityId == null || entityId.isEmpty) { out = out._add(failed: 1); continue; }`; :230-231 — `final id = raw[spec.pk]?.toString(); if (id == null || id.isEmpty) return stats._add(failed: 1);`. None of the three throws. The whole batch runs inside `_db.transaction(() {...})` (apply_change.dart:141) and the cursor is written inside that same block at :158-162. lib/core/db/local_database.dart:445-455 — `transaction` only rolls back when `body()` throws (`_db.execute('COMMIT'); committed = true;` on the normal path), so a batch containing only counted failures commits and the cursor lands past them. lib/core/sync/replication_service.dart:161 merely folds `stats.failed` into a `rowsSkipped` counter; nothing branches on it (apply_change.dart:15-16 says as much, and grep confirms no runtime consumer).

### User impact

A malformed or pk-less row from the feed is dropped permanently rather than retried. The terminal shows a stale or absent record for that entity forever, and the only trace is a counter no screen or log acts on.

### Second reader

MECHANISM — confirmed exactly as described. lib/core/db/apply_change.dart:191-194 `if (row is! Map) { out = out._add(failed: 1); continue; }`; :209-212 `if (entityId == null || entityId.isEmpty) { out = out._add(failed: 1); continue; }`; :231 `if (id == null || id.isEmpty) return stats._add(failed: 1);`. None throws. The batch runs in `_db.transaction(() {` (:141) and the cursor is written inside it at :158-162 `if (next > _db.syncCursor) _db.syncCursor = next;`. lib/core/db/local_database.dart:445-457 — `_db.execute('BEGIN'); ... final result = body(); _db.execute('COMMIT'); committed = true;`, rollback only in the `if (!committed)` branch, so a batch of counted failures commits with the cursor past them. lib/core/sync/replication_service.dart:161 `skipped += stats.skippedPending + stats.skippedUnknown + stats.failed;` and `rowsSkipped` appears nowhere outside replication_service.dart's own fields and `toString()` (:62,69,79,179,187,196,204) — grep of lib/ for `ApplyStats` returns only change_feed_relay.dart:49 and local_change_relay.dart:144, both of which merely return it. So "no runtime consumer" holds.

NOT IN-FLIGHT — `git show HEAD:lib/core/db/apply_change.dart` contains all three branches (HEAD lines 145, 163, 184), the same `_db.transaction` (HEAD:94) and the same cursor write (HEAD:115). The other session's diff only inserts `_retireClientTwin` and the LAN sink above them; line numbers shifted, semantics identical.

REACHABILITY — this is where the claim breaks. Every cited trigger is structurally impossible for this backend to emit. (1) back/app/internal/model/sync.go:9-11 `Created []map[string]interface{}` / `Updated []map[string]interface{}` — elements can only marshal as JSON objects or `null`, and `null` requires `change_log.payload` to hold the JSON literal `null`, which no writer produces: every insert is `to_jsonb(NEW)` (app/migrations/tenants/8_movements.up.sql:55,58,63 and 72_change_log_redact_credentials.up.sql:41,44,48) or `to_jsonb(t)` (71_change_log_triggers_batch2.up.sql:146), and a SQL-NULL payload is filtered by `if len(payload) > 0` (back/app/internal/service/sync.go:95,104) so it is never appended at all. (2) pk-less row: `to_jsonb(NEW)` carries every column including the primary key, and `EntitySpec.pk` is pinned to the trigger's argument by test/registry_backend_pin_test.dart:513-535 (`if (actual != spec.pk) ... 'EntitySpec.pk must match the trigger argument'`), which fails CI on drift. (3) empty delete id: guarded server-side at back/app/internal/service/sync.go:112-114 `case "delete": if entityID != "" { ec.Deleted = append(ec.Deleted, entityID) }`, and `Deleted []string` cannot carry null.

DELIBERATE, PINNED BEHAVIOUR — test/local_database_test.dart:388-403 `test('malformed rows are counted, not thrown', ...)` expects `stats.failed, 3` for exactly the three cited branches. Throwing instead would roll the batch back and wedge the cursor, blocking the entire feed forever on one bad row, which is the worse failure the current shape trades against.

Ran `flutter test test/local_database_test.dart` on the current working tree: 40/40 pass.

**Second reader's correction:** Two material errors. (1) SEVERITY/REACHABILITY: the claim asserts "a malformed or pk-less row from the feed" as if the feed produces them. It cannot. Go's `[]map[string]interface{}` plus `to_jsonb(NEW)` for every change_log writer means every created/updated element is an object carrying every column including the pk; `EntitySpec.pk` is CI-pinned to the trigger's `log_change('<pk>')` argument; and the empty-delete-id branch is dead because the server already guards `if entityID != ""` on a `[]string`. This is a latent robustness gap against a hypothetical future feed (a hand-written change_log insert, a backend that stops using to_jsonb, or a corrupted-yet-valid-JSON LAN relay body via change_feed_relay.dart:64), not a live data-loss path. HIGH is not defensible; LOW is. (2) "FOREVER" IS WRONG: because payload is the complete row (`to_jsonb(NEW)`), the next write of any kind to that database row emits a fresh full change_log entry that upserts and repairs the replica. The window is "until the next write to that entity", not permanent. Only a row never touched again stays missing — and separately I confirmed the client never reads `snapshot_required` (zero hits for it across lib/ and test/), so no dedicated repair path exists for that residual case. Not dependent on the other session's uncommitted work.

**Second reader's impact assessment:** In production today: none observed or reachable — the backend cannot emit a row that hits these branches. If a future feed change or a corrupted LAN-relayed batch did produce one, a cashier would see one record missing or stale on the affected screen until anyone next edits that record on the server, at which point it silently self-corrects. A record never edited again would stay wrong indefinitely, with no screen, log or alert showing it — the `failed` count is folded into `rowsSkipped`, which is rendered nowhere.

---

## `S4a` — A delete skipped as pending never returns

**Area:** Sync & replica integrity  
**First pass:** CONFIRMED / HIGH  
**Second pass:** PARTIAL / LOW  ← **disputed**  
**In flight:** rests on another session's uncommitted work  

### Evidence

lib/core/db/apply_change.dart:213-216 — `if (_db.isPending(entity, entityId)) { out = out._add(skippedPending: 1); continue; }` inside the deletes loop, with the cursor advanced unconditionally at :158-162 (identical skip at :320-322 in `applyOne`). Deletion is a hard delete, so there is no tombstone left locally either: local_database.dart:373-376 — `void deleteRow(String entity, String id) { _db.execute('DELETE FROM $entity WHERE id = ?', [id]); ... }`. The asymmetry with an update is real: an update self-heals only if the pending local op writes something server-side that regenerates a change_log row, but a server-side-deleted row can generate no further change_log rows by construction — its table has no row left for `log_change()` to fire on (back/app/migrations/tenants/8_movements.up.sql:42+). And the guard does clear: `OutboxDrainer._succeed` (outbox_drainer.dart:146) and `_fail` (:246) both call `clearPending`, so the terminal ends up unguarded and holding a row that will never be contradicted. `markPending` has no TTL — local_database.dart:696-702 stores `since` but nothing reads it (grep for the pending table's `since` finds no reader).

### User impact

A dish deleted from the menu, a table removed from a hall, or a staff member deactivated on one terminal while another terminal has an unsent edit on that same row: the deletion is skipped on that terminal and never redelivered. It keeps selling a withdrawn item or showing a table nobody else can see, indefinitely, and only a full re-bootstrap clears it.

### Second reader

CODE AS QUOTED IS REAL AND COMMITTED. apply_change.dart:213-216 `if (_db.isPending(entity, entityId)) { out = out._add(skippedPending: 1); continue; }`; cursor advanced unconditionally at :158-162 `if (next > _db.syncCursor) _db.syncCursor = next;`; identical skip at :320-322; hard delete at local_database.dart:369-373 `void deleteRow(String entity, String id) { _db.execute('DELETE FROM $entity WHERE id = ?', [id]);`; no TTL reader — `LocalTables.pending` appears only at local_database.dart:132/698/708/715 (INSERT, DELETE, SELECT 1), nothing reads `since`; clearPending in outbox_drainer.dart:146 and :246. All present at HEAD (`git show HEAD:lib/core/db/apply_change.dart` lines 166-170, 190, 216-219).

BUT THE DELETE BRANCH IS UNREACHABLE FOR EVERY ENTITY THE POS CAN MARK PENDING. An id only lands in `changes[entity]['deleted']` when the change_log row's action is 'delete' (back/app/internal/service/sync.go:112 `case "delete": ... ec.Deleted = append(ec.Deleted, entityID)`), and log_change() emits 'delete' only for a real SQL DELETE (back/app/migrations/tenants/8_movements.up.sql:61-64 `ELSIF (TG_OP = 'DELETE') THEN v_action := 'delete';`). Every POS-entity delete in the backend is a SOFT delete, i.e. an UPDATE, which logs action='update': goods.sql.go:299-303 `const deleteGood ... UPDATE goods SET deleted_at = EXTRACT(EPOCH FROM NOW())::BIGINT`; cafe_tables.sql.go:241-244 (same shape); halls.sql.go:85-89; categories.sql.go:262-266; users.sql.go:1608-1612 `const softDeleteUser ... UPDATE users SET deleted_at = ...`; organization.sql.go:133-137 (translations); order.sql.go:581-585 (order_items). `grep -rn "DELETE FROM" --include=*.go internal/` over the whole backend returns exactly three tenant/main-schema hits: price_for_plans, user_payments (payments.sql.go:101-118) and main-db brands. Of those only `user_payments` is a replicated entity (entity_registry.dart:563) and it is never written locally — that registry line is its ONLY occurrence in lib/ — so it can never be pending.

REACHABILITY OF THE SKIP AT ALL: `git grep -n 'applyOne(\|applyFromPeer' HEAD -- lib` finds no applyFromPeer caller and only outbox_drainer.dart:155/:197 plus orders_repository_impl create/update calls; the one applyOne(action:'delete') at HEAD is OutboxDrainer._reconcile, which runs after `_succeed` already did `_db.clearPending(op.entity, entityId)` (outbox_drainer.dart:146), so the guard cannot fire there. Also note sync_engine.dart:258-263 `// Send before receiving` — `await _outbox.drain(); await _replication.drain();` — the guard is cleared before the pull in the ordinary tick.

**Second reader's correction:** Two things are wrong. (1) WRONG LINE / WRONG SCENARIO. None of the three named scenarios reaches apply_change.dart:213-216. The backend never hard-deletes goods, cafe_tables, halls, users, categories, translations or order_items — all are `UPDATE ... SET deleted_at`, so they arrive on /sync/pull in the `updated` array and go through `_applyUpsert`, hitting the OTHER guard at apply_change.dart:237. (2) THE FINDING'S OWN EXCUSE FOR UPDATES IS FALSE. It says an update 'self-heals only if the pending local op writes something server-side that regenerates a change_log row' and treats deletes as uniquely unrecoverable. A soft-delete UPDATE is exactly one change_log row too; once the cursor passes it nothing redelivers it, and the client has no snapshot repair path (`/api/v1/sync/snapshot` exists in the backend — handler/sync_snapshot.go — but grep for 'snapshot' in lib/ shows the client never calls it, and it ignores the server's `snapshot_required` flag from sync.go:144). So the asymmetry the finding rests on does not exist; the update skip is equally permanent, and it is the one that actually fires. IN_FLIGHT CAVEAT: the only genuinely reachable delete-with-pending path is the LAN peer relay (local_change_relay.dart:168 `_applier.applyFromPeer(...)` -> applyOne :320), and `applyFromPeer`/`_emitLocalChange`/`applyLocalDelete` do not exist at HEAD — that whole path is the other session's uncommitted work. Even there it usually self-heals, because the originating terminal's delete also reaches the server, which soft-deletes and emits an `updated` row the peer applies once its guard clears.

**Second reader's impact assessment:** None from the cited code as it stands: no cashier can produce a change_log 'delete' for a menu item, table, hall or staff member, so the skipped-delete-never-redelivered scenario cannot occur today. The residual real risk sits on a different line (the upsert skip at :237): if a terminal happens to be holding an unsent edit on a row at the exact moment the pull that carries that row's soft-delete arrives — an outbox op in backoff, a blocked causal chain, or the SyncEngine.hydrateNow() path (sync_engine.dart:286) which pulls without draining first — that terminal keeps showing a withdrawn dish or a removed table until a logout/branch-switch re-bootstrap (auth_cubit.dart:136 clearAll, replication_service.dart:244 resetAndBootstrap). Narrow window, admin-only entities, and it is not what this finding describes.

---

## `S6a` — validateRegistry does not check numericKeys against promoted columns

**Area:** Sync & replica integrity  
**First pass:** PARTIAL / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

THE VALIDATION GAP IS REAL — lib/core/db/entity_registry.dart:640-689 `validateRegistry()` checks duplicates (`if (!seen.add(spec.name))`), local-table collision, empty pk, pendingReason consistency, reserved promoted names, duplicate promoted names, and redactKeys-vs-promoted (`for (final key in spec.redactKeys) { if (columns.contains(key)) { problems.add('${spec.name}: "$key" is both promoted and redacted'); } }`). There is no loop over `spec.numericKeys` at all.

BUT THE 'NO CURRENT ENTITY OVERLAPS' PART IS FALSE. Parsed all 38 specs mechanically for promoted∩numericKeys; exactly one hit: `goods`, on `price`. entity_registry.dart:333-346: `PromotedColumn('price', SqlType.real),` ... `numericKeys: { 'price', 'cost_price', 'profit', 'profit_margin', 'markup_percent', },`.

The overlap is harmless as written, and only because the column happens to be REAL. payload_normalizer.dart:47-49 turns the JSON number into a canonical string (`out[key] = numToCanonicalString(value);`), then local_database.dart:423-441 `_coerce` recovers it: `case SqlType.real: if (value is num) return value.toDouble(); return double.tryParse(value.toString());` — `double.tryParse('15000.5')` is 15000.5. The claim's failure mode is correct only for `SqlType.integer`, whose branch is `return int.tryParse(value.toString());` and would give null on '42.86'. No integer promoted column is currently a numericKey, so nothing is broken today.

### Correction to the original claim

The claim's key assertion — "Claimed latent - no current entity overlaps" — is wrong. `goods` DOES overlap: `price` is both a promoted REAL column and a numericKey. The bug is latent for the opposite reason to the one given: not because no overlap exists, but because the one overlap that exists lands on a REAL column whose _coerce branch parses the canonical string back to a double. (Note local_database.dart, which holds _coerce, is being edited by the other session; the _coerce body itself is untouched by that diff.)

### User impact

None today — goods prices store and sort correctly. The exposure is future: adding a numericKey to any existing INTEGER promoted column, or promoting an existing numericKey as INTEGER, would silently store NULL for every fractional value with no test or validator objecting. On `orders.bill_no` or `cafe_tables.number` that would mean rows dropping out of ORDER BY and range filters.

---

## `W8` — The write-path census has structural blind spots

**Area:** Write path & outbox  
**First pass:** CONFIRMED / LOW  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

test/write_path_guard_test.dart:532-541 — `const String kRepositoryRoot = 'lib/features/view/main/data/repository';` / `List<String> repositoryFiles() => Directory(kRepositoryRoot).listSync().whereType<File>().map((f) => f.path.replaceAll(r'\', '/')).where((p) => p.endsWith('.dart')).toList()..sort();` — no `recursive: true`, and one hard-coded root. It is the sole input to every census assertion (:1052, :1111, :1139, :1211).
What that excludes, verified by grep: the only repository implementation outside that root is lib/features/view/auth/data/repositories/login_repository_impl.dart (note the directory is `repositories`, not `repository` — it can never be picked up). Blocs/cubits under lib/features/view/main/presentation/cubit/** are likewise outside it, and that is where two of the write paths in this group live: shift_bloc.dart:228 calls `inject<LocalWriter>().enqueueOnly(...)` directly, and menu_manage_screen.dart:323 drives a create from a widget — neither is censused.
All of lib/core/** is outside it too, including lib/core/outbox/*, lib/core/db/apply_change.dart and lib/core/services/offline_queue/offline_queue_service.dart.
networkWrite literal — same file :487-489: `networkWrite: mutatingDataSourceCalls.any((m) => reach.contains('_dataSources.$m(')),`. The field name `_dataSources` is hard-coded, so any repository holding its remote under a different name scores `networkWrite: false` and, per `compliant` at :421-425, can pass while POSTing directly.

### Correction to the original claim

The 'non-recursive' framing is accurate but currently moot: `lib/features/view/main/data/repository/` has no subdirectories (13 flat .dart files), so recursion would add nothing today. The operative gap is the single hard-coded root, which is what actually hides blocs, widgets, lib/core/** and the auth repository. The `_dataSources` observation is a latent hole, not a live one — main_repository_impl.dart:18 is the only file in the censused directory with a data-source field at all, and it is spelled `_dataSources`.

### User impact

No direct effect on a cashier or venue. The consequence is that this guard test cannot catch the very regressions the other findings describe: a bloc or a widget writing straight to the network or the database, or an auth repository doing the same, passes the census by construction — so the 'every write goes through the outbox' invariant is enforced over roughly one directory rather than the app.

---


# NONE

## `S2` — users/create replay duplication

**Area:** Sync & replica integrity  
**First pass:** REFUTED / NONE  
**Second pass:** not re-checked (below the critical/high threshold)  

### Evidence

The premise that the create ever reaches a register handler is false. lib/features/view/main/data/data_source/main_datasources.dart:1169-1172 — `final response = await _client.post(ListAPI.authRegister, data: body);` with lib/core/api/list_api.dart:13 — `static const String authRegister = "api/v1/auth/register";`. But back/app/internal/handler/handler.go:36-44 registers only `/login`, `/login-pincode`, `/terminal/branches`, `/terminal/token`, `/refresh` under the `/auth` group, with an explicit line at :42: `// Public self-registration disabled — staff users are created via POST /api/v1/users by admins`. `grep -rn '/register' app/internal --include=*.go` returns exactly one hit: the stale swagger annotation `// @Router /api/v1/auth/register [post]` at handler/auth.go:166. `h.RegisterUser` is defined (auth.go:167) but never routed. Even if it were routed, it is not the duplicate-prone create the claim assumes: service/auth.go:276-288 rejects on existing phone/username before insert, and :364-374 maps a 23505 constraint violation to 'user with this phone number already exists' — so a replay is refused, never duplicated; and :294-299 restricts the endpoint to role 'user' only, rejecting every staff role.

### Correction to the original claim

Wrong on both halves. There is no idempotency hazard because there is no reachable endpoint: `POST api/v1/auth/register` is unrouted and echo answers 404. That 404 becomes `NotFoundFailure` → `outcomeForFailure` → `OutboxOutcome.permanent` (lib/core/outbox/failure_outcome.dart:39) → `users_outbox.dart:27-33` returns permanent → `OutboxDrainer._fail(permanent: true)` quarantines the op (outbox_drainer.dart:231-247). The real defect is worse than the one claimed and has the opposite shape: staff creation is 100% broken, deterministically, not probabilistically on a crash. The correct target is `users.POST("", h.CreateStaffUser, ...)` at handler.go:93. Note also that `_fail` clears pending but never clears the provisional marker set by `LocalWriter.create` (local_writer.dart:112), so the fabricated local user row is left behind under its client-invented id.

### User impact

Every staff user an admin creates on the POS is written locally, queued, rejected with 404 and quarantined. The new cashier or waiter appears on the settings screen on that one terminal, never reaches the server, and never appears on any other terminal — and cannot log in anywhere.

---

# Sequencing

The findings interact. Fixing them in the wrong order converts a policy violation into data loss.

## The one ordering constraint that really matters

`L3` (followers contact the cloud directly) and `L4` (the LAN op-relay for follower writes is
orphaned) are the same design decision seen from two sides, and **`L4` must be fixed first**.

Today a follower's writes reach the backend *because* the follower has its own uplink — the very
thing `L3` says should not happen. Cutting the follower's direct cloud access first would satisfy
the stated rule and simultaneously strand every follower write with no path to the server. The
relay has to exist before the uplink is removed.

## Suggested order

1. **`W1`** — a new menu item cannot be saved at all. Standalone, no dependencies, and it is a
   functional failure rather than an architectural one.
2. **`A1`** — the PIN-screen Logout button. The fix is to route it through `deleteUserSession`
   (which already preserves the offline cache) and add a confirmation. Small, isolated, removes the
   only one-tap path to an unusable offline terminal.
3. **`W2` + `S8a` + `S8b` + `S8c`** — one coherent piece of work: point the sync-status UI at
   `OutboxStore` instead of the retired Hive queue, stop stamping `lastSyncAt` on failure, and
   re-enable manual retry. Until this lands, every other sync problem is invisible to the operator,
   which makes field diagnosis of everything below impossible.
4. **`W3` + `A6`** — guard `clearAll` on outbox depth, and decide what a brand switch does with
   another tenant's undrained writes.
5. **`A2` + `A3`** — narrow `isDefiniteAuthRejection` so a 404 or a transport-shaped 4xx cannot
   purge a cached credential from an unattended background path.
6. **`L4`, then `L3`** — build the relay, then close the uplink. In that order.
7. **`S1a`** — a backend change (a lag watermark, an overlap window, or a commit-ordered cursor).
   Independent of the client work and can proceed in parallel.
8. **`S5a`** — needs a product decision first: branch-scope the feed server-side, or filter by
   branch in the client queries. Only relevant to multi-branch brands.

`C6` (the `api.dart` barrel defeating both architecture guards) is a one-line fix and should go in
with whatever lands first — it is what allows a regression in any of the above to ship green.

---

# Limits of this audit

Stated plainly, because a review that hides its own gaps is worse than one with fewer findings.

**Not verified against a running system.** Every finding is from source. No finding was reproduced
on real hardware, on a multi-terminal LAN, or against a live backend. The three transport-lifecycle
defects (`LA`, `LB`, `LC`) and the drain-ordering defect (`W4`) are code-evident but have no test
coverage and were not executed.

**Backend behaviour partly assumed.** Response codes for a wrong PIN, an unknown path and an expired
refresh token on `api.maryaidev.uz` were not observed. `A2`, `A4` and `A5` all depend on which code
the live server actually returns. Access and refresh token TTLs were not established, which sets the
window for `A4` and `A7`.

**Deployment facts unavailable.** Whether `CHANGE_LOG_COMPACTION_ENABLED` is set anywhere (`S4b`),
and whether migration 71's 50 000-row backfill cap fired for any real tenant (`S5c`), are both
per-environment questions that cannot be answered from either repository.

**Size figures are modelled, not measured.** The ~1.5–2 GB/year estimate in `S7` is derived from
schema widths and stated venue throughput. No production terminal was measured. The *absence of
pruning* is confirmed; the magnitude is an estimate.

**Concurrent edits.** Another session was actively editing `lib/core/outbox/`, `lib/core/db/`,
`lib/core/services/lan_hub/` and `lib/core/sync/local_change_relay.dart` throughout. Findings marked
**in flight** rest on that uncommitted state and should be re-checked once it lands.

**Platform specifics.** `flutter_secure_storage` behaviour on the actual Linux and Windows terminal
images (`A16`) was not tested; no platform options are configured.

---

# Note on the older documents

`ARCHITECTURE_COMPLIANCE_REVIEW.md` in this directory reviews commit `ca88ed3` and is over 100
commits stale. Nine of its ten violations have since been fixed — `CacheService` is deleted, no
screen injects `MainRepository`, the transactions/archives/users/halls/menu domains are local, and
the Leader→Follower `changeFeed` message type exists and is wired. It should be deleted rather than
read. The same caution applies to the other root-level plan documents, which describe intended
states that the code has since passed, changed, or abandoned.
