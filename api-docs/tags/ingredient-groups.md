# ingredient-groups

8 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/ingredient-groups`

**Get all ingredient groups**

Retrieve all ingredient groups with pagination and optional search

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `search` | query | string | no | Search by name |

**Responses**

- `200` — List of all ingredient groups → `array<model.IngredientGroupResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredient-groups`

**Create a new ingredient group**

Create a new ingredient group with name and optional translation

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateIngredientGroupRequest | yes | Ingredient group creation data |

**Body schema:** `model.CreateIngredientGroupRequest`

**Responses**

- `201` — Ingredient group created successfully → `model.IngredientGroupResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-groups-lang`

**Get all ingredient groups with language support**

Retrieve all ingredient groups with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |

**Responses**

- `200` — Ingredient groups retrieved successfully → `array<model.IngredientGroupResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-groups-lang/{id}`

**Get ingredient group by ID with language support**

Retrieve a specific ingredient group by its ID with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Group ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |

**Responses**

- `200` — Ingredient group details → `model.IngredientGroupResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient group not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/ingredient-groups/{id}`

**Delete ingredient group**

Soft delete an ingredient group (mark as deleted without removing from database)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Group ID |

**Responses**

- `200` — Ingredient group deleted successfully → `model.SuccessResponse`
- `400` — Invalid group ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredient-groups/{id}`

**Get ingredient group by ID**

Retrieve a specific ingredient group by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Group ID |

**Responses**

- `200` — Ingredient group details → `model.IngredientGroupResponse`
- `400` — Invalid group ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient group not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/ingredient-groups/{id}`

**Update ingredient group**

Update an existing ingredient group's information

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Group ID |
| `input` | body | model.UpdateIngredientGroupRequest | yes | Ingredient group update data |

**Body schema:** `model.UpdateIngredientGroupRequest`

**Responses**

- `200` — Ingredient group updated successfully → `model.IngredientGroupResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient group not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredient-groups/{id}/restore`

**Restore ingredient group**

Restore a previously deleted ingredient group

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient Group ID |

**Responses**

- `200` — Ingredient group restored successfully → `model.SuccessResponse`
- `400` — Invalid group ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

