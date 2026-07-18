# stop-list

6 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/stop-list`

**Get stop list for current branch**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit (default 20) |
| `offset` | query | integer | no | Offset (default 0) |

**Responses**

- `200` — OK → `model.PaginatedStopListResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/stop-list`

**Add item to stop list**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.CreateStopListRequest | yes | Stop list item |

**Body schema:** `model.CreateStopListRequest`

**Responses**

- `201` — Created → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/stop-list/logs`

**Get stop list logs for current branch**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `limit` | query | integer | no | Limit (default 20) |
| `offset` | query | integer | no | Offset (default 0) |

**Responses**

- `200` — OK → `model.PaginatedStopListResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/stop-list/{id}`

**Remove item from stop list**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Stop list item ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`

---

### `GET` `/api/v1/stop-list/{id}`

**Get stop list item by ID**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Stop list item ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`

---

### `PUT` `/api/v1/stop-list/{id}`

**Update stop list item**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Stop list item ID |
| `request` | body | model.UpdateStopListRequest | yes | Update data |

**Body schema:** `model.UpdateStopListRequest`

**Responses**

- `200` — OK → `model.SuccessResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`

---

