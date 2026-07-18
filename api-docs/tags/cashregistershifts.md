# CashRegisterShifts

6 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/cash-register-shifts`

**List cash register shifts**

Returns a paginated list of cash register shifts. Filter by cash_register_id, cashier_id, or status (open/closed).

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `cash_register_id` | query | string | no | Filter by cash register ID |
| `cashier_id` | query | string | no | Filter by cashier ID |
| `status` | query | string | no | Filter by status: open or closed |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `array<model.CashRegisterShiftResponse>`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/cash-register-shifts`

**Open cash register shift**

Opens a new shift for a cash register. Only one active shift per cash register is allowed.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `request` | body | model.OpenCashRegisterShiftRequest | yes | Open shift request |

**Body schema:** `model.OpenCashRegisterShiftRequest`

**Responses**

- `201` — Created → `model.CashRegisterShiftResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/cash-register-shifts/active`

**Get active shift**

Returns the currently open shift for the given cash register.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `cash_register_id` | query | string | yes | Cash Register ID |

**Responses**

- `200` — OK → `model.CashRegisterShiftResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/cash-register-shifts/{id}`

**Delete cash register shift**

Soft-deletes a cash register shift by ID.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/cash-register-shifts/{id}`

**Get cash register shift**

Returns a single cash register shift by its ID.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |

**Responses**

- `200` — OK → `model.CashRegisterShiftResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/cash-register-shifts/{id}/close`

**Close cash register shift**

Closes an open shift by recording closing cash and card amounts.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |
| `request` | body | model.CloseCashRegisterShiftRequest | yes | Close shift request |

**Body schema:** `model.CloseCashRegisterShiftRequest`

**Responses**

- `200` — OK → `model.CashRegisterShiftResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

