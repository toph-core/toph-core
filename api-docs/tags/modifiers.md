# modifiers

6 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/modifiers`

**Get modifiers**

Retrieve modifiers with optional search by name, description, or code

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `q` | query | string | no | Search query |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedModifiersResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/modifiers/with-calculations`

**Create modifier with calculations**

Create a new modifier and its ingredient/compound calculations in one atomic transaction.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateModifierWithCalculationsRequest | yes | Modifier + calculations |

**Body schema:** `model.CreateModifierWithCalculationsRequest`

**Responses**

- `201` — Created → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/modifiers/{id}`

**Delete modifier**

Soft delete a modifier by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Modifier ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/modifiers/{id}`

**Get modifier by ID**

Retrieve a modifier by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Modifier ID |

**Responses**

- `200` — OK → `model.ModifierResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/modifiers/{id}`

**Update modifier**

Update a modifier by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Modifier ID |
| `request` | body | model.UpdateModifierRequest | yes | Modifier update request |

**Body schema:** `model.UpdateModifierRequest`

**Responses**

- `200` — OK → `model.ModifierResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/modifiers/{id}/restore`

**Restore modifier**

Restore a soft deleted modifier by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Modifier ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

