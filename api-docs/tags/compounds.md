# compounds

12 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/compounds`

**Get all compounds**

Retrieve all compounds with pagination, optional search, department filter and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by compound name or description |
| `department_id` | query | string | no | Filter by department ID |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedCompoundsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/compounds`

**Create a new compound**

Create a new compound with ingredients and pricing

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateCompoundRequest | yes | Compound creation data |

**Body schema:** `model.CreateCompoundRequest`

**Responses**

- `201` — Compound created successfully → `model.CompoundResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/compounds-lang`

**Get all compounds with language support**

Retrieve all compounds with names and descriptions translated to specified language, with optional search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |
| `search` | query | string | no | Search by compound name or description |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedCompoundsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/compounds-lang/{id}`

**Get compound by ID with language support**

Retrieve a specific compound by its ID with names and descriptions translated to specified language

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Compound ID |
| `lang` | query | string | no | Language code (uz, ru, en - default: uz) |

**Responses**

- `200` — Compound details → `model.CompoundResponse`
- `400` — Invalid request parameters → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Compound not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/compounds/department/{departmentId}`

**Get compounds by department**

Retrieve all compounds for a specific department

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `departmentId` | path | string | yes | Department ID |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |

**Responses**

- `200` — Compounds found → `array<model.CompoundResponse>`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/compounds/with-calculations`

**Create compound with multiple ingredients and child compounds (One Save)**

Create a new compound with its ingredient/child compound calculations in one atomic transaction.
The compound price is auto-calculated as sum of all calculation total_costs.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateCompoundWithCalculationsRequest | yes | Compound + ingredients + child compounds |

**Body schema:** `model.CreateCompoundWithCalculationsRequest`

**Responses**

- `201` — Compound and all calculations created successfully → `model.CompoundWithCalculationsResponse`
- `400` — Invalid request (missing fields, invalid UUIDs, etc.) → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal error (ingredient not found, no invoice, etc.) → `model.ErrorResponse`

---

### `DELETE` `/api/v1/compounds/{id}`

**Delete a compound**

Soft delete a compound by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Compound ID |

**Responses**

- `204` — Compound deleted successfully
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Compound not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/compounds/{id}`

**Get a compound by ID**

Retrieve a specific compound by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Compound ID |

**Responses**

- `200` — Compound found → `model.CompoundResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Compound not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/compounds/{id}`

**Update a compound**

Update an existing compound

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Compound ID |
| `input` | body | model.UpdateCompoundRequest | yes | Compound update data |

**Body schema:** `model.UpdateCompoundRequest`

**Responses**

- `200` — Compound updated successfully → `model.CompoundResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Compound not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/compounds/{id}/recalculate-price`

**Recalculate compound price**

Manually recalculate the price of a compound based on all ingredient calculations

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Compound ID |

**Responses**

- `200` — Price recalculated successfully → `model.CompoundResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Compound not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/compounds/{id}/restore`

**Restore a compound**

Restore a soft-deleted compound by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Compound ID |

**Responses**

- `200` — Compound restored successfully → `model.CompoundResponse`
- `400` — Invalid ID format → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Compound not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/compounds/{id}/with-calculations`

**Update compound with multiple ingredients and child compounds (One Save)**

Update a compound and atomically replace all its calculations in one transaction.
Old calculations are deleted, new ones inserted, price recalculated once at the end.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Compound ID |
| `request` | body | model.UpdateCompoundWithCalculationsRequest | yes | Compound update + ingredients + child compounds |

**Body schema:** `model.UpdateCompoundWithCalculationsRequest`

**Responses**

- `200` — Compound and all calculations updated successfully → `model.CompoundWithCalculationsResponse`
- `400` — Invalid request (missing fields, invalid UUIDs, etc.) → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal error (ingredient not found, no invoice, etc.) → `model.ErrorResponse`

---

