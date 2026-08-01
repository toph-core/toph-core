# Prompt — Offline-First Re-Architecture for the Mary AI POS

## Role

Act as a senior distributed-systems architect with real production experience in offline-first and local-first sync systems. Your job in this session is to produce an architecture plan, not code. Be opinionated: where there are multiple viable approaches, pick one, justify it, and name what it costs.

## System context

- **Product:** Mary AI — multi-tenant restaurant management and POS platform.
- **Backend:** Go + PostgreSQL, REST API.
- **Web/admin:** React + TypeScript.
- **POS client runtime:** `[FILL IN — Electron / Tauri / Flutter / React Native / Android / native Windows]`
- **Local DB on the POS device:** `[FILL IN — SQLite, embedded Postgres, or "recommend one"]`
- **Topology:** tenant → branches → 1..N POS terminals per branch, typically on the same LAN.
- **Today:** the POS is online-dependent. It issues GET requests against the backend on demand and breaks when the connection drops.
- **Network reality:** `[FILL IN — how long an outage must be survivable: minutes? a full shift? a full day?]`

## Objective

Re-architect the POS so that it is fully operable with no WAN connectivity, and so that multiple terminals in one branch stay consistent with each other and eventually with the server.

## Non-negotiable requirements

1. **Local DB is the only read path.** On login (PIN or otherwise) the client hydrates all reference data into a local database. The client-facing UI never calls the backend directly — it reads and writes locally only.
2. **Two-layer split.** The application separates into (a) a **sync engine** that owns all communication with the backend and reconciliation, and (b) a **client layer** that owns user interaction and local reads/writes. Define the interface between them precisely.
3. **Periodic sync.** Pull and push on a ~60s cycle, plus immediate event-driven push for high-value mutations (order closed, payment taken, shift closed). Explain why polling alone is or isn't sufficient, and whether a push channel (WebSocket/SSE) is warranted.
4. **LAN clustering.** When several terminals share a branch network, one is designated the **local server** and the others connect to it. It behaves like a miniature version of the cloud backend.
5. **Shared printer routing.** Only one machine has the receipt printer physically attached. Closing a check on *any* terminal must produce the printout on the machine that owns the printer.
6. **No data loss and no duplicate financial records.** Ever. Every ambiguity resolves toward "no double charge, no lost order."

## Design problems to solve explicitly

Do not gloss over any of these. If one is genuinely out of scope, say so and why.

### Data classification

Partition every entity into sync classes before designing anything else. At minimum: server-authoritative reference data (menu, categories, modifiers, prices, tax rules, tables/halls, staff, roles/permissions, printer routing rules), client-originated transactional data (orders, order items, payments, discounts, voids, refunds, shift/cash sessions), and shared mutable state with contention (table occupancy, stock levels, order sequence counters). Each class gets a different sync direction, conflict policy, and retention rule. Produce this as a table.

### Identity and numbering

- Client-generated IDs (UUIDv7 or ULID) so records are created offline without server round-trips. The server must never reassign an ID.
- Human-readable order/check numbers are a separate problem: they must be unique per branch per day, monotonic enough for staff and accounting, and generated while offline. Propose a scheme (per-device prefixes, pre-allocated ranges leased from the server, or leader-issued sequences) and state the failure mode of each.

### Sync protocol

Specify the wire contract, not just the idea:

- Delta pull based on a server-side change cursor or sequence number — not `updated_at` alone, which breaks under clock skew and concurrent writes. Justify your choice.
- Tombstones for deletes, with a retention window.
- Pagination and resumability for the initial hydration, which may be large on a full menu.
- **Outbox pattern** for outgoing mutations: durable local queue, ordered where ordering matters, at-least-once delivery with **idempotency keys** so retries can't double-post a payment.
- Backoff, jitter, and reconnect-storm avoidance when a branch comes back online and every terminal retries at once.
- Partial batch failure: what happens when mutation 3 of 10 is rejected by the server for a business-rule reason (e.g. an item that no longer exists)? Define a poison-message / quarantine path with operator visibility. Silent drops are not acceptable.

### Conflict resolution

Produce an explicit conflict matrix — one row per entity, with the policy and the reasoning. Cover at minimum:

- Two waiters editing the same open order on two terminals simultaneously.
- The same order closed and paid on two terminals during a network partition.
- Reference data changed on the server while a device holds a stale copy mid-order (price changed after the item was added — which price wins?).
- Stock decrements from multiple terminals (this is a counter, not a value — treat it accordingly).
- A shift closed on one terminal while another still has open orders.
- Server-side edits to an order that the client also edited offline.

Default posture: transactional data is append-only and client-authoritative; reference data is server-authoritative; contended counters need commutative operations or a single owner. Deviate where justified. Order line items should probably be modeled as an event log rather than a mutable row set — evaluate that.

### LAN cluster and leader election

- **Discovery:** mDNS/Bonjour vs. static configuration vs. a server-provided branch roster. Restaurant networks are hostile — pick something that survives a consumer router.
- **Election:** manual designation (an admin marks one terminal as primary) vs. automatic election. Full Raft is almost certainly over-engineering here; argue for what's actually needed.
- **Failover:** the leader machine is unplugged mid-service. What happens in the next 5 seconds? Do followers go read-only, promote a new leader, or fall back to fully independent operation and merge later? What are the correctness implications of each?
- **Split brain:** two halves of the LAN each elect a leader. How is this detected and healed?
- **Rejoin:** a terminal that was standalone for 40 minutes rejoins the cluster. Reconciliation procedure.
- **Clocks:** device clocks in the field are wrong. Use hybrid logical clocks or Lamport timestamps for ordering; treat wall-clock time as display metadata only. State where wall-clock time is nevertheless legally required (fiscal receipts).
- **Cluster vs. cloud sync:** does the leader act as the sole uplink to the backend (followers sync only through it), or does every terminal sync independently? Recommend one and explain the tradeoff for duplicate work, bandwidth, and failure isolation.

### Printing

- Model print jobs as first-class replicated entities with a state machine: `queued → claimed → printing → printed | failed`. The terminal that owns a given printer claims jobs and executes them.
- **Exactly-once printing** is the hard part. Ack semantics, claim leases with timeouts, and dedupe so a retry after an ambiguous failure doesn't print two receipts. A reprinted fiscal receipt is a real problem, not a cosmetic one.
- Printer-owning machine is off or offline: hold the queue, fail over to another printer, or block the close? Different answers for kitchen tickets vs. customer receipts — kitchen tickets are urgent and locally re-printable; a customer check is not.
- Multiple printers by role (receipt, kitchen, bar) with routing rules per product category. Rules live in reference data and must be available offline.
- Cover the transport (ESC/POS over USB/serial, network printers) and where the driver layer lives.

### Offline authentication and authorization

- PIN login must work with zero connectivity: cached credential hashes, snapshotted role/permission sets, defined TTL.
- Revocation lag: an employee is fired at 10:00 and the terminal syncs at 10:01. What's the exposure window and how is it bounded?
- Privileged actions (voids, discounts, drawer opens, price overrides) performed offline — logged locally with full audit trail, pushed on reconnect, and reviewable server-side.

### Payments and fiscal compliance

- Card/terminal payments are inherently online. Define the degraded mode explicitly — is the POS allowed to close a check with a card payment it cannot yet verify?
- Cash must always work.
- **Uzbekistan fiscal requirements are a hard external constraint.** Online cash register / fiscal module rules govern how long a receipt may go unreported and whether offline issuance is permitted at all. Flag this as a blocking question rather than assuming it's solvable in software.

### Storage, migrations, and lifecycle

- Local DB sizing, retention, and pruning of closed orders and synced print jobs. A terminal running for two years cannot grow unbounded.
- Encryption at rest and what happens when a terminal is stolen (per-device tokens, remote revoke).
- **Schema migration across a fleet where devices may be offline for days.** Version the local schema, version the sync API, and define the forced-upgrade path and the compatibility window.
- Cold start and disaster recovery: local DB corrupted, device replaced — full rehydration procedure.
- Multi-tenant scoping: a device must only ever hold its own branch's data.

### Security on the LAN

Do not treat the local network as trusted. Address transport encryption between terminals, device provisioning and pairing, and how a rogue device on the branch WiFi is prevented from joining the cluster.

### Observability

- Operator-visible sync status: last successful sync, pending outbox depth, cluster role, printer reachability. Staff must be able to see "we're offline" without guessing.
- Conflict and quarantine log, with a manual resolution path.
- Server-side fleet visibility: which terminals are stale, which have stuck queues.
- Force-resync escape hatch.

### Testing

Specify how this gets verified: deterministic simulation of partitions and message reordering, clock-skew tests, leader-kill tests during an open transaction, duplicate-delivery tests, and a soak test that runs a full simulated service offline and then reconnects.

### Migration path

The system is live. Propose a phased rollout: which entities move to local-first first, whether there's a dual-read/dual-write period, feature flags, per-branch canary, and rollback procedure at each phase.

## Deliverable

Produce, in this order:

1. **Assumptions and open questions** — anything I under-specified, called out before you build on it.
2. **Architecture overview** — components, boundaries, and data flow, including the sync-layer/client-layer interface.
3. **Data classification table** — entity, sync direction, conflict policy, retention.
4. **Sync protocol specification** — endpoints, payload shapes, cursor semantics, idempotency, error taxonomy.
5. **Conflict matrix** — scenario, resolution rule, rationale.
6. **Cluster design** — discovery, election, failover, split-brain handling, rejoin.
7. **Print subsystem design** — job state machine, ownership, dedupe, failure modes.
8. **Failure-mode table** — for each realistic failure, what the user sees and what the system does.
9. **Phased implementation plan** — milestones with acceptance criteria, ordered by risk.
10. **Explicit list of what this design does *not* handle** and the residual risks I'm accepting.

## Rules of engagement

- Do not write implementation code yet. Pseudocode is fine for election and reconciliation algorithms.
- Where you are guessing about my system, mark it clearly as an assumption rather than stating it as fact.
- If a requirement I gave is a bad idea, say so directly and propose the alternative.
- Prefer boring, proven mechanisms over novel ones. This handles money.
- End with the three decisions you think are highest-risk and most worth me pushing back on.