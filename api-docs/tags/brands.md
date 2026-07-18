# brands

11 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/admin/brands`

**List brands**

Get all brands with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit (default: 10, max: 100) |
| `offset` | query | integer | no | Offset (default: 0) |

**Responses**

- `200` — OK → `array<model.BrandResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/admin/brands`

**Create brand**

Create a new brand

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateBrandRequest | yes | Brand creation request |

**Body schema:** `model.CreateBrandRequest`

**Responses**

- `201` — Created → `model.BrandResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/admin/brands/{id}`

**Delete brand**

Delete a brand by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/admin/brands/{id}`

**Get brand**

Get a brand by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand ID |

**Responses**

- `200` — OK → `model.BrandResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/admin/brands/{id}`

**Update brand**

Update a brand by ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand ID |
| `request` | body | model.UpdateBrandRequest | yes | Brand update request |

**Body schema:** `model.UpdateBrandRequest`

**Responses**

- `200` — OK → `model.BrandResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/admin/brands/{id}/superadmins`

**List brand superadmins**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand UUID |

**Responses**

- `200` — OK → `array<model.BrandSuperadminResponse>`

---

### `POST` `/api/v1/admin/brands/{id}/superadmins`

**Create brand superadmin**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand UUID |
| `request` | body | model.CreateBrandSuperadminRequest | yes | Superadmin creation request |

**Body schema:** `model.CreateBrandSuperadminRequest`

**Responses**

- `201` — Created → `model.BrandSuperadminResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/admin/brands/{id}/superadmins/{user_id}`

**Delete brand superadmin**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand UUID |
| `user_id` | path | string | yes | User UUID |

**Responses**

- `200` — OK

---

### `GET` `/api/v1/admin/brands/{id}/superadmins/{user_id}`

**Get brand superadmin**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand UUID |
| `user_id` | path | string | yes | User UUID |

**Responses**

- `200` — OK → `model.BrandSuperadminResponse`

---

### `PUT` `/api/v1/admin/brands/{id}/superadmins/{user_id}`

**Update brand superadmin**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Brand UUID |
| `user_id` | path | string | yes | User UUID |
| `request` | body | model.UpdateBrandSuperadminRequest | yes | Update request |

**Body schema:** `model.UpdateBrandSuperadminRequest`

**Responses**

- `200` — OK → `model.BrandSuperadminResponse`

---

### `GET` `/api/v1/brand/info`

**Get own brand info**

Returns brand info derived from the token's brand_id claim

_Auth: Bearer required_

**Responses**

- `200` — OK → `model.BrandResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`

---

