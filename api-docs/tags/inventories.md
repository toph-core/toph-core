# inventories

12 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/inventories`

**Get inventories**

Retrieve inventories with pagination, filters, search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `date_from` | query | string | no | Start date (YYYY-MM-DD) |
| `date_to` | query | string | no | End date (YYYY-MM-DD) |
| `storage_id` | query | string | no | Storage ID |
| `ingredient_id` | query | string | no | Ingredient ID |
| `status` | query | string | no | Inventory status (draft, active, deleted) |
| `search` | query | string | no | Search by description or number |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. storage_id) |

**Responses**

- `200` — OK → `model.PaginatedInventoriesResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/inventories`

**Create a new inventory**

Create a new inventory with date, storage_id, optional description fields and status

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateInventoryRequest | yes | Inventory creation data |

**Body schema:** `model.CreateInventoryRequest`

**Responses**

- `201` — Inventory created successfully → `model.InventoryResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/inventories/batch`

**Batch delete inventories**

Soft delete multiple inventories. Reverses stock changes for any that are active.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.DeleteInventoriesBatchRequest | yes | List of inventory IDs to delete |

**Body schema:** `model.DeleteInventoriesBatchRequest`

**Responses**

- `200` — Inventories deleted successfully → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Inventory not found → `model.ErrorResponse`
- `409` — Inventory already deleted or not the latest → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/inventories/batch`

**Create inventory with items**

Creates an inventory and upserts its items in a single request

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateInventoryBatchRequest | yes | Inventory batch creation data |

**Body schema:** `model.CreateInventoryBatchRequest`

**Responses**

- `201` — Created → `model.CreateInventoryBatchResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/inventories/{id}`

**Delete inventory**

Soft delete an inventory

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |

**Responses**

- `204` — Inventory deleted successfully → `model.SuccessResponse`
- `400` — Invalid inventory ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Inventory not found → `model.ErrorResponse`
- `409` — Inventory already deleted or not the latest → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/inventories/{id}`

**Get inventory by ID**

Retrieve a specific inventory by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. storage_id) |

**Responses**

- `200` — Inventory retrieved successfully → `model.InventoryResponse`
- `400` — Invalid inventory ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Inventory not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/inventories/{id}`

**Update inventory**

Update an inventory fields (date, storage_id, descriptions, status)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |
| `input` | body | model.UpdateInventoryRequest | yes | Inventory update data |

**Body schema:** `model.UpdateInventoryRequest`

**Responses**

- `200` — Inventory updated successfully → `model.InventoryResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/inventories/{id}/calculate`

**Calculate inventory totals**

Calculate and persist inventory totals (surplus_amount, shortage_amount, remaining_amount) into the inventory

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |

**Responses**

- `200` — Inventory calculated successfully → `model.InventoryResponse`
- `400` — Invalid inventory ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/inventories/{id}/items`

**Get inventory items**

Retrieve computed inventory items for an inventory (system qty from stock, counted qty, difference, amounts)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. ingredient_id) |

**Responses**

- `200` — Inventory items retrieved successfully → `array<model.InventoryItemComputedResponse>`
- `400` — Invalid inventory ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/inventories/{id}/items/batch`

**Batch delete inventory items**

Remove specific inventory items by ID. Reverses stock if the inventory is active.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |
| `input` | body | model.DeleteInventoryItemsBatchRequest | yes | List of inventory item IDs to delete |

**Body schema:** `model.DeleteInventoryItemsBatchRequest`

**Responses**

- `200` — Inventory items deleted successfully → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/inventories/{id}/items/batch`

**Replace inventory items batch**

Full replace of inventory items. Optionally update inventory fields (date, storage_id, status, description) in the same call. Stock adjusted on status transition.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |
| `input` | body | model.UpsertInventoryItemsRequest | yes | Inventory items batch data (items required; inventory fields optional) |

**Body schema:** `model.UpsertInventoryItemsRequest`

**Responses**

- `200` — Inventory items updated successfully → `object`
- `400` — Invalid request or inventory is deleted → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/inventories/{id}/restore`

**Restore inventory**

Restore a previously deleted inventory

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |

**Responses**

- `200` — Inventory restored successfully → `model.InventoryResponse`
- `400` — Invalid inventory ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

