# ingredient-stock

11 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/ingredient-stock`

**Get all ingredient stock**

Retrieve all ingredient stock records with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `ingredient_id` | query | string | no | Filter by ingredient ID |
| `ingredient_name` | query | string | no | Search by ingredient name |
| `search` | query | string | no | Search by ingredient name |
| `storage_id` | query | string | no | Filter by storage ID |
| `measurement` | query | string | no | Filter by measurement (kg, l, piece) |
| `sort_by` | query | string | no | Sort by: created_at, quantity, price_per_unit |
| `sort_order` | query | string | no | Sort order: asc, desc |

**Responses**

- `200` — List of all ingredient stock → `array<model.IngredientStockResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredient-stock`

**Create ingredient stock**

Create a new stock record for an ingredient at a specific branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateIngredientStockRequest | yes | Ingredient stock creation data |

**Body schema:** `model.CreateIngredientStockRequest`

**Responses**

- `201` — Ingredient stock created successfully → `model.IngredientStockResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-stock/branch/{branchId}`

**Get stock by branch ID**

Retrieve all ingredient stock for a specific branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `branchId` | path | string | yes | Branch ID |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Expand FK relations (comma-separated: ingredient_id, storage_id, branch_id) |

**Responses**

- `200` — List of ingredient stock for the branch → `array<model.IngredientStockResponse>`
- `400` — Invalid branch ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-stock/by-ingredient-branch`

**Get stock by ingredient and branch**

Retrieve stock information for a specific ingredient at a specific branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `ingredient_id` | query | string | yes | Ingredient ID |
| `branch_id` | query | string | yes | Branch ID |

**Responses**

- `200` — Ingredient stock details → `model.IngredientStockResponse`
- `400` — Invalid parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient stock not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-stock/ingredient/{ingredientId}`

**Get stock by ingredient ID**

Retrieve stock for a specific ingredient across all branches

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `ingredientId` | path | string | yes | Ingredient ID |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Expand FK relations (comma-separated: ingredient_id, storage_id, branch_id) |

**Responses**

- `200` — List of stock for the ingredient → `array<model.IngredientStockResponse>`
- `400` — Invalid ingredient ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/ingredient-stock/{id}`

**Delete ingredient stock**

Soft delete an ingredient stock record (mark as deleted without removing from database)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Stock ID |

**Responses**

- `200` — Ingredient stock deleted successfully → `model.SuccessResponse`
- `400` — Invalid stock ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-stock/{id}`

**Get ingredient stock by ID**

Retrieve a specific ingredient stock record by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Stock ID |
| `expand` | query | string | no | Expand FK relations (comma-separated: ingredient_id, storage_id, branch_id) |

**Responses**

- `200` — Ingredient stock details → `model.IngredientStockResponse`
- `400` — Invalid stock ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient stock not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/ingredient-stock/{id}`

**Update ingredient stock**

Update the quantity of an ingredient stock record

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Stock ID |
| `input` | body | model.UpdateIngredientStockRequest | yes | Stock update data |

**Body schema:** `model.UpdateIngredientStockRequest`

**Responses**

- `200` — Ingredient stock updated successfully → `model.IngredientStockResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient stock not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredient-stock/{id}/add`

**Add to ingredient stock**

Add a specified quantity to an existing ingredient stock

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Stock ID |
| `input` | body | handler.stockAdjustRequest | yes | Quantity to add |

**Body schema:** `handler.stockAdjustRequest`

**Responses**

- `200` — Quantity added successfully → `model.IngredientStockResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredient-stock/{id}/remove`

**Remove from ingredient stock**

Remove a specified quantity from an existing ingredient stock

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Stock ID |
| `input` | body | handler.stockAdjustRequest | yes | Quantity to remove |

**Body schema:** `handler.stockAdjustRequest`

**Responses**

- `200` — Quantity removed successfully → `model.IngredientStockResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredient-stock/{id}/restore`

**Restore ingredient stock**

Restore a previously deleted ingredient stock record

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Stock ID |

**Responses**

- `200` — Ingredient stock restored successfully → `model.SuccessResponse`
- `400` — Invalid stock ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

