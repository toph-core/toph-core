# reports

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/bills`

**Get bills**

List bills (orders) with bill snapshots and filters, supports expand

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `start` | query | string | no | Start date/time (RFC3339 or YYYY-MM-DD) |
| `end` | query | string | no | End date/time (RFC3339 or YYYY-MM-DD) |
| `bill_no` | query | integer | no | Bill number to search within the date range |
| `bill_status` | query | string | no | Bill status (opened, closed, paid) |
| `payment_type` | query | string | no | Payment type (cash, card) |
| `waiter_id` | query | string | no | Waiter ID (UUID) |
| `hall_id` | query | string | no | Hall ID (UUID) |
| `table_id` | query | string | no | Table ID (UUID) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand relations (comma-separated: user_id, hall_id, table_id, etc) |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/bills/{id}`

**Get bill details**

Get full bill details including items, supports expand

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Bill ID (UUID) |
| `expand` | query | string | no | Expand relations (comma-separated: user_id, hall_id, etc) |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-reports`

**Get ingredient report**

Retrieve ingredient report for a storage within a date range. Supports sorting by numeric fields and filtering by measurement and ingredient IDs.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `storage_id` | query | string | yes | Storage ID |
| `start` | query | string | no | Start datetime (RFC3339) or date (YYYY-MM-DD) |
| `end` | query | string | no | End datetime (RFC3339) or date (YYYY-MM-DD) |
| `ingredient_id` | query | string | no | Ingredient ID (optional filter) |
| `measurement` | query | string | no | Filter by exact measurement/unit |
| `ingredient_ids` | query | string | no | Comma-separated ingredient UUIDs to filter |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Ingredient report retrieved successfully → `array<model.IngredientReportItem>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-reports/inventory-status`

**Get ingredient inventory status report**

Retrieve ingredient report where begin_qty is anchored at the most recent inventory count event. For each ingredient, the report finds the latest inventory_surplus_in or inventory_shortage_out event and uses its stock_after as begin_qty. Subsequent movements are summed normally. If an ingredient has no inventory event, begin_qty defaults to 0 and all movements are included.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `storage_id` | query | string | yes | Storage ID (UUID) |
| `end` | query | string | no | End datetime (RFC3339 or YYYY-MM-DD format). Defaults to current time |
| `ingredient_id` | query | string | no | Optional filter: return only this ingredient (UUID) |
| `limit` | query | integer | no | Pagination: items per page (default: 20) |
| `offset` | query | integer | no | Pagination: offset from start (default: 0) |
| `expand` | query | string | no | Expand related fields (comma-separated) |

**Responses**

- `200` — Inventory status report retrieved successfully → `model.IngredientReportPaginatedResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-reports/{ingredientId}`

**Get ingredient report item**

Retrieve ingredient report for a specific ingredient within a storage and date range

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `ingredientId` | path | string | yes | Ingredient ID |
| `storage_id` | query | string | yes | Storage ID |
| `start` | query | string | no | Start datetime (RFC3339) or date (YYYY-MM-DD) |
| `end` | query | string | no | End datetime (RFC3339) or date (YYYY-MM-DD) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Ingredient report item retrieved successfully → `model.IngredientReportItem`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-reports/{ingredientId}/movements`

**Get ingredient report movements**

Retrieve ingredient stock movements for a specific ingredient within a storage and date range. The event_type field returns one of the following labels: invoice, order_out, deduction_in, deduction_out, transfer_in, transfer_out, outgoing_invoice, separation_act_in, separation_act_out, shipment_in, shipment_out, inventory_surplus, inventory_shortage, manual_in, manual_out, manual_adjustment. Unknown event types are returned as-is.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `ingredientId` | path | string | yes | Ingredient ID |
| `storage_id` | query | string | yes | Storage ID |
| `start` | query | string | no | Start datetime (RFC3339) or date (YYYY-MM-DD) |
| `end` | query | string | no | End datetime (RFC3339) or date (YYYY-MM-DD) |
| `limit` | query | integer | no | Limit (default: 50) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Ingredient report movements retrieved successfully → `array<model.IngredientStockMovementResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/reports/branches`

**Branches profit report**

One row per branch: orders, guests, revenue (grand_total), cost of goods sold (at sale time), service amount, discount, net profit (revenue - cost) and profit margin %. Only paid orders, filtered by date range. Aggregates across all branches; optionally narrowed to specific branch IDs.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `start_date` | query | string | yes | Start date (YYYY-MM-DD) |
| `end_date` | query | string | yes | End date (YYYY-MM-DD, inclusive) |
| `branch_ids` | query | string | no | Comma-separated branch UUIDs to filter |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `model.BranchesReportResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/reports/goods`

**Goods sales report**

Paginated report: qty sold, selling price, cost price, markup per dish. Only paid orders. Filters by date range, department, category, dish, waiter, hall, table, good IDs. Sortable by total_qty, avg_sell_price, total_sell, avg_cost_price, total_cost, avg_markup, total_markup, name.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `start_date` | query | string | yes | Start date (YYYY-MM-DD) |
| `end_date` | query | string | yes | End date (YYYY-MM-DD, inclusive) |
| `department_id` | query | string | no | Filter by department UUID |
| `category_id` | query | string | no | Filter by category UUID |
| `good_id` | query | string | no | Filter by specific good UUID |
| `waiter_id` | query | string | no | Filter by waiter UUID |
| `hall_id` | query | string | no | Filter by hall UUID |
| `table_id` | query | string | no | Filter by table UUID |
| `good_ids` | query | string | no | Comma-separated good UUIDs to filter |
| `department_ids` | query | string | no | Comma-separated department UUIDs to filter |
| `category_ids` | query | string | no | Comma-separated category UUIDs to filter |
| `waiter_ids` | query | string | no | Comma-separated waiter UUIDs to filter |
| `hall_ids` | query | string | no | Comma-separated hall UUIDs to filter |
| `table_ids` | query | string | no | Comma-separated table UUIDs to filter |
| `cost_min` | query | number | no | Min average cost price per unit (inclusive) |
| `cost_max` | query | number | no | Max average cost price per unit (inclusive) |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.GoodsReportResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/reports/goods/{id}/orders`

**Good orders report**

Per-order breakdown for a specific good: qty, sell price, cost price, markup per order. Only paid orders.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Good UUID |
| `start_date` | query | string | yes | Start date (YYYY-MM-DD) |
| `end_date` | query | string | yes | End date (YYYY-MM-DD, inclusive) |
| `waiter_id` | query | string | no | Filter by waiter UUID |
| `hall_id` | query | string | no | Filter by hall UUID |
| `table_id` | query | string | no | Filter by table UUID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.GoodOrdersReportResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

