# departments

9 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/departments`

**Get all departments**

Retrieve all departments with pagination, optional search, storage filter and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by department name |
| `storage_id` | query | string | no | Filter by storage ID |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedDepartmentsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/departments`

**Create a new department**

Create a new department with name, optional translation ID, and storage ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateDepartmentRequest | yes | Department creation data |

**Body schema:** `model.CreateDepartmentRequest`

**Responses**

- `201` — Department created successfully → `model.DepartmentResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/departments-lang`

**Get all departments with language support**

Retrieve all departments with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand FK relations (comma-separated: storage_id, name_i18n) |

**Responses**

- `200` — Departments retrieved successfully → `array<model.DepartmentResponse>`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/departments-lang/{id}`

**Get department by ID with language support**

Retrieve a specific department by its ID with names translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Department ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `expand` | query | string | no | Expand FK relations (comma-separated: storage_id, name_i18n) |

**Responses**

- `200` — Department details → `model.DepartmentResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Department not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/departments/storage/{storageId}`

**Get departments by storage ID**

Retrieve all departments for a specific storage

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `storageId` | path | string | yes | Storage ID |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand FK relations (comma-separated: storage_id, name_i18n) |

**Responses**

- `200` — Departments found → `array<model.DepartmentResponse>`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/departments/{id}`

**Delete a department**

Soft delete a department by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Department ID |

**Responses**

- `204` — Department deleted successfully
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Department not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/departments/{id}`

**Get a department by ID**

Retrieve a specific department by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Department ID |
| `expand` | query | string | no | Expand FK relations (comma-separated: storage_id, name_i18n) |

**Responses**

- `200` — Department found → `model.DepartmentResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Department not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/departments/{id}`

**Update a department**

Update an existing department

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Department ID |
| `input` | body | model.UpdateDepartmentRequest | yes | Department update data |

**Body schema:** `model.UpdateDepartmentRequest`

**Responses**

- `200` — Department updated successfully → `model.DepartmentResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Department not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/departments/{id}/restore`

**Restore a department**

Restore a soft-deleted department by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Department ID |

**Responses**

- `200` — Department restored successfully → `model.DepartmentResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Department not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

