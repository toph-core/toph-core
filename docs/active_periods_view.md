> Backend mechanics (§1-§7) mirrored for reference from
> `back/docs/architecture/04_active_periods_view.md`. §8 onward describes the
> frontend consumption of this data, which lives only in this repo.

# Active Periods View (per-segment price/amount freeze)

How the system prices and displays each individual table-segment of a
time-based session — the data behind the "active periods" dialog, which
replaced the old flat pause-history view. Builds directly on
[`table_charge_time_based.md`](table_charge_time_based.md); read that first
for the session/segment domain model.

## 1. The gap this closes

`table_charge_time_based.md` §5 originally claimed that a segment is priced
at its own table's rate at the moment it closes. That was true of the
*intent*, but not of the *implementation* until this change: `calcSessionAmountFromSegments`
priced every segment — including already-closed ones — via a **live**
`GetCafeTableByID` lookup on every call. Two concrete bugs followed:

- If an admin changed a table's `price_per_hour` while a multi-segment
  session was still open, the next read would silently re-price the
  *older, already-finished* segment at the *new* rate — a segment's charge
  changing after the fact, with no corresponding real-world event.
- If a segment's table was later soft-deleted, pricing that segment failed
  outright (`GetCafeTableByID`'s `deleted_at = 0` filter finds nothing), so
  the whole session's amount computation errored.

Both are fixed by **freezing** a segment's price, computed amount, and
table number the moment it closes, instead of re-deriving them from
`cafe_tables` on every subsequent read.

## 2. Schema: `table_time_session_segments`

Migration `68_table_segment_price_freeze.up.sql` adds three nullable
columns, populated only at close time:

| Column | Type | Populated when |
|---|---|---|
| `price_per_hour` | `NUMERIC(15,2)` | segment closes |
| `amount` | `NUMERIC(15,2)` | segment closes |
| `table_number` | `INTEGER` | segment closes |

`NULL` while a segment is still open (`ended_at IS NULL`) — there is nothing
to freeze yet; the live value is computed on read (see §4). A best-effort
backfill prices already-closed segments at *today's* rate — exact only if
the table's rate hasn't changed since, since there is no rate-history table
in this schema. This is a known limitation for pre-migration data.

## 3. Freezing at close: 3 call sites, no new queries

Every place that calls `UpdateTableTimeSessionSegmentClose` now also passes
that segment's own table's current `price_per_hour`/`number` and the
computed `amount` (`calcAmount(activeSeconds, price)`):

1. `TableTimerS.CloseTableTimer` — reuses `ctxRow.PricePerHour`/`ctxRow.Number`.
2. `OrderS.TransferOrder`, Time-based→Time-based branch — uses
   `sourceTable.PricePerHour`/`sourceTable.Number`.
3. `OrderS.TransferOrder`, Time-based→Simple branch — same `sourceTable`.

## 4. Reading segments: `buildTableHistory`

Populates each segment's `TableNumber`/`PricePerHour`/`Amount`:

- **Closed segment**: read straight from the frozen columns. No DB lookup.
- **The one still-open segment**: priced live from the order's current
  table context.

## 5. `calcSessionAmountFromSegments` — now a pure sum

Sums each segment's already-populated `Amount` — no DB access, no
per-segment price resolution. The one place a session's segments are ever
summed into money.

## 6. JSON — no new endpoints

`table_number`, `price_per_hour`, `amount` (all optional) on each entry of:

- `GET /orders/{id}/table-timer` → `table_history[]` (open orders, live).
- `GET /bills/{id}` → `table_sessions[].segments[]` (any order, closed or
  open).

## 7. Worked example: price change mid-session

```
segment 1 (room A): active_seconds=3600, frozen price_per_hour=30000, frozen amount=30000.00
segment 2 (room B): active_seconds=3600, live price_per_hour=50000, live amount=50000.00

calcSessionAmountFromSegments = 30000.00 + 50000.00 = 80000.00
```

Segment 1's frozen `30000.00` is untouched even if room A's rate changes
after segment 1 closed.

---

## 8. Frontend: single source of truth, two consumers

### Data flow

Both consumers below feed from **the same backend response shape**
(`table_sessions[].segments[]`) and the same Dart parser — there is one
place, not two, where the JSON becomes a `List<TableSegment>`:

```dart
// table_segment_model.dart
List<TableSegment> parseBillTableSessionsToSegments(Object? tableSessionsJson)
```

- **Open orders**: `TableTimerCubit._fetchBillDetails` (renamed from
  `_fetchBillPauses`) already polls `GET /bills/{orderId}` every 60s for
  `pause_periods` — it now also parses `table_sessions` through the shared
  function into `TableTimerState.billSegments`.
- **Archive (closed orders)**: `ArchiveDetailEntity.activePeriods`, parsed
  from the *same* `/bills/{id}` response's `table_sessions` field via the
  same shared function (`archive_detail_model.dart`, `@JsonKey(name:
  'table_sessions', fromJson: parseBillTableSessionsToSegments)`).

`TableSegment` (`table_segment_model.dart`) carries `tableNumber`,
`pricePerHour`, `amount` alongside the existing `activeSeconds`/`tableId`/etc.

### Live ticking the open segment (client-side secondary source of truth)

Per design decision: the backend is authoritative for every frozen (closed)
segment; the client only needs a real-time layer for the *currently open*
segment between 60s polls — reusing the existing `computeAnchoredLiveAmount`
helper (`table_timer_response_model.dart`), not a new formula.

`TableTimerCubit._tickLastSegment` (called every second from the same
`Timer.periodic` that ticks the overall `displayActiveSec`/`displayAmount`)
overlays a live value onto only the **last** entry of `billSegments` if it's
still open (`leftAt == null`):

```
liveSec    = lastSegment.activeSeconds + secondsSinceLastBillFetch
liveAmount = computeAnchoredLiveAmount(
               baseAmount: lastSegment.amount,
               elapsedSinceSyncSec: secondsSinceLastBillFetch,
               currentPricePerHour: currentTable.pricePerHour,
             )
```

Every closed segment before it is left untouched. The result is exposed as
`TableTimerState.displaySegments`, and `effectiveSegments = displaySegments ??
billSegments` is what the UI reads. `displaySegments` is explicitly cleared
whenever ticking stops (pause, close, order switch) so it can never shadow a
fresher `billSegments` fetched afterward — see
`TableTimerCubit._startUiTickIfRunning`.

### Shared widget

`lib/features/view/main/presentation/widgets/active_periods_view.dart`:

- `ActivePeriodsDialog` — modal, opened from the order screen's timer chip
  (`order_actions_bar.dart`'s `_TimerCompact`), fed
  `timerState.effectiveSegments` (ticking).
- `ActivePeriodsSection` — inline expandable card, used in Archive's
  sidebar (`archive_right_sider_bar.dart`), fed `detail.activePeriods`
  (frozen, no ticking needed — the order is already paid).
- Both render the same row (table number, duration via the existing
  `int.toHHMMSS` extension, price/hour and charge via the existing
  `num.formatN` extension) and the same summary footer, which **computes
  its own total from the segments list passed to it** rather than trusting
  a separately-computed total — the footer can never disagree with the rows
  above it.

This fully replaced the old pause-interval UI (`_PauseHistoryDialog`,
`_PauseHistoryDropdown`/`_PauseHistoryList`, and their formatters) in both
files. The printed cashier receipt (`cashier_receipt_builder.dart`) still
prints the flat pause list — a separate, out-of-scope follow-up.
