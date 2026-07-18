# Good Details

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/compounds/{compound_id}/goods`

**Get good details by compound ID**

Get all good details using a specific compound with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `compound_id` | path | string | yes | Compound ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.GoodDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/good-details`

**Create good detail**

Create a new good detail (ingredient or compound in a good)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateGoodDetailRequest | yes | Create good detail request |

**Body schema:** `model.CreateGoodDetailRequest`

**Responses**

- `201` — Created → `model.GoodDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/good-details/{id}`

**Delete good detail**

Delete a good detail (soft delete)

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

### `GET` `/api/v1/good-details/{id}`

**Get good detail**

Get good detail by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |

**Responses**

- `200` — OK → `model.GoodDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/good-details/{id}`

**Update good detail**

Update good detail

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |
| `request` | body | model.UpdateGoodDetailRequest | yes | Update good detail request |

**Body schema:** `model.UpdateGoodDetailRequest`

**Responses**

- `200` — OK → `model.GoodDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/good-details/{id}/quantity`

**Update good detail quantity**

Update good detail quantity

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |
| `request` | body | model.UpdateGoodDetailQuantityRequest | yes | Update quantity request |

**Body schema:** `model.UpdateGoodDetailQuantityRequest`

**Responses**

- `200` — OK → `model.GoodDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/good-details/{id}/restore`

**Restore good detail**

Restore a deleted good detail

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Detail ID |

**Responses**

- `200` — OK → `model.GoodDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/goods/{good_id}/details`

**Get good details by good ID**

Get all good details for a specific good

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `good_id` | path | string | yes | Good ID |

**Responses**

- `200` — OK → `array<model.GoodDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredients/{ingredient_id}/goods`

**Get good details by ingredient ID**

Get all good details using a specific ingredient with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `ingredient_id` | path | string | yes | Ingredient ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.GoodDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

