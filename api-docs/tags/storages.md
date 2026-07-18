# storages

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/storages`

**Get all storages**

Retrieve all storages with pagination, optional search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by storage name |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedStoragesResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/storages`

**Create a new storage**

Create a new storage with name, branch ID, and optional translation ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateStorageRequest | yes | Storage creation data |

**Body schema:** `model.CreateStorageRequest`

**Responses**

- `201` — Storage created successfully → `model.StorageResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/storages-lang`

**Get all storages with language support**

Retrieve all storages with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. name_i18n) |

**Responses**

- `200` — Storages retrieved successfully → `array<model.StorageResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/storages-lang/{id}`

**Get storage by ID with language support**

Retrieve a specific storage by its ID with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Storage ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. name_i18n) |

**Responses**

- `200` — Storage details → `model.StorageResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Storage not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/storages/branch/{branchId}`

**Get storages by branch ID**

Retrieve all storages for a specific branch

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `branchId` | path | string | yes | Branch ID |
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. name_i18n) |

**Responses**

- `200` — List of storages for the branch → `array<model.StorageResponse>`
- `400` — Invalid branch ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/storages/{id}`

**Delete storage**

Soft delete a storage (mark as deleted without removing from database)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Storage ID |

**Responses**

- `200` — Storage deleted successfully → `model.SuccessResponse`
- `400` — Invalid storage ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/storages/{id}`

**Get storage by ID**

Retrieve a specific storage by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Storage ID |
| `expand` | query | string | no | Comma-separated relations to expand (e.g. name_i18n) |

**Responses**

- `200` — Storage details → `model.StorageResponse`
- `400` — Invalid storage ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Storage not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/storages/{id}`

**Update storage**

Update a storage's information

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Storage ID |
| `input` | body | model.UpdateStorageRequest | yes | Storage update data |

**Body schema:** `model.UpdateStorageRequest`

**Responses**

- `200` — Storage updated successfully → `model.StorageResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/storages/{id}/restore`

**Restore storage**

Restore a previously deleted storage

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Storage ID |

**Responses**

- `200` — Storage restored successfully → `model.SuccessResponse`
- `400` — Invalid storage ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

