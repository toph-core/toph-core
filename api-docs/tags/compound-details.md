# Compound Details

7 endpoint(s)

[← Back to index](../README.md)

### `POST` `/api/v1/compound-details`

**Create compound detail**

Create a new compound detail (ingredient in a compound)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateCompoundDetailRequest | yes | Create compound detail request |

**Body schema:** `model.CreateCompoundDetailRequest`

**Responses**

- `201` — Created → `model.CompoundDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/compound-details/{id}`

**Delete compound detail**

Delete a compound detail (soft delete)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/compound-details/{id}`

**Get compound detail**

Get compound detail by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |

**Responses**

- `200` — OK → `model.CompoundDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/compound-details/{id}`

**Update compound detail**

Update compound detail quantity

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |
| `request` | body | model.UpdateCompoundDetailRequest | yes | Update compound detail request |

**Body schema:** `model.UpdateCompoundDetailRequest`

**Responses**

- `200` — OK → `model.CompoundDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/compound-details/{id}/restore`

**Restore compound detail**

Restore a deleted compound detail

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |

**Responses**

- `200` — OK → `model.CompoundDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/compounds/{compound_id}/details`

**Get compound details by compound ID**

Get all compound details for a specific compound

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `compound_id` | path | string | yes | Compound ID |

**Responses**

- `200` — OK → `array<model.CompoundDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredients/{ingredient_id}/compounds`

**Get compound details by ingredient ID**

Get all compound details using a specific ingredient with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `ingredient_id` | path | string | yes | Ingredient ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.CompoundDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

