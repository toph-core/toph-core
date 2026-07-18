# ingredients

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/ingredient-groups/{groupId}/ingredients`

**Get ingredients by group ID**

Retrieve all ingredients belonging to a specific group

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `groupId` | path | string | yes | Ingredient Group ID |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |

**Responses**

- `200` — List of ingredients in the group → `array<model.IngredientResponse>`
- `400` — Invalid group ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredients`

**Get all ingredients**

Retrieve all ingredients with pagination and optional search

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `search` | query | string | no | Search by name |
| `expand` | query | string | no | Expand FK relations (comma-separated: group_id, name_i18n) |

**Responses**

- `200` — List of all ingredients → `array<model.IngredientResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredients`

**Create a new ingredient**

Create a new ingredient with name, group, measurement, and optional fields

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateIngredientRequest | yes | Ingredient creation data |

**Body schema:** `model.CreateIngredientRequest`

**Responses**

- `201` — Ingredient created successfully → `model.IngredientResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredients-lang`

**Get all ingredients with language support**

Retrieve all ingredients with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand FK relations (comma-separated: group_id, name_i18n) |

**Responses**

- `200` — Ingredients retrieved successfully → `array<model.IngredientResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredients-lang/{id}`

**Get ingredient by ID with language support**

Retrieve a specific ingredient by its ID with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `expand` | query | string | no | Expand FK relations (comma-separated: group_id, name_i18n) |

**Responses**

- `200` — Ingredient details → `model.IngredientResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/ingredients/{id}`

**Delete ingredient**

Soft delete an ingredient (mark as deleted without removing from database)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient ID |

**Responses**

- `200` — Ingredient deleted successfully → `model.SuccessResponse`
- `400` — Invalid ingredient ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/ingredients/{id}`

**Get ingredient by ID**

Retrieve a specific ingredient by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient ID |
| `expand` | query | string | no | Expand FK relations (comma-separated: group_id, name_i18n) |

**Responses**

- `200` — Ingredient details → `model.IngredientResponse`
- `400` — Invalid ingredient ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/ingredients/{id}`

**Update ingredient**

Update an existing ingredient's information

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient ID |
| `input` | body | model.UpdateIngredientRequest | yes | Ingredient update data |

**Body schema:** `model.UpdateIngredientRequest`

**Responses**

- `200` — Ingredient updated successfully → `model.IngredientResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Ingredient not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/ingredients/{id}/restore`

**Restore ingredient**

Restore a previously deleted ingredient

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Ingredient ID |

**Responses**

- `200` — Ingredient restored successfully → `model.SuccessResponse`
- `400` — Invalid ingredient ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

