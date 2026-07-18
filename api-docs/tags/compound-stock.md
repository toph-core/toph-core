# Compound Stock

11 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/branches/{branch_id}/compound-stock`

**Get compound stock by branch**

Get all compound stocks for a specific branch with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `branch_id` | path | string | yes | Branch ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.CompoundStockResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/compound-stock`

**Get all compound stock**

Get all compound stocks with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.CompoundStockResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/compound-stock`

**Create compound stock**

Create a new compound stock entry for a branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateCompoundStockRequest | yes | Create compound stock request |

**Body schema:** `model.CreateCompoundStockRequest`

**Responses**

- `201` — Created → `model.CompoundStockResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/compound-stock/search`

**Get compound stock by compound and branch**

Get compound stock for a specific compound in a specific branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `compound_id` | query | string | yes | Compound ID |
| `branch_id` | query | string | yes | Branch ID |

**Responses**

- `200` — OK → `model.CompoundStockResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/compound-stock/{id}`

**Delete compound stock**

Delete compound stock (soft delete)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Stock ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/compound-stock/{id}`

**Get compound stock**

Get compound stock by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Stock ID |

**Responses**

- `200` — OK → `model.CompoundStockResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/compound-stock/{id}`

**Update compound stock**

Update compound stock quantity

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Stock ID |
| `request` | body | model.UpdateCompoundStockRequest | yes | Update compound stock request |

**Body schema:** `model.UpdateCompoundStockRequest`

**Responses**

- `200` — OK → `model.CompoundStockResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/compound-stock/{id}/add`

**Add to compound stock**

Add quantity to compound stock

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Stock ID |
| `request` | body | model.AddToCompoundStockRequest | yes | Add to compound stock request |

**Body schema:** `model.AddToCompoundStockRequest`

**Responses**

- `200` — OK → `model.CompoundStockResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/compound-stock/{id}/remove`

**Remove from compound stock**

Remove quantity from compound stock

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Stock ID |
| `request` | body | model.RemoveFromCompoundStockRequest | yes | Remove from compound stock request |

**Body schema:** `model.RemoveFromCompoundStockRequest`

**Responses**

- `200` — OK → `model.CompoundStockResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/compound-stock/{id}/restore`

**Restore compound stock**

Restore deleted compound stock

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Stock ID |

**Responses**

- `200` — OK → `model.CompoundStockResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/compounds/{compound_id}/stock`

**Get compound stock by compound**

Get all stock entries for a specific compound across all branches with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `compound_id` | path | string | yes | Compound ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.CompoundStockResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

