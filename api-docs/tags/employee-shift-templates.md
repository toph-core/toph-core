# employee-shift-templates

5 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/employee-shift-templates`

**List shift templates**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `employee_id` | query | string | no | Filter by employee ID |
| `branch_id` | query | string | no | Filter by branch ID |
| `is_active` | query | boolean | no | Filter by active status |
| `page` | query | integer | no | Page number (default 1) |
| `limit` | query | integer | no | Page size (default 20) |

**Responses**

- `200` — OK → `model.TemplateListSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `POST` `/api/v1/employee-shift-templates`

**Create shift template**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.CreateTemplateRequest | yes | Template data |

**Body schema:** `model.CreateTemplateRequest`

**Responses**

- `201` — Created → `model.TemplateSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `DELETE` `/api/v1/employee-shift-templates/{id}`

**Delete shift template**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Template ID |

**Responses**

- `200` — OK → `model.TemplateSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `404` — Not Found → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

### `GET` `/api/v1/employee-shift-templates/{id}`

**Get shift template by ID**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Template ID |

**Responses**

- `200` — OK → `model.TemplateSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `404` — Not Found → `model.ErrorData`

---

### `PATCH` `/api/v1/employee-shift-templates/{id}`

**Update shift template**

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Template ID |
| `input` | body | model.UpdateTemplateRequest | yes | Fields to update |

**Body schema:** `model.UpdateTemplateRequest`

**Responses**

- `200` — OK → `model.TemplateSwaggerResponse`
- `400` — Bad Request → `model.ErrorData`
- `404` — Not Found → `model.ErrorData`
- `500` — Internal Server Error → `model.ErrorData`

---

