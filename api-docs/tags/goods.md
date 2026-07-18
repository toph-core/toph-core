# Goods

13 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/categories/{category_id}/goods`

**Get goods by category**

Get goods by category with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `category_id` | path | string | yes | Category ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.GoodResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/departments/{department_id}/goods`

**Get goods by department**

Get goods by department with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `department_id` | path | string | yes | Department ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.GoodResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/goods`

**Get all goods**

Get all goods with pagination, search, filters and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |
| `category_id` | query | string | no | Filter by category ID |
| `department_id` | query | string | no | Filter by department ID |
| `storage_id` | query | string | no | Filter by storage ID |
| `search` | query | string | no | Search by name or description |
| `min_price` | query | string | no | Minimum price |
| `max_price` | query | string | no | Maximum price |
| `min_cost` | query | string | no | Minimum cost price (себестоимость) |
| `max_cost` | query | string | no | Maximum cost price (себестоимость) |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |

**Responses**

- `200` — OK → `model.PaginatedGoodsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/goods`

**Create good**

Create a new good/menu item

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateGoodRequest | yes | Create good request |

**Body schema:** `model.CreateGoodRequest`

**Responses**

- `201` — Created → `model.GoodResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/goods-lang`

**Get all goods with language support**

Retrieve all goods/menu items with names and descriptions translated to specified language, including search, filters and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |
| `category_id` | query | string | no | Filter by category ID |
| `department_id` | query | string | no | Filter by department ID |
| `storage_id` | query | string | no | Filter by storage ID |
| `search` | query | string | no | Search by name or description |
| `min_price` | query | string | no | Minimum price |
| `max_price` | query | string | no | Maximum price |
| `min_cost` | query | string | no | Minimum cost price (себестоимость) |
| `max_cost` | query | string | no | Maximum cost price (себестоимость) |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |

**Responses**

- `200` — OK → `model.PaginatedGoodsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/goods-lang/{id}`

**Get good by ID with language support**

Retrieve a specific good/menu item by its ID with names and descriptions translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Good ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |

**Responses**

- `200` — Good details → `model.GoodResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Good not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/goods/with-calculations`

**Create good with multiple ingredients and compounds (One Save)**

Create a new good/menu item with its ingredient/compound calculations in one atomic transaction.

**How it works:**
- Create the good first
- Then create all ingredient calculations (price override or from ingredient.price_per_unit)
- Then create all compound calculations (price override or from compound.price)
- If any calculation fails, everything is rolled back (good won't be created)

**Example Request:**
```json
{
"good": { "name": "Osh", "price": "85000.00" },
"ingredient_calculations": [
{ "ingredient_id": "sabzi-uuid", "quantity": "2.5", "price": "8000.00" },
{ "ingredient_id": "guruch-uuid", "quantity": "0.5" }
],
"compound_calculations": [
{ "compound_id": "salad-uuid", "quantity": "3", "price": "15000.00" },
{ "compound_id": "xamir-uuid", "quantity": "1" }
],
"modifiers": [
{
"modifier_id": "modifier-uuid-1",
"is_required": false,
"sort_order": 1,
"ingredient_calculations": [
{ "ingredient_id": "ing-uuid", "quantity": "2.5", "price": "8000.00" }
],
"compound_calculations": [
{ "compound_id": "comp-uuid", "quantity": "1" }
]
}
]
}
```

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateGoodWithCalculationsRequest | yes | Good + ingredient calculations + compound calculations + modifiers |

**Body schema:** `model.CreateGoodWithCalculationsRequest`

**Responses**

- `201` — Good, calculations, and modifiers created successfully → `model.GoodWithCalculationsResponse`
- `400` — Invalid request (missing fields, invalid UUIDs, etc.) → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal error (ingredient not found, no invoice for ingredient, etc.) → `model.ErrorResponse`

---

### `DELETE` `/api/v1/goods/{id}`

**Delete good**

Delete a good (soft delete)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Good ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/goods/{id}`

**Get good**

Get good by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Good ID |

**Responses**

- `200` — OK → `model.GoodResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/goods/{id}`

**Update good**

Update good details

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Good ID |
| `request` | body | model.UpdateGoodRequest | yes | Update good request |

**Body schema:** `model.UpdateGoodRequest`

**Responses**

- `200` — OK → `model.GoodResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/goods/{id}/markup`

**Set good markup percent**

Set or clear markup percent (наценка). When set, the selling price is derived from cost (price = cost*(1+markup/100)) and recalculated automatically when cost changes. Send markup_percent null to clear it (manual price).

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Good ID |
| `request` | body | model.UpdateGoodMarkupRequest | yes | Update good markup request |

**Body schema:** `model.UpdateGoodMarkupRequest`

**Responses**

- `200` — OK → `model.GoodResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/goods/{id}/price`

**Update good price**

Update good price

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Good ID |
| `request` | body | model.UpdateGoodPriceRequest | yes | Update good price request |

**Body schema:** `model.UpdateGoodPriceRequest`

**Responses**

- `200` — OK → `model.GoodResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/goods/{id}/restore`

**Restore good**

Restore a deleted good

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Good ID |

**Responses**

- `200` — OK → `model.GoodResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

