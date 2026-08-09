# LAN Hub, Leader Election & Table Leasing

This writes down the local-connection design as discussed and cross-checks it against
what's actually in the code today (`lib/core/services/lan_hub/`,
`lib/core/services/lease/`). It's the deep dive on one specific piece of
`BACKEND_SYNC_PLAN.md` (its §6/§7) — that doc has the surrounding sync-engine context
(triggers, conflict resolution); this one is just hub + leasing, in full.

## 1. The problem this exists to solve

Almost everything in this app resolves conflicts *after the fact* — two terminals can
each write locally, queue to the outbox, and sync later, because most conflicts (two
edits to the same order, a duplicate payment attempt) are safely resolvable once both
sides are visible to each other (idempotency keys, last-write-wins, 409-merge — see
`BACKEND_SYNC_PLAN.md` §12).

Opening a table doesn't fit that pattern. If two terminals both think a table is free and
both open it locally, you don't get a resolvable data conflict — you get two live orders
running against one physical table, discovered only when someone eventually looks. That's
a real-time UX problem, not a data problem, so it's the one place the design accepts a
synchronous-ish check before committing, instead of "write now, reconcile later." Table
lease arbitration is the one deliberate exception to "the UI never awaits the network."

Everything below exists to make that one check fast (LAN, not internet) and to make sure
a venue doesn't lose the ability to do that check just because one terminal (possibly
acting as the coordinator) goes down mid-shift.

## 2. Topology: hub-and-spoke, scoped per branch

One terminal at a time acts as **leader** (`LanMode.server`) and runs a local LAN server;
every other terminal is a **follower** (`LanMode.client`) connected to it. There's no
mesh, no gossip between followers — a follower only ever talks to the current leader.

**Scoped to one branch, not the whole brand.** Confirmed directly in code: both the auth
handshake (`LanHubMessage.auth` carries `branchId`, the leader rejects a mismatch) and
`LeaderElectionService._onAnnouncement` (`if (a.branchId != myBranchId) return;`,
`leader_election_service.dart:152`) ignore anything from a different branch outright. Two
terminals in the same brand but different branches never coordinate with each other over
LAN — which lines up with `CLIENT_FACING_OFFLINE_PLAN.md`'s login item: branch is already
the natural coordination boundary on both the data-retention side and the LAN side.

**Solo mode exists as a first-class case, not a fallback bolted on.** A single-terminal
venue runs with `LanMode.disabled` — `LeaseManager` arbitrates against its own state with
no network involved at all (`lease_manager.dart:95-98`). Nothing about the design requires
a second terminal to exist.

## 3. Discovery & connection

- Terminals find each other via a UDP broadcast beacon (`LanDiscoveryService`) — not a
  fixed IP or manual pairing.
- The same beacon **is** the heartbeat channel once Leader Election is active — a
  deliberate reuse, not a separate mechanism, because two processes can't bind the same
  UDP port (`leader_election_service.dart:26-31`). The beacon carries role, priority,
  epoch, and terminal id (`heartbeatExtra`, `leader_election_service.dart:238-243`).
- Every new connection to the leader must send `LanHubMessage.auth` (staff session JWT +
  branch id) **first** — the server holds the socket out of broadcast until that's
  validated (`lan_hub_message.dart:136-137`). A branch mismatch or bad token gets
  `authFail` with a machine-readable reason.

## 4. Leader Election

**Current status, stated plainly: this is fully built and has never run in production.**
It's registered and auto-started in DI, but gated behind a disabled-by-default flag
(`electionEnabledKey`) that nothing in the app ever flips — so every real build today
runs with it inert. The class's own doc comment explains why: it was shipped ahead of a
canary-hardware rollout it never got, per the (now-deleted) design doc's own rollout
discipline. See §7 of `BACKEND_SYNC_PLAN.md` for the action items; here's what it actually
does, mechanically, as verified by reading `leader_election_service.dart` directly:

| Mechanic | Value | Where |
|---|---|---|
| Heartbeat interval | 3s (default, configurable) | `heartbeatInterval`, line 47/62 |
| Missed beats before "leader is dead" | 3 (≈9s) | `missedBeatsBeforeDead`, line 50/63 |
| Base election wait | 1s + priority factor + jitter | `_startElection`, lines 215-222 |
| Priority → wait-time formula | `2000 / (priority + 1)` ms, higher priority = shorter wait | line 217 |
| Random jitter | 0-300ms | line 218 |
| Epoch persistence | `SharedPreferences`, written *before* announcing/adopting | `_persistEpoch`, line 87 |
| Priority assignment | random 1-999, generated once, persisted; `setPriority` hook for a future settings override | lines 94-102 |

**Why epoch fencing matters here specifically:** a terminal that was leader, crashed, and
rebooted must not resume acting as leader on stale authority — it has to observe an epoch
at least as high as whatever's currently live before it can claim again. Persisting the
epoch *before* acting on it (not after) is what makes that hold across a crash, not just
across a graceful restart.

**Why "bully algorithm, no vote, no quorum" was the choice (§7's framing, still accurate
to the code):** no round-trip consensus protocol, no majority requirement — whoever has
the highest priority claims fastest, and anyone who hears a valid claim while waiting
simply stands down (`_onAnnouncement`, lines 168-171). Simple, fast, appropriate for a
handful of terminals on one LAN segment where the failure mode that matters is "leader
terminal loses power," not Byzantine actors.

**The one genuine gap in the mechanics, not just the rollout:** on an equal-epoch
announcement from a different terminal, the code stands down / records the peer's IP with
**no terminal-id comparison at all** (lines 163-178, comment explicitly calls this "a
genuine segment-split... deliberately not auto-resolved here"). Two candidates that both
compute the same new epoch and claim before hearing each other land exactly here with no
deterministic winner. Concrete, scoped fix, tracked in `BACKEND_SYNC_PLAN.md` §7.

**What flipping the mode actually does:** this isn't a passive flag. `_claimLeadership`
and `_becomeFollower` both call `_lanHub.setMode(...)` followed by `_lanHub.restart()`
(lines 194-197, 233-234) — becoming leader or follower actually restarts the local LAN
server/client. This is why enabling this for the first time deserves the staged rollout
called out in `BACKEND_SYNC_PLAN.md` rather than a flag flip in every venue at once.

## 5. Table Leasing

**Current status:** fully implemented and, as of the client-facing plan's carve-out,
temporarily un-called. `LeaseManager` is wired into `CreateOrderBloc`'s table-open path
(`create_order_bloc.dart:123`) — but `CLIENT_FACING_OFFLINE_PLAN.md` comments that call
out for now ("no exceptions whatsoever" for the client side, until this gets picked back
up as its own piece of work). The class itself, and everything below, stays intact and
ready for when that happens — nothing here needs to be rebuilt later, just re-called.

**The durable/ephemeral split**, verified directly in `_arbitrate` (`lease_manager.dart:164-179`):

1. **Durable check** — is any table already `busy` in `LocalDatabase` right now? This is
   just `LocalDatabase`'s ordinary replica of table status — no lease-specific recovery
   logic needed, because it's already durable business data that's correct across a
   restart on its own.
2. **Ephemeral check** — an in-memory `Map<tableId, (claimant, claimedAt)>` with a 5s TTL
   (`_ephemeralTtl`, line 79), catching the sub-second race window between two terminals
   both passing the durable check before either one's write actually lands.

**Why the ephemeral map is allowed to just vanish on leader restart/failover** — stated
directly in the code (lines 68-71): losing it only means an in-flight request has to
retry, never a silent double-grant, because the durable check still catches anything that
actually committed. The ephemeral map is a race-window guard, not a source of truth.

**Mode-aware arbitration, no wasted round trips:**
- `disabled` (solo) or `server` (this terminal already is the leader) → arbitrate
  in-memory immediately, zero network hops (`acquireTableLease`, lines 94-102).
- `client` → send `leaseRequest` to the leader, 5s timeout
  (`LanHubClient.requestLease`), three possible outcomes: `granted`, `rejected` (with
  `heldBy` when known, surfaced to the cashier as "already opened on another terminal"),
  or `unreachable` (leader down or unreachable — distinguished from a rejection so the
  caller's error copy can tell "no" apart from "couldn't ask").

**Current policy on rejection/unreachable, as actually implemented (not a documented
table — this is what `create_order_bloc.dart:124-133` does today):** both cases **block**
the table-open and show an error; there's no "allow unverified" or "fall back to solo"
behavior implemented. If a softer policy is ever wanted for the unreachable case
specifically, that's a live design decision, not something already decided elsewhere —
flagging it here rather than assuming an answer.

**Release path:** the UI calls `releaseTableLease` the instant the order-open write
commits (same-process callback if this terminal is the leader, one fire-and-forget LAN
message otherwise) — the 5s TTL above is purely the backstop for a UI action that
abandons the flow without ever calling release at all.

## 6. Lease Recovery & the leader-crash-mid-relay race

The one race this design discloses rather than eliminates: a follower gets `granted`,
the leader crashes before that grant's corresponding release/durable-write is visible
anywhere else, a new leader gets elected, and a *second* terminal asks for the same table
and also gets `granted` — because the new leader has no memory of the dead leader's
in-flight ephemeral claim (by design, per §5 above).

This is accepted, not silently ignored: the **consequence** (a losing terminal's order
data getting dropped) is what actually gets closed, via the 409-merge conflict resolution
already implemented in `OfflineQueueService._execCreateOrder`
(`offline_queue_service.dart:265-335`, see `BACKEND_SYNC_PLAN.md` §12) — when the losing
side's create-order op eventually syncs and gets a 409, its items get merged into the
winning order via the add-items endpoint instead of silently discarded. The double-open
itself isn't prevented in this narrow window; its downstream damage is.

## 7. Wire protocol

All messages are one `LanHubMessage` shape (`lan_hub_message.dart`) with a `type` enum and
purpose-specific optional fields. Every request/reply pair correlates via an id field
(`opId` for relay, `printJobId` for print jobs, `leaseTerminalId` + `tableId` together for
leases — leases don't need a separate correlation id since a lease message only ever
concerns exactly one table).

| Type | Direction | Purpose |
|---|---|---|
| `auth` / `authOk` / `authFail` | follower → leader, first message on any connection | Validates JWT + branch id before the socket joins broadcast |
| `tableStatus` | broadcast | Live table free/busy/away state fan-out |
| `ping` | either | Liveness/keepalive |
| `relayOp` / `relayOpResult` | follower → leader | "Execute this one queued outbox op against the cloud on my behalf" — for a follower with LAN but no internet of its own |
| `leaseRequest` / `leaseGranted` / `leaseRejected` | follower → leader, directed RPC | Table-open arbitration, §5 above |
| `leaseRelease` | follower → leader, fire-and-forget | Evict an ephemeral claim early, best-effort |
| `printJobAnnounce` / `printJobClaim` / `printJobResult` | broadcast, then directed | A terminal without the target USB printer announces a print job; whichever terminal actually has that printer claims and executes it |

`relayOp` and the lease messages are both "directed leader RPC, single reply" in shape.
`printJobAnnounce` is structurally different — broadcast-to-all-except-sender, then
whoever claims it takes over — because it's solving "who owns this printer," not "ask the
one authority." Worth knowing these are two different interaction patterns riding the same
transport, not the same pattern reused twice.

## 8. What's built vs. wired vs. active — the three separate questions

This is the piece worth being precise about, since the three don't move together:

| | Built | Wired into a real caller | Active in any real build today |
|---|---|---|---|
| `LeaseManager` | Yes | Yes (`CreateOrderBloc`) | **No** — client plan just commented out the call |
| `LeaderElectionService` | Yes | Yes (internally complete, DI-registered, auto-started) | **No** — disabled-by-default flag, nothing ever sets it true |
| `WaiterCubit`'s own table-open path | — | Never called `LeaseManager` at all | N/A — different gap, see below |
| 409-merge / payment idempotency (§12) | Yes | Yes, on `CreateOrderBloc`/`PaymentBloc` | Yes — but not on `WaiterCubit`'s parallel path |

The `WaiterCubit` row is the same recurring theme as in `BACKEND_SYNC_PLAN.md`: it's a
second, independent table-open/order/payment path that bypasses the lease gate entirely
(confirmed zero references to `LeaseManager` anywhere in `waiter_cubit.dart`). Whatever
gets decided about re-enabling the lease call site or turning on Leader Election, that
decision doesn't reach the Waiter screen unless its rebuild (already scoped as item 5 in
`CLIENT_FACING_OFFLINE_PLAN.md`) routes it through the same `OrdersRepository` path
`CreateOrderBloc` uses.

## 9. Open questions (not decided here)

1. **When does the commented-out lease call come back?** The client-facing plan parked
   it deliberately ("we will make it work later on") — this doc doesn't change that, just
   confirms there's nothing left to build first. It's ready whenever that call gets
   un-commented.
2. **Leader Election enable path** — manual per-venue settings toggle vs. default-on
   after a trust-building period. Bigger blast radius than anything else in this plan
   (decides which terminal thinks it's in charge), covered in `BACKEND_SYNC_PLAN.md` §7.
3. **Rejection-vs-unreachable policy** — right now both block identically. Worth a
   deliberate answer on whether "leader unreachable" should ever behave differently
   (e.g., allow with a visible "unverified" marker) rather than leaving it as an
   accidental default.

## 10. Action items (see `BACKEND_SYNC_PLAN.md` §6/§7 for full detail)

- Terminal-id tiebreak on equal-epoch collisions (§4 above).
- `lease_manager_test.dart` / `leader_election_test.dart` — neither exists today; given
  Leader Election has never run against real multi-terminal hardware, this is the
  highest-priority item before any enable-path decision gets acted on.
- Correct two stale doc comments (`lease_manager.dart:22-28`, `di.dart:150-152`) that
  still claim the lease isn't wired into `CreateOrderBloc` — it is.
- Route `WaiterCubit`'s table-open through the same lease-gated path (delivered via the
  Waiter rebuild in the client-facing plan, not new code here).

This is a plan/design document only — nothing here has been implemented or changed.
