# Invoice Details

11 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/invoice-details`

**Get all invoice details**

Get all invoice details with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `array<model.InvoiceDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/invoice-details`

**Create invoice detail**

Create a new line item in an invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateInvoiceDetailRequest | yes | Create invoice detail request |

**Body schema:** `model.CreateInvoiceDetailRequest`

**Responses**

- `201` — Created → `model.InvoiceDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/invoice-details/batch`

**Create multiple invoice details in batch**

Create multiple line items in an invoice with a single API call

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | array<model.CreateInvoiceDetailRequest> | yes | Array of invoice detail requests |

**Body schema:** `array<model.CreateInvoiceDetailRequest>`

**Responses**

- `201` — Created → `model.InvoiceDetailBatchResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/invoice-details/ingredient/{ingredient_id}`

**Get invoice details by ingredient ID**

Get all invoice details containing a specific ingredient with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `ingredient_id` | path | string | yes | Ingredient ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `array<model.InvoiceDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/invoice-details/invoice/{invoice_id}`

**Get invoice details by invoice ID**

Get all line items for a specific invoice with pagination

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `invoice_id` | path | string | yes | Invoice ID |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `array<model.InvoiceDetailResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/invoice-details/{id}`

**Delete invoice detail**

Delete (soft delete) an invoice detail

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice Detail ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/invoice-details/{id}`

**Get invoice detail by ID**

Get a single invoice detail by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice Detail ID |

**Responses**

- `200` — OK → `model.InvoiceDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/invoice-details/{id}`

**Update invoice detail**

Update an existing invoice detail (line item)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice Detail ID |
| `request` | body | model.UpdateInvoiceDetailRequest | yes | Update invoice detail request |

**Body schema:** `model.UpdateInvoiceDetailRequest`

**Responses**

- `200` — OK → `model.InvoiceDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/invoice-details/{id}/quantity`

**Update invoice detail quantity**

Update the quantity of a line item in an invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice Detail ID |
| `request` | body | model.UpdateInvoiceDetailQuantityRequest | yes | Quantity update request |

**Body schema:** `model.UpdateInvoiceDetailQuantityRequest`

**Responses**

- `200` — OK → `model.InvoiceDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/invoice-details/{id}/restore`

**Restore invoice detail**

Restore a soft-deleted invoice detail

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice Detail ID |

**Responses**

- `200` — OK → `model.InvoiceDetailResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/invoice-details/{id}/with-ingredient`

**Get invoice detail with ingredient**

Get invoice detail including the associated ingredient information

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice Detail ID |

**Responses**

- `200` — OK → `model.InvoiceDetailWithIngredientResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

