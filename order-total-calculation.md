# Order Total Calculation — Frontend Guide

How an order's total amount is built up, from individual items to the final grand
total the customer pays. This document is the source of truth for the frontend
when **displaying a running bill** and when **collecting payment**.

> All money values are Uzbek so'm. Final amounts are **integers** (rounded to 0
> decimals). The only place decimals appear is the raw table-time session amount
> (2 decimals), which is rounded when it enters the bill.

---

## 1. TL;DR — the formula

```
items_amount   = Σ (item.quantity × item.price)      // only non-cancelled items
table_charge   = time-based tables only (see §3)     // 0 for normal tables
service_amount = ROUND((items_amount + table_charge) × service_percent / 100)
base_total     = items_amount + table_charge + service_amount
discount       = discount_percent ? base_total × %/100 : discount_amount   // §5
grand_total    = MAX(ROUND(base_total − discount), 0)
```

At payment:

```
total_paid     = cash_amount + card_amount
change_amount  = MAX(total_paid − grand_total, 0)
```

**The `grand_total` above is authoritative** — it is exactly what the
`POST /orders/{id}/pay` endpoint recomputes and enforces. The frontend should
display this same number so the customer is never surprised at payment time.

---

## 2. Components

| Component | Meaning | Source |
|---|---|---|
| `items_amount` (food_total) | Sum of ordered items | order items |
| `table_charge` | Time played on a time-based table | table time sessions |
| `service_amount` | Service fee (%) on items **+ table** | `service_percent` |
| `discount` | Percent or flat discount | request / stored |
| `grand_total` | Final amount due | computed |
| `change_amount` | Money returned to customer | computed at pay |

---

## 3. Items amount

```
items_amount = Σ (item.quantity × item.price)
```

- Only items whose status is **not** `cancelled` are counted.
- `item.price` is the unit price captured on the order line (already includes any
  selected modifiers — the frontend does not add modifiers again).

---

## 4. Table time charge (time-based tables only)

Applies **only** when the table's `table_type = "time_based"` (e.g. billiard / PS
rooms). Normal tables (`simple`) are **never** charged for time.

```
table_charge = (accumulated_active_seconds / 3600) × price_per_hour
```

- `accumulated_active_seconds` counts only **active** (non-paused) time.
- The charge accrues while the timer runs and is finalized when the timer is
  closed (which happens automatically during payment).
- ⚠️ A timer left running accrues a large charge. Example: a room left on for
  47.8 active hours at 30 000/hour = **1 434 800**. Always show the live table
  charge so the cashier notices this before paying.

### Getting the live table charge

`GET /orders/{id}/table-price` → returns the current table amount:

```json
{
  "table_id": "…",
  "price_per_hour": "30000.00",
  "started_at": "2026-07-12T13:17:20Z",
  "duration_minutes": 93.5,
  "duration_hours": 1.5583,
  "total_price": "46750.00"      // ← current table_charge
}
```

Use `total_price` as the `table_charge` when computing the total and when sending
the payment (see §8).

---

## 5. Service charge

```
service_amount = ROUND((items_amount + table_charge) × service_percent / 100)
```

- `service_percent` is fixed on the order when it is created, taken from the
  branch's `default_service_percent` (fallback **20%**).
- Takeaway orders (no table) have `service_percent = 0`.
- ‼️ **Service applies to the table charge too**, not just items. This matters for
  time-based tables — see §7.

---

## 6. Discount

Sent only at payment time. Two mutually exclusive forms:

| Field | Meaning | Priority |
|---|---|---|
| `discount_percent` | e.g. `"10"` = 10% off `base_total` | **wins** if both sent |
| `discount_amount` | flat so'm off, e.g. `"5000"` | used only if percent absent |

```
discount = discount_percent ? ROUND(base_total × discount_percent / 100)
                            : discount_amount
```

Rules enforced by the backend (validation errors if broken):
- `discount_percent` must be between `0` and `100`.
- `discount_amount` cannot be negative.
- You cannot send both at once.

---

## 7. Two totals: displayed vs. charged ‼️ (read this)

There is a subtle difference between what the **read/display** path returns and
what the **payment** path charges, for **time-based tables**:

| Path | Formula for the table part |
|---|---|
| `GET /orders/{id}` (`total_amount`) | adds the **raw** `table_charge` (no service on it) |
| `POST /orders/{id}/pay` (`grand_total`) | charges **service on the table_charge** too |

So the payment total can be **higher** than the displayed `total_amount` by
`service_percent × table_charge`.

**Recommendation:** to avoid "insufficient payment" surprises, the frontend should
compute and display the total using the **payment formula** (§1), i.e. include the
table charge in the service base:

```
displayed_total = MAX(ROUND(
    items_amount
  + table_charge
  + (items_amount + table_charge) × service_percent / 100
  − discount
), 0)
```

This equals the authoritative `grand_total`.

---

## 8. Payment — `POST /orders/{id}/pay`

### Request body

```json
{
  "payment_type": "cash",            // "cash" | "card" | "split"
  "customer_paid_amount": "300000",  // REQUIRED, > 0 — total handed by customer
  "cash_amount": "200000",           // split only
  "card_amount": "100000",           // split only
  "discount_percent": "10",          // optional (§6)
  "discount_amount": "5000",         // optional (§6)
  "discount_comment": "…",           // optional
  "table_charge": "46750",           // optional — from GET table-price; auto-calc if omitted
  "user_id": "…",                    // optional — cashier (falls back to token)
  "cash_register_id": "…"            // optional
}
```

### Payment types

| `payment_type` | What to send | `total_paid` |
|---|---|---|
| `cash` | `customer_paid_amount` only (no cash/card fields) | = customer_paid_amount |
| `card` | `customer_paid_amount` only (no cash/card fields) | = customer_paid_amount |
| `split` | `cash_amount` + `card_amount` **and** `customer_paid_amount` | = cash + card |

For **split**, the backend requires `cash_amount + card_amount == customer_paid_amount`.

### `table_charge` handling
- If you **omit** `table_charge`, the backend auto-computes it from the table's
  time sessions. Recommended: fetch it from `GET table-price` and send it, so the
  displayed and charged values match exactly.
- If you **send** it, that value is used as-is.

### Success response (`200`)

```json
{
  "status": "success",
  "message": "Order marked as paid successfully",
  "data": {
    "id": "…",
    "table_id": "…",
    "cashier_id": "…",
    "status": "paid",
    "order_type": "dine_in",
    "total_amount": "139768",
    "paid_at": "2026-07-13T12:05:26Z",
    "items": [],
    "…": "…"
  },
  "code": 200
}
```

After success the order is fully closed server-side: `status = paid`, the table is
freed, and the timer session is closed. **Refetch the orders/tables list** to
refresh the UI. (`items` is always an array — never `null`.)

### Underpayment error (`400`)

If `customer_paid_amount` (or cash+card) does not cover `grand_total`, the pay is
rejected with an itemized reason:

```
insufficient payment: paid 295200 but 2016960 is due
(food 246000 + table time charge 1434800 + service 336160 - discount 0)
```

Use these numbers to tell the cashier exactly what is still owed (most often an
unnoticed table time charge).

### Small rounding tolerance
The backend accepts a tiny shortfall (`allowed_gap`): `1` so'm for normal tables,
or `ROUND(price_per_hour / 60)` (one minute of time) for time-based tables. You do
not need to implement this — just know that a 1-so'm rounding difference will not
fail the payment.

---

## 9. Order detail fields (`GET /orders/{id}`)

Fields relevant to totals returned in the order response:

| Field | Meaning |
|---|---|
| `items_amount` | `items_amount` / food_total |
| `service_percent` | e.g. `"20"` |
| `service_amount` | service fee |
| `table_type` | `"time_based"` when applicable |
| `price_per_hour` | table hourly rate |
| `table_started_at` | when the timer started |
| `table_amount` | **live** table charge (raw) |
| `total_amount` | running total (see §7 caveat) |

For time-based tables, `total_amount` on an unpaid order already includes the live
raw `table_amount`, but **not** service on it — see §7.

---

## 10. Worked examples

### Example A — normal table, cash

```
items_amount   = 246 000
table_charge   = 0
service_percent= 20
service_amount = ROUND(246000 × 20/100)          = 49 200
base_total     = 246000 + 0 + 49200              = 295 200
discount       = 0
grand_total    = 295 200
```
Customer pays `customer_paid_amount = "295200"`, `payment_type = "cash"` → change 0.

### Example B — time-based table with food (the tricky one)

```
items_amount   = 246 000
table_charge   = 1 434 800     // 47.8 active hours × 30 000/hr
service_percent= 20
service_amount = ROUND((246000 + 1434800) × 20/100) = 336 160
base_total     = 246000 + 1434800 + 336160          = 2 016 960
discount       = 0
grand_total    = 2 016 960
```
If the frontend showed only `295 200` (food + service, no table), payment of
`295 200` is **rejected**. Show `2 016 960`.

### Example C — split payment with 10% discount

```
items_amount   = 500 000
table_charge   = 0
service_amount = ROUND(500000 × 20/100)          = 100 000
base_total     = 600 000
discount       = ROUND(600000 × 10/100)          = 60 000
grand_total    = 540 000
```
Send `payment_type = "split"`, `cash_amount = "300000"`, `card_amount = "240000"`,
`customer_paid_amount = "540000"`, `discount_percent = "10"`.

---

## 11. Frontend checklist

- [ ] Compute the displayed total with the **payment formula** (§7) so it matches
      `grand_total` exactly — include the table charge in the service base.
- [ ] For time-based tables, fetch the live table charge from
      `GET /orders/{id}/table-price` and include it (and send it in the pay body).
- [ ] Surface the table charge prominently — a forgotten timer can dwarf the food.
- [ ] `discount_percent` overrides `discount_amount`; never send both.
- [ ] For `split`, ensure `cash_amount + card_amount == customer_paid_amount`.
- [ ] On `400 insufficient payment`, show the itemized breakdown from the message.
- [ ] After a `200` pay, **refetch** orders/tables to reflect the closed state.
- [ ] Treat `items` as possibly empty `[]` (never `null`).
```
