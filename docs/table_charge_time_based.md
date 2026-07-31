> Mirrored for reference from the backend repo:
> `back/docs/architecture/03_table_charge_time_based.md`. This is the
> authoritative backend billing model for time-based tables — treat the
> backend repo as the source of truth if this drifts out of date.

# Table Charge for Time-Based Tables

How the system meters and bills time on `time_based` tables (billiard / PS
rooms), from the live timer clock up to the final amount charged at payment.
This complements [`02_order_table_transfer.md`](02_order_table_transfer.md)
(what happens to the timer during a table transfer) and
`order-total-calculation.md` (the frontend-facing total formula) — this
document is the backend mechanics behind both.

## 1. Domain model

| Concept | Table / Type | Location |
|---|---|---|
| Table type | `cafe_tables.table_type` = `simple` \| `time_based` | `model/cafe_table.go:7,14-15` |
| Timer session | `table_time_sessions` | `migrations/tenants/33_table_timer_foundation.up.sql` |
| Session segment | `table_time_session_segments` | `migrations/tenants/48_table_transfer_segments.up.sql` |
| Timer audit event | `table_time_events` | `migrations/tenants/33_table_timer_foundation.up.sql` |
| Service layer | `TableTimerS` | `app/internal/service/table_timer.go` |

- Only `time_based` tables ever get a `table_time_sessions` row. `simple`
  tables are never charged (`calcAmountWithTableType`,
  `table_timer.go:205-215`, guards this even if a stray `price_per_hour` is
  present).
- One **session** = one continuous stay for an order on time-based table(s).
  A session has one or more **segments** — one per physical table it
  touched, since a transfer between two time-based tables keeps the session
  open and just closes/opens a segment (see §4 of
  `02_order_table_transfer.md`).
- **Events** (`started`, `paused`, `resumed`, `closed`, `transfer`) are an
  append-only audit log used to reconstruct pause intervals and history —
  they don't drive billing directly, `accumulated_active_sec` does.

## 2. Timer lifecycle (state machine)

`state ∈ {running, paused, closed}`, enforced by a DB check constraint.

```
StartTableTimerIfNeeded  →  running   (creates session + initial segment, event "started")
PauseTableTimer          →  paused    (freezes accumulated_active_sec, event "paused")
ResumeTableTimer         →  running   (sets a new active_started_at, event "resumed")
CloseTableTimer          →  closed    (closes segment, freezes final_amount, event "closed")
```

All four are gated to `order_type = dine_in` and the order's **current**
table being `time_based` (`getTimerContext`, `table_timer.go:95-126`), with
one deliberate exception: `ensureTimerMutable` (`table_timer.go:128-175`)
still allows pause/resume/close if the order's table was transferred away
from time-based but an **open** time-based session is still dangling — this
prevents orphaned sessions from becoming unmanageable.

Uniqueness constraints prevent double-booking:
- `uq_table_time_sessions_open_order` — an order can have at most one open
  session.
- `uq_table_time_sessions_open_table` — a table can have at most one open
  session (this is also what a Time-based→Time-based transfer race hits,
  translated to `"target table is already busy"`).

## 3. How active seconds accumulate

```go
// table_timer.go:177-186
func calcTotalActiveSec(session, now) int64 {
    total := session.AccumulatedActiveSec
    if session.State == "running" && session.ActiveStartedAt.Valid {
        total += now.Unix() - session.ActiveStartedAt.Unix()
    }
    return total
}
```

- `accumulated_active_sec` is the *frozen* running total as of the last
  pause/resume/close.
- While `running`, the live total adds `now − active_started_at` on top —
  this is why the amount keeps climbing between polls without a DB write.
- Pausing calls `calcTotalActiveSec` once more, stores the result back into
  `accumulated_active_sec`, and clears the "live" delta (no `active_started_at`
  while paused) — paused time is never counted.
- Resuming just stamps a fresh `active_started_at`; `accumulated_active_sec`
  is untouched until the next pause/close.

## 4. Turning seconds into money

```go
// table_timer.go:188-199
func calcAmount(totalSec int64, pricePerHour numeric) *string {
    total := (float64(totalSec) / 3600.0) * pricePerHour
    return formatFloat(total, 2 decimals)
}
```

```
table_charge (per session) = (accumulated_active_seconds / 3600) × price_per_hour
```

`calcAmountWithTableType` (`table_timer.go:205-215`) wraps this with the
simple-table guard mentioned in §1. This is the number surfaced as:
- `CurrentAmount` in `GET /orders/{id}/table-timer` and
  `GET /orders/{id}/table-price` while the session is open (live, recomputed
  on every read).
- `FinalAmount` on the session row once `CloseTableTimer` runs — frozen,
  never recalculated again.

## 5. Multi-segment sessions (transfers)

A session's total charge is **not** simply `price_per_hour × total time` when
the order was transferred between time-based tables mid-stay, because each
segment can be on a table with a different rate. `CloseTableTimer` and the
Time-based→Time-based transfer path both close out the *current segment*
using its own table's `price_per_hour`, and the session's
`accumulated_active_sec` / `final_amount` is the running sum across all
segments to date (`app/internal/service/order.go:4658-4764`, transfer
handling; `calculateFinalAmountForSessionTransfer`, `order.go:5002`). See
[`02_order_table_transfer.md` §4](02_order_table_transfer.md) for the full
transfer-scenario breakdown (Simple↔Simple, Simple→Time-based,
Time-based→Time-based, Time-based→Simple) and what each does to the
session/segment.

`buildTableHistory` (`table_timer.go:389-461`) reconstructs the full
per-segment breakdown (which table, active/paused seconds, pause intervals,
move reasons) for display — this is the `table_history` array on the timer
response. As of [`active_periods_view.md`](active_periods_view.md) this
array is no longer purely informational: each segment also carries its own
frozen `price_per_hour`/`amount`/`table_number`, and
`calcSessionAmountFromSegments` sums exactly these values to bill a session.

> **2026-07-30 audit note:** the claim in this section that segments are
> already priced individually and summed was **not true of the shipped
> code** as of this date — `calcAmount`/`calcAmountWithTableType` and
> `computeTableChargeFromSessions` all priced the *entire* multi-segment
> total at a single (the current table's) rate, and the Time-based→Simple
> close path could drop an earlier segment's time entirely. Both were fixed
> shortly after via `calcSessionAmountFromSegments`. A follow-up gap — that
> fix re-derived every segment's price *live* on every read, so an admin
> price change could retroactively re-price an already-closed segment — was
> then closed by freezing each segment's price/amount at close time; see
> [`active_periods_view.md`](active_periods_view.md) for the full mechanism.
> This section's description is now accurate.

## 6. Aggregating charge for an order: `computeTableChargeFromSessions`

An order can accumulate **multiple** sessions over its lifetime (e.g.
Time-based → Simple → Time-based again). `computeTableChargeFromSessions`
(`order.go:2358-2410`) is the authoritative sum used when the client doesn't
supply `table_charge` explicitly at payment:

```
table_charge (order) = Σ over all time-based sessions for the order:
    closed session  → session.final_amount   (frozen)
    open session    → live current amount    (recomputed now)
```

Returns `nil` (not `0`) when the order has no time-based sessions at all, so
`simple`-table orders leave `table_charge` untouched. This mirrors the
per-session logic used elsewhere so the bill display and the amount actually
charged never diverge (see the doc comment at `order.go:2349-2357`).

## 7. Final billing: `PayOrderBill` (the authoritative SQL)

`app/internal/repository/pg/tenantsdb/bills_custom.go:196-331` computes the
grand total **in SQL**, atomically with the payment write:

```sql
food_total      = Σ (qty × price) for non-cancelled items
table_charge    = $9  -- passed in; server pre-computes via §6 if the client omitted it
service_amount  = (food_total + table_charge) × service_percent / 100   -- ‼ service applies to table_charge too
base_total      = food_total + table_charge + service_amount
discount_amount = discount_percent ? base_total × percent/100 : discount_amount
grand_total     = GREATEST(ROUND(base_total − discount_amount), 0)
```

### Underpayment tolerance (`allowed_gap`)

```sql
allowed_gap = time_based table with price_per_hour > 0
                ? GREATEST(ROUND(price_per_hour / 60), 1)   -- one minute of table time
                : 1                                          -- one so'm otherwise
```

If `total_paid` is short of `grand_total` by no more than `allowed_gap`, the
payment is still accepted (`settlement_calc`): `grand_total` and
`table_charge` are both shaved down to what was actually paid, rather than
rejecting a payment over a rounding-sized gap. Anything short by more than
`allowed_gap` fails the `UPDATE ... WHERE p.total_paid + p.allowed_gap >=
p.grand_total` guard, and `PayOrderBill` returns `"insufficient payment"`
(`bills_custom.go:327-329`; the itemized message with the food/table/service
breakdown is composed by the caller in `order.go`).

### Why `table_charge` can be passed explicitly

`MarkOrderPaid` (`order.go:1153` onward) accepts an optional `table_charge`
in the request. If omitted, it's computed server-side via §6 right before
the SQL call (`order.go:1261-1272`) so a room is never silently billed `0`.
If the client passes a value (e.g. what `GET /orders/{id}/table-price`
returned a moment earlier), it's honored as-is — this keeps the displayed
and charged numbers in sync even if a few seconds pass between the two
calls.

### Closing the timer at payment

The timer is closed at the **handler** layer, not inside the service/SQL
call. `Handler.MarkOrderPaid` (`handler/order.go:1100-1192`) calls
`TableTimer().CloseTableTimer` *first* (freezing `final_amount` on the open
session), then calls `OrderS.MarkOrderPaid`. If the client didn't send an
explicit `table_charge` in the request body, the handler substitutes the
just-frozen `timerResp.FinalAmount` as `effectiveTableCharge`
(`handler/order.go:1174-1176`) before it ever reaches
`computeTableChargeFromSessions` — so by the time the service layer
computes the order-level sum (§6), the session it just closed already has a
`final_amount` rather than being read live. A failure to close the timer
only blocks payment if it's not one of the "ignorable" errors (e.g. no
timer for a simple-table order) — see `isIgnorableTableTimerCloseError`.

## 8. API surface

| Endpoint | Purpose |
|---|---|
| `POST /orders/{id}/table-timer/start` | Start (or idempotently return) the timer |
| `GET /orders/{id}/table-timer` | Current timer state + live amount + table history |
| `POST /orders/{id}/table-timer/pause` | Pause, freezing `accumulated_active_sec` |
| `POST /orders/{id}/table-timer/resume` | Resume from pause |
| `GET /orders/{id}/table-price` | Convenience view: duration + live `total_price` for display (`handler/order.go:980-1055`) |
| `POST /orders/{id}/transfer` | May start/continue/close a session depending on table types — see `02_order_table_transfer.md` |
| `POST /orders/{id}/pay` | Freezes and charges the table amount; authoritative `grand_total` |

`RolesCanControlTableTimer` / `RolesCanPayOrder` gate these
(`middleware/rbac.go`).

## 9. Worked example (multi-segment + payment)

A PS room at 30 000/hr, played for 90 minutes, then transferred mid-session
to a second PS room at 40 000/hr for another 30 minutes, then paid:

```
Segment 1 (table A, 30000/hr): 90 min active   → 45 000
Segment 2 (table B, 40000/hr): 30 min active    → 20 000
accumulated_active_sec (session)                = 7200s (120 min)
session.final_amount (on close)                 = 65 000

table_charge (order, via computeTableChargeFromSessions) = 65 000
items_amount   = 100 000
service_percent= 20
service_amount = ROUND((100000 + 65000) × 0.20)  = 33 000
base_total     = 100000 + 65000 + 33000          = 198 000
grand_total    = 198 000
```

Note `service_amount` is based on the **summed** session amount, not
per-segment — segments only matter for computing the sum correctly across
differently-priced tables; billing math after that point treats the order's
`table_charge` as a single number.

## 10. Gotchas

- A timer left running silently accrues — always surface the **live**
  amount to the cashier before payment (see `order-total-calculation.md`
  §4 for the "47.8 hours forgotten" example).
- The displayed running total on `GET /orders/{id}` does **not** include
  service-on-table-charge (raw `table_amount` only); the payment path does.
  This is a known display/charge asymmetry — see
  `order-total-calculation.md` §7.
- `discount_percent` and `discount_amount` are mutually exclusive; percent
  wins if the caller sends both to the service layer (SQL itself only looks
  at percent when non-null, per `disc_calc`).
- Simple tables can never end up with a non-null `table_charge` — the
  `calcAmountWithTableType` guard and the `PayOrderBill` `ct.table_type =
  'time_based'` check on `allowed_gap` are two independent enforcement
  points for this invariant.
