# inventory_items

4 endpoint(s)

[← Back to index](../README.md)

### `POST` `/api/v1/inventories/{id}/items`

**Upsert inventory items**

Upsert (create/update) counted quantities for ingredients in an inventory and return computed rows

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory ID |
| `input` | body | model.UpsertInventoryItemsRequest | yes | Inventory items upsert data |

**Body schema:** `model.UpsertInventoryItemsRequest`

**Responses**

- `200` — Inventory items updated successfully → `object`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/inventory-items`

**Get inventory items**

Retrieve inventory items with pagination (limit/offset). Optionally filter by inventory_id.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `inventory_id` | query | string | no | Inventory ID to filter items |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |

**Responses**

- `200` — Inventory items retrieved successfully → `array<model.InventoryItemResponse>`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/inventory-items/{id}`

**Delete inventory item**

Soft delete an inventory item by inventory item ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory Item ID |

**Responses**

- `204` — Inventory item deleted successfully → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/inventory-items/{id}`

**Update inventory item**

Update inventory item counted_quantity by inventory item ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Inventory Item ID |
| `input` | body | model.UpdateInventoryItemRequest | yes | Inventory item update data |

**Body schema:** `model.UpdateInventoryItemRequest`

**Responses**

- `200` — Inventory item updated successfully → `model.InventoryItemResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

