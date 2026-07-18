# branches

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/branches`

**Get all branches**

Retrieve all branches with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — List of all branches → `array<model.BranchResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/branches`

**Create a new branch**

Create a new branch with name, address, and phone

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateBranchRequest | yes | Branch creation data |

**Body schema:** `model.CreateBranchRequest`

**Responses**

- `201` — Branch created successfully → `model.BranchResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/branches-lang`

**Get all branches with language support**

Retrieve all branches with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Branches retrieved successfully → `array<model.BranchResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/branches-lang/detail`

**Get branch detail (storages + categories) with language support**

Retrieve branches with nested storages and each storage's categories, localized. A brand superadmin gets every branch; a branch-scoped user gets only their branch.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |

**Responses**

- `200` — Branch detail retrieved successfully → `array<model.BranchDetailResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/branches-lang/{id}`

**Get branch by ID with language support**

Retrieve a specific branch by its ID with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Branch ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |

**Responses**

- `200` — Branch details → `model.BranchResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Branch not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/branches/{id}`

**Delete branch**

Soft delete a branch (mark as deleted without removing from database)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Branch ID |

**Responses**

- `200` — Branch deleted successfully → `model.SuccessResponse`
- `400` — Invalid branch ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/branches/{id}`

**Get branch by ID**

Retrieve a specific branch by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Branch ID |

**Responses**

- `200` — Branch details → `model.BranchResponse`
- `400` — Invalid branch ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Branch not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/branches/{id}`

**Update branch**

Update a branch's name, name_i18n, phone, or default service percent

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Branch ID |
| `input` | body | model.UpdateBranchRequest | yes | Branch update data |

**Body schema:** `model.UpdateBranchRequest`

**Responses**

- `200` — Branch updated successfully → `model.BranchResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/branches/{id}/restore`

**Restore branch**

Restore a previously deleted branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Branch ID |

**Responses**

- `200` — Branch restored successfully → `model.SuccessResponse`
- `400` — Invalid branch ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

