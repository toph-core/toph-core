# order-table-timer

4 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/orders/{id}/table-timer`

**Get order table timer**

Returns current table timer state for the order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `403` — Forbidden → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/table-timer/pause`

**Pause order table timer**

Pauses the active table timer for the given order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `403` — Forbidden → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/table-timer/resume`

**Resume order table timer**

Resumes a paused table timer for the given order

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `403` — Forbidden → `model.ErrorResponse`

---

### `POST` `/api/v1/orders/{id}/table-timer/start`

**Start order table timer**

Starts table timer for a time-based table if needed

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Order ID |

**Responses**

- `200` — OK → `object`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `403` — Forbidden → `model.ErrorResponse`

---

