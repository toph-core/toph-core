# cafe-tables

16 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/cafe-tables`

**Get all cafe tables**

Retrieve all cafe tables with pagination, optional search, hall filter, status filter and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by table number |
| `hall_id` | query | string | no | Filter by hall ID |
| `status` | query | string | no | Filter by table status |
| `table_type` | query | string | no | Filter by table type |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |

**Responses**

- `200` — OK → `model.PaginatedCafeTablesResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/cafe-tables`

**Create a new cafe table**

Create a new cafe table in a specific hall

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateCafeTableRequest | yes | Create Cafe Table Request |

**Body schema:** `model.CreateCafeTableRequest`

**Responses**

- `201` — Created → `model.CafeTableResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/available/capacity`

**Get available tables by capacity**

Get available tables that can accommodate a minimum number of guests

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `capacity` | query | integer | yes | Minimum capacity |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `array<model.CafeTableResponse>`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/available/hall/{hall_id}`

**Get available tables by hall**

Get all available (free) tables in a specific hall

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `hall_id` | path | string | yes | Hall ID |

**Responses**

- `200` — OK → `array<model.CafeTableResponse>`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/available/hall/{hall_id}/capacity`

**Get available tables by hall and capacity**

Get available tables in a specific hall that can accommodate a minimum number of guests

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `hall_id` | path | string | yes | Hall ID |
| `capacity` | query | integer | yes | Minimum capacity |

**Responses**

- `200` — OK → `array<model.CafeTableResponse>`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/hall-status`

**Get cafe tables by hall and status**

Get tables in a specific hall with a specific status

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `hall_id` | query | string | no | Hall ID |
| `status` | query | string | no | Status |

**Responses**

- `200` — OK → `array<model.CafeTableResponse>`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/hall/{hall_id}`

**Get cafe tables by hall ID**

Get all tables in a specific hall

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `hall_id` | path | string | yes | Hall ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `array<model.CafeTableResponse>`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/stats/occupancy`

**Get table occupancy statistics**

Get overall cafe table occupancy statistics

_Auth: Bearer required_

**Responses**

- `200` — OK → `model.TableOccupancyStats`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/status/{status}`

**Get cafe tables by status**

Get tables with a specific status

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `status` | path | string | yes | Status |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `array<model.CafeTableResponse>`
- `400` — Bad Request → `model.ErrorResponse`

---

### `DELETE` `/api/v1/cafe-tables/{id}`

**Delete a cafe table**

Soft delete a cafe table

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cafe Table ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `GET` `/api/v1/cafe-tables/{id}`

**Get cafe table by ID**

Get a specific cafe table by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cafe Table ID |

**Responses**

- `200` — OK → `model.CafeTableResponse`
- `404` — Not Found → `model.ErrorResponse`

---

### `PUT` `/api/v1/cafe-tables/{id}`

**Update a cafe table**

Update a cafe table details

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cafe Table ID |
| `request` | body | model.UpdateCafeTableRequest | yes | Update Cafe Table Request |

**Body schema:** `model.UpdateCafeTableRequest`

**Responses**

- `200` — OK → `model.CafeTableResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `POST` `/api/v1/cafe-tables/{id}/restore`

**Restore a cafe table**

Restore a soft deleted cafe table

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cafe Table ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `POST` `/api/v1/cafe-tables/{id}/set-busy`

**Set table as busy**

Mark a cafe table as busy (occupied)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cafe Table ID |

**Responses**

- `200` — OK → `model.CafeTableResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `POST` `/api/v1/cafe-tables/{id}/set-free`

**Set table as free**

Mark a cafe table as free (available)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cafe Table ID |

**Responses**

- `200` — OK → `model.CafeTableResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

### `PATCH` `/api/v1/cafe-tables/{id}/status`

**Update cafe table status**

Update the status of a cafe table

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Cafe Table ID |
| `request` | body | model.UpdateCafeTableStatusRequest | yes | Update Cafe Table Status Request |

**Body schema:** `model.UpdateCafeTableStatusRequest`

**Responses**

- `200` — OK → `model.CafeTableResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`

---

