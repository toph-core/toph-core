# OutgoingInvoices

10 endpoint(s)

[← Back to index](../README.md)

### `GET` `/api/v1/outgoing-invoices`

**List outgoing invoices**

List invoices filtered by storage, group, status, date range. Returns total count and total sum.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `storage_id` | query | string | no | Filter by storage UUID |
| `group_id` | query | string | no | Filter by deduction act group UUID |
| `status` | query | string | no | Filter by status (active/cancelled) |
| `start_date` | query | string | no | Start date (RFC3339) |
| `end_date` | query | string | no | End date (RFC3339) |
| `limit` | query | integer | no | Limit |
| `offset` | query | integer | no | Offset |

**Responses**

- `200` — OK → `model.OutgoingInvoiceListResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/outgoing-invoices`

**Create outgoing invoice**

Create a new outgoing invoice. Add items, then confirm to deduct stock.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateOutgoingInvoiceRequest | yes | Create outgoing invoice |

**Body schema:** `model.CreateOutgoingInvoiceRequest`

**Responses**

- `201` — Created → `model.OutgoingInvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/outgoing-invoices/batch`

**Create outgoing invoice with items (batch)**

Creates invoice header and upserts all items in one request. Returns full invoice with stock preview.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `request` | body | model.CreateOutgoingInvoiceBatchRequest | yes | Batch create |

**Body schema:** `model.CreateOutgoingInvoiceBatchRequest`

**Responses**

- `201` — Created → `model.OutgoingInvoiceWithItemsResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/outgoing-invoices/{id}`

**Delete outgoing invoice**

Soft-deletes an invoice. Only active invoices can be deleted.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `GET` `/api/v1/outgoing-invoices/{id}`

**Get outgoing invoice by ID**

Returns invoice header + all items with stock_before/stock_after

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `200` — OK → `model.OutgoingInvoiceWithItemsResponse`
- `404` — Not Found → `model.ErrorResponse`

---

### `PUT` `/api/v1/outgoing-invoices/{id}`

**Update outgoing invoice**

Update storage, group, date, description. Only works on active invoices.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |
| `request` | body | model.UpdateOutgoingInvoiceRequest | yes | Update invoice |

**Body schema:** `model.UpdateOutgoingInvoiceRequest`

**Responses**

- `200` — OK → `model.OutgoingInvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/outgoing-invoices/{id}/cancel`

**Cancel outgoing invoice**

Cancels an invoice (no stock change)

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `200` — OK → `model.OutgoingInvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/outgoing-invoices/{id}/confirm`

**Confirm outgoing invoice**

Confirms invoice. Deducts each item's quantity from ingredient_stock and saves stock snapshots.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |

**Responses**

- `200` — OK → `model.OutgoingInvoiceResponse`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `POST` `/api/v1/outgoing-invoices/{id}/items`

**Upsert outgoing invoice items**

Add/update multiple ingredient items. Returns items with live stock preview.

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |
| `request` | body | model.UpsertOutgoingInvoiceItemsRequest | yes | Items to upsert |

**Body schema:** `model.UpsertOutgoingInvoiceItemsRequest`

**Responses**

- `200` — OK → `array<model.OutgoingInvoiceItemResponse>`
- `400` — Bad Request → `model.ErrorResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

### `DELETE` `/api/v1/outgoing-invoices/{id}/items/{item_id}`

**Delete outgoing invoice item**

Remove an ingredient item from an active invoice

_Auth: Bearer required_

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `lang` | query | string | no | Language (uz, ru, en) |
| `id` | path | string | yes | Invoice ID |
| `item_id` | path | string | yes | Item ID |

**Responses**

- `200` — OK → `model.SuccessResponse`
- `500` — Internal Server Error → `model.ErrorResponse`

---

