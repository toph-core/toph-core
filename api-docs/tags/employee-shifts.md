# employee-shifts

13 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/branches/{branch_id}/employee-shifts`

**List shifts by branch**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `page` | query | string | no | Page (default 1) |
| `limit` | query | string | no | Limit (default 20) |
| `date_from` | query | string | no | RFC3339 date from |
| `date_to` | query | string | no | RFC3339 date to |

**Responses**

- `200` — OK → `model.EmployeeShiftListSwaggerResponse`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/employee-shifts`

**List shifts by employee**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `employee_id` | query | string | yes | Employee ID |
| `page` | query | integer | no | Page (default 1) |
| `limit` | query | integer | no | Limit (default 20) |

**Responses**

- `200` — OK → `model.EmployeeShiftListSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `POST` `/api/v1/employee-shifts`

**Create employee shift**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateEmployeeShiftRequest | yes | Shift data |

**Body schema:** `model.CreateEmployeeShiftRequest`

**Responses**

- `201` — Created → `model.EmployeeShiftSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/employee-shifts/my-active`

**Get my active shift**

_Auth: Bearer required_

**Responses**

- `200` — OK → `model.EmployeeShiftSwaggerResponse`
- `500` — Internal Server Error → `model.ErrorData`

---

### `POST` `/api/v1/employee-shifts/vacation`

**Create vacation request**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.VacationRequestRequest | yes | Vacation request data |

**Body schema:** `model.VacationRequestRequest`

**Responses**

- `201` — Created → `model.VacationSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/employee-shifts/vacations`

**List vacation requests**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `status` | query | string | no | Filter by status (pending, approved, rejected) |
| `page` | query | integer | no | Page (default 1) |
| `limit` | query | integer | no | Limit (default 20) |

**Responses**

- `200` — OK → `model.EmployeeShiftListSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/employee-shifts/{id}`

**Get shift by ID**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |

**Responses**

- `200` — OK → `model.EmployeeShiftSwaggerResponse`
- `404` — Not Found → `model.ErrorData`

---

### `POST` `/api/v1/employee-shifts/{id}/approve`

**Approve vacation request**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |

**Responses**

- `200` — OK → `model.VacationSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `404` — Not Found → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `POST` `/api/v1/employee-shifts/{id}/end`

**End employee shift**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |
| `input` | body | model.EndEmployeeShiftRequest | yes | Payment amount |

**Body schema:** `model.EndEmployeeShiftRequest`

**Responses**

- `200` — OK → `model.EmployeeShiftSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `404` — Not Found → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `POST` `/api/v1/employee-shifts/{id}/reject`

**Reject vacation request**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |

**Responses**

- `200` — OK → `model.VacationSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `404` — Not Found → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `POST` `/api/v1/employee-shifts/{id}/start`

**Start employee shift**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Shift ID |

**Responses**

- `200` — OK → `model.StartShiftSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `404` — Not Found → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/employees/{id}/active-shift`

**Get active shift by employee ID**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Employee ID |

**Responses**

- `200` — OK → `model.EmployeeShiftSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/employees/{id}/salary-report`

**Get employee salary report**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Employee ID |
| `date_from` | query | string | yes | Start date (YYYY-MM-DD) |
| `date_to` | query | string | yes | End date (YYYY-MM-DD) |

**Responses**

- `200` — OK → `model.SalaryReportSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

