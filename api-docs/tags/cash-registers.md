# cash-registers

7 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/cash-registers`

**Get all cash registers**

Retrieve all cash registers for the current branch with optional search filter

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Filter by name |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Cash registers retrieved successfully → `array<model.CashRegisterResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/cash-registers`

**Create a new cash register**

Create a new cash register for the current branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CashRegisterRequest | yes | Cash register data |

**Body schema:** `model.CashRegisterRequest`

**Responses**

- `201` — Cash register created successfully → `model.CashRegisterResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/cash-registers/branch/{branchId}`

**Get cash registers by branch ID**

Retrieve all cash registers for a specific branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `branchId` | path | string | yes | Branch ID |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |

**Responses**

- `200` — Cash registers retrieved successfully → `array<model.CashRegisterResponse>`
- `400` — Invalid branch ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/cash-registers/{id}`

**Delete cash register**

Soft delete a cash register

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cash register ID |

**Responses**

- `200` — Cash register deleted successfully → `model.SuccessResponse`
- `400` — Invalid ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Cash register not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/cash-registers/{id}`

**Get cash register by ID**

Retrieve a cash register by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cash register ID |

**Responses**

- `200` — Cash register retrieved successfully → `model.CashRegisterResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Cash register not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/cash-registers/{id}`

**Update cash register**

Update a cash register

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cash register ID |
| `request` | body | model.CashRegisterRequest | yes | Cash register update data |

**Body schema:** `model.CashRegisterRequest`

**Responses**

- `200` — Cash register updated successfully → `model.CashRegisterResponse`
- `400` — Invalid request format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Cash register not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/cash-registers/{id}/restore`

**Restore cash register**

Restore a soft-deleted cash register

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cash register ID |

**Responses**

- `200` — Cash register restored successfully → `model.SuccessResponse`
- `400` — Invalid ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

