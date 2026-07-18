# Modifier Calculations

5 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/modifiers/calculations`

**List modifier calculations**

Returns all ingredient/child-compound calculation rows for a modifier.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `modifier_id` | query | string | yes | Modifier ID |
| `lang` | query | string | no | Language (uz, ru, en) |

**Responses**

- `200` — Modifier calculations retrieved successfully → `object`
- `400` — modifier_id is required / invalid → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Modifier not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/modifiers/calculations`

**Create modifier calculation**

Add an ingredient or child compound to a modifier tech-card.

**Use this API when a modifier itself consumes stock.**

Examples:
- Extra cheese -> ingredient cheese, quantity 0.05
- Salad set -> child compound salad-base, quantity 1

Provide exactly one of:
- ingredient_id
- compound_to_add_id

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateModifierCalculationRequest | yes | Modifier calculation request |

**Body schema:** `model.CreateModifierCalculationRequest`

**Responses**

- `201` — Modifier calculation created successfully → `object`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Modifier / ingredient / compound not found → `model.ErrorResponse`
- `409` — Conflict → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/modifiers/calculations/{id}`

**Delete modifier calculation**

Soft-delete a modifier calculation row.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Modifier Calculation ID |
| `lang` | query | string | no | Language (uz, ru, en) |

**Responses**

- `200` — Modifier calculation deleted successfully → `model.SuccessResponse`
- `400` — Invalid id → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Modifier calculation not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/modifiers/calculations/{id}`

**Get modifier calculation by ID**

Returns a single modifier calculation row.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Modifier Calculation ID |
| `lang` | query | string | no | Language (uz, ru, en) |

**Responses**

- `200` — Modifier calculation retrieved successfully → `object`
- `400` — Invalid id → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Modifier calculation not found → `model.ErrorResponse`

---

### `PUT` `/api/v1/modifiers/calculations/{id}`

**Update modifier calculation**

Update quantity for a modifier calculation row.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Modifier Calculation ID |
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.UpdateModifierCalculationRequest | yes | Update modifier calculation request |

**Body schema:** `model.UpdateModifierCalculationRequest`

**Responses**

- `200` — Modifier calculation updated successfully → `object`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Modifier calculation not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

