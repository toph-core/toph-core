# Invoices

12 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/invoices`

**Get all invoices**

Get all invoices with optional filters: date range, storage, supplier, ingredient, status, search and sorting

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |
| `date_from` | query | string | no | Filter from date (YYYY-MM-DD or RFC3339) |
| `date_to` | query | string | no | Filter to date (YYYY-MM-DD or RFC3339) |
| `storage_id` | query | string | no | Filter by storage ID |
| `supplier_id` | query | string | no | Filter by supplier ID |
| `ingredient_id` | query | string | no | Filter by ingredient ID (invoices containing this ingredient) |
| `status` | query | string | no | Filter by status (pending, arrived, received, cancelled) |
| `search` | query | string | no | Search by supplier name, phone or total amount |
| `sort_by` | query | string | no | Sort by field |
| `sort_order` | query | string | no | Sort order |
| `expand` | query | string | no | Expand related fields |

**Responses**

- `200` — OK → `model.PaginatedInvoicesResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/invoices`

**Create supplier invoice**

Create a new supplier invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateInvoiceRequest | yes | Create invoice request |

**Body schema:** `model.CreateInvoiceRequest`

**Responses**

- `201` — Created → `model.InvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/invoices/batch`

**Batch delete invoices**

Delete multiple invoices at once. Arrived → stock reversed + deleted. Pending → cancelled.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `input` | body | model.DeleteInvoicesBatchRequest | yes | IDs to delete |

**Body schema:** `model.DeleteInvoicesBatchRequest`

**Responses**

- `200` — Deleted → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `POST` `/api/v1/invoices/batch`

**Create invoice with details in batch**

Create a new invoice and all its line items in one atomic call

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateInvoiceWithDetailsRequest | yes | Create invoice with details request |

**Body schema:** `model.CreateInvoiceWithDetailsRequest`

**Responses**

- `201` — Created → `model.CreateInvoiceWithDetailsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/invoices/{id}`

**Delete invoice**

Delete (soft delete) an invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `204` — No Content
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/invoices/{id}`

**Get invoice by ID**

Get a single invoice by its ID

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `200` — OK → `model.InvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PUT` `/api/v1/invoices/{id}`

**Update invoice**

Update an existing invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |
| `request` | body | model.UpdateInvoiceRequest | yes | Update invoice request |

**Body schema:** `model.UpdateInvoiceRequest`

**Responses**

- `200` — OK → `model.InvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/invoices/{id}/details`

**Get invoice with details**

Get a complete invoice including all line items and ingredient details

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `200` — OK → `model.InvoiceGetWithDetailsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/invoices/{id}/details/batch`

**Batch delete invoice details**

Delete multiple invoice detail line items at once, reversing stock for each

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | Invoice ID |
| `input` | body | model.DeleteInvoiceDetailsBatchRequest | yes | Detail IDs to delete |

**Body schema:** `model.DeleteInvoiceDetailsBatchRequest`

**Responses**

- `200` — Deleted → `model.SuccessResponse`
- `400` — Invalid request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal server error → `model.ErrorResponse`

---

### `PUT` `/api/v1/invoices/{id}/details/batch`

**Batch update invoice details**

Replace all details of an invoice. Optionally update invoice-level fields (status, supplier_id, storage_id, total_amount, date). Stock is applied only when invoice status is or becomes 'arrived'. Setting status to 'arrived' applies stock; it was already 'arrived', old stock is reversed and new stock applied.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |
| `request` | body | model.UpsertInvoiceDetailsRequest | yes | Invoice fields (optional) + new details |

**Body schema:** `model.UpsertInvoiceDetailsRequest`

**Responses**

- `200` — OK → `model.UpsertInvoiceDetailsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/invoices/{id}/restore`

**Restore invoice**

Restore a soft-deleted invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `200` — OK → `model.InvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `PATCH` `/api/v1/invoices/{id}/status`

**Update invoice status**

Update the status of an invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |
| `request` | body | model.UpdateInvoiceStatusRequest | yes | Status update request |

**Body schema:** `model.UpdateInvoiceStatusRequest`

**Responses**

- `200` — OK → `model.InvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `401` — Unauthorized → `model.ErrorResponse`
- `404` — Not Found → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

