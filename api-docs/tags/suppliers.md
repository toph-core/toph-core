# Suppliers

6 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/suppliers`

**Get all suppliers**

Retrieve all suppliers with pagination, optional search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `search` | query | string | no | Search by supplier name |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `limit` | query | integer | no | Limit (default: 20) |
| `offset` | query | integer | no | Offset (default: 0) |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedSuppliersResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/suppliers`

**Create supplier**

Create a new supplier

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateSupplierRequest | yes | Create supplier request |

**Body schema:** `model.CreateSupplierRequest`

**Responses**

- `201` — Created → `model.SupplierResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/suppliers/{id}`

**Delete supplier**

Soft delete a supplier

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Supplier ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/suppliers/{id}`

**Get supplier by ID**

Get a single supplier by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Supplier ID |

**Responses**

- `200` — OK → `model.SupplierResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/suppliers/{id}`

**Update supplier**

Update a supplier

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Supplier ID |
| `request` | body | model.UpdateSupplierRequest | yes | Update supplier request |

**Body schema:** `model.UpdateSupplierRequest`

**Responses**

- `200` — OK → `model.SupplierResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/suppliers/{id}/restore`

**Restore supplier**

Restore a soft-deleted supplier

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Supplier ID |

**Responses**

- `200` — OK → `model.SupplierResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

