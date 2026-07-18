# translations

6 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/translations`

**Get all translations**

Retrieve all translations with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit results (default: 20) |
| `offset` | query | integer | no | Offset for pagination (default: 0) |

**Responses**

- `200` — List of all translations → `array<model.TranslationResponse>`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/translations`

**Create a new translation**

Create a new translation with uz, ru, en content

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateTranslationRequest | yes | Translation creation data |

**Body schema:** `model.CreateTranslationRequest`

**Responses**

- `201` — Translation created successfully → `model.TranslationResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/translations/{id}`

**Delete translation**

Soft delete a translation (mark as deleted without removing from database)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Translation ID |

**Responses**

- `200` — Translation deleted successfully → `model.SuccessResponse`
- `400` — Invalid translation ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `GET` `/api/v1/translations/{id}`

**Get translation by ID**

Retrieve a specific translation by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Translation ID |

**Responses**

- `200` — Translation details → `model.TranslationResponse`
- `400` — Invalid translation ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Translation not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/translations/{id}`

**Update translation**

Update an existing translation by ID (partial update of uz/ru/en)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Translation ID |
| `input` | body | model.UpdateTranslationRequest | yes | Translation update data |

**Body schema:** `model.UpdateTranslationRequest`

**Responses**

- `200` — Translation updated successfully → `model.TranslationResponse`
- `400` — Invalid request data → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Translation not found → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/translations/{id}/restore`

**Restore translation**

Restore a previously deleted translation

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Translation ID |

**Responses**

- `200` — Translation restored successfully → `model.SuccessResponse`
- `400` — Invalid translation ID → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

