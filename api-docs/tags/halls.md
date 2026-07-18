# halls

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/halls`

**Get all halls**

Retrieve all halls with pagination, optional search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by hall name |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedHallsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/halls`

**Create a new hall**

Create a new hall with name, branch ID, and optional translation ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateHallRequest | yes | Hall creation data |

**Body schema:** `model.CreateHallRequest`

**Responses**

- `201` — Hall created successfully → `model.HallResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/halls-lang`

**Get all halls with language support**

Retrieve all halls with names translated to specified language, with optional search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `search` | query | string | no | Search by hall name |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedHallsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/halls-lang/branch/{branchId}`

**Get halls by branch ID with language support**

Retrieve all halls for a specific branch with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `branchId` | path | string | yes | Branch ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — Halls retrieved successfully → `array<model.HallResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/halls/branch/{branchId}`

**Get all halls with branch  ID -  language support**

Retrieve all halls with names translated to specified language (uz, ru, en)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/halls/{id}`

**Delete a hall**

Soft delete a hall by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Hall ID |

**Responses**

- `204` — Hall deleted successfully
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Hall not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/halls/{id}`

**Get a hall by ID**

Retrieve a specific hall by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Hall ID |

**Responses**

- `200` — Hall found → `model.HallResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Hall not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/halls/{id}`

**Update a hall**

Update an existing hall

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Hall ID |
| `input` | body | model.UpdateHallRequest | yes | Hall update data |

**Body schema:** `model.UpdateHallRequest`

**Responses**

- `200` — Hall updated successfully → `model.HallResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Hall not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/halls/{id}/restore`

**Restore a hall**

Restore a soft-deleted hall by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Hall ID |

**Responses**

- `200` — Hall restored successfully → `model.HallResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Hall not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

