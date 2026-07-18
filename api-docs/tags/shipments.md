# Shipments

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/shipments`

**List shipments**

List shipments filtered by storage, supplier, status, date range. Returns pagination info and total_amount_sum for the filtered range.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `storage_id` | query | string | no | Filter by storage UUID |
| `supplier_id` | query | string | no | Filter by supplier UUID |
| `status` | query | string | no | Filter by status (draft/active/cancelled) |
| `start_date` | query | string | no | Start date (RFC3339) |
| `end_date` | query | string | no | End date (RFC3339) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `array<model.ShipmentResponse>`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/shipments`

**Create shipment**

Create a new shipment. Use status="draft" (default) or status="active". If active, stock is deducted immediately.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateShipmentRequest | yes | Create shipment |

**Body schema:** `model.CreateShipmentRequest`

**Responses**

- `201` — Created → `model.ShipmentResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/shipments/batch`

**Create shipment with items (batch)**

Creates a shipment header and upserts all provided items in a single request. Use status="draft" (default) or status="active" to immediately deduct stock.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateShipmentBatchRequest | yes | Batch create |

**Body schema:** `model.CreateShipmentBatchRequest`

**Responses**

- `201` — Created → `model.ShipmentWithItemsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/shipments/{id}`

**Delete shipment**

Soft-deletes a shipment. If the shipment was active, ingredient stock is reversed.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shipment ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/shipments/{id}`

**Get shipment by ID**

Returns shipment header + all items with stock_before/stock_after snapshots

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shipment ID |

**Responses**

- `200` — OK → `model.ShipmentWithItemsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`

---

### `PUT` `/api/v1/shipments/{id}`

**Update shipment**

Update storage, supplier, date, description, and/or status. Setting status="active" deducts stock (draft→active). Setting status="draft" reverses stock (active→draft).

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shipment ID |
| `request` | body | model.UpdateShipmentRequest | yes | Update shipment |

**Body schema:** `model.UpdateShipmentRequest`

**Responses**

- `200` — OK → `model.ShipmentResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/shipments/{id}/batch`

**Update shipment with items (batch)**

Updates a shipment header and upserts all provided items in a single request.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shipment ID |
| `request` | body | model.UpdateShipmentBatchRequest | yes | Batch update |

**Body schema:** `model.UpdateShipmentBatchRequest`

**Responses**

- `200` — OK → `model.ShipmentWithItemsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/shipments/{id}/items`

**Upsert shipment items**

Add/update multiple ingredient items. Each item is upserted (insert or update by ingredient_id). Returns items with live stock preview.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shipment ID |
| `request` | body | model.UpsertShipmentItemsRequest | yes | Items to upsert |

**Body schema:** `model.UpsertShipmentItemsRequest`

**Responses**

- `200` — OK → `array<model.ShipmentItemResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/shipments/{id}/items/{item_id}`

**Delete shipment item**

Remove an ingredient item from a shipment

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shipment ID |
| `item_id` | path | string | yes | Item ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

