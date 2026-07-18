# Dashboard

3 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/dashboard/kpis`

**Get dashboard KPIs**

Returns KPI metrics for current and previous periods

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `start` | query | string | yes | Start date (RFC3339 format) |
| `end` | query | string | yes | End date (RFC3339 format) |
| `previous_start` | query | string | no | Previous period start date (RFC3339 format, optional) |
| `previous_end` | query | string | no | Previous period end date (RFC3339 format, optional) |
| `group_by` | query | string | no | Group by (day, week, month) |
| `lang` | query | string | no | Language (uz, ru, en) |

**Responses**

- `200` — OK → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/dashboard/overview`

**Get dashboard overview**

Returns aggregated dashboard data including KPIs, sales dynamics, revenue by payment types, revenue by categories, and dish sales

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `start` | query | string | yes | Start date (RFC3339 format) |
| `end` | query | string | yes | End date (RFC3339 format) |
| `previous_start` | query | string | no | Previous period start date (RFC3339 format, optional) |
| `previous_end` | query | string | no | Previous period end date (RFC3339 format, optional) |
| `group_by` | query | string | no | Group by (day, week, month) |
| `dish_metric` | query | string | no | Dish metric (revenue, quantity) |
| `dish_sort` | query | string | no | Dish sort (asc, desc) |
| `limit` | query | integer | no | Limit for dish sales |
| `lang` | query | string | no | Language (uz, ru, en) |

**Responses**

- `200` — OK → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/dashboard/sales-dynamics`

**Get dashboard sales dynamics**

Returns sales dynamics for current and previous periods

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `start` | query | string | yes | Start date (RFC3339 format) |
| `end` | query | string | yes | End date (RFC3339 format) |
| `previous_start` | query | string | no | Previous period start date (RFC3339 format, optional) |
| `previous_end` | query | string | no | Previous period end date (RFC3339 format, optional) |
| `group_by` | query | string | no | Group by (day, week, month) |
| `lang` | query | string | no | Language (uz, ru, en) |

**Responses**

- `200` — OK → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

